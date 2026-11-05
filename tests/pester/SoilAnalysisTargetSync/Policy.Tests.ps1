BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/SoilAnalysisTargetSync/SoilAnalysisTargetSync.psm1') -Force
}

Describe 'ConvertTo-CalendarDate' {
    It 'reads <Text> as <Expected>' -TestCases @(
        @{ Text = '2026-04-10'; Expected = '2026-04-10' }
        @{ Text = '2026-4-1 8:05:00'; Expected = '2026-04-01' }
        @{ Text = '2026/04/10 23:59:59'; Expected = '2026-04-10' }
        @{ Text = '2026/4/1 8:05'; Expected = '2026-04-01' }
        @{ Text = '2026年4月10日'; Expected = '2026-04-10' }
        @{ Text = '2026年04月10日 08:00:00'; Expected = '2026-04-10' }
        @{ Text = '2026-04-10T23:30:00+09:00'; Expected = '2026-04-10' }
        @{ Text = '2026-04-10T00:30:00.123-05:00'; Expected = '2026-04-10' }
        @{ Text = '2026-04-10T23:30:00Z'; Expected = '2026-04-10' }
        @{ Text = '  2026-04-10   08:00:00 '; Expected = '2026-04-10' }
        @{ Text = '2026-04-10 08:00 JST'; Expected = '2026-04-10' }
    ) {
        param($Text, $Expected)
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Text = $Text; Expected = $Expected } {
            param($Text, $Expected)
            (ConvertTo-CalendarDate -Text $Text).ToString('yyyy-MM-dd') | Should -Be $Expected
        }
    }

    It 'keeps the displayed calendar date of offset timestamps instead of converting the time zone' {
        InModuleScope SoilAnalysisTargetSync {
            (ConvertTo-CalendarDate -Text '2026-04-10T23:30:00-10:00').Day | Should -Be 10
            (ConvertTo-CalendarDate -Text '2026-04-10T00:30:00+14:00').Day | Should -Be 10
        }
    }

    It 'returns null for missing or unreadable values' -TestCases @(
        @{ Text = '' }, @{ Text = '-' }, @{ Text = ' - ' }, @{ Text = '昨日' }, @{ Text = '10/04/2026' }, @{ Text = '2026-13-01' }
    ) {
        param($Text)
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Text = $Text } {
            param($Text)
            ConvertTo-CalendarDate -Text $Text | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-AnalysisDecision' {
    It 'decides <Decision> for completed=<Completed> measured=<Measured>' -TestCases @(
        @{ Completed = '-'; Measured = '2026-04-10'; Decision = 'On'; Days = $null; Code = '' }
        @{ Completed = ''; Measured = 'broken'; Decision = 'On'; Days = $null; Code = '' }
        @{ Completed = 'not a date'; Measured = '2026-04-10'; Decision = 'Error'; Days = $null; Code = 'ANALYSIS_DATE_INVALID' }
        @{ Completed = '2026-04-01'; Measured = '-'; Decision = 'Error'; Days = $null; Code = 'MEASURED_DATE_INVALID' }
        @{ Completed = '2026-04-10'; Measured = '2026-04-09 23:59:59'; Decision = 'Error'; Days = -1; Code = 'DATE_ORDER_INCONSISTENT' }
        @{ Completed = '2026-04-03 23:00:00'; Measured = '2026-04-10 01:00:00'; Decision = 'On'; Days = 7; Code = '' }
        @{ Completed = '2026-04-04 00:00:00'; Measured = '2026-04-10 23:59:59'; Decision = 'Off'; Days = 6; Code = '' }
        @{ Completed = '2026-04-10'; Measured = '2026-04-10'; Decision = 'Off'; Days = 0; Code = '' }
    ) {
        param($Completed, $Measured, $Decision, $Days, $Code)
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Completed = $Completed; Measured = $Measured; Decision = $Decision; Days = $Days; Code = $Code } {
            param($Completed, $Measured, $Decision, $Days, $Code)
            $result = Get-AnalysisDecision -AnalysisCompleted $Completed -LastMeasured $Measured -DaysThreshold 7
            $result.Decision | Should -Be $Decision
            $result.ElapsedDays | Should -Be $Days
            $result.ErrorCode | Should -Be $Code
        }
    }

    It 'describes the rules with the configured threshold' {
        InModuleScope SoilAnalysisTargetSync {
            (Get-AnalysisRuleDescription -DaysThreshold 9) -join "`n" | Should -Match '差が 9 日以上 → ON'
        }
    }
}

