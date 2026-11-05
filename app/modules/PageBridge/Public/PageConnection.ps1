# PageBridge の公開窓口。実行基盤（JobHost）だけが使う。各ジョブはこれを直接呼ばない。

$script:BridgeLogShape = @{
    Info = @('Message')
    Warn = @('Message')
}

function Test-PageTargetIdentity {
    <#
    .SYNOPSIS
    1つのタブに一時的に接続し、スクリプトを注入して画面識別を実行する。
    .DESCRIPTION
    接続前の失敗は stage=connect、接続後の失敗は stage=identify として例外に印を付ける
    （Select-IdentifiedPageTarget が続行可否を判断するため）。
    #>
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][object]$Context
    )

    try {
        $session = Open-CdpSession `
            -Transport $Context.Transport `
            -WebSocketUrl ([string]$Target.webSocketDebuggerUrl) `
            -ConnectTimeoutSeconds $Context.ConnectTimeoutSeconds `
            -CommandTimeoutSeconds $Context.CommandTimeoutSeconds `
            -Clock $Context.Clock
    }
    catch {
        $_.Exception.Data['pagebridge.probe.stage'] = 'connect'
        throw
    }

    try {
        $state = New-PageGatewayState -Session $session -Catalog $Context.Catalog -ScriptPaths $Context.ScriptPaths -JobName $Context.JobName -Log $Context.Log
        [void](Invoke-PageBundleInjection -State $state)
        $identity = Invoke-PageOperation -State $state -Operation $Context.Catalog.IdentityOperation

        if ($identity.ok -eq $true) {
            return [pscustomobject]@{ Matched = $true; Reason = '画面識別に一致しました。' }
        }

        $failed = @($identity.checks | Where-Object { $_.ok -ne $true -and $_.severity -eq 'fatal' } | ForEach-Object { $_.name })
        return [pscustomobject]@{ Matched = $false; Reason = "画面識別に一致しません（fatal: $($failed -join ', ')）。" }
    }
    catch {
        $_.Exception.Data['pagebridge.probe.stage'] = 'identify'
        throw
    }
    finally {
        Close-CdpSession -Session $session
    }
}

function Open-PageConnection {
    <#
    .SYNOPSIS
    ジョブの画面識別に一致するタブを1つ選んで接続し、接続オブジェクトを返す。
    .OUTPUTS
    Session / Target（Title, Url） / Gateway（Inject, Invoke, WaitUntil, WaitFor, Assert）
    .PARAMETER Transport
    省略時は実ブラウザ用（New-CdpTransport）。テストでは偽物を渡す。
    .PARAMETER Clock
    省略時は実時間。テストでは偽物の時計を渡す。
    #>
    param(
        [Parameter(Mandatory)][string]$DebuggerUrl,
        [Parameter(Mandatory)][int]$ConnectTimeoutSeconds,
        [Parameter(Mandatory)][int]$CommandTimeoutSeconds,
        [Parameter(Mandatory)][object]$Catalog,
        [Parameter(Mandatory)][string[]]$ScriptPaths,
        [Parameter(Mandatory)][string]$JobName,
        [Parameter(Mandatory)][object]$Log,
        [AllowNull()][object]$Transport = $null,
        [AllowNull()][object]$Clock = $null
    )

    if ($null -eq $Transport) { $Transport = New-CdpTransport }
    if ($null -eq $Clock) { $Clock = New-BridgeSystemClock }
    Assert-PortShape -Port $Transport -PortName 'CdpTransport' -Members $script:CdpTransportShape
    Assert-PortShape -Port $Clock -PortName 'Clock' -Members $script:BridgeClockShape
    Assert-PortShape -Port $Log -PortName 'Log' -Members $script:BridgeLogShape

    $probeContext = [pscustomobject]@{
        Transport = $Transport
        Clock = $Clock
        Catalog = $Catalog
        ScriptPaths = $ScriptPaths
        JobName = $JobName
        Log = $Log
        ConnectTimeoutSeconds = $ConnectTimeoutSeconds
        CommandTimeoutSeconds = $CommandTimeoutSeconds
    }
    $identify = Get-Command -Name Test-PageTargetIdentity -CommandType Function
    $probe = {
        param($Target)
        & $identify -Target $Target -Context $probeContext
    }.GetNewClosure()

    $targets = @(Get-CdpPageTargets -Transport $Transport -DebuggerUrl $DebuggerUrl)
    $target = Select-IdentifiedPageTarget -Targets $targets -Probe $probe -Log $Log

    $session = Open-CdpSession `
        -Transport $Transport `
        -WebSocketUrl ([string]$target.webSocketDebuggerUrl) `
        -ConnectTimeoutSeconds $ConnectTimeoutSeconds `
        -CommandTimeoutSeconds $CommandTimeoutSeconds `
        -Clock $Clock

    $state = New-PageGatewayState -Session $session -Catalog $Catalog -ScriptPaths $ScriptPaths -JobName $JobName -Log $Log
    $title = [string](Get-PropertyValue -InputObject $target -Name 'title' -Default '')
    $url = [string](Get-PropertyValue -InputObject $target -Name 'url' -Default '')

    $info = Get-PortMember -Port $Log -PortName 'Log' -Member 'Info'
    & $info -Message "操作対象のタブ: $title <$url>"

    return [pscustomobject]@{
        Session = $session
        Target = [pscustomobject]@{ Title = $title; Url = $url }
        Gateway = New-PageGateway -State $state
        Log = $Log
    }
}

function Close-PageConnection {
    <#
    .SYNOPSIS
    接続を閉じる。何度呼んでもよい。
    #>
    param([AllowNull()][object]$Connection)

    if ($null -eq $Connection) { return }
    Close-CdpSession -Session $Connection.Session
}

function Set-PageDownloadDirectory {
    <#
    .SYNOPSIS
    接続中のタブのダウンロード先を設定する（ディレクトリは呼び出し側が作成済みであること）。
    #>
    param(
        [Parameter(Mandatory)][object]$Connection,
        [Parameter(Mandatory)][string]$Directory
    )

    $method = Set-CdpDownloadBehavior -Session $Connection.Session -Directory $Directory -Log $Connection.Log
    $info = Get-PortMember -Port $Connection.Log -PortName 'Log' -Member 'Info'
    & $info -Message "ブラウザのダウンロード先を設定しました（$method）: $Directory"
}

function Test-PageBridgeFatalError {
    <#
    .SYNOPSIS
    ブラウザとの通信を続けられない種類のエラーかを返す（セッション切断・通信タイムアウト・ヘルパー消失など）。
    #>
    param([AllowNull()][object]$ErrorObject)

    return (Test-BridgeFatalCategory -Category (Get-BridgeErrorCategory -ErrorObject $ErrorObject))
}
