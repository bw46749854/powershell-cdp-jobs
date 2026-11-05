BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/JobKit/JobKit.psm1') -Force -DisableNameChecking
    Import-Module (Get-RepositoryPath 'app/modules/JobChains/JobChains.psm1') -Force

    $script:RunRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'monthly-runs'

    function New-ChildResult {
        param([string]$Job, [hashtable]$Outputs = @{}, [hashtable]$Summary = @{})
        return New-JobResult -Job $Job -Outputs $Outputs -Summary $Summary
    }

    function New-ChainContext {
        <#
        子ジョブの結果を差し替えられる連携ジョブ用の Context。
        .PARAMETER Children
        ジョブ名 → 結果（値）または { param($Bound) ... }（例外で失敗を表す）
        #>
        param(
            [hashtable]$Children = @{},
            [hashtable]$ChildSettings = @{},
            [object]$Exists = $true,
            [object]$Listed = @(),
            [hashtable]$Settings = @{}
        )

        $calls = New-CallRecorder
        $log = New-RecordingLog
        $childrenCopy = $Children
        $settingsCopy = $ChildSettings
        $listedCopy = $Listed

        $jobs = New-ScriptedPort -Name 'Jobs' -Calls $calls -Members @{
            Run = @{ Parameters = @('JobName', 'Overrides'); Result = {
                    param($Bound)
                    $child = $childrenCopy[$Bound.JobName]
                    if ($child -is [scriptblock]) { return & $child $Bound }
                    return $child
                }.GetNewClosure() }
            GetSettings = @{ Parameters = @('JobName'); Result = { param($Bound) $settingsCopy[$Bound.JobName] }.GetNewClosure() }
        }
        $files = New-ScriptedPort -Name 'Files' -Calls $calls -Members @{
            EnsureDirectory = @{ Parameters = @('Path', 'Purpose'); Result = { param($Bound) $Bound.Path } }
            Exists = @{ Parameters = @('Path'); Result = $Exists }
            ListFiles = @{ Parameters = @('Directory', 'Filter'); Result = { param($Bound) $listedCopy }.GetNewClosure() }
        }

        return [pscustomobject]@{
            Calls = $calls
            Log = $log
            Context = [pscustomobject]@{
                Settings = $Settings
                Services = [pscustomobject]@{
                    Log = $log
                    Clock = New-ManualClock -Start ([datetime]'2026-05-01T06:15:42')
                    Files = $files
                    Jobs = $jobs
                    Browser = $null
                }
            }
        }
    }

    function Get-RunCall {
        param([object]$Chain, [string]$JobName)
        return @($Chain.Calls | Where-Object { $_.Port -eq 'Jobs' -and $_.Member -eq 'Run' -and $_.Arguments.JobName -eq $JobName })
    }
}

