BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/PlotRosterExport/PlotRosterExport.psm1') -Force

    $script:ValidSettings = @{
        TempDirectory = '/work/weekly/roster_tmp'
        DownloadDirectory = '/work/weekly/downloads'
        DownloadedFilePattern = '^.+\.csv$'
        OutputFileNameTemplate = 'plot_roster_{0}.csv'
        DownloadTimeoutSeconds = 120
        DownloadStableSeconds = 2
        MenuTimeoutSeconds = 10
    }

    function New-RosterTestPorts {
        param([System.Collections.ArrayList]$Calls, [hashtable]$PageOverrides = @{})

        $pageMembers = @{
            Connect = @{ Result = [pscustomobject]@{ Title = '区画一覧'; Url = 'http://localhost/plots' } }
            UseDownloadDirectory = @{ Parameters = @('Path') }
            Load = @{}
            AssertInitialScreen = @{}
            AssertExportScreen = @{}
            OpenTaskMenu = @{}
            WaitExportItemReady = @{ Parameters = @('TimeoutSeconds'); Result = $true }
            ClickExportItem = @{ Result = [pscustomobject]@{ ok = $true; action = 'export-clicked' } }
            AssertExportAccepted = @{}
        }
        foreach ($key in $PageOverrides.Keys) { $pageMembers[$key] = $PageOverrides[$key] }

        return [pscustomobject]@{
            Log = New-RecordingLog
            Clock = New-ScriptedPort -Name 'Clock' -Calls $Calls -Members @{ Now = @{ Result = [datetime]'2026-04-15T09:30:00' } }
            Files = New-ScriptedPort -Name 'Files' -Calls $Calls -Members @{
                EnsureDirectory = @{ Parameters = @('Path', 'Purpose'); Result = { param($Bound) $Bound.Path } }
                ClearDirectory = @{ Parameters = @('Path', 'Purpose') }
                MoveToUnique = @{ Parameters = @('Path', 'DestinationDirectory', 'FileName'); Result = { param($Bound) "$($Bound.DestinationDirectory)/$($Bound.FileName)" } }
            }
            Downloads = New-ScriptedPort -Name 'Downloads' -Calls $Calls -Members @{
                WaitForFile = @{ Parameters = @('Directory', 'Filter', 'NamePattern', 'TimeoutSeconds', 'StableSeconds', 'RejectEmpty'); Result = [pscustomobject]@{ Name = 'plots_export.csv'; FullName = '/work/weekly/roster_tmp/plots_export.csv'; Length = 120 } }
            }
            Page = New-ScriptedPort -Name 'Page' -Calls $Calls -Members $pageMembers
        }
    }
}

Describe 'Read-PlotRosterExportSettings' {
    It 'reads every setting with its type' {
        InModuleScope PlotRosterExport -Parameters @{ Settings = $script:ValidSettings } {
            param($Settings)
            $read = Read-PlotRosterExportSettings -Settings $Settings
            $read.MenuTimeoutSeconds | Should -Be 10
            $read.DownloadStableSeconds | Should -Be 2
            $read.OutputFileNameTemplate | Should -Be 'plot_roster_{0}.csv'
        }
    }

    It 'requires a date placeholder in the output name template' {
        $settings = $script:ValidSettings.Clone()
        $settings.OutputFileNameTemplate = 'plot_roster.csv'
        InModuleScope PlotRosterExport -Parameters @{ Settings = $settings } {
            param($Settings)
            { Read-PlotRosterExportSettings -Settings $Settings } | Should -Throw '*{0}*'
        }
    }

    It 'names the missing setting' {
        $settings = $script:ValidSettings.Clone()
        $settings.Remove('MenuTimeoutSeconds')
        InModuleScope PlotRosterExport -Parameters @{ Settings = $settings } {
            param($Settings)
            { Read-PlotRosterExportSettings -Settings $Settings } | Should -Throw '*Jobs.PlotRosterExport.MenuTimeoutSeconds がありません*'
        }
    }
}

Describe 'Get-RosterExportFileName' {
    It 'inserts the month and day of the run date' {
        InModuleScope PlotRosterExport {
            Get-RosterExportFileName -Template 'plot_roster_{0}.csv' -Date ([datetime]'2026-04-05') | Should -Be 'plot_roster_0405.csv'
        }
    }

    It 'rejects names that are not CSV or not a plain file name' {
        InModuleScope PlotRosterExport {
            { Get-RosterExportFileName -Template 'plot_roster_{0}.txt' -Date ([datetime]'2026-04-05') } | Should -Throw '*.csv で終わる*'
            { Get-RosterExportFileName -Template 'sub/plot_{0}.csv' -Date ([datetime]'2026-04-05') } | Should -Throw '*使えない文字*'
        }
    }
}

