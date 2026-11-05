# Log サービス。
#
#   Info / Warn / Error  -Message      1行のログ
#   Section              -Title        区切り線付きの見出し
#   Data                 -Label -Data  オブジェクトを JSON で残す（ページ操作の結果など、調査用）
#
# 出力先（sink）はコンソールと、設定で有効にした場合のファイル。
# 設定（Common.Logging）: Level（Debug / Info / Warning / Error）、Console、File、Directory。

$script:HostLogLevels = @{ Debug = 0; Info = 1; Warning = 2; Error = 3 }

$script:HostLogShape = @{
    Info = @('Message')
    Warn = @('Message')
    Error = @('Message')
    Section = @('Title')
    Data = @('Label', 'Data')
}

function Read-HostLogSettings {
    param([AllowNull()][object]$Logging)

    if ($null -eq $Logging) { $Logging = @{} }
    if (-not ($Logging -is [hashtable])) { throw '設定 Common.Logging は hashtable で指定してください。' }

    $level = [string](Get-PropertyValue -InputObject $Logging -Name 'Level' -Default 'Info')
    if (-not $script:HostLogLevels.ContainsKey($level)) {
        throw "設定 Common.Logging.Level は Debug / Info / Warning / Error のいずれかで指定してください（実際: $level）。"
    }

    $console = Get-PropertyValue -InputObject $Logging -Name 'Console' -Default $true
    $file = Get-PropertyValue -InputObject $Logging -Name 'File' -Default $false
    if (-not ($console -is [bool]) -or -not ($file -is [bool])) {
        throw '設定 Common.Logging.Console / File は $true / $false で指定してください。'
    }

    $directory = [string](Get-PropertyValue -InputObject $Logging -Name 'Directory' -Default '')
    if ($file -and [string]::IsNullOrWhiteSpace($directory)) {
        throw '設定 Common.Logging.File が $true のときは Common.Logging.Directory が必要です。'
    }

    return [pscustomobject]@{ Level = $level; Console = $console; File = $file; Directory = $directory }
}

function New-HostConsoleWriter {
    <#
    .SYNOPSIS
    コンソールへの書き出し口。Write-Host を使う唯一の場所（テストでは記録用の writer に差し替える）。
    #>
    return {
        param([string]$Level, [string]$Line)
        $color = switch ($Level) {
            'Warning' { 'Yellow' }
            'Error' { 'Red' }
            default { $null }
        }
        if ($color) { Write-Host $Line -ForegroundColor $color } else { Write-Host $Line }
    }
}

function Format-HostLogLine {
    param(
        [Parameter(Mandatory)][datetime]$Time,
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RunId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message
    )

    return ('[{0}] [{1,-7}] [{2}] {3}' -f $Time.ToString('yyyy-MM-dd HH:mm:ss'), $Level.ToUpperInvariant(), $RunId, $Message)
}

function Write-HostLogEntry {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][ValidateSet('Debug', 'Info', 'Warning', 'Error')][string]$Level,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message
    )

    if ($script:HostLogLevels[$Level] -lt $script:HostLogLevels[$State.Settings.Level]) { return }

    $now = & (Get-PortMember -Port $State.Clock -PortName 'Clock' -Member 'Now')
    $line = Format-HostLogLine -Time $now -Level $Level -RunId $State.RunId -Message $Message

    if ($State.Settings.Console) {
        & $State.ConsoleWriter $Level $line
    }

    if ($State.FilePath) {
        [System.IO.File]::AppendAllText($State.FilePath, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
    }
}

function Write-HostLogSection {
    param([Parameter(Mandatory)][object]$State, [Parameter(Mandatory)][string]$Title)

    Write-HostLogEntry -State $State -Level Info -Message ''
    Write-HostLogEntry -State $State -Level Info -Message ('=' * 60)
    Write-HostLogEntry -State $State -Level Info -Message $Title
    Write-HostLogEntry -State $State -Level Info -Message ('=' * 60)
}

function Write-HostLogData {
    param([Parameter(Mandatory)][object]$State, [AllowEmptyString()][string]$Label, [AllowNull()][object]$Data)

    $json = ConvertTo-Json -InputObject $Data -Depth 8 -Compress
    $prefix = if ([string]::IsNullOrWhiteSpace($Label)) { '' } else { "$Label " }
    Write-HostLogEntry -State $State -Level Info -Message ($prefix + $json)
}

function New-HostLog {
    <#
    .SYNOPSIS
    Log サービスを作る。ファイル出力が有効なら <Directory>/<JobName>_<RunId>.log に追記する。
    .PARAMETER ConsoleWriter
    param($Level, $Line) の scriptblock。省略時は Write-Host。
    #>
    param(
        [AllowNull()][object]$Logging,
        [Parameter(Mandatory)][string]$JobName,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][object]$Clock,
        [AllowNull()][scriptblock]$ConsoleWriter = $null
    )

    $settings = Read-HostLogSettings -Logging $Logging
    if ($null -eq $ConsoleWriter) { $ConsoleWriter = New-HostConsoleWriter }

    $filePath = $null
    if ($settings.File) {
        $directory = Initialize-SafeDirectory -Path $settings.Directory -Purpose 'ログ'
        $filePath = Join-Path $directory ('{0}_{1}.log' -f $JobName, $RunId)
    }

    $state = [pscustomobject]@{
        Settings = $settings
        RunId = $RunId
        Clock = $Clock
        ConsoleWriter = $ConsoleWriter
        FilePath = $filePath
    }

    $writeEntry = Get-Command -Name Write-HostLogEntry -CommandType Function
    $writeSection = Get-Command -Name Write-HostLogSection -CommandType Function
    $writeData = Get-Command -Name Write-HostLogData -CommandType Function

    return [pscustomobject]@{
        FilePath = $filePath
        Info = { [CmdletBinding()] param([AllowEmptyString()][string]$Message = '') & $writeEntry -State $state -Level Info -Message $Message }.GetNewClosure()
        Warn = { [CmdletBinding()] param([AllowEmptyString()][string]$Message = '') & $writeEntry -State $state -Level Warning -Message $Message }.GetNewClosure()
        Error = { [CmdletBinding()] param([AllowEmptyString()][string]$Message = '') & $writeEntry -State $state -Level Error -Message $Message }.GetNewClosure()
        Section = { [CmdletBinding()] param([Parameter(Mandatory)][string]$Title) & $writeSection -State $state -Title $Title }.GetNewClosure()
        Data = { [CmdletBinding()] param([AllowEmptyString()][string]$Label = '', [AllowNull()][object]$Data) & $writeData -State $state -Label $Label -Data $Data }.GetNewClosure()
    }
}