Describe 'ConvertFrom-RosterCsvText' {
    It 'maps Japanese headers to record fields and ignores other columns (<Name>)' -TestCases @(
        @{ Name = 'comma'; Text = "区画コード,担当者,稼働状態,最終計測日時,土壌分析の依頼,土壌分析の完了,作物`r`nGH1-A01,staff1,稼働中,2026-04-10 08:00:00,-,2026-04-01 09:00:00,トマト`r`n" }
        @{ Name = 'tab'; Text = "作物`t区画コード`t担当者`t稼働状態`t最終計測日時`t土壌分析の依頼`t土壌分析の完了`nトマト`tGH1-A01`tstaff1`t稼働中`t2026-04-10 08:00:00`t-`t2026-04-01 09:00:00`n" }
    ) {
        param($Name, $Text)
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Text = $Text } {
            param($Text)
            $records = @(ConvertFrom-RosterCsvText -Text $Text)
            $records.Count | Should -Be 1
            $records[0].PlotCode | Should -Be 'GH1-A01'
            $records[0].AnalysisCompleted | Should -Be '2026-04-01 09:00:00'
            $records[0].PSObject.Properties.Name | Should -Not -Contain '作物'
        }
    }

    It 'rejects a CSV without required columns or without data rows' {
        InModuleScope SoilAnalysisTargetSync {
            { ConvertFrom-RosterCsvText -Text "区画コード,担当者`r`nGH1-A01,x`r`n" } | Should -Throw '*必須の列がありません*稼働状態*'
            { ConvertFrom-RosterCsvText -Text "区画コード,担当者,稼働状態,最終計測日時,土壌分析の依頼,土壌分析の完了`r`n" } | Should -Throw '*データ行がありません*'
            { ConvertFrom-RosterCsvText -Text "`r`nGH1-A01" } | Should -Throw '*見出し行）が空*'
        }
    }
}

Describe 'New-SoilAnalysisPlan' {
    BeforeAll {
        function New-Record {
            param([string]$PlotCode, [string]$Completed = '2026-04-09', [string]$Measured = '2026-04-10')
            return [pscustomobject]@{ PlotCode = $PlotCode; Owner = 'o'; Status = 's'; LastMeasured = $Measured; AnalysisRequested = '-'; AnalysisCompleted = $Completed }
        }
    }

    It 'splits plots into ON and OFF targets in a fixed order' {
        $records = @((New-Record -PlotCode 'GH1-A01' -Completed '-'), (New-Record -PlotCode 'GH1-A02'), (New-Record -PlotCode 'GH1-A03' -Completed '2026-03-01'))
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Records = $records } {
            param($Records)
            $plan = New-SoilAnalysisPlan -Records $Records -DaysThreshold 7

            @($plan.CsvErrors).Count | Should -Be 0
            @($plan.Targets | ForEach-Object { "$($_.PlotCode)=$($_.Desired)" }) | Should -Be @('GH1-A01=True', 'GH1-A03=True', 'GH1-A02=False')
            $plan.Targets[1].ElapsedDays | Should -Be 40
            @(Get-SoilAnalysisPlanFindings -Plan $plan).Count | Should -Be 0
        }
    }

    It 'records blank and duplicated plot codes as CSV errors and creates no targets' {
        $records = @((New-Record -PlotCode ''), (New-Record -PlotCode 'GH1-A02'), (New-Record -PlotCode 'GH1-A02' -Completed '-'), (New-Record -PlotCode 'GH1-A04'))
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Records = $records } {
            param($Records)
            $plan = New-SoilAnalysisPlan -Records $Records -DaysThreshold 7

            @($plan.CsvErrors | ForEach-Object { $_.Code }) | Should -Be @('PLOT_CODE_BLANK', 'PLOT_CODE_DUPLICATED', 'PLOT_CODE_DUPLICATED')
            $plan.CsvErrors[1].Reason | Should -Match 'GH1-A02 が 2 件'
            @($plan.Targets).Count | Should -Be 0
        }
    }

    It 'collects every unreadable row instead of stopping at the first one' {
        $records = @((New-Record -PlotCode 'GH1-A01' -Completed 'x'), (New-Record -PlotCode 'GH1-A02' -Measured 'y'), (New-Record -PlotCode 'GH1-A03' -Completed '2026-04-11'))
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Records = $records } {
            param($Records)
            $plan = New-SoilAnalysisPlan -Records $Records -DaysThreshold 7
            @($plan.CsvErrors | ForEach-Object { $_.Code }) | Should -Be @('ANALYSIS_DATE_INVALID', 'MEASURED_DATE_INVALID', 'DATE_ORDER_INCONSISTENT')
            $plan.CsvErrors[2].ElapsedDays | Should -Be -1
        }
    }

    It 'reports a classification count that does not add up' {
        InModuleScope SoilAnalysisTargetSync {
            $plan = [pscustomobject]@{ Records = @(1, 2, 3); OnRecords = @(1); OffRecords = @(2); Targets = @() }
            (Get-SoilAnalysisPlanFindings -Plan $plan)[0].Code | Should -Be 'CSV_CLASSIFICATION_COUNT_MISMATCH'
        }
    }
}