Describe 'Invoke-WeeklySoilAnalysisSyncJob' {
    BeforeAll {
        $script:CsvPath = '/work/weekly/plot_roster_0501.csv'
        $script:WeeklyChildren = @{
            PlotRosterExport = (New-ChildResult -Job 'PlotRosterExport' -Outputs @{ ExportedCsvPath = $script:CsvPath; DownloadedCsvPath = '/work/tmp/x.csv' } -Summary @{})
            SoilAnalysisTargetSync = (New-ChildResult -Job 'SoilAnalysisTargetSync' -Outputs @{ CsvErrorPath = '/work/weekly/csv_errors.csv'; FailurePath = '/work/weekly/sync_failures.csv' } -Summary @{ OnTargets = 3; OffTargets = 2 })
        }
    }

    It 'exports the roster, confirms the CSV exists, then syncs with that CSV' {
        $chain = New-ChainContext -Children $script:WeeklyChildren

        $result = Invoke-WeeklySoilAnalysisSyncJob -Context $chain.Context

        Get-PortCalls -Calls $chain.Calls | Should -Be @('Jobs.Run', 'Files.Exists', 'Jobs.Run')
        $runs = @($chain.Calls | Where-Object { $_.Member -eq 'Run' })
        $runs[0].Arguments.JobName | Should -Be 'PlotRosterExport'
        $runs[0].Arguments.Overrides.Count | Should -Be 0
        $runs[1].Arguments.JobName | Should -Be 'SoilAnalysisTargetSync'
        $runs[1].Arguments.Overrides.InputCsvPath | Should -Be $script:CsvPath
        $chain.Calls[1].Arguments.Path | Should -Be $script:CsvPath

        $result.Job | Should -Be 'WeeklySoilAnalysisSync'
        $result.Outputs.InputCsvPath | Should -Be $script:CsvPath
        $result.Outputs.SoilAnalysisTargetSync.FailurePath | Should -Be '/work/weekly/sync_failures.csv'
        $result.Summary.SoilAnalysisTargetSync.OnTargets | Should -Be 3
        Get-LogMessages -Log $chain.Log | Should -Contain "引き渡し: SoilAnalysisTargetSync.InputCsvPath = $($script:CsvPath)"
    }

    It 'does not run the sync when the exported CSV does not exist' {
        $chain = New-ChainContext -Children $script:WeeklyChildren -Exists $false

        { Invoke-WeeklySoilAnalysisSyncJob -Context $chain.Context } | Should -Throw '*PlotRosterExport が出力した CSV が見つかりません*'
        @(Get-RunCall -Chain $chain -JobName 'SoilAnalysisTargetSync').Count | Should -Be 0
    }

    It 'does not run the sync when the export result has no CSV path' {
        $children = $script:WeeklyChildren.Clone()
        $children.PlotRosterExport = New-ChildResult -Job 'PlotRosterExport' -Outputs @{ ExportedCsvPath = ' ' }
        $chain = New-ChainContext -Children $children

        { Invoke-WeeklySoilAnalysisSyncJob -Context $chain.Context } | Should -Throw '*PlotRosterExport の結果に Outputs.ExportedCsvPath がありません*'
        Get-PortCalls -Calls $chain.Calls | Should -Be @('Jobs.Run')
    }

    It 'stops at the first failing child and passes its error on' {
        $children = $script:WeeklyChildren.Clone()
        $children.PlotRosterExport = { param($Bound) throw 'PlotRosterExport は異常終了しました: 画面が違います' }
        $chain = New-ChainContext -Children $children

        { Invoke-WeeklySoilAnalysisSyncJob -Context $chain.Context } | Should -Throw '*画面が違います*'
        @(Get-RunCall -Chain $chain -JobName 'SoilAnalysisTargetSync').Count | Should -Be 0
    }

    It 'rejects a child result that does not follow the result protocol (<Case>)' -TestCases @(
        @{ Case = 'two results'; Child = { param($Bound) 'leaked'; New-JobResult -Job 'PlotRosterExport' } ; Expected = '*1つだけ*' }
        @{ Case = 'another job'; Child = { param($Bound) New-JobResult -Job 'SoilAnalysisTargetSync' }; Expected = '*別のジョブ名*' }
        @{ Case = 'nothing'; Child = { param($Bound) }; Expected = '*1つだけ*' }
    ) {
        param($Case, $Child, $Expected)
        $children = $script:WeeklyChildren.Clone()
        $children.PlotRosterExport = $Child
        $chain = New-ChainContext -Children $children

        { Invoke-WeeklySoilAnalysisSyncJob -Context $chain.Context } | Should -Throw $Expected
        @(Get-RunCall -Chain $chain -JobName 'SoilAnalysisTargetSync').Count | Should -Be 0
    }
}

