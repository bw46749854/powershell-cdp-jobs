Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# E2E テスト（タグ E2E）の土台: モック画面の Web サーバーと、リモートデバッグを有効にしたブラウザを起動・停止する。
#
# ブラウザは次の順で探す。見つからなければ E2E テストは Skipped になる（失敗にはしない）。
#   1. 環境変数 E2E_BROWSER_PATH
#   2. Microsoft Edge / Google Chrome の標準のインストール先（Windows）
#   3. /opt/pw-browsers/chromium、PATH 上の chromium / google-chrome（Linux）

Import-Module (Join-Path $PSScriptRoot 'TestSupport.psm1') -DisableNameChecking
Add-Type -AssemblyName System.Net.Http

function Find-E2EBrowser {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:E2E_BROWSER_PATH)) { [void]$candidates.Add($env:E2E_BROWSER_PATH) }
    foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        [void]$candidates.Add((Join-Path $root 'Microsoft\Edge\Application\msedge.exe'))
        [void]$candidates.Add((Join-Path $root 'Google\Chrome\Application\chrome.exe'))
    }
    [void]$candidates.Add('/opt/pw-browsers/chromium')
    foreach ($name in @('chromium', 'chromium-browser', 'google-chrome')) {
        $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { [void]$candidates.Add($command.Source) }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-FreeTcpPort {
    $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
    $listener.Start()
    try { return $listener.LocalEndpoint.Port }
    finally { $listener.Stop() }
}

function Get-PowerShellExecutable {
    return (Get-Process -Id $PID).Path
}

function Start-E2EProcess {
    <#
    .SYNOPSIS
    子プロセスを起動する。出力は LogDirectory のファイルへ（失敗の調査用）。Windows ではウィンドウを出さない。
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$LogDirectory,
        [Parameter(Mandatory)][string]$Name
    )

    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $options = @{
        FilePath = $FilePath
        ArgumentList = $ArgumentList
        PassThru = $true
        RedirectStandardOutput = (Join-Path $LogDirectory "$Name.out.log")
        RedirectStandardError = (Join-Path $LogDirectory "$Name.err.log")
    }
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $options.WindowStyle = 'Hidden' }
    return Start-Process @options
}

function Invoke-LocalHttp {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Method = 'GET'
    )

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $client = New-Object System.Net.Http.HttpClient -ArgumentList $handler
    $client.Timeout = [TimeSpan]::FromSeconds(5)
    try {
        $request = New-Object System.Net.Http.HttpRequestMessage -ArgumentList ([System.Net.Http.HttpMethod]::new($Method)), $Uri
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
    }
    finally {
        $client.Dispose()
    }
}

function Wait-E2ECondition {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [Parameter(Mandatory)][string]$Description,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = ''
    while ((Get-Date) -lt $deadline) {
        try {
            if (& $Condition) { return }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 250
    }
    throw "E2E の準備がタイムアウトしました: $Description $lastError"
}

function Start-MockSite {
    param([Parameter(Mandatory)][int]$Port, [Parameter(Mandatory)][string]$LogDirectory)

    $server = Get-RepositoryPath 'mock/server.ps1'
    $process = Start-E2EProcess -Name 'mock-site' -LogDirectory $LogDirectory -FilePath (Get-PowerShellExecutable) -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$server`"", '-Port', $Port)
    Wait-E2ECondition -Description "モック画面の Web サーバー（ポート $Port）" -Condition { (Invoke-LocalHttp -Uri "http://localhost:$Port/").Status -eq 200 }
    return $process
}

function Get-E2EPageTargets {
    param([Parameter(Mandatory)][int]$DebugPort)

    $text = (Invoke-LocalHttp -Uri "http://localhost:$DebugPort/json").Text
    return @(($text | ConvertFrom-Json) | Where-Object { $_.type -eq 'page' })
}

function Start-E2EBrowser {
    <#
    .SYNOPSIS
    ヘッドレスのブラウザを専用のプロファイルで起動し、指定した URL をそれぞれ別のタブで開く。
    .NOTES
    ヘッドレスでは起動時に複数の URL を渡せないため、2つ目以降は /json/new で開く。
    #>
    param(
        [Parameter(Mandatory)][string]$BrowserPath,
        [Parameter(Mandatory)][int]$DebugPort,
        [Parameter(Mandatory)][string]$ProfileDirectory,
        [Parameter(Mandatory)][string[]]$Urls,
        [Parameter(Mandatory)][string]$LogDirectory
    )

    New-Item -ItemType Directory -Path $ProfileDirectory -Force | Out-Null
    $arguments = @(
        '--headless=new', '--no-sandbox', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
        "--remote-debugging-port=$DebugPort", "--user-data-dir=`"$ProfileDirectory`"", '--window-size=1400,900',
        $Urls[0]
    )
    $process = Start-E2EProcess -Name 'browser' -LogDirectory $LogDirectory -FilePath $BrowserPath -ArgumentList $arguments
    Wait-E2ECondition -Description "ブラウザのリモートデバッグ（ポート $DebugPort）" -Condition { @(Get-E2EPageTargets -DebugPort $DebugPort).Count -ge 1 }

    foreach ($url in @($Urls | Select-Object -Skip 1)) {
        $opened = Invoke-LocalHttp -Uri "http://localhost:$DebugPort/json/new?$url" -Method 'PUT'
        if ($opened.Status -ge 400) { [void](Invoke-LocalHttp -Uri "http://localhost:$DebugPort/json/new?$url") }
    }

    foreach ($url in $Urls) {
        Wait-E2ECondition -Description "タブの表示: $url" -Condition {
            @(Get-E2EPageTargets -DebugPort $DebugPort | Where-Object { $_.url -eq $url -and $_.title -and $_.title -ne $url }).Count -eq 1
        }
    }
    return $process
}

