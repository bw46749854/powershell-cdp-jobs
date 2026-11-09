Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# テスト用の偽物（fake）と小道具。
# 本番のポートと同じメンバー名・同じパラメーター名を持たせ、呼び出しを記録する。
# 各ファイルのテストは「本番実装を差し替えた状態」で振る舞いを固定する。

function Get-RepositoryPath {
    <#
    .SYNOPSIS
    リポジトリ直下からの相対パスを絶対パスにする。
    #>
    param([Parameter(Mandatory)][string]$RelativePath)

    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    return (Join-Path $root $RelativePath)
}

function New-CallRecorder {
    $list = New-Object System.Collections.ArrayList
    return , $list
}

function New-ManualClock {
    <#
    .SYNOPSIS
    手動で進む時計。Sleep を呼ぶと、その分だけ時刻が進む（実時間は待たない）。
    .PARAMETER StepMilliseconds
    Now を呼ぶたびに自動で進める時間。期限切れの経路をテストするときに使う。
    #>
    param(
        [datetime]$Start = [datetime]'2026-04-15T09:30:00',
        [int]$StepMilliseconds = 0
    )

    $state = [pscustomobject]@{ Now = $Start; Sleeps = (New-CallRecorder) }

    return [pscustomobject]@{
        State = $state
        Now = {
            [CmdletBinding()] param()
            $current = $state.Now
            if ($StepMilliseconds -gt 0) { $state.Now = $state.Now.AddMilliseconds($StepMilliseconds) }
            return $current
        }.GetNewClosure()
        Sleep = {
            [CmdletBinding()] param([Parameter(Mandatory)][int]$Milliseconds)
            [void]$state.Sleeps.Add($Milliseconds)
            $state.Now = $state.Now.AddMilliseconds($Milliseconds)
        }.GetNewClosure()
    }
}

function New-RecordingLog {
    <#
    .SYNOPSIS
    ログポートの偽物。Entries に Level / Message を記録する。
    #>
    $entries = New-CallRecorder

    return [pscustomobject]@{
        Entries = $entries
        Info = { [CmdletBinding()] param([AllowEmptyString()][string]$Message) [void]$entries.Add([pscustomobject]@{ Level = 'Info'; Message = $Message }) }.GetNewClosure()
        Warn = { [CmdletBinding()] param([AllowEmptyString()][string]$Message) [void]$entries.Add([pscustomobject]@{ Level = 'Warn'; Message = $Message }) }.GetNewClosure()
        Error = { [CmdletBinding()] param([AllowEmptyString()][string]$Message) [void]$entries.Add([pscustomobject]@{ Level = 'Error'; Message = $Message }) }.GetNewClosure()
        Section = { [CmdletBinding()] param([Parameter(Mandatory)][string]$Title) [void]$entries.Add([pscustomobject]@{ Level = 'Section'; Message = $Title }) }.GetNewClosure()
        Data = { [CmdletBinding()] param([AllowEmptyString()][string]$Label, [AllowNull()][object]$Data) [void]$entries.Add([pscustomobject]@{ Level = 'Data'; Message = $Label; Data = $Data }) }.GetNewClosure()
    }
}

function Get-LogMessages {
    param(
        [Parameter(Mandatory)][object]$Log,
        [string]$Level = ''
    )

    return @($Log.Entries | Where-Object { [string]::IsNullOrEmpty($Level) -or $_.Level -eq $Level } | ForEach-Object { $_.Message })
}

function New-CategorizedTestException {
    <#
    .SYNOPSIS
    PageBridge の分類付き例外と同じ形の例外を作る（偽トランスポートから投げる用）。
    #>
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Message
    )

    $exception = New-Object System.InvalidOperationException -ArgumentList $Message
    $exception.Data['pagebridge.category'] = $Category
    return $exception
}

