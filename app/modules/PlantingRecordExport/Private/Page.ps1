# 画面操作を業務の名前で表すページポート。

$script:PlantingPageShape = @{
    Connect = @()
    UseDownloadDirectory = @('Path')
    Load = @()
    AssertScreen = @()
    AssertList = @()
    ReadTotalCount = @()
    ReadVisibleRows = @()
    ScrollToTop = @()
    ScrollDown = @()
    OpenDetail = @('RowId', 'PlotCode')
    WaitDetailFor = @('RowId', 'PlotCode')
    OpenPlantingTab = @()
    AssertPlantingTab = @()
    ReadDetailPlotCode = @()
    ClickPlantingCsv = @()
    CloseDetail = @()
    WaitDetailClosed = @('TimeoutSeconds')
}

function Wait-PlantingDetailFor {
    <#
    .SYNOPSIS
    区画詳細が「クリックした区画」を表示するまで待ち、その対応を契約として確認する。
      1. 一覧で選択中の行が、クリックした区画になる
      2. 区画詳細に、その区画コードが表示される
      3. 1 と 2 が同時に成り立つ（契約）
    #>
    param(
        [Parameter(Mandatory)][object]$Browser,
        [Parameter(Mandatory)][string]$RowId,
        [Parameter(Mandatory)][string]$PlotCode
    )

    $expectedRowId = $RowId
    $expectedPlotCode = $PlotCode
    $isClickedRow = {
        param($Value)
        return ($null -ne $Value -and $Value.ok -eq $true -and $Value.rowId -eq $expectedRowId -and $Value.plotCode -eq $expectedPlotCode)
    }.GetNewClosure()

    [void](& $Browser.WaitFor -Operation 'ReadSelectedRow' -Accept $isClickedRow -TimeoutSeconds 10)
    [void](& $Browser.WaitUntil -Operation 'IsDetailReadyFor' -Arguments @($PlotCode))
    return & $Browser.Assert -Operation 'CheckOpenedDetail' -Arguments @($RowId, $PlotCode) -Description "開いた区画詳細の契約: $PlotCode ($RowId)"
}

function New-PlantingPage {
    param([Parameter(Mandatory)][object]$Browser)

    $waitDetail = Get-Command -Name Wait-PlantingDetailFor -CommandType Function

    return [pscustomobject]@{
        Connect = { [CmdletBinding()] param() & $Browser.Connect }.GetNewClosure()
        UseDownloadDirectory = { [CmdletBinding()] param([Parameter(Mandatory)][string]$Path) & $Browser.SetDownloadDirectory -Path $Path }.GetNewClosure()
        Load = { [CmdletBinding()] param() & $Browser.Inject }.GetNewClosure()
        AssertScreen = { [CmdletBinding()] param() & $Browser.Assert -Operation 'CheckScreen' }.GetNewClosure()
        AssertList = { [CmdletBinding()] param() & $Browser.Assert -Operation 'CheckList' }.GetNewClosure()
        ReadTotalCount = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'ReadTotalCount' }.GetNewClosure()
        ReadVisibleRows = { [CmdletBinding()] param() @(& $Browser.Invoke -Operation 'ReadVisibleRows') }.GetNewClosure()
        ScrollToTop = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'ScrollToTop' }.GetNewClosure()
        ScrollDown = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'ScrollDown' }.GetNewClosure()
        OpenDetail = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$RowId, [Parameter(Mandatory)][string]$PlotCode)
            & $Browser.Invoke -Operation 'OpenDetail' -Arguments @($RowId, $PlotCode)
        }.GetNewClosure()
        WaitDetailFor = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$RowId, [Parameter(Mandatory)][string]$PlotCode)
            & $waitDetail -Browser $Browser -RowId $RowId -PlotCode $PlotCode
        }.GetNewClosure()
        OpenPlantingTab = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'OpenPlantingTab' }.GetNewClosure()
        AssertPlantingTab = { [CmdletBinding()] param() & $Browser.Assert -Operation 'CheckPlantingTab' }.GetNewClosure()
        ReadDetailPlotCode = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'ReadDetailPlotCode' }.GetNewClosure()
        ClickPlantingCsv = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'ClickPlantingCsv' }.GetNewClosure()
        CloseDetail = { [CmdletBinding()] param() & $Browser.Invoke -Operation 'CloseDetail' }.GetNewClosure()
        WaitDetailClosed = {
            [CmdletBinding()] param([Parameter(Mandatory)][int]$TimeoutSeconds)
            & $Browser.WaitUntil -Operation 'IsDetailClosed' -TimeoutSeconds $TimeoutSeconds
        }.GetNewClosure()
    }
}