Describe 'Scan state and reconciliation' {
    BeforeAll {
        function New-Target {
            param([string]$PlotCode, [bool]$Desired)
            return [pscustomobject]@{ PlotCode = $PlotCode; Desired = $Desired; Reason = 'r'; Record = [pscustomobject]@{ PlotCode = $PlotCode; Owner = 'o'; Status = 's'; LastMeasured = ''; AnalysisRequested = ''; AnalysisCompleted = '' } }
        }
    }

    It 'returns only visible, unprocessed targets and records bad rows and conflicts' {
        $index = @{ 'GH1-A01' = (New-Target 'GH1-A01' $true); 'GH1-A02' = (New-Target 'GH1-A02' $false); 'GH1-A03' = (New-Target 'GH1-A03' $true) }
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Index = $index } {
            param($Index)
            $state = New-SoilAnalysisScanState
            $state.Processed['GH1-A02'] = $true
            $visible = @(
                [pscustomobject]@{ plotCode = 'GH1-A03'; rowId = 'p3' },
                [pscustomobject]@{ plotCode = 'GH1-A01'; rowId = 'p1' },
                [pscustomobject]@{ plotCode = 'GH1-A02'; rowId = 'p2' },
                [pscustomobject]@{ plotCode = 'GH9-Z99'; rowId = 'p9' },
                [pscustomobject]@{ plotCode = ''; rowId = 'px' },
                [pscustomobject]@{ plotCode = 'GH1-A01'; rowId = 'p1-copy' }
            )

            @(Update-SoilAnalysisScanState -State $state -TargetIndex $Index -VisibleRows $visible) | Should -Be @('GH1-A01', 'GH1-A03')
            $state.Seen.Count | Should -Be 4
            $state.BadRows.Keys | Should -Be @('rowId=px plotCode=')
            $state.Conflicts['GH1-A01'] | Should -Match 'p1.*p1-copy'
        }
    }

    It 'is complete only when every plot was seen and every target processed' {
        InModuleScope SoilAnalysisTargetSync {
            $state = New-SoilAnalysisScanState
            $state.Seen['a'] = $true; $state.Seen['b'] = $true; $state.Processed['a'] = $true
            Test-SoilAnalysisScanComplete -State $state -ExpectedTotal 2 -TargetCount 2 | Should -BeFalse
            $state.Processed['b'] = $true
            Test-SoilAnalysisScanComplete -State $state -ExpectedTotal 2 -TargetCount 2 | Should -BeTrue
            Test-SoilAnalysisScanComplete -State $state -ExpectedTotal 3 -TargetCount 2 | Should -BeFalse
        }
    }

    It 'lists every mismatch between the CSV plan and the scanned list' {
        $index = @{ 'GH1-A01' = (New-Target 'GH1-A01' $true); 'GH1-A02' = (New-Target 'GH1-A02' $false); 'GH1-A03' = (New-Target 'GH1-A03' $true) }
        InModuleScope SoilAnalysisTargetSync -Parameters @{ Index = $index } {
            param($Index)
            $state = New-SoilAnalysisScanState
            $state.Seen['GH1-A01'] = $true; $state.SeenRowIds['GH1-A01'] = 'p1'
            $state.Seen['GH1-A02'] = $true; $state.SeenRowIds['GH1-A02'] = 'p2'
            $state.Seen['GH9-Z99'] = $true; $state.SeenRowIds['GH9-Z99'] = 'p9'
            $state.Processed['GH1-A01'] = $true
            $state.BadRows['rowId= plotCode='] = $true
            $state.Conflicts['GH1-A01'] = 'x'

            $codes = @(Get-SoilAnalysisScanFindings -State $state -TargetIndex $Index -ExpectedTotal 3 -MaxLoops 5 | ForEach-Object { "$($_.Code):$($_.PlotCode)" })
            $codes | Should -Be @(
                'SCAN_LOOP_LIMIT:', 'UI_ROW_WITHOUT_KEY:', 'UI_PLOT_CODE_CONFLICT:GH1-A01',
                'PLOT_NOT_FOUND_IN_UI:GH1-A03', 'PLOT_NOT_IN_CSV:GH9-Z99',
                'SYNC_NOT_ATTEMPTED:GH1-A02', 'PROCESSED_COUNT_MISMATCH:'
            )
        }
    }

    It 'checks success counts by desired state and the final checkbox state' {
        InModuleScope SoilAnalysisTargetSync {
            $plan = [pscustomobject]@{ Targets = @([pscustomobject]@{ Desired = $true }, [pscustomobject]@{ Desired = $true }, [pscustomobject]@{ Desired = $false }) }
            $successes = @(
                [pscustomobject]@{ desiredChecked = $true; effectiveCheckedNow = $true; changed = $true; alreadyAligned = $false },
                [pscustomobject]@{ desiredChecked = $false; effectiveCheckedNow = $true; changed = $false; alreadyAligned = $true }
            )
            $breakdown = Get-SoilAnalysisSuccessBreakdown -Successes $successes
            @($breakdown.Changed).Count | Should -Be 1
            @($breakdown.AlreadyAligned).Count | Should -Be 1
            @(Get-SoilAnalysisSuccessFindings -Breakdown $breakdown -Plan $plan | ForEach-Object { $_.Code }) | Should -Be @('ON_SUCCESS_COUNT_MISMATCH', 'SUCCESS_NOT_ALIGNED')
        }
    }
}
