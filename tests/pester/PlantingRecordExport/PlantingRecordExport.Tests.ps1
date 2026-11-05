BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/JobHost/JobHost.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/PlantingRecordExport/PlantingRecordExport.psm1') -Force

    function New-SimulatedLedgerPage {
        <#
        作付け台帳の偽物。ClickPlantingCsv で一時ディレクトリに planting_20260415.csv を作る（ブラウザのダウンロードの代わり）。
        .PARAMETER WrongDetailFor   区画詳細に別の区画コードを表示する区画
        .PARAMETER NoDownloadFor    CSV 出力してもファイルができない区画
        #>
        param(
            [Parameter(Mandatory)][string[]]$PlotCodes,
            [Parameter(Mandatory)][string]$TempDirectory,
            [int]$WindowSize = 2,
            [AllowNull()][object]$Total = -1,
            [string[]]$WrongDetailFor = @(),
            [string[]]$NoDownloadFor = @(),
            [System.Collections.ArrayList]$Calls = (New-CallRecorder)
        )

        if ($null -ne $Total -and $Total -lt 0) { $Total = $PlotCodes.Count }
        $state = [pscustomobject]@{ Offset = 0; Open = ''; Closes = 0 }

        $members = @{
            Connect = @{}; Load = @{}; AssertScreen = @{}; AssertList = @{}
            UseDownloadDirectory = @{ Parameters = @('Path') }
            ReadTotalCount = @{ Result = $Total }
            ReadVisibleRows = @{ Result = {
                    param($Bound)
                    $end = [Math]::Min($state.Offset + $WindowSize, $PlotCodes.Count)
                    for ($i = $state.Offset; $i -lt $end; $i++) { [pscustomobject]@{ rowId = "r-$i"; plotCode = $PlotCodes[$i] } }
                }.GetNewClosure() }
            ScrollToTop = @{ Result = { param($Bound) $state.Offset = 0 }.GetNewClosure() }
            ScrollDown = @{ Result = {
                    param($Bound)
                    $before = $state.Offset
                    if ($state.Offset + $WindowSize -lt $PlotCodes.Count) { $state.Offset++ }
                    [pscustomobject]@{ ok = $true; moved = ($state.Offset -ne $before) }
                }.GetNewClosure() }
            OpenDetail = @{ Parameters = @('RowId', 'PlotCode'); Result = { param($Bound) $state.Open = $Bound.PlotCode; [pscustomobject]@{ ok = $true } }.GetNewClosure() }
            WaitDetailFor = @{ Parameters = @('RowId', 'PlotCode') }
            OpenPlantingTab = @{ Result = [pscustomobject]@{ ok = $true; action = 'tab-clicked' } }
            AssertPlantingTab = @{ Result = (New-ContractResult -Scope 'plantingExport.plantingTab' -Details @{ scopeSource = 'tabpanel' }) }
            ReadDetailPlotCode = @{ Result = {
                    param($Bound)
                    if ($WrongDetailFor -contains $state.Open) { return 'GH9-Z99' }
                    return $state.Open
                }.GetNewClosure() }
            ClickPlantingCsv = @{ Result = {
                    param($Bound)
                    if ($NoDownloadFor -notcontains $state.Open) {
                        Set-Content -LiteralPath (Join-Path $TempDirectory 'planting_20260415.csv') -Value "作物名,品種,定植日`r`nトマト,桃太郎,2026-03-12" -Encoding UTF8
                    }
                    [pscustomobject]@{ ok = $true; action = 'csv-clicked' }
                }.GetNewClosure() }
            CloseDetail = @{ Result = { param($Bound) $state.Closes++; $state.Open = ''; [pscustomobject]@{ ok = $true; alreadyClosed = $false } }.GetNewClosure() }
            WaitDetailClosed = @{ Parameters = @('TimeoutSeconds'); Result = $true }
        }

        return [pscustomobject]@{ State = $state; Port = (New-ScriptedPort -Name 'Page' -Calls $Calls -Members $members) }
    }

    function New-PlantingTestPorts {
        param([Parameter(Mandatory)][object]$Page)

        $clock = New-ManualClock
        $log = New-RecordingLog
        $services = InModuleScope JobHost -Parameters @{ Clock = $clock; Log = $log } {
            param($Clock, $Log)
            [pscustomobject]@{
                Files = New-HostFileService
                Downloads = New-HostDownloadService -Clock $Clock
                Lists = New-HostListService -Clock $Clock -Log $Log
            }
        }

        return [pscustomobject]@{
            Log = $log
            Clock = $clock
            Files = $services.Files
            Downloads = $services.Downloads
            Lists = $services.Lists
            Page = $Page.Port
        }
    }

    function New-PlantingTestSettings {
        param([Parameter(Mandatory)][string]$Root)
        return [pscustomobject]@{
            TempDirectory = (Join-Path $Root 'tmp')
            DownloadDirectory = (Join-Path $Root 'downloads')
            DownloadFilePrefix = 'planting_'
            FailureCsvFileName = 'planting_export_failures.csv'
            DownloadTimeoutSeconds = 5
            DownloadStableSeconds = 1
            DetailCloseWaitSeconds = 3
            MaxScanLoops = 50
            StallLimit = 2
        }
    }

    function Invoke-PlantingTestFlow {
        param([Parameter(Mandatory)][object]$Ports, [Parameter(Mandatory)][object]$Settings)
        InModuleScope PlantingRecordExport -Parameters @{ Ports = $Ports; Settings = $Settings } {
            param($Ports, $Settings)
            Assert-PlantingExportPorts -Ports $Ports
            Invoke-PlantingExportFlow -Ports $Ports -Settings $Settings
        }
    }
}

