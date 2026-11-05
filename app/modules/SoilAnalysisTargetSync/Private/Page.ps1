# 画面操作を業務の名前で表すページポート。
# 「土壌分析を依頼」をクリックする操作は、操作カタログにもこのポートにも存在しない（存在させない）。

$script:SoilAnalysisPageShape = @{
    Connect = @()
    Load = @()
    AssertScreen = @()
    AssertList = @()
    PrepareScope = @()
    ReadVisibleRows = @()
    SyncSelection = @('PlotCode', 'Desired')
    AssertAnalysisMenuEnabled = @()
    ScrollToTop = @()
    ScrollDown = @()
    IsFatal = @('ErrorObject')
}

function New-SoilAnalysisPage {
    param([Parameter(Mandatory)][object]$Browser)

    return [pscustomobject]@{
        Connect = { [CmdletBinding()] param() & $Browser.Connect }.GetNewClosure()
        Load = { [CmdletBinding()] param() & $Browser.Inject }.GetNewClosure()
        AssertScreen = { [CmdletBinding()] param() & $Browser.Assert -Operation 'CheckScreen' -TimeoutSeconds 30 }.GetNewClosure()
        AssertList = { [CmdletBinding()] param() & $Browser.Assert -Operation 'CheckList' -TimeoutSeconds 30 }.GetNewClosure()
        PrepareScope = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'PrepareScope' }.GetNewClosure()
        ReadVisibleRows = { [CmdletBinding()] param() @(& $Browser.Invoke -Operation 'ReadVisibleRows') }.GetNewClosure()
        SyncSelection = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$PlotCode, [Parameter(Mandatory)][bool]$Desired)
            & $Browser.Invoke -Operation 'SyncSelection' -Arguments @($PlotCode, $Desired)
        }.GetNewClosure()
        AssertAnalysisMenuEnabled = { [CmdletBinding()] param() & $Browser.Assert -Operation 'CheckAnalysisMenu' -TimeoutSeconds 10 }.GetNewClosure()
        ScrollToTop = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'ScrollToTop' }.GetNewClosure()
        ScrollDown = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'ScrollDown' }.GetNewClosure()
        IsFatal = { [CmdletBinding()] param([AllowNull()][object]$ErrorObject) & $Browser.IsFatal -ErrorObject $ErrorObject }.GetNewClosure()
    }
}
