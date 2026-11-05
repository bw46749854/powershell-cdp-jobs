BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/SoilAnalysisTargetSync/SoilAnalysisTargetSync.psm1') -Force

    $script:Header = '区画コード,担当者,稼働状態,最終計測日時,土壌分析の依頼,土壌分析の完了'

    function New-CsvText {
        param([string[]]$Lines)
        return (@($script:Header) + $Lines) -join "`r`n"
    }

    function New-SimulatedList {
        <#
        仮想スクロールする一覧の偽物。WindowSize 行ずつ表示し、ScrollDown で1行ずつ進む。
        #>
        param(
            [string[]]$PlotCodes,
            [string[]]$Selected = @(),
            [int]$WindowSize = 2,
            [hashtable]$FailFor = @{},
            [string[]]$FatalFor = @(),
            [int]$Count = -1
        )

        if ($Count -lt 0) { $Count = $PlotCodes.Count }
        $state = [pscustomobject]@{ Offset = 0; Selected = @{}; Synced = (New-CallRecorder) }
        foreach ($code in $Selected) { $state.Selected[$code] = $true }

        $members = @{
            Connect = @{}; Load = @{}; ScrollToTop = @{ Result = { param($Bound) $state.Offset = 0; [pscustomobject]@{ ok = $true } }.GetNewClosure() }
            AssertScreen = @{ Result = (New-ContractResult -Scope 'soilAnalysisSync.screen') }
            AssertList = @{ Result = (New-ContractResult -Scope 'soilAnalysisSync.list' -Details @{ plotCount = $Count }) }
            PrepareScope = @{ Result = [pscustomobject]@{ ok = $true; reason = 'single_valid_pinned_pane' } }
            ReadVisibleRows = @{ Result = {
                    param($Bound)
                    $end = [Math]::Min($state.Offset + $WindowSize, $PlotCodes.Count)
                    for ($i = $state.Offset; $i -lt $end; $i++) {
                        [pscustomobject]@{ plotCode = $PlotCodes[$i]; rowId = "p$i"; effectiveChecked = $state.Selected.ContainsKey($PlotCodes[$i]) }
                    }
                }.GetNewClosure() }
            ScrollDown = @{ Result = {
                    param($Bound)
                    $before = $state.Offset
                    if ($state.Offset + $WindowSize -lt $PlotCodes.Count) { $state.Offset++ }
                    [pscustomobject]@{ ok = $true; changed = ($state.Offset -ne $before) }
                }.GetNewClosure() }
            SyncSelection = @{ Parameters = @('PlotCode', 'Desired'); Result = {
                    param($Bound)
                    $code = $Bound.PlotCode
                    [void]$state.Synced.Add("$code=$($Bound.Desired)")
                    if ($FatalFor -contains $code) { throw (New-CategorizedTestException -Category 'session-lost' -Message 'WebSocket closed') }
                    if ($FailFor.ContainsKey($code)) { return [pscustomobject]@{ ok = $false; reason = $FailFor[$code]; plotCode = $code; rowId = 'p?' } }
                    $was = $state.Selected.ContainsKey($code)
                    if ($Bound.Desired) { $state.Selected[$code] = $true } else { $state.Selected.Remove($code) }
                    [pscustomobject]@{ ok = $true; plotCode = $code; desiredChecked = [bool]$Bound.Desired; effectiveCheckedNow = [bool]$Bound.Desired; changed = ($was -ne $Bound.Desired); alreadyAligned = ($was -eq $Bound.Desired) }
                }.GetNewClosure() }
            AssertAnalysisMenuEnabled = @{ Result = (New-ContractResult -Scope 'soilAnalysisSync.postSelection') }
            IsFatal = @{ Parameters = @('ErrorObject'); Result = { param($Bound) (Get-PropertyCategory $Bound.ErrorObject) -in @('session-lost', 'timeout', 'helper-missing') } }
        }

        return [pscustomobject]@{ State = $state; Members = $members }
    }

    function Get-PropertyCategory {
        param($ErrorObject)
        $exception = $ErrorObject
        if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) { $exception = $ErrorObject.Exception }
        while ($null -ne $exception) {
            if ($exception.Data.Contains('pagebridge.category')) { return $exception.Data['pagebridge.category'] }
            $exception = $exception.InnerException
        }
        return ''
    }

    function New-SyncTestPorts {
        param(
            [Parameter(Mandatory)][AllowEmptyString()][string]$CsvText,
            [Parameter(Mandatory)][object]$List,
            [hashtable]$PageOverrides = @{},
            [System.Collections.ArrayList]$Calls = (New-CallRecorder)
        )

        $saved = New-CallRecorder
        $members = $List.Members.Clone()
        foreach ($key in $PageOverrides.Keys) { $members[$key] = $PageOverrides[$key] }

        return [pscustomobject]@{
            Calls = $Calls
            Saved = $saved
            Log = New-RecordingLog
            Clock = New-ManualClock
            Files = New-ScriptedPort -Name 'Files' -Calls $Calls -Members @{
                EnsureDirectory = @{ Parameters = @('Path', 'Purpose'); Result = { param($Bound) $Bound.Path } }
                Exists = @{ Parameters = @('Path'); Result = $true }
                ReadText = @{ Parameters = @('Path'); Result = $CsvText }
                SaveCsv = @{ Parameters = @('Path', 'Rows', 'Columns', 'Within', 'WhenEmpty'); Result = {
                        param($Bound)
                        [void]$saved.Add([pscustomobject]@{ Path = $Bound.Path; Rows = @($Bound.Rows); Columns = $Bound.Columns; WhenEmpty = $Bound.WhenEmpty })
                        [pscustomobject]@{ Path = $Bound.Path; Written = (@($Bound.Rows).Count -gt 0); Removed = $false; Count = @($Bound.Rows).Count }
                    }.GetNewClosure() }
            }
            Page = New-ScriptedPort -Name 'Page' -Calls $Calls -Members $members
        }
    }

    $script:Settings = [pscustomobject]@{
        InputCsvPath = '/work/weekly/downloads/plot_roster_0415.csv'
        OutputDirectory = '/work/weekly/downloads'
        CsvErrorFileName = 'soil_analysis_csv_errors.csv'
        FailureCsvFileName = 'soil_analysis_sync_failures.csv'
        DaysThreshold = 7
        MaxScanLoops = 50
        StallLimit = 2
    }

    function Invoke-TestFlow {
        param([Parameter(Mandatory)][object]$Ports)
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Ports = $Ports; Settings = $script:Settings } {
            param($Ports, $Settings)
            Invoke-SoilAnalysisSyncFlow -Ports $Ports -Settings $Settings
        }
    }

    function Get-SavedRows {
        param([object]$Ports, [string]$FileName)
        return @(@($Ports.Saved | Where-Object { $_.Path -like "*$FileName" })[-1].Rows)
    }
}

