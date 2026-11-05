BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/JobHost/JobHost.psm1') -Force

    function New-ChainFixtureApp {
        <#
        本物の JobChains と LastMonthPlantingDigest を、ブラウザを使う子ジョブだけ差し替えたジョブ定義で動かす app。
        子ジョブの差し替えはジョブ定義（jobs.psd1）だけで行う。連携ジョブのコードには手を入れない。
        #>
        param([Parameter(Mandatory)][string]$Name)

        $projectRoot = Join-Path $TestDrive $Name
        $appRoot = Join-Path $projectRoot 'app'
        $config = Join-Path $appRoot 'config'
        $modules = Join-Path $appRoot 'modules'
        New-Item -ItemType Directory -Path $config, $modules -Force | Out-Null

        $jobKit = Get-RepositoryPath 'app/modules/JobKit/JobKit.psm1'
        Set-Content -LiteralPath (Join-Path $modules 'Stubs.psm1') -Encoding UTF8 -Value @"
Import-Module -Name '$jobKit' -DisableNameChecking

function Invoke-StubRosterExportJob {
    param([Parameter(Mandatory)]`$Context)
    `$directory = & `$Context.Services.Files.EnsureDirectory -Path `$Context.Settings.OutputDirectory -Purpose 'stub'
    `$path = Join-Path `$directory 'plot_roster.csv'
    if (-not `$Context.Settings.SkipWrite) { Set-Content -LiteralPath `$path -Value '"区画コード","担当者"' -Encoding UTF8 }
    return New-JobResult -Job 'PlotRosterExport' -Outputs @{ ExportedCsvPath = `$path }
}

function Invoke-StubSoilSyncJob {
    param([Parameter(Mandatory)]`$Context)
    `$firstLine = @(Get-Content -LiteralPath `$Context.Settings.InputCsvPath -Encoding UTF8)[0]
    return New-JobResult -Job 'SoilAnalysisTargetSync' -Outputs @{ ReceivedInputCsvPath = `$Context.Settings.InputCsvPath; FirstLine = `$firstLine }
}

function Invoke-StubPlantingExportJob {
    param([Parameter(Mandatory)]`$Context)
    `$downloads = & `$Context.Services.Files.EnsureDirectory -Path `$Context.Settings.DownloadDirectory -Purpose 'stub'
    if (-not `$Context.Settings.SkipWrite) {
        `$bytes = [System.Text.Encoding]::UTF8.GetPreamble() + [System.Text.Encoding]::UTF8.GetBytes("作物名,品種,定植日``r``nトマト,桃太郎,2026-03-12``r``nナス,千両,2026-02-20")
        [System.IO.File]::WriteAllBytes((Join-Path `$downloads 'planting_20260415_GH2-B01.csv'), [byte[]]`$bytes)
    }
    return New-JobResult -Job 'PlantingRecordExport' -Outputs @{ TempDirectory = `$Context.Settings.TempDirectory; DownloadDirectory = `$downloads }
}
"@

        $chains = Get-RepositoryPath 'app/modules/JobChains/JobChains.psm1'
        $digest = Get-RepositoryPath 'app/modules/LastMonthPlantingDigest/LastMonthPlantingDigest.psm1'
        Set-Content -LiteralPath (Join-Path $config 'jobs.psd1') -Encoding UTF8 -Value @"
@{
    Jobs = @{
        WeeklySoilAnalysisSync = @{ Module = '$chains'; Command = 'Invoke-WeeklySoilAnalysisSyncJob'; UsesBrowser = `$false }
        MonthlyPlantingReport = @{ Module = '$chains'; Command = 'Invoke-MonthlyPlantingReportJob'; UsesBrowser = `$false }
        PlotRosterExport = @{ Module = 'modules/Stubs.psm1'; Command = 'Invoke-StubRosterExportJob'; UsesBrowser = `$false }
        SoilAnalysisTargetSync = @{ Module = 'modules/Stubs.psm1'; Command = 'Invoke-StubSoilSyncJob'; UsesBrowser = `$false }
        PlantingRecordExport = @{ Module = 'modules/Stubs.psm1'; Command = 'Invoke-StubPlantingExportJob'; UsesBrowser = `$false }
        LastMonthPlantingDigest = @{ Module = '$digest'; Command = 'Invoke-LastMonthPlantingDigestJob'; UsesBrowser = `$false }
    }
}
"@
        Set-Content -LiteralPath (Join-Path $config 'settings.psd1') -Encoding UTF8 -Value @'
@{
    Common = @{ Logging = @{ Level = 'Info'; Console = $true; File = $false } }
    Jobs = @{
        WeeklySoilAnalysisSync = @{}
        MonthlyPlantingReport = @{ RunRootDirectory = 'work/monthly' }
        PlotRosterExport = @{ OutputDirectory = 'work/weekly'; SkipWrite = $false }
        SoilAnalysisTargetSync = @{ InputCsvPath = 'work/weekly/not-this-one.csv' }
        PlantingRecordExport = @{ TempDirectory = 'work/tmp'; DownloadDirectory = 'work/downloads'; DownloadFilePrefix = 'planting_'; SkipWrite = $false }
        LastMonthPlantingDigest = @{
            TargetDirectory = 'work/downloads'
            OutputCsvFileName = 'planting_last_month.csv'
            FailureCsvFileName = 'planting_last_month_failures.csv'
            FileNamePattern = '^planting_\d{8}_(GH\d-[A-Z]\d{2})\.csv$'
            RequiredHeaders = @('作物名', '品種', '定植日')
        }
    }
}
'@
        return [pscustomobject]@{ ProjectRoot = $projectRoot; AppRoot = $appRoot; Settings = (Join-Path $config 'settings.psd1') }
    }

    function New-ChainServices {
        $lines = New-CallRecorder
        return [pscustomobject]@{
            Lines = $lines
            Overrides = @{
                Clock = (New-ManualClock -Start ([datetime]'2026-04-15T09:30:00'))
                ConsoleWriter = { param($Level, $Line) [void]$lines.Add($Line) }.GetNewClosure()
            }
        }
    }

    function Set-FixtureSetting {
        param([string]$Path, [string]$Old, [string]$New)
        (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Replace($Old, $New) | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

Describe 'WeeklySoilAnalysisSync through the job host' {
    It 'passes the exported CSV to the sync job instead of the sync job''s own setting' {
        $app = New-ChainFixtureApp -Name 'weekly'
        $services = New-ChainServices

        $result = Invoke-HostedJob -AppRoot $app.AppRoot -JobName 'WeeklySoilAnalysisSync' -ServiceOverrides $services.Overrides

        $exported = [System.IO.Path]::GetFullPath((Join-Path $app.ProjectRoot 'work/weekly/plot_roster.csv'))
        $result.Outputs.InputCsvPath | Should -Be $exported
        $result.Outputs.SoilAnalysisTargetSync.ReceivedInputCsvPath | Should -Be $exported
        $result.Outputs.SoilAnalysisTargetSync.FirstLine | Should -Be '"区画コード","担当者"'
        @($services.Lines | Where-Object { $_ -match 'SoilAnalysisTargetSync 開始' }).Count | Should -Be 1
    }

    It 'stops before the sync job when the roster CSV was not written' {
        $app = New-ChainFixtureApp -Name 'weekly-missing'
        Set-FixtureSetting -Path $app.Settings -Old "OutputDirectory = 'work/weekly'; SkipWrite = `$false" -New "OutputDirectory = 'work/weekly'; SkipWrite = `$true"
        $services = New-ChainServices

        { Invoke-HostedJob -AppRoot $app.AppRoot -JobName 'WeeklySoilAnalysisSync' -ServiceOverrides $services.Overrides } | Should -Throw '*出力した CSV が見つかりません*'

        @($services.Lines | Where-Object { $_ -match 'SoilAnalysisTargetSync 開始' }).Count | Should -Be 0
        @($services.Lines | Where-Object { $_ -match 'WeeklySoilAnalysisSync は異常終了しました' }).Count | Should -Be 1
    }
}

Describe 'MonthlyPlantingReport through the job host' {
    It 'exports into a fresh run directory and digests exactly that directory' {
        $app = New-ChainFixtureApp -Name 'monthly'
        $staleDownloads = Join-Path $app.ProjectRoot 'work/downloads'
        New-Item -ItemType Directory -Path $staleDownloads -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $staleDownloads 'planting_20260301_GH9-Z99.csv') -Value 'stale' -Encoding UTF8
        $services = New-ChainServices

        $result = Invoke-HostedJob -AppRoot $app.AppRoot -JobName 'MonthlyPlantingReport' -ServiceOverrides $services.Overrides

        $runDirectory = [System.IO.Path]::GetFullPath((Join-Path $app.ProjectRoot 'work/monthly/20260415_093000'))
        $downloads = Join-Path $runDirectory 'planting_export_downloads'
        $result.Outputs.RunDirectory | Should -Be $runDirectory
        $result.Outputs.PlantingRecordExport.TempDirectory | Should -Be (Join-Path $runDirectory 'planting_export_tmp')
        $result.Outputs.PlantingRecordExport.DownloadDirectory | Should -Be $downloads
        $result.Outputs.ExportedCsvPaths | Should -Be @((Join-Path $downloads 'planting_20260415_GH2-B01.csv'))

        $digest = @(Import-Csv -LiteralPath $result.Outputs.LastMonthPlantingDigest.OutputCsvPath -Encoding UTF8)
        $digest.Count | Should -Be 1
        $digest[0].'区画コード' | Should -Be 'GH2-B01'
        $digest[0].'作物名' | Should -Be 'トマト'
        $result.Summary.LastMonthPlantingDigest.InputFiles | Should -Be 1
    }

    It 'stops before the digest job when the export saved no planting CSV' {
        $app = New-ChainFixtureApp -Name 'monthly-empty'
        Set-FixtureSetting -Path $app.Settings -Old "DownloadFilePrefix = 'planting_'; SkipWrite = `$false" -New "DownloadFilePrefix = 'planting_'; SkipWrite = `$true"
        $services = New-ChainServices

        { Invoke-HostedJob -AppRoot $app.AppRoot -JobName 'MonthlyPlantingReport' -ServiceOverrides $services.Overrides } | Should -Throw '*成果物 CSV*'

        @($services.Lines | Where-Object { $_ -match 'LastMonthPlantingDigest 開始' }).Count | Should -Be 0
    }
}
