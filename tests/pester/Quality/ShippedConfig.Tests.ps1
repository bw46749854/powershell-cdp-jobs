BeforeDiscovery {
    $script:JobNames = @((Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '../../../app/config/jobs.psd1')).Jobs.Keys | Sort-Object)
}

# 同梱の設定ファイル（app/config）が、各ジョブ自身の検証を通ることを確かめる。
# 設定キーの追加・改名をしたのに settings.psd1 や jobs.psd1 を直し忘れた状態を、実行前に検出するためのテスト。

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/JobHost/JobHost.psm1') -Force

    $script:AppRoot = Get-RepositoryPath 'app'
    $script:Settings = InModuleScope JobHost -Parameters @{ Path = (Get-RepositoryPath 'app/config/settings.psd1'); ProjectRoot = (Get-RepositoryPath '.') } {
        param($Path, $ProjectRoot)
        Import-HostSettings -Path $Path -ProjectRoot $ProjectRoot
    }
    $script:Catalog = InModuleScope JobHost -Parameters @{ Path = (Get-RepositoryPath 'app/config/jobs.psd1'); AppRoot = (Get-RepositoryPath 'app') } {
        param($Path, $AppRoot)
        Import-JobCatalog -Path $Path -AppRoot $AppRoot
    }

    # ジョブ名 → そのジョブの設定を読む関数（モジュール内の非公開関数）。設定を持たないジョブは $null。
    $script:SettingsReaders = @{
        PlotRosterExport = @{ Module = 'PlotRosterExport'; Reader = 'Read-PlotRosterExportSettings' }
        SoilAnalysisTargetSync = @{ Module = 'SoilAnalysisTargetSync'; Reader = 'Read-SoilAnalysisSyncSettings' }
        PlantingRecordExport = @{ Module = 'PlantingRecordExport'; Reader = 'Read-PlantingExportSettings' }
        LastMonthPlantingDigest = @{ Module = 'LastMonthPlantingDigest'; Reader = 'Read-PlantingDigestSettings' }
        WeeklySoilAnalysisSync = $null
        MonthlyPlantingReport = @{ Module = 'JobChains'; Reader = 'Read-MonthlyPlantingReportSettings' }
    }
}

Describe 'app/config/jobs.psd1' {
    It 'defines job <_> with files that exist and a command the module exports' -TestCases $script:JobNames {
        $entry = $script:Catalog[$_]
        InModuleScope JobHost -Parameters @{ Entry = $entry } { param($Entry) Assert-JobCatalogEntryFiles -Entry $Entry }

        $module = Import-Module -Name $entry.Module -Force -PassThru -DisableNameChecking
        @($module.ExportedFunctions.Keys) | Should -Contain $entry.Command
        $entry.Command | Should -Be "Invoke-$($_)Job"
    }

    It 'has settings for exactly the jobs it defines' {
        @($script:Settings.Jobs.Keys | Sort-Object) | Should -Be @($script:Catalog.Keys | Sort-Object)
        @($script:SettingsReaders.Keys | Sort-Object) | Should -Be @($script:Catalog.Keys | Sort-Object)
    }

    It 'loads the same page scripts, in the same order, as the browser script tests do' {
        $testSupport = Get-Content -LiteralPath (Get-RepositoryPath 'tests/js/support/page.js') -Raw -Encoding UTF8
        foreach ($entry in @($script:Catalog.Values | Where-Object { $_.UsesBrowser })) {
            $helper = (Import-PowerShellDataFile -LiteralPath $entry.Operations).Helper
            $block = [regex]::Match($testSupport, "(?s)\b$helper\s*:\s*\[(.*?)\]")
            $block.Success | Should -BeTrue -Because "tests/js/support/page.js の SCRIPTS に $helper が必要"
            $testScripts = @([regex]::Matches($block.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
            $catalogScripts = @($entry.Scripts | ForEach-Object { 'app/' + $_.Substring($script:AppRoot.Length + 1).Replace('\', '/') })
            $testScripts | Should -Be $catalogScripts -Because "$($entry.Name) のスクリプト一覧"
        }
    }
}

Describe 'app/config/settings.psd1' {
    It 'passes the settings validation of job <_>' -TestCases $script:JobNames {
        $reader = $script:SettingsReaders[$_]
        if ($null -eq $reader) {
            $script:Settings.Jobs[$_].Count | Should -Be 0 -Because "$_ は設定を持たない"
            return
        }

        Import-Module -Name $script:Catalog[$_].Module -Force -DisableNameChecking
        $jobSettings = InModuleScope JobHost -Parameters @{ Settings = $script:Settings; JobName = $_; ProjectRoot = (Get-RepositoryPath '.') } {
            param($Settings, $JobName, $ProjectRoot)
            Get-HostJobSettings -Settings $Settings -JobName $JobName -ProjectRoot $ProjectRoot
        }
        $read = InModuleScope $reader.Module -Parameters @{ Reader = $reader.Reader; JobSettings = $jobSettings } {
            param($Reader, $JobSettings)
            & $Reader -Settings $JobSettings
        }
        @($read.PSObject.Properties.Name | Sort-Object) | Should -Be @($jobSettings.Keys | Sort-Object) -Because '設定ファイルのキーと、ジョブが読むキーは一致する（読まれないキーを残さない）'
    }

    It 'has valid common browser and logging settings' {
        InModuleScope JobHost -Parameters @{ Common = $script:Settings.Common } {
            param($Common)
            (Read-HostBrowserSettings -Common $Common).DebuggerUrl | Should -Match '^http://(localhost|127\.0\.0\.1):\d+/json$'
            (Read-HostLogSettings -Logging $Common.Logging).Level | Should -Be 'Info'
        }
    }

    It 'keeps run-time data under the work folder that git ignores' {
        foreach ($job in @($script:Settings.Jobs.Keys)) {
            foreach ($key in @($script:Settings.Jobs[$job].Keys | Where-Object { $_ -like '*Directory' })) {
                $script:Settings.Jobs[$job][$key] | Should -BeLike ((Get-RepositoryPath 'work') + '*') -Because "Jobs.$job.$key"
            }
        }
        Get-Content -LiteralPath (Get-RepositoryPath '.gitignore') -Encoding UTF8 | Should -Contain '/work/'
    }
}

Describe 'Launchers' {
    It 'start only jobs that the job catalog defines' {
        $launchers = @(Get-ChildItem -LiteralPath (Get-RepositoryPath '.') -Filter '*.bat' -File)
        $launchers.Count | Should -Be 2
        foreach ($launcher in $launchers) {
            $text = [System.IO.File]::ReadAllText($launcher.FullName)
            $match = [regex]::Match($text, 'app\\invoke-job\.ps1" -JobName (\w+)')
            $match.Success | Should -BeTrue -Because $launcher.Name
            @($script:Catalog.Keys) | Should -Contain $match.Groups[1].Value
            [regex]::Matches($text, '-JobName').Count | Should -Be 1 -Because "$($launcher.Name) は1つのジョブだけを起動する"
        }
    }
}