function New-SimulatedPage {
    <#
    .SYNOPSIS
    偽 CDP トランスポートが応答する「ページ」。ページスクリプトの代わりに PowerShell の scriptblock で応答する。
    .PARAMETER Methods
    メソッド名 → param($Arguments) を受け取り値を返す scriptblock。
    例外を投げると、ページ内 JavaScript の例外（exceptionDetails）として返る。
    .PARAMETER HelperMethods
    注入時の ack で「実装済み」と報告するメソッド一覧（省略時は Methods のキー）。
    #>
    param(
        [Parameter(Mandatory)][string]$WebSocketUrl,
        [string]$Title = 'page',
        [string]$Url = 'http://localhost/page',
        [string]$Helper = 'sampleHelper',
        [hashtable]$Methods = @{},
        [AllowNull()][string[]]$HelperMethods = $null,
        [bool]$KernelLoaded = $true
    )

    if ($null -eq $HelperMethods) { $HelperMethods = @($Methods.Keys) }

    return [pscustomobject]@{
        WebSocketUrl = $WebSocketUrl
        Title = $Title
        Url = $Url
        Helper = $Helper
        Methods = $Methods
        HelperMethods = $HelperMethods
        KernelLoaded = $KernelLoaded
        Calls = (New-CallRecorder)
    }
}

