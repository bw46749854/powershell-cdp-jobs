BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '../support/E2EHarness.psm1') -Force
    $script:BrowserPath = Find-E2EBrowser
}

# 実ブラウザ（ヘッドレス）とモック画面で、ジョブを本番と同じ入口（Invoke-HostedJob）から通しで動かす。
# ブラウザが見つからない環境では Skipped になる。実行: pwsh -File tools/Invoke-Tests.ps1 -Suite Pester -IncludeE2E
Describe 'Jobs against the mock site in a real browser' -Tag 'E2E' -Skip:(-not $script:BrowserPath) {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../support/TestSupport.psm1') -Force
        Import-Module (Join-Path $PSScriptRoot '../support/E2EHarness.psm1') -Force
        Import-Module (Get-RepositoryPath 'app/modules/JobHost/JobHost.psm1') -Force

        $script:AppRoot = Get-RepositoryPath 'app'
        $script:SitePort = Get-FreeTcpPort
        $script:DebugPort = Get-FreeTcpPort
        $script:ConsoleUrl = "http://localhost:$($script:SitePort)/greenhouse-console/"
        $script:LedgerUrl = "http://localhost:$($script:SitePort)/planting-ledger/"
        $script:WorkRoot = Join-Path $TestDrive 'work'
        $logs = Join-Path $TestDrive 'logs'
        $script:Server = Start-MockSite -Port $script:SitePort -LogDirectory $logs
        $script:Browser = Start-E2EBrowser -BrowserPath (Find-E2EBrowser) -DebugPort $script:DebugPort -ProfileDirectory (Join-Path $TestDrive 'profile') -Urls @($script:ConsoleUrl, $script:LedgerUrl) -LogDirectory $logs
        $script:SettingsPath = New-E2ESettingsFile -Path (Join-Path $TestDrive 'settings.psd1') -WorkRoot $script:WorkRoot -DebugPort $script:DebugPort

        function Invoke-E2EJob {
            param(
                [Parameter(Mandatory)][string]$JobName,
                [hashtable]$SettingsOverrides = @{},
                [System.Collections.ArrayList]$Lines = (New-CallRecorder)
            )
            $lines = $Lines
            $writer = { param($Level, $Line) [void]$lines.Add($Line) }.GetNewClosure()
            $result = Invoke-HostedJob -AppRoot $script:AppRoot -JobName $JobName -SettingsPath $script:SettingsPath -SettingsOverrides $SettingsOverrides -ServiceOverrides @{ ConsoleWriter = $writer }
            return [pscustomobject]@{ Result = $result; Lines = $lines }
        }

        function Get-ExpectedAnalysisTargets {
            <#
            週次の判定ルール（docs/jobs/soil-analysis-target-sync.md）をテスト側で独立に書いたもの。
            #>
            param([Parameter(Mandatory)][string]$CsvPath, [int]$DaysThreshold = 7)
            $rows = @(Import-Csv -LiteralPath $CsvPath -Encoding UTF8)
            return @($rows | Where-Object {
                    $completed = $_.'土壌分析の完了'
                    if ($completed -eq '-' -or [string]::IsNullOrWhiteSpace($completed)) { return $true }
                    $days = ([datetime]::Parse($_.'最終計測日時').Date - [datetime]::Parse($completed).Date).TotalDays
                    return $days -ge $DaysThreshold
                } | ForEach-Object { $_.'区画コード' } | Sort-Object)
        }
    }

    AfterAll {
        Stop-E2EProcess -Process $script:Browser
        Stop-E2EProcess -Process $script:Server
    }

    Context 'WeeklySoilAnalysisSync' {
        It 'exports the roster and leaves exactly the plots due for analysis selected, without requesting analysis' {
            $run = Invoke-E2EJob -JobName 'WeeklySoilAnalysisSync'

            $csvPath = $run.Result.Outputs.InputCsvPath
            Test-Path -LiteralPath $csvPath | Should -BeTrue
            $expected = Get-ExpectedAnalysisTargets -CsvPath $csvPath
            $selected = @(Invoke-E2EPageScript -DebugPort $script:DebugPort -Url $script:ConsoleUrl -Expression 'window.mockConsole.selectedPlotCodes()')

            $expected.Count | Should -BeGreaterThan 0
            $selected | Should -Be $expected
            $run.Result.Summary.SoilAnalysisTargetSync.Succeeded | Should -Be 60
            Invoke-E2EPageScript -DebugPort $script:DebugPort -Url $script:ConsoleUrl -Expression 'window.mockConsole.requestClicks()' | Should -Be 0
            Test-Path -LiteralPath $run.Result.Outputs.SoilAnalysisTargetSync.FailurePath | Should -BeFalse
        }

        It 'changes nothing when run again on an already aligned screen' {
            $run = Invoke-E2EJob -JobName 'WeeklySoilAnalysisSync'

            @($run.Lines | Where-Object { $_ -match '変更した\s*:\s*0 件' }).Count | Should -Be 1
            $run.Result.Summary.SoilAnalysisTargetSync.Succeeded | Should -Be 60
        }

        It 'refuses to work on the plot list when another group is selected (a change of meaning)' {
            [void](Invoke-E2EPageScript -DebugPort $script:DebugPort -Url $script:ConsoleUrl -Expression "document.querySelector('[role=treeitem][data-group=gh1]').click(); document.title")
            try {
                $lines = New-CallRecorder
                { Invoke-E2EJob -JobName 'PlotRosterExport' -Lines $lines } | Should -Throw '*一致するタブが見つかりません*'
                ($lines -join "`n") | Should -Match 'identity\.group\.default\.selected「グループツリーで「全区画（既定）」だけが選択されていること」'
                @(Get-ChildItem -LiteralPath (Join-Path $script:WorkRoot 'weekly/tmp/plot_roster_export') -File -ErrorAction SilentlyContinue).Count | Should -Be 0
            }
            finally {
                [void](Invoke-E2EPageScript -DebugPort $script:DebugPort -Url $script:ConsoleUrl -Expression "document.querySelector('[role=treeitem][data-group=all]').click(); document.title")
            }
        }
    }

    Context 'MonthlyPlantingReport' {
        It 'saves one planting CSV per plot into a fresh run directory and digests last month''s plantings' {
            $run = Invoke-E2EJob -JobName 'MonthlyPlantingReport'

            $total = [int](Invoke-E2EPageScript -DebugPort $script:DebugPort -Url $script:LedgerUrl -Expression "document.querySelector('[data-bind=""plotList.total""]').textContent")
            $exported = @($run.Result.Outputs.ExportedCsvPaths)
            $exported.Count | Should -Be $total
            $codes = @($exported | ForEach-Object { [regex]::Match([System.IO.Path]::GetFileName($_), '^planting_\d{8}_(GH2-B\d{2})\.csv$').Groups[1].Value })
            @($codes | Where-Object { $_ } | Sort-Object -Unique).Count | Should -Be $total

            $today = (Get-Date).Date
            $start = (New-Object datetime -ArgumentList $today.Year, $today.Month, 1).AddMonths(-1)
            $end = $start.AddMonths(1)
            $expected = @(foreach ($path in $exported) {
                    $code = [regex]::Match([System.IO.Path]::GetFileName($path), '_(GH2-B\d{2})\.csv$').Groups[1].Value
                    foreach ($row in @(Import-Csv -LiteralPath $path -Encoding UTF8)) {
                        if ([string]::IsNullOrWhiteSpace($row.'定植日')) { continue }
                        $planted = [datetime]::ParseExact($row.'定植日', 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                        if ($planted -ge $start -and $planted -lt $end) { "$code/$($row.'作物名')/$($row.'品種')/$($row.'定植日')" }
                    }
                })
            $digest = @(Import-Csv -LiteralPath $run.Result.Outputs.LastMonthPlantingDigest.OutputCsvPath -Encoding UTF8 | ForEach-Object { "$($_.'区画コード')/$($_.'作物名')/$($_.'品種')/$($_.'定植日')" })

            $expected.Count | Should -BeGreaterThan 0
            ($digest | Sort-Object) | Should -Be ($expected | Sort-Object)
            $failures = @(Import-Csv -LiteralPath $run.Result.Outputs.LastMonthPlantingDigest.FailurePath -Encoding UTF8)
            $failures.Count | Should -Be 1
            $failures[0].PlotCode | Should -Be 'GH2-B07'
            $run.Result.Outputs.RunDirectory | Should -BeLike (Join-Path $script:WorkRoot 'monthly/runs/*')
        }

        It 'absorbs a structural change: the plot code column moved to the scrolling side of the grid' {
            $flip = "(() => { const s = document.getElementById('code-side'); s.value = 'SIDE'; s.dispatchEvent(new Event('change', { bubbles: true })); return document.querySelectorAll('#body-main td[headers=""plots-col-code""]').length; })()"
            Invoke-E2EPageScript -DebugPort $script:DebugPort -Url $script:LedgerUrl -Expression $flip.Replace('SIDE', 'main') | Should -BeGreaterThan 0
            try {
                $directory = Join-Path $script:WorkRoot 'structural'
                $run = Invoke-E2EJob -JobName 'PlantingRecordExport' -SettingsOverrides @{ TempDirectory = (Join-Path $directory 'tmp'); DownloadDirectory = (Join-Path $directory 'downloads') }
                $run.Result.Summary.Succeeded | Should -Be $run.Result.Summary.Total
                @(Get-ChildItem -LiteralPath (Join-Path $directory 'downloads') -Filter 'planting_*.csv').Count | Should -Be $run.Result.Summary.Total
            }
            finally {
                [void](Invoke-E2EPageScript -DebugPort $script:DebugPort -Url $script:LedgerUrl -Expression $flip.Replace('SIDE', 'fixed'))
            }
        }
    }
}