Describe 'Planting record names' {
    It 'appends the plot code after removing the browser duplicate number' {
        InModuleScope PlantingRecordExport {
            Get-PlantingRecordFileName -DownloadedName 'planting_20260415.csv' -PlotCode 'GH2-B01' | Should -Be 'planting_20260415_GH2-B01.csv'
            Get-PlantingRecordFileName -DownloadedName 'planting_20260415 (3).csv' -PlotCode 'GH2-B01' | Should -Be 'planting_20260415_GH2-B01.csv'
            Get-PlantingRecordFileName -DownloadedName 'planting_20260415.csv' -PlotCode "GH2 B01/x`u{3000}" | Should -Be 'planting_20260415_GH2_B01_x.csv'
        }
    }

    It 'builds row keys only from rows that have both identifiers' {
        InModuleScope PlantingRecordExport {
            Get-PlantingRowKey -Row ([pscustomobject]@{ rowId = 'r-1'; plotCode = 'GH2-B01' }) | Should -Be 'r-1|GH2-B01'
            Get-PlantingRowKey -Row ([pscustomobject]@{ rowId = ''; plotCode = 'GH2-B01' }) | Should -Be ''
            Get-PlantingRowKey -Row ([pscustomobject]@{ rowId = 'r-1' }) | Should -Be ''
        }
    }
}