Describe 'Invoke-SoilAnalysisSyncFlow' {
    It 'aligns every plot across scroll positions and finishes without failures' {
        $csv = New-CsvText -Lines @(
            'GH1-A01,o,稼働中,2026-04-10 08:00:00,-,-',
            'GH1-A02,o,稼働中,2026-04-10 08:00:00,-,2026-04-09 08:00:00',
            'GH1-A03,o,稼働中,2026-04-10 08:00:00,-,2026-03-01 08:00:00',
            'GH1-A04,o,稼働中,2026-04-10 08:00:00,-,2026-04-08 08:00:00'
        )
        $list = New-SimulatedList -PlotCodes @('GH1-A01', 'GH1-A02', 'GH1-A03', 'GH1-A04') -Selected @('GH1-A02', 'GH1-A03')
        $ports = New-SyncTestPorts -CsvText $csv -List $list

        $outcome = Invoke-TestFlow -Ports $ports

        @($list.State.Synced) | Should -Be @('GH1-A01=True', 'GH1-A02=False', 'GH1-A03=True', 'GH1-A04=False')
        $outcome.Scan.StopReason | Should -Be 'complete'
        $outcome.Scan.Successes.Count | Should -Be 4
        (Get-SavedRows -Ports $ports -FileName 'soil_analysis_sync_failures.csv').Count | Should -Be 0
        @($ports.Saved | ForEach-Object { $_.WhenEmpty }) | Should -Be @('Remove', 'Remove')
        (Get-PortCalls -Calls $ports.Calls -Port 'Page') | Should -Contain 'Page.AssertAnalysisMenuEnabled'
    }

    It 'stops before touching the browser when the CSV has data errors' {
        $csv = New-CsvText -Lines @('GH1-A01,o,稼働中,2026-04-10,-,broken', ',o,稼働中,2026-04-10,-,-')
        $ports = New-SyncTestPorts -CsvText $csv -List (New-SimulatedList -PlotCodes @('GH1-A01'))

        { Invoke-TestFlow -Ports $ports } | Should -Throw '*CSV データエラーが 2 件*'

        @(Get-PortCalls -Calls $ports.Calls -Port 'Page').Count | Should -Be 0
        $errors = Get-SavedRows -Ports $ports -FileName 'soil_analysis_csv_errors.csv'
        @($errors | ForEach-Object { $_.Code }) | Should -Be @('ANALYSIS_DATE_INVALID', 'PLOT_CODE_BLANK')
        $errors[0].Timestamp | Should -Be '2026-04-15 09:30:00'
        @($ports.Saved).Count | Should -Be 2
    }

    It 'does not start clicking when the CSV and the list disagree on the count' {
        $csv = New-CsvText -Lines @('GH1-A01,o,稼働中,2026-04-10,-,-', 'GH1-A02,o,稼働中,2026-04-10,-,-')
        $ports = New-SyncTestPorts -CsvText $csv -List (New-SimulatedList -PlotCodes @('GH1-A01', 'GH1-A02') -Count 3)

        { Invoke-TestFlow -Ports $ports } | Should -Throw '*CSV の行数と一覧の件数が一致しません*'

        (Get-PortCalls -Calls $ports.Calls) | Should -Not -Contain 'Page.SyncSelection'
        @(Get-SavedRows -Ports $ports -FileName 'soil_analysis_sync_failures.csv' | ForEach-Object { $_.Code }) | Should -Be @('CSV_UI_COUNT_MISMATCH', 'FATAL_ERROR')
    }

    It 'keeps going after a plot fails and reports it at the end' {
        $csv = New-CsvText -Lines @('GH1-A01,o,稼働中,2026-04-10,-,-', 'GH1-A02,o,稼働中,2026-04-10,-,-', 'GH1-A03,o,稼働中,2026-04-10,-,-')
        $list = New-SimulatedList -PlotCodes @('GH1-A01', 'GH1-A02', 'GH1-A03') -FailFor @{ 'GH1-A02' = 'checkbox_disabled' }
        $ports = New-SyncTestPorts -CsvText $csv -List $list

        { Invoke-TestFlow -Ports $ports } | Should -Throw '*失敗が 2 件*'

        @($list.State.Synced).Count | Should -Be 3
        $failures = Get-SavedRows -Ports $ports -FileName 'soil_analysis_sync_failures.csv'
        @($failures | ForEach-Object { $_.Code }) | Should -Be @('SYNC_FAILED', 'ON_SUCCESS_COUNT_MISMATCH')
        $failures[0].PlotCode | Should -Be 'GH1-A02'
        $failures[0].Reason | Should -Match 'checkbox_disabled'
    }

    It 'stops at once when the browser session is lost' {
        $csv = New-CsvText -Lines @('GH1-A01,o,稼働中,2026-04-10,-,-', 'GH1-A02,o,稼働中,2026-04-10,-,-', 'GH1-A03,o,稼働中,2026-04-10,-,-')
        $list = New-SimulatedList -PlotCodes @('GH1-A01', 'GH1-A02', 'GH1-A03') -FatalFor @('GH1-A01')
        $ports = New-SyncTestPorts -CsvText $csv -List $list

        { Invoke-TestFlow -Ports $ports } | Should -Throw '*通信を続けられないため停止*'

        @($list.State.Synced) | Should -Be @('GH1-A01=True')
        @(Get-SavedRows -Ports $ports -FileName 'soil_analysis_sync_failures.csv' | ForEach-Object { $_.Code }) | Should -Be @('SYNC_EXCEPTION', 'FATAL_ERROR')
    }

    It 'reports plots missing from the list and plots the CSV does not know' {
        $csv = New-CsvText -Lines @('GH1-A01,o,稼働中,2026-04-10,-,-', 'GH1-A02,o,稼働中,2026-04-10,-,-')
        $list = New-SimulatedList -PlotCodes @('GH1-A01', 'GH9-Z99')
        $ports = New-SyncTestPorts -CsvText $csv -List $list

        { Invoke-TestFlow -Ports $ports } | Should -Throw '*失敗が*'

        $codes = @(Get-SavedRows -Ports $ports -FileName 'soil_analysis_sync_failures.csv' | ForEach-Object { "$($_.Code):$($_.PlotCode)" })
        $codes | Should -Be @('PLOT_NOT_FOUND_IN_UI:GH1-A02', 'PLOT_NOT_IN_CSV:GH9-Z99', 'PROCESSED_COUNT_MISMATCH:', 'ON_SUCCESS_COUNT_MISMATCH:')
    }

    It 'skips the analysis menu check when no plot needs to be ON' {
        $csv = New-CsvText -Lines @('GH1-A01,o,稼働中,2026-04-10,-,2026-04-09')
        $ports = New-SyncTestPorts -CsvText $csv -List (New-SimulatedList -PlotCodes @('GH1-A01'))

        [void](Invoke-TestFlow -Ports $ports)

        (Get-PortCalls -Calls $ports.Calls) | Should -Not -Contain 'Page.AssertAnalysisMenuEnabled'
    }

    It 'fails the run when the analysis request item does not become enabled' {
        $csv = New-CsvText -Lines @('GH1-A01,o,稼働中,2026-04-10,-,-')
        $ports = New-SyncTestPorts -CsvText $csv -List (New-SimulatedList -PlotCodes @('GH1-A01')) -PageOverrides @{
            AssertAnalysisMenuEnabled = @{ Result = { param($Bound) throw 'ページ契約違反: 「土壌分析を依頼」の有効化' } }
        }

        { Invoke-TestFlow -Ports $ports } | Should -Throw '*失敗が 1 件*'
        (Get-SavedRows -Ports $ports -FileName 'soil_analysis_sync_failures.csv')[0].Code | Should -Be 'REQUEST_MENU_NOT_ENABLED'
    }

    It 'explains a missing input CSV' {
        $ports = New-SyncTestPorts -CsvText '' -List (New-SimulatedList -PlotCodes @())
        $ports.Files = New-ScriptedPort -Name 'Files' -Calls $ports.Calls -Members @{
            EnsureDirectory = @{ Parameters = @('Path', 'Purpose') }
            Exists = @{ Parameters = @('Path'); Result = $false }
            ReadText = @{ Parameters = @('Path') }
            SaveCsv = @{ Parameters = @('Path', 'Rows', 'Columns', 'Within', 'WhenEmpty'); Result = [pscustomobject]@{ Written = $true; Removed = $false; Count = 1 } }
        }

        { Invoke-TestFlow -Ports $ports } | Should -Throw '*入力 CSV が見つかりません*'
    }
}

