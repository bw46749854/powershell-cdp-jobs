# 画面操作を業務の名前で表すページポート。
# Flow は「どの操作カタログの操作をどう呼ぶか」を知らず、ここで付けた名前だけを使う。

$script:PlotRosterPageShape = @{
    Connect = @()
    UseDownloadDirectory = @('Path')
    Load = @()
    AssertInitialScreen = @()
    AssertExportScreen = @()
    OpenTaskMenu = @()
    WaitExportItemReady = @('TimeoutSeconds')
    ClickExportItem = @()
    AssertExportAccepted = @()
}

function New-PlotRosterPage {
    param([Parameter(Mandatory)][object]$Browser)

    return [pscustomobject]@{
        Connect = { [CmdletBinding()] param() & $Browser.Connect }.GetNewClosure()
        UseDownloadDirectory = { [CmdletBinding()] param([Parameter(Mandatory)][string]$Path) & $Browser.SetDownloadDirectory -Path $Path }.GetNewClosure()
        Load = { [CmdletBinding()] param() & $Browser.Inject }.GetNewClosure()
        AssertInitialScreen = { [CmdletBinding()] param() & $Browser.Assert -Operation 'CheckInitialScreen' }.GetNewClosure()
        AssertExportScreen = { [CmdletBinding()] param() & $Browser.Assert -Operation 'CheckExportScreen' }.GetNewClosure()
        OpenTaskMenu = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'OpenTaskMenu' }.GetNewClosure()
        WaitExportItemReady = {
            [CmdletBinding()] param([Parameter(Mandatory)][int]$TimeoutSeconds)
            & $Browser.WaitUntil -Operation 'IsExportItemReady' -TimeoutSeconds $TimeoutSeconds
        }.GetNewClosure()
        ClickExportItem = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'ClickExportItem' }.GetNewClosure()
        AssertExportAccepted = { [CmdletBinding()] param() & $Browser.Assert -Operation 'CheckExportAccepted' }.GetNewClosure()
    }
}