Describe 'Invoke-PlantingExportFlow' {
    It 'saves one CSV per plot with the plot code in its name and closes every detail' {
        $root = Join-Path $TestDrive 'happy'
        $settings = New-PlantingTestSettings -Root $root
        New-Item -ItemType Directory -Path $settings.TempDirectory -Force | Out-Null
        $page = New-SimulatedLedgerPage -PlotCodes @('GH2-B01', 'GH2-B02', 'GH2-B03') -TempDirectory $settings.TempDirectory
        $ports = New-PlantingTestPorts -Page $page

        $outcome = Invoke-PlantingTestFlow -Ports $ports -Settings $settings

        @($outcome.Successes | ForEach-Object { Split-Path -Leaf $_.CsvPath }) | Should -Be @('planting_20260415_GH2-B01.csv', 'planting_20260415_GH2-B02.csv', 'planting_20260415_GH2-B03.csv')
        $outcome.Traversal.StopReason | Should -Be 'expected-count'
        Test-Path -LiteralPath (Join-Path $settings.DownloadDirectory 'planting_export_failures.csv') | Should -BeFalse
        $page.State.Closes | Should -Be 4 -Because 'the detail is closed once before the scan and after every plot'
        @(Get-ChildItem -LiteralPath $settings.TempDirectory).Count | Should -Be 0
    }

    It 'records a plot whose detail shows another plot as a failure and keeps going' {
        $root = Join-Path $TestDrive 'wrong-detail'
        $settings = New-PlantingTestSettings -Root $root
        New-Item -ItemType Directory -Path $settings.TempDirectory -Force | Out-Null
        $page = New-SimulatedLedgerPage -PlotCodes @('GH2-B01', 'GH2-B02', 'GH2-B03') -TempDirectory $settings.TempDirectory -WrongDetailFor @('GH2-B02')
        $ports = New-PlantingTestPorts -Page $page

        { Invoke-PlantingTestFlow -Ports $ports -Settings $settings } | Should -Throw '*失敗した区画が 1 件*'

        $failures = @(Import-Csv -LiteralPath (Join-Path $settings.DownloadDirectory 'planting_export_failures.csv') -Encoding UTF8)
        $failures.Count | Should -Be 1
        $failures[0].PlotCode | Should -Be 'GH2-B02'
        $failures[0].Reason | Should -Match '対象=GH2-B02 表示=GH9-Z99'
        $failures[0].Timestamp | Should -Match '^2026-04-15 09:\d{2}:\d{2}$'
        @(Get-ChildItem -LiteralPath $settings.DownloadDirectory -Filter 'planting_2026*.csv').Count | Should -Be 2
        $page.State.Closes | Should -Be 4
    }

    It 'records a plot whose download never completes and keeps going' {
        $root = Join-Path $TestDrive 'no-download'
        $settings = New-PlantingTestSettings -Root $root
        New-Item -ItemType Directory -Path $settings.TempDirectory -Force | Out-Null
        $page = New-SimulatedLedgerPage -PlotCodes @('GH2-B01', 'GH2-B02') -TempDirectory $settings.TempDirectory -NoDownloadFor @('GH2-B01')
        $ports = New-PlantingTestPorts -Page $page

        { Invoke-PlantingTestFlow -Ports $ports -Settings $settings } | Should -Throw '*失敗した区画が 1 件*'

        (Import-Csv -LiteralPath (Join-Path $settings.DownloadDirectory 'planting_export_failures.csv') -Encoding UTF8)[0].Reason | Should -Match 'ダウンロードの完了を確認できませんでした'
    }

    It 'stops before the scan when the list count cannot be read' {
        $root = Join-Path $TestDrive 'no-total'
        $settings = New-PlantingTestSettings -Root $root
        $page = New-SimulatedLedgerPage -PlotCodes @('GH2-B01') -TempDirectory $settings.TempDirectory -Total $null
        $ports = New-PlantingTestPorts -Page $page

        { Invoke-PlantingTestFlow -Ports $ports -Settings $settings } | Should -Throw '*件数を読めません*'
        (Get-PortCalls -Calls $page.Port.Calls) | Should -Not -Contain 'Page.OpenDetail'
    }

    It 'fails when the list ends before the expected number of plots was processed' {
        $root = Join-Path $TestDrive 'short-list'
        $settings = New-PlantingTestSettings -Root $root
        New-Item -ItemType Directory -Path $settings.TempDirectory -Force | Out-Null
        $page = New-SimulatedLedgerPage -PlotCodes @('GH2-B01', 'GH2-B02') -TempDirectory $settings.TempDirectory -Total 3
        $ports = New-PlantingTestPorts -Page $page

        { Invoke-PlantingTestFlow -Ports $ports -Settings $settings } | Should -Throw '*一覧の件数 3 件に対して、処理できたのは 2 件*end-of-list*'
    }

    It 'treats a detail that cannot be closed as a warning, not a failure' {
        $root = Join-Path $TestDrive 'close-warning'
        $settings = New-PlantingTestSettings -Root $root
        New-Item -ItemType Directory -Path $settings.TempDirectory -Force | Out-Null
        $page = New-SimulatedLedgerPage -PlotCodes @('GH2-B01') -TempDirectory $settings.TempDirectory
        $page.Port.CloseDetail = { [CmdletBinding()] param() [pscustomobject]@{ ok = $false; severity = 'warning'; reason = 'close_button_not_unique' } }
        $ports = New-PlantingTestPorts -Page $page

        $outcome = Invoke-PlantingTestFlow -Ports $ports -Settings $settings

        @($outcome.Successes).Count | Should -Be 1
        (Get-LogMessages -Log $ports.Log -Level Warn) -join "`n" | Should -Match 'close_button_not_unique'
    }
}