Describe 'Soil analysis page port and job wiring' {
    It 'maps business names to catalog operations and never exposes the analysis request' {
        $calls = New-CallRecorder
        $browser = New-ScriptedPort -Name 'Browser' -Calls $calls -Members @{
            Connect = @{}; Inject = @{}
            Invoke = @{ Parameters = @('Operation', 'Arguments', 'TimeoutSeconds') }
            Assert = @{ Parameters = @('Operation', 'Arguments', 'TimeoutSeconds', 'Description') }
            IsFatal = @{ Parameters = @('ErrorObject'); Result = $true }
        }

        InModuleScope SoilAnalysisTargetSync -Parameters @{ Browser = $browser } {
            param($Browser)
            $page = New-SoilAnalysisPage -Browser $Browser
            & $page.AssertList
            & $page.SyncSelection -PlotCode 'GH1-A01' -Desired $false
            & $page.AssertAnalysisMenuEnabled
            $page.PSObject.Properties.Name | Should -Not -Contain 'RequestAnalysis'
        }

        @($calls | ForEach-Object { "$($_.Member):$($_.Arguments.Operation)" }) | Should -Be @('Assert:CheckList', 'Invoke:SyncSelection', 'Assert:CheckAnalysisMenu')
        @($calls[1].Arguments.Arguments) | Should -Be @('GH1-A01', $false)
    }

    It 'returns counts through the job result' {
        $csv = New-CsvText -Lines @('GH1-A01,o,稼働中,2026-04-10,-,-', 'GH1-A02,o,稼働中,2026-04-10,-,2026-04-09')
        $ports = New-SyncTestPorts -CsvText $csv -List (New-SimulatedList -PlotCodes @('GH1-A01', 'GH1-A02'))
        $context = [pscustomobject]@{
            Settings = @{
                InputCsvPath = $script:Settings.InputCsvPath; OutputDirectory = $script:Settings.OutputDirectory
                CsvErrorFileName = $script:Settings.CsvErrorFileName; FailureCsvFileName = $script:Settings.FailureCsvFileName
                DaysThreshold = 7; MaxScanLoops = 50; StallLimit = 2
            }
            Services = [pscustomobject]@{ Log = $ports.Log; Clock = $ports.Clock; Files = $ports.Files; Browser = [pscustomobject]@{} }
        }

        InModuleScope SoilAnalysisTargetSync -Parameters @{ Context = $context; Page = $ports.Page } {
            param($Context, $Page)
            Mock New-SoilAnalysisPage { $Page }
            $result = Invoke-SoilAnalysisTargetSyncJob -Context $Context
            $result.Summary.OnTargets | Should -Be 1
            $result.Summary.OffTargets | Should -Be 1
            $result.Summary.Succeeded | Should -Be 2
            $result.Outputs.FailurePath | Should -Match 'soil_analysis_sync_failures\.csv$'
        }
    }

    It 'has an operation catalog that PageBridge accepts' {
        Import-Module (Get-RepositoryPath 'app/modules/PageBridge/PageBridge.psm1') -Force
        $catalog = Import-PageOperationCatalog -Path (Get-RepositoryPath 'app/modules/SoilAnalysisTargetSync/PageOperations.psd1')
        $catalog.Helper | Should -Be 'soilAnalysisSync'
        @($catalog.Operations.Values | Where-Object { $_.Method -match 'request' }).Count | Should -Be 0
    }
}