Describe 'Invoke-MonthlyPlantingReportJob' {
    BeforeAll {
        $script:RunDirectory = Join-Path $script:RunRoot '20260501_061542'
        $script:Downloads = Join-Path $script:RunDirectory 'planting_export_downloads'
        $script:Temp = Join-Path $script:RunDirectory 'planting_export_tmp'
        $script:MonthlyChildren = @{
            PlantingRecordExport = (New-ChildResult -Job 'PlantingRecordExport' -Outputs @{ DownloadDirectory = $script:Downloads } -Summary @{ Total = 2 })
            LastMonthPlantingDigest = (New-ChildResult -Job 'LastMonthPlantingDigest' -Outputs @{ OutputCsvPath = (Join-Path $script:Downloads 'planting_last_month.csv') } -Summary @{ Plantings = 4 })
        }
        $script:MonthlyChildSettings = @{ PlantingRecordExport = @{ DownloadFilePrefix = 'planting_' } }
        $script:Saved = @(
            [pscustomobject]@{ Name = 'planting_20260501_GH1-A01.csv'; FullName = (Join-Path $script:Downloads 'planting_20260501_GH1-A01.csv') }
        )
    }

    It 'creates a run directory from the clock and hands its folders to both child jobs' {
        $chain = New-ChainContext -Children $script:MonthlyChildren -ChildSettings $script:MonthlyChildSettings -Listed $script:Saved -Settings @{ RunRootDirectory = $script:RunRoot }

        $result = Invoke-MonthlyPlantingReportJob -Context $chain.Context

        Get-PortCalls -Calls $chain.Calls | Should -Be @('Files.EnsureDirectory', 'Files.EnsureDirectory', 'Files.EnsureDirectory', 'Jobs.Run', 'Jobs.GetSettings', 'Files.ListFiles', 'Jobs.Run')
        @($chain.Calls | Where-Object { $_.Member -eq 'EnsureDirectory' } | ForEach-Object { $_.Arguments.Path }) | Should -Be @($script:RunDirectory, $script:Temp, $script:Downloads)

        $export = Get-RunCall -Chain $chain -JobName 'PlantingRecordExport'
        $export[0].Arguments.Overrides.TempDirectory | Should -Be $script:Temp
        $export[0].Arguments.Overrides.DownloadDirectory | Should -Be $script:Downloads
        $listing = @($chain.Calls | Where-Object { $_.Member -eq 'ListFiles' })[0]
        $listing.Arguments.Directory | Should -Be $script:Downloads
        $listing.Arguments.Filter | Should -Be 'planting_*.csv'
        (Get-RunCall -Chain $chain -JobName 'LastMonthPlantingDigest')[0].Arguments.Overrides.TargetDirectory | Should -Be $script:Downloads

        $result.Job | Should -Be 'MonthlyPlantingReport'
        $result.Summary.RunStamp | Should -Be '20260501_061542'
        $result.Outputs.RunDirectory | Should -Be $script:RunDirectory
        ,$result.Outputs.ExportedCsvPaths | Should -BeOfType [string[]]
        $result.Outputs.ExportedCsvPaths | Should -Be @($script:Saved[0].FullName)
        $result.Outputs.LastMonthPlantingDigest.OutputCsvPath | Should -Be (Join-Path $script:Downloads 'planting_last_month.csv')
        $result.Summary.LastMonthPlantingDigest.Plantings | Should -Be 4
    }

    It 'does not run the digest when no exported CSV was saved' {
        $chain = New-ChainContext -Children $script:MonthlyChildren -ChildSettings $script:MonthlyChildSettings -Listed @() -Settings @{ RunRootDirectory = $script:RunRoot }

        { Invoke-MonthlyPlantingReportJob -Context $chain.Context } | Should -Throw '*成果物 CSV（planting_*.csv）が保存先にありません*'
        @(Get-RunCall -Chain $chain -JobName 'LastMonthPlantingDigest').Count | Should -Be 0
    }

    It 'does not run the digest when the export fails' {
        $children = $script:MonthlyChildren.Clone()
        $children.PlantingRecordExport = { param($Bound) throw '処理に失敗した区画が 1 件あります。' }
        $chain = New-ChainContext -Children $children -ChildSettings $script:MonthlyChildSettings -Listed $script:Saved -Settings @{ RunRootDirectory = $script:RunRoot }

        { Invoke-MonthlyPlantingReportJob -Context $chain.Context } | Should -Throw '*処理に失敗した区画*'
        @(Get-RunCall -Chain $chain -JobName 'LastMonthPlantingDigest').Count | Should -Be 0
    }

    It 'refuses a download prefix that is missing or would act as a wildcard (<Case>)' -TestCases @(
        @{ Case = 'missing'; Prefix = $null; Expected = '*Jobs.PlantingRecordExport.DownloadFilePrefix*' }
        @{ Case = 'asterisk'; Prefix = 'planting_*'; Expected = '*ワイルドカード文字*' }
        @{ Case = 'brackets'; Prefix = 'planting[1]'; Expected = '*ワイルドカード文字*' }
    ) {
        param($Case, $Prefix, $Expected)
        $childSettings = @{ PlantingRecordExport = @{} }
        if ($null -ne $Prefix) { $childSettings.PlantingRecordExport.DownloadFilePrefix = $Prefix }
        $chain = New-ChainContext -Children $script:MonthlyChildren -ChildSettings $childSettings -Listed $script:Saved -Settings @{ RunRootDirectory = $script:RunRoot }

        { Invoke-MonthlyPlantingReportJob -Context $chain.Context } | Should -Throw $Expected
        @(Get-RunCall -Chain $chain -JobName 'LastMonthPlantingDigest').Count | Should -Be 0
    }

    It 'requires its own run root setting before doing anything' {
        $chain = New-ChainContext -Children $script:MonthlyChildren -Settings @{}

        { Invoke-MonthlyPlantingReportJob -Context $chain.Context } | Should -Throw '*Jobs.MonthlyPlantingReport.RunRootDirectory*'
        $chain.Calls.Count | Should -Be 0
    }
}