function New-FakeCdpTransport {
    <#
    .SYNOPSIS
    CDP トランスポートの偽物。/json のタブ一覧と、Runtime.evaluate への応答をシミュレートする。
    .PARAMETER Pages
    New-SimulatedPage の配列。タブ一覧はここから作る。
    .PARAMETER OnCommand
    param($Request, $Page) を受け取り、応答メッセージ（hashtable）の配列を返す scriptblock。
    $null を返すと既定の応答（Runtime.evaluate のシミュレーション）を使う。
    イベントの割り込みや CDP エラー応答のテストに使う。
    #>
    param(
        [object[]]$Pages = @(),
        [AllowNull()][object[]]$ExtraTargets = @(),
        [AllowNull()][scriptblock]$OnCommand = $null,
        [AllowNull()][string]$TargetListError = $null,
        [string[]]$UnreachablePages = @()
    )

    $state = [pscustomobject]@{
        Pages = $Pages
        Sent = (New-CallRecorder)
        Connections = (New-CallRecorder)
        Aborted = (New-CallRecorder)
        Closed = (New-CallRecorder)
    }

    $newException = Get-Command -Name New-CategorizedTestException -CommandType Function
    $simulate = {
        param($Request, $Page)

        $id = $Request.id
        if ($Request.method -ne 'Runtime.evaluate') {
            return @(@{ id = $id; result = @{} })
        }

        $expression = [string]$Request.params.expression
        if ($expression -match 'window\.__pagekit\.ack\(') {
            [void]$Page.Calls.Add([pscustomobject]@{ Method = '#inject'; Arguments = @() })
            if (-not $Page.KernelLoaded) {
                return @(@{ id = $id; result = @{ result = @{ type = 'object'; value = @{ ok = $false; reason = 'kernel_missing'; methods = @() } } } })
            }
            return @(@{ id = $id; result = @{ result = @{ type = 'object'; value = @{ ok = $true; helper = $Page.Helper; methods = @($Page.HelperMethods); kernelVersion = 'test' } } } })
        }

        $methodMatch = [regex]::Match($expression, 'helper\["(?<method>[A-Za-z0-9_$]+)"\]')
        $argsMatch = [regex]::Match($expression, 'method\.apply\(helper, \[(?<args>[\s\S]*)\]\);')
        $method = $methodMatch.Groups['method'].Value
        $arguments = @()
        if ($argsMatch.Success -and -not [string]::IsNullOrWhiteSpace($argsMatch.Groups['args'].Value)) {
            $arguments = @(ConvertFrom-Json -InputObject ('[' + $argsMatch.Groups['args'].Value + ']') | ForEach-Object { $_ })
        }

        [void]$Page.Calls.Add([pscustomobject]@{ Method = $method; Arguments = $arguments })

        if (-not $Page.Methods.ContainsKey($method)) {
            return @(@{ id = $id; result = @{ result = @{ type = 'undefined' }; exceptionDetails = @{ text = 'Uncaught'; exception = @{ description = "Error: [pagekit:method-missing] $method" } } } })
        }

        try {
            $value = & $Page.Methods[$method] $arguments
        }
        catch {
            return @(@{ id = $id; result = @{ result = @{ type = 'object' }; exceptionDetails = @{ text = 'Uncaught'; exception = @{ description = "Error: $($_.Exception.Message)" } } } })
        }

        return @(@{ id = $id; result = @{ result = @{ type = 'object'; value = $value } } })
    }

    return [pscustomobject]@{
        State = $state
        GetText = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][int]$TimeoutSeconds)
            if ($TargetListError) { throw $TargetListError }
            $list = @()
            foreach ($page in $state.Pages) {
                $list += @{ type = 'page'; title = $page.Title; url = $page.Url; webSocketDebuggerUrl = $page.WebSocketUrl; id = $page.WebSocketUrl }
            }
            foreach ($extra in @($ExtraTargets)) { if ($null -ne $extra) { $list += $extra } }
            return (ConvertTo-Json -InputObject @($list) -Depth 10)
        }.GetNewClosure()
        Connect = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][int]$TimeoutMilliseconds)
            if ($UnreachablePages -contains $Uri) { throw "connection refused: $Uri" }
            $page = @($state.Pages | Where-Object { $_.WebSocketUrl -eq $Uri })[0]
            $handle = [pscustomobject]@{ Uri = $Uri; Page = $page; Queue = (New-Object System.Collections.Queue) }
            [void]$state.Connections.Add($Uri)
            return $handle
        }.GetNewClosure()
        Send = {
            [CmdletBinding()] param([Parameter(Mandatory)][object]$Handle, [Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][int]$TimeoutMilliseconds)
            $request = ConvertFrom-Json -InputObject $Text
            [void]$state.Sent.Add([pscustomobject]@{ Uri = $Handle.Uri; Method = $request.method; Request = $request })

            $messages = $null
            if ($OnCommand) { $messages = & $OnCommand $request $Handle.Page }
            if ($null -eq $messages) { $messages = & $simulate $request $Handle.Page }
            foreach ($message in @($messages)) {
                if ($message -is [string]) { $Handle.Queue.Enqueue($message) }
                else { $Handle.Queue.Enqueue((ConvertTo-Json -InputObject $message -Compress -Depth 30)) }
            }
        }.GetNewClosure()
        Receive = {
            [CmdletBinding()] param([Parameter(Mandatory)][object]$Handle, [Parameter(Mandatory)][int]$TimeoutMilliseconds)
            if ($Handle.Queue.Count -eq 0) {
                throw (& $newException -Category 'timeout' -Message 'fake transport: no message')
            }
            $next = $Handle.Queue.Dequeue()
            if ($next -eq '#close') { return $null }
            return $next
        }.GetNewClosure()
        Close = {
            [CmdletBinding()] param([AllowNull()][object]$Handle, [Parameter(Mandatory)][int]$TimeoutMilliseconds)
            [void]$state.Closed.Add($Handle.Uri)
        }.GetNewClosure()
        Abort = {
            [CmdletBinding()] param([AllowNull()][object]$Handle)
            [void]$state.Aborted.Add($Handle.Uri)
        }.GetNewClosure()
    }
}