Describe 'Planting page port' {
    It 'waits for the clicked row, then the detail, then checks their correspondence' {
        $calls = New-CallRecorder
        $browser = New-ScriptedPort -Name 'Browser' -Calls $calls -Members @{
            WaitFor = @{ Parameters = @('Operation', 'Arguments', 'Accept', 'TimeoutSeconds', 'Description') }
            WaitUntil = @{ Parameters = @('Operation', 'Arguments', 'TimeoutSeconds', 'Description') }
            Assert = @{ Parameters = @('Operation', 'Arguments', 'TimeoutSeconds', 'Description'); Result = 'contract' }
        }

        InModuleScope PlantingRecordExport -Parameters @{ Browser = $browser } {
            param($Browser)
            $page = New-PlantingPage -Browser $Browser
            & $page.WaitDetailFor -RowId 'r-1' -PlotCode 'GH2-B01' | Should -Be 'contract'
        }

        @($calls | ForEach-Object { "$($_.Member):$($_.Arguments.Operation)" }) | Should -Be @('WaitFor:ReadSelectedRow', 'WaitUntil:IsDetailReadyFor', 'Assert:CheckOpenedDetail')
        $accept = $calls[0].Arguments.Accept
        & $accept ([pscustomobject]@{ ok = $true; rowId = 'r-1'; plotCode = 'GH2-B01' }) | Should -BeTrue
        & $accept ([pscustomobject]@{ ok = $true; rowId = 'r-2'; plotCode = 'GH2-B01' }) | Should -BeFalse
        & $accept ([pscustomobject]@{ ok = $false; count = 0 }) | Should -BeFalse
        @($calls[2].Arguments.Arguments) | Should -Be @('r-1', 'GH2-B01')
    }

    It 'has an operation catalog that PageBridge accepts' {
        Import-Module (Get-RepositoryPath 'app/modules/PageBridge/PageBridge.psm1') -Force
        $catalog = Import-PageOperationCatalog -Path (Get-RepositoryPath 'app/modules/PlantingRecordExport/PageOperations.psd1')
        $catalog.Helper | Should -Be 'plantingRecordExport'
        $catalog.Operations.CloseDetail.Kind | Should -Be 'Cleanup'
    }
}

Describe 'Invoke-PlantingRecordExportJob' {
    It 'returns the saved CSV paths and counts through the job result' {
        $root = Join-Path $TestDrive 'job'
        $settings = New-PlantingTestSettings -Root $root
        New-Item -ItemType Directory -Path $settings.TempDirectory -Force | Out-Null
        $page = New-SimulatedLedgerPage -PlotCodes @('GH2-B01', 'GH2-B02') -TempDirectory $settings.TempDirectory
        $ports = New-PlantingTestPorts -Page $page
        $jobSettings = @{}
        foreach ($property in $settings.PSObject.Properties) { $jobSettings[$property.Name] = $property.Value }
        $context = [pscustomobject]@{
            Settings = $jobSettings
            Services = [pscustomobject]@{ Log = $ports.Log; Clock = $ports.Clock; Files = $ports.Files; Downloads = $ports.Downloads; Lists = $ports.Lists; Browser = [pscustomobject]@{} }
        }

        InModuleScope PlantingRecordExport -Parameters @{ Context = $context; Page = $page.Port } {
            param($Context, $Page)
            Mock New-PlantingPage { $Page }
            $result = Invoke-PlantingRecordExportJob -Context $Context
            $result.Summary.Succeeded | Should -Be 2
            $result.Summary.Total | Should -Be 2
            @($result.Outputs.ExportedCsvPaths).Count | Should -Be 2
            $result.Outputs.DownloadDirectory | Should -Be $Context.Settings.DownloadDirectory
        }
    }
}