Describe 'Invoke-PlotRosterExportFlow' {
    It 'prepares directories, validates the screen, exports, waits for the download, and saves it under the dated name' {
        $calls = New-CallRecorder
        $ports = New-RosterTestPorts -Calls $calls

        $outcome = InModuleScope PlotRosterExport -Parameters @{ Ports = $ports; Settings = $script:ValidSettings } {
            param($Ports, $Settings)
            Invoke-PlotRosterExportFlow -Ports $Ports -Settings (Read-PlotRosterExportSettings -Settings $Settings)
        }

        $outcome.ExportedCsvPath | Should -Be '/work/weekly/downloads/plot_roster_0415.csv'
        $outcome.DownloadedCsvPath | Should -Be '/work/weekly/roster_tmp/plots_export.csv'

        (Get-PortCalls -Calls $calls | Where-Object { $_ -ne 'Clock.Now' }) | Should -Be @(
            'Files.EnsureDirectory', 'Files.EnsureDirectory', 'Files.ClearDirectory',
            'Page.Connect', 'Page.UseDownloadDirectory', 'Page.Load',
            'Page.AssertInitialScreen', 'Page.AssertExportScreen',
            'Page.OpenTaskMenu', 'Page.WaitExportItemReady', 'Page.ClickExportItem', 'Page.AssertExportAccepted',
            'Downloads.WaitForFile', 'Files.MoveToUnique'
        )

        $clear = @($calls | Where-Object { $_.Member -eq 'ClearDirectory' })[0]
        $clear.Arguments.Path | Should -Be '/work/weekly/roster_tmp'
        $wait = @($calls | Where-Object { $_.Member -eq 'WaitForFile' })[0]
        $wait.Arguments.Filter | Should -Be '*.csv'
        $wait.Arguments.RejectEmpty | Should -BeTrue
        $wait.Arguments.Directory | Should -Be '/work/weekly/roster_tmp'
        (@($calls | Where-Object { $_.Member -eq 'WaitExportItemReady' })[0]).Arguments.TimeoutSeconds | Should -Be 10
    }

    It 'never clicks export or waits for a download when the screen contract fails' {
        $calls = New-CallRecorder
        $ports = New-RosterTestPorts -Calls $calls -PageOverrides @{ AssertExportScreen = @{ Result = { param($Bound) throw 'ページ契約違反: CSV 出力前の画面' } } }

        InModuleScope PlotRosterExport -Parameters @{ Ports = $ports; Settings = $script:ValidSettings } {
            param($Ports, $Settings)
            { Invoke-PlotRosterExportFlow -Ports $Ports -Settings (Read-PlotRosterExportSettings -Settings $Settings) } | Should -Throw '*ページ契約違反*'
        }

        (Get-PortCalls -Calls $calls) | Should -Not -Contain 'Page.ClickExportItem'
        (Get-PortCalls -Calls $calls) | Should -Not -Contain 'Downloads.WaitForFile'
    }
}

Describe 'Plot roster page port' {
    It 'maps business-named page actions to catalog operations' {
        $calls = New-CallRecorder
        $browser = New-ScriptedPort -Name 'Browser' -Calls $calls -Members @{
            Connect = @{}; Inject = @{}; SetDownloadDirectory = @{ Parameters = @('Path') }
            Invoke = @{ Parameters = @('Operation', 'Arguments', 'TimeoutSeconds') }
            WaitUntil = @{ Parameters = @('Operation', 'Arguments', 'TimeoutSeconds', 'Description') }
            Assert = @{ Parameters = @('Operation', 'Arguments', 'TimeoutSeconds', 'Description') }
        }

        InModuleScope PlotRosterExport -Parameters @{ Browser = $browser } {
            param($Browser)
            $page = New-PlotRosterPage -Browser $Browser
            & $page.AssertInitialScreen
            & $page.OpenTaskMenu
            & $page.WaitExportItemReady -TimeoutSeconds 7
            & $page.ClickExportItem
            & $page.AssertExportAccepted
        }

        @($calls | ForEach-Object { "$($_.Member):$($_.Arguments.Operation)" }) | Should -Be @(
            'Assert:CheckInitialScreen', 'Invoke:OpenTaskMenu', 'WaitUntil:IsExportItemReady', 'Invoke:ClickExportItem', 'Assert:CheckExportAccepted'
        )
        $calls[2].Arguments.TimeoutSeconds | Should -Be 7
    }
}

Describe 'Invoke-PlotRosterExportJob' {
    It 'returns the saved CSV path through the job result protocol' {
        $calls = New-CallRecorder
        $ports = New-RosterTestPorts -Calls $calls
        $browser = [pscustomobject]@{}
        $context = [pscustomobject]@{
            Settings = $script:ValidSettings
            Services = [pscustomobject]@{ Log = $ports.Log; Clock = $ports.Clock; Files = $ports.Files; Downloads = $ports.Downloads; Browser = $browser }
        }

        InModuleScope PlotRosterExport -Parameters @{ Context = $context; Page = $ports.Page } {
            param($Context, $Page)
            Mock New-PlotRosterPage { $Page }
            $result = Invoke-PlotRosterExportJob -Context $Context
            $result.Job | Should -Be 'PlotRosterExport'
            $result.Outputs.ExportedCsvPath | Should -Be '/work/weekly/downloads/plot_roster_0415.csv'
        }
    }

    It 'refuses to run without the browser service' {
        $context = [pscustomobject]@{ Settings = $script:ValidSettings; Services = [pscustomobject]@{ Browser = $null } }
        { Invoke-PlotRosterExportJob -Context $context } | Should -Throw '*UsesBrowser*'
    }

    It 'has an operation catalog that PageBridge accepts' {
        Import-Module (Get-RepositoryPath 'app/modules/PageBridge/PageBridge.psm1') -Force
        $catalog = Import-PageOperationCatalog -Path (Get-RepositoryPath 'app/modules/PlotRosterExport/PageOperations.psd1')
        $catalog.Helper | Should -Be 'plotRosterExport'
        $catalog.IdentityOperation | Should -Be 'DetectScreen'
    }
}
