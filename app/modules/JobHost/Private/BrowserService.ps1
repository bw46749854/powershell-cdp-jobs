# Browser サービス: ブラウザを使うジョブだけに渡す、そのジョブの操作カタログに束縛された窓口。
#
#   Connect                 画面識別に一致するタブを1つ選んで接続する（接続済みなら張り直す）
#   SetDownloadDirectory    -Path
#   Inject                  ページスクリプトを注入する
#   Invoke / WaitUntil / WaitFor / Assert   操作カタログ経由の呼び出し（PageBridge のゲートウェイ）
#   IsFatal                 -ErrorObject   ブラウザとの通信を続けられないエラーか
#   Close                   切断する（何度呼んでもよい）
#
# 設定（Common.Browser）: DebuggerUrl、ConnectTimeoutSeconds、CommandTimeoutSeconds。

$script:HostBrowserShape = @{
    Connect = @()
    SetDownloadDirectory = @('Path')
    Inject = @()
    Invoke = @('Operation', 'Arguments', 'TimeoutSeconds')
    WaitUntil = @('Operation', 'Arguments', 'TimeoutSeconds', 'Description')
    WaitFor = @('Operation', 'Arguments', 'Accept', 'TimeoutSeconds', 'Description')
    Assert = @('Operation', 'Arguments', 'TimeoutSeconds', 'Description')
    IsFatal = @('ErrorObject')
    Close = @()
}

function Read-HostBrowserSettings {
    param([AllowNull()][object]$Common)

    $browser = Get-PropertyValue -InputObject $Common -Name 'Browser'
    if (-not ($browser -is [hashtable])) {
        throw '設定 Common.Browser（DebuggerUrl / ConnectTimeoutSeconds / CommandTimeoutSeconds）がありません。'
    }

    return [pscustomobject]@{
        DebuggerUrl = Read-JobSetting -Settings $browser -Name 'DebuggerUrl' -Kind Text -Scope 'Common.Browser'
        ConnectTimeoutSeconds = Read-JobSetting -Settings $browser -Name 'ConnectTimeoutSeconds' -Kind Integer -Minimum 1 -Scope 'Common.Browser'
        CommandTimeoutSeconds = Read-JobSetting -Settings $browser -Name 'CommandTimeoutSeconds' -Kind Integer -Minimum 1 -Scope 'Common.Browser'
    }
}

function Get-HostBrowserGateway {
    param([Parameter(Mandatory)][object]$State)

    if ($null -eq $State.Connection) {
        throw 'ブラウザに接続していません。先に Connect を呼んでください。'
    }

    return $State.Connection.Gateway
}

function Connect-HostBrowser {
    param([Parameter(Mandatory)][object]$State)

    Close-HostBrowser -State $State
    $State.Connection = Open-PageConnection `
        -DebuggerUrl $State.Settings.DebuggerUrl `
        -ConnectTimeoutSeconds $State.Settings.ConnectTimeoutSeconds `
        -CommandTimeoutSeconds $State.Settings.CommandTimeoutSeconds `
        -Catalog $State.Catalog `
        -ScriptPaths $State.Entry.Scripts `
        -JobName $State.Entry.Name `
        -Log $State.Log `
        -Transport $State.Transport `
        -Clock $State.Clock

    return $State.Connection.Target
}

function Close-HostBrowser {
    param([Parameter(Mandatory)][object]$State)

    if ($null -ne $State.Connection) {
        Close-PageConnection -Connection $State.Connection
        $State.Connection = $null
    }
}

function Invoke-HostBrowserGateway {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][ValidateSet('Inject', 'Invoke', 'WaitUntil', 'WaitFor', 'Assert')][string]$Member,
        [hashtable]$Parameters = @{}
    )

    $gateway = Get-HostBrowserGateway -State $State
    $call = Get-PortMember -Port $gateway -PortName 'PageGateway' -Member $Member
    return & $call @Parameters
}

function New-HostBrowserService {
    <#
    .PARAMETER Transport
    省略時は実ブラウザ。テストでは偽の CDP トランスポートを渡す。
    #>
    param(
        [Parameter(Mandatory)][object]$Common,
        [Parameter(Mandatory)][object]$Entry,
        [Parameter(Mandatory)][object]$Log,
        [Parameter(Mandatory)][object]$Clock,
        [AllowNull()][object]$Transport = $null
    )

    $state = [pscustomobject]@{
        Settings = Read-HostBrowserSettings -Common $Common
        Entry = $Entry
        Catalog = Import-PageOperationCatalog -Path $Entry.Operations
        Log = $Log
        Clock = $Clock
        Transport = $Transport
        Connection = $null
    }

    $connect = Get-Command -Name Connect-HostBrowser -CommandType Function
    $close = Get-Command -Name Close-HostBrowser -CommandType Function
    $gateway = Get-Command -Name Invoke-HostBrowserGateway -CommandType Function
    $setDownload = Get-Command -Name Set-PageDownloadDirectory -CommandType Function
    $isFatal = Get-Command -Name Test-PageBridgeFatalError -CommandType Function
    $requireGateway = Get-Command -Name Get-HostBrowserGateway -CommandType Function

    return [pscustomobject]@{
        Connect = {
            [CmdletBinding()] param()
            & $connect -State $state
        }.GetNewClosure()
        SetDownloadDirectory = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
            [void](& $requireGateway -State $state)
            & $setDownload -Connection $state.Connection -Directory $Path
        }.GetNewClosure()
        Inject = {
            [CmdletBinding()] param()
            & $gateway -State $state -Member 'Inject'
        }.GetNewClosure()
        Invoke = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Operation, [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(), [int]$TimeoutSeconds = 0)
            & $gateway -State $state -Member 'Invoke' -Parameters @{ Operation = $Operation; Arguments = $Arguments; TimeoutSeconds = $TimeoutSeconds }
        }.GetNewClosure()
        WaitUntil = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Operation, [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(), [int]$TimeoutSeconds = 0, [AllowEmptyString()][string]$Description = '')
            & $gateway -State $state -Member 'WaitUntil' -Parameters @{ Operation = $Operation; Arguments = $Arguments; TimeoutSeconds = $TimeoutSeconds; Description = $Description }
        }.GetNewClosure()
        WaitFor = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Operation, [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(), [Parameter(Mandatory)][scriptblock]$Accept, [int]$TimeoutSeconds = 0, [AllowEmptyString()][string]$Description = '')
            & $gateway -State $state -Member 'WaitFor' -Parameters @{ Operation = $Operation; Arguments = $Arguments; Accept = $Accept; TimeoutSeconds = $TimeoutSeconds; Description = $Description }
        }.GetNewClosure()
        Assert = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Operation, [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @(), [int]$TimeoutSeconds = 0, [AllowEmptyString()][string]$Description = '')
            & $gateway -State $state -Member 'Assert' -Parameters @{ Operation = $Operation; Arguments = $Arguments; TimeoutSeconds = $TimeoutSeconds; Description = $Description }
        }.GetNewClosure()
        IsFatal = {
            [CmdletBinding()] param([AllowNull()][object]$ErrorObject)
            & $isFatal -ErrorObject $ErrorObject
        }.GetNewClosure()
        Close = {
            [CmdletBinding()] param()
            & $close -State $state
        }.GetNewClosure()
    }
}