function New-ContractResult {
    <#
    .SYNOPSIS
    ページ契約結果（contract result）と同じ形のオブジェクトを作る。
    .PARAMETER Failures
    失敗させる確認項目。@{ name; severity('fatal'|'warning'); message } の配列。
    #>
    param(
        [Parameter(Mandatory)][string]$Scope,
        [hashtable[]]$Failures = @(),
        [hashtable]$Details = @{}
    )

    $checks = @()
    foreach ($failure in $Failures) {
        $severity = 'fatal'
        if ($failure.ContainsKey('severity')) { $severity = $failure.severity }
        $checks += [pscustomobject]@{ name = $failure.name; ok = $false; severity = $severity; message = [string]$failure.message; details = [pscustomobject]@{} }
    }
    $checks += [pscustomobject]@{ name = 'always.ok'; ok = $true; severity = 'fatal'; message = ''; details = [pscustomobject]@{} }

    $fatal = @($checks | Where-Object { -not $_.ok -and $_.severity -eq 'fatal' }).Count
    $warning = @($checks | Where-Object { -not $_.ok -and $_.severity -eq 'warning' }).Count

    return [pscustomobject]@{
        scope = $Scope
        ok = ($fatal -eq 0)
        fatalCount = $fatal
        warningCount = $warning
        checks = $checks
        details = [pscustomobject]$Details
    }
}


function New-ScriptedMember {
    param(
        [Parameter(Mandatory)][string]$PortName,
        [Parameter(Mandatory)][string]$MemberName,
        [string[]]$Parameters = @(),
        [AllowNull()][object]$Handler,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Calls
    )

    $parameterText = (@($Parameters | ForEach-Object { '$' + $_ }) -join ', ')
    $body = @"
[CmdletBinding()]
param($parameterText)
`$bound = @{}
foreach (`$key in `$PSBoundParameters.Keys) { `$bound[`$key] = `$PSBoundParameters[`$key] }
[void]`$Calls.Add([pscustomobject]@{ Port = `$PortName; Member = `$MemberName; Arguments = `$bound })
if (`$Handler -is [scriptblock]) { & `$Handler `$bound } else { `$Handler }
"@
    return [scriptblock]::Create($body).GetNewClosure()
}

function New-ScriptedPort {
    <#
    .SYNOPSIS
    形（メンバー名とパラメーター名）を宣言して、呼び出しを記録する偽のポートを作る。
    .PARAMETER Members
    メンバー名 → @{ Parameters = @('Path', ...); Result = <値> または { param($Bound) ... } }
    Result を省略すると $null を返す。
    .PARAMETER Calls
    複数のポートで共有する呼び出し記録（ポートをまたいだ順序を検証するときに渡す）。
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Members,
        [AllowNull()][AllowEmptyCollection()][System.Collections.ArrayList]$Calls = $null
    )

    if ($null -eq $Calls) { $Calls = New-Object System.Collections.ArrayList }
    $port = [ordered]@{ Calls = $Calls }
    foreach ($memberName in @($Members.Keys)) {
        $definition = $Members[$memberName]
        $parameters = @()
        $handler = $null
        if ($definition -is [hashtable]) {
            if ($definition.ContainsKey('Parameters')) { $parameters = @($definition.Parameters) }
            if ($definition.ContainsKey('Result')) { $handler = $definition.Result }
        }
        $port[$memberName] = New-ScriptedMember -PortName $Name -MemberName $memberName -Parameters $parameters -Handler $handler -Calls $Calls
    }

    return [pscustomobject]$port
}

function Get-PortCalls {
    <#
    .SYNOPSIS
    記録された呼び出しを「Port.Member」の文字列配列で返す（順序の検証用）。
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Calls,
        [string]$Port = ''
    )

    return @($Calls | Where-Object { [string]::IsNullOrEmpty($Port) -or $_.Port -eq $Port } | ForEach-Object { "$($_.Port).$($_.Member)" })
}

Export-ModuleMember -Function @(
    'Get-RepositoryPath',
    'New-CallRecorder',
    'New-ManualClock',
    'New-RecordingLog',
    'Get-LogMessages',
    'New-CategorizedTestException',
    'New-SimulatedPage',
    'New-FakeCdpTransport',
    'New-ContractResult',
    'New-ScriptedPort',
    'Get-PortCalls'
)