function Stop-E2EProcess {
    param([AllowNull()][System.Diagnostics.Process]$Process)

    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            $Process.Kill()
            [void]$Process.WaitForExit(5000)
        }
    }
    catch { }
}

function Invoke-E2EPageScript {
    <#
    .SYNOPSIS
    URL が一致するタブで JavaScript の式を評価し、値を返す（テストの準備と結果の確認用）。
    .DESCRIPTION
    テスト対象（PageBridge）とは別の、最小限の CDP クライアントで評価する。
    確認する側が対象と同じ仕組みに依存すると、同じ誤りを見逃すため。
    #>
    param(
        [Parameter(Mandatory)][int]$DebugPort,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Expression
    )

    $target = @(Get-E2EPageTargets -DebugPort $DebugPort | Where-Object { $_.url -eq $Url })
    if ($target.Count -ne 1) { throw "タブを1つに決められません: $Url（$($target.Count) 件）" }

    $socket = New-Object System.Net.WebSockets.ClientWebSocket
    $socket.Options.Proxy = $null
    $timeout = New-Object System.Threading.CancellationTokenSource -ArgumentList ([TimeSpan]::FromSeconds(30))
    try {
        [void]$socket.ConnectAsync([Uri]$target[0].webSocketDebuggerUrl, $timeout.Token).GetAwaiter().GetResult()
        $request = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $Expression; returnByValue = $true; awaitPromise = $true } } | ConvertTo-Json -Depth 5 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($request)
        [void]$socket.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $timeout.Token).GetAwaiter().GetResult()

        $buffer = New-Object byte[] 65536
        while ($true) {
            $stream = New-Object System.IO.MemoryStream
            do {
                $received = $socket.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (, $buffer)), $timeout.Token).GetAwaiter().GetResult()
                $stream.Write($buffer, 0, $received.Count)
            } while (-not $received.EndOfMessage)
            $message = [System.Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
            if ($message.PSObject.Properties['id'] -and $message.id -eq 1) { break }
        }

        if ($message.PSObject.Properties['error']) { throw "CDP エラー: $($message.error.message)" }
        if ($message.result.PSObject.Properties['exceptionDetails']) { throw "ページ内の例外: $($message.result.exceptionDetails.text) $($message.result.result.description)" }
        return $message.result.result.value
    }
    finally {
        $socket.Dispose()
        $timeout.Dispose()
    }
}

function ConvertTo-Psd1Text {
    <#
    .SYNOPSIS
    hashtable / 配列 / 文字列 / 数値 / 真偽値を .psd1 の書式にする（E2E 用の設定ファイルを書くため）。
    #>
    param([AllowNull()][object]$Value, [int]$Indent = 0)

    $pad = '    ' * $Indent
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { if ($Value) { return '$true' } else { return '$false' } }
    if ($Value -is [int] -or $Value -is [long]) { return [string]$Value }
    if ($Value -is [string]) { return "'" + $Value.Replace("'", "''") + "'" }
    if ($Value -is [System.Collections.IDictionary]) {
        $lines = @('@{')
        foreach ($key in @($Value.Keys | Sort-Object)) {
            $lines += "$pad    $key = $(ConvertTo-Psd1Text -Value $Value[$key] -Indent ($Indent + 1))"
        }
        $lines += "$pad}"
        return ($lines -join "`n")
    }
    if ($Value -is [System.Array]) {
        return '@(' + ((@($Value) | ForEach-Object { ConvertTo-Psd1Text -Value $_ -Indent ($Indent + 1) }) -join ', ') + ')'
    }
    throw "psd1 に変換できない値です: $($Value.GetType().FullName)"
}

function New-E2ESettingsFile {
    <#
    .SYNOPSIS
    同梱の settings.psd1 をもとに、出力先を WorkRoot に、接続先をテスト用のブラウザに変えた設定ファイルを作る。
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$WorkRoot,
        [Parameter(Mandatory)][int]$DebugPort
    )

    $settings = Import-PowerShellDataFile -LiteralPath (Get-RepositoryPath 'app/config/settings.psd1')
    $settings.Common.Browser.DebuggerUrl = "http://localhost:$DebugPort/json"
    $settings.Common.Logging.File = $false
    foreach ($job in @($settings.Jobs.Values)) {
        foreach ($key in @($job.Keys)) {
            if (($key -like '*Directory' -or $key -like '*Path') -and $job[$key] -is [string]) {
                $job[$key] = Join-Path $WorkRoot ($job[$key] -replace '^work[\\/]', '' -replace '^%USERPROFILE%[\\/]', 'home/')
            }
        }
    }
    $settings.Jobs.PlotRosterExport.DownloadTimeoutSeconds = 30
    $settings.Jobs.PlantingRecordExport.DownloadTimeoutSeconds = 30

    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $true
    [System.IO.File]::WriteAllText($Path, (ConvertTo-Psd1Text -Value $settings), $encoding)
    return $Path
}

Export-ModuleMember -Function @(
    'Find-E2EBrowser',
    'Get-FreeTcpPort',
    'Start-MockSite',
    'Start-E2EBrowser',
    'Stop-E2EProcess',
    'Get-E2EPageTargets',
    'Invoke-E2EPageScript',
    'New-E2ESettingsFile',
    'ConvertTo-Psd1Text'
)
