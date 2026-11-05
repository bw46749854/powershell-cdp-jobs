BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/JobHost/JobHost.psm1') -Force

    function Write-DataFile {
        param([Parameter(Mandatory)][string]$Body)
        $path = Join-Path $TestDrive ("data_{0}.psd1" -f [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $path -Value $Body -Encoding UTF8
        return $path
    }
}

Describe 'Import-HostSettings' {
    It 'resolves *Path and *Directory values against the project root, in nested tables too' {
        $env:GH_TEST_DATA = (Join-Path $TestDrive 'envdata')
        $path = Write-DataFile -Body @'
@{
    Common = @{ Logging = @{ Directory = 'work\logs' }; Browser = @{ DebuggerUrl = 'http://localhost:9222/json' } }
    Jobs = @{
        Sample = @{
            TempDirectory = 'work/tmp'
            InputCsvPath = '%GH_TEST_DATA%\input.csv'
            OutputCsvFileName = 'out.csv'
            Nested = @{ ArchiveDirectory = 'archive' }
        }
    }
}
'@
        InModuleScope JobHost -Parameters @{ Path = $path; Root = $TestDrive } {
            param($Path, $Root)
            $settings = Import-HostSettings -Path $Path -ProjectRoot $Root
            $sample = $settings.Jobs.Sample

            $sample.TempDirectory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path (Join-Path $Root 'work') 'tmp')))
            $sample.InputCsvPath | Should -Be ([System.IO.Path]::GetFullPath((Join-Path (Join-Path $Root 'envdata') 'input.csv')))
            $sample.Nested.ArchiveDirectory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $Root 'archive')))
            $sample.OutputCsvFileName | Should -Be 'out.csv'
            $settings.Common.Logging.Directory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path (Join-Path $Root 'work') 'logs')))
            $settings.Common.Browser.DebuggerUrl | Should -Be 'http://localhost:9222/json'
        }
    }

    It 'requires Common and Jobs tables' {
        $path = Write-DataFile -Body "@{ Jobs = @{} }"
        InModuleScope JobHost -Parameters @{ Path = $path; Root = $TestDrive } {
            param($Path, $Root)
            { Import-HostSettings -Path $Path -ProjectRoot $Root } | Should -Throw '*Common*'
            { Import-HostSettings -Path (Join-Path $Root 'nope.psd1') -ProjectRoot $Root } | Should -Throw '*見つかりません*'
        }
    }
}

Describe 'Get-HostJobSettings' {
    It 'returns a deep copy with resolved overrides applied' {
        InModuleScope JobHost -Parameters @{ Root = $TestDrive } {
            param($Root)
            $settings = @{ Common = @{}; Jobs = @{ Sample = @{ TargetDirectory = '/original'; Headers = @('A', 'B'); Limit = 3 } } }

            $copy = Get-HostJobSettings -Settings $settings -JobName 'Sample' -Overrides @{ TargetDirectory = 'runs/20260415' } -ProjectRoot $Root
            $copy.TargetDirectory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path (Join-Path $Root 'runs') '20260415')))
            @($copy.Headers) | Should -Be @('A', 'B')

            $copy.Headers[0] = 'changed'
            $copy.Limit = 9
            $settings.Jobs.Sample.Headers[0] | Should -Be 'A'
            $settings.Jobs.Sample.Limit | Should -Be 3
            $settings.Jobs.Sample.TargetDirectory | Should -Be '/original'
        }
    }

    It 'fails clearly when the job has no settings' {
        InModuleScope JobHost {
            { Get-HostJobSettings -Settings @{ Common = @{}; Jobs = @{} } -JobName 'Missing' -ProjectRoot '/' } | Should -Throw '*Jobs.Missing*'
        }
    }
}

Describe 'Import-JobCatalog' {
    It 'resolves module, operation catalog, and script paths against the app root' {
        $path = Write-DataFile -Body @'
@{
    Jobs = @{
        BrowserJob = @{
            Module = 'modules/BrowserJob/BrowserJob.psm1'
            Command = 'Invoke-BrowserJobJob'
            UsesBrowser = $true
            Browser = @{
                Operations = 'modules\BrowserJob\PageOperations.psd1'
                Scripts = @('browser/kernel/pagekit.js', 'browser/features/x.js')
            }
        }
        FileJob = @{ Module = 'modules/FileJob/FileJob.psm1'; Command = 'Invoke-FileJobJob'; UsesBrowser = $false }
    }
}
'@
        InModuleScope JobHost -Parameters @{ Path = $path; AppRoot = (Join-Path $TestDrive 'app') } {
            param($Path, $AppRoot)
            $catalog = Import-JobCatalog -Path $Path -AppRoot $AppRoot

            $browserJob = Get-JobCatalogEntry -Catalog $catalog -JobName 'BrowserJob'
            $browserJob.UsesBrowser | Should -BeTrue
            $browserJob.Module | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $AppRoot 'modules/BrowserJob/BrowserJob.psm1')))
            $browserJob.Operations | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $AppRoot 'modules/BrowserJob/PageOperations.psd1')))
            @($browserJob.Scripts).Count | Should -Be 2
            $browserJob.Scripts[1] | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $AppRoot 'browser/features/x.js')))

            $fileJob = Get-JobCatalogEntry -Catalog $catalog -JobName 'FileJob'
            $fileJob.UsesBrowser | Should -BeFalse
            @($fileJob.Scripts).Count | Should -Be 0
        }
    }

    It 'rejects job definitions that break the catalog rules' -TestCases @(
        @{ Case = 'unknown key'; Entry = "@{ Module = 'm.psm1'; Command = 'Invoke-XJob'; UsesBrowser = `$false; DomScripts = @() }"; Expected = "*未知のキー 'DomScripts'*" }
        @{ Case = 'implicit UsesBrowser'; Entry = "@{ Module = 'm.psm1'; Command = 'Invoke-XJob' }"; Expected = '*UsesBrowser*明示*' }
        @{ Case = 'browser job without Browser'; Entry = "@{ Module = 'm.psm1'; Command = 'Invoke-XJob'; UsesBrowser = `$true }"; Expected = '*Browser（Operations と Scripts）が必要*' }
        @{ Case = 'file job with Browser'; Entry = "@{ Module = 'm.psm1'; Command = 'Invoke-XJob'; UsesBrowser = `$false; Browser = @{} }"; Expected = '*Browser は指定できません*' }
        @{ Case = 'scripts as a single string'; Entry = "@{ Module = 'm.psm1'; Command = 'Invoke-XJob'; UsesBrowser = `$true; Browser = @{ Operations = 'o.psd1'; Scripts = 'a.js' } }"; Expected = '*配列*' }
        @{ Case = 'empty scripts'; Entry = "@{ Module = 'm.psm1'; Command = 'Invoke-XJob'; UsesBrowser = `$true; Browser = @{ Operations = 'o.psd1'; Scripts = @() } }"; Expected = '*配列*' }
        @{ Case = 'bad command name'; Entry = "@{ Module = 'm.psm1'; Command = 'Invoke XJob; Remove-Item'; UsesBrowser = `$false }"; Expected = '*動詞-名詞*' }
        @{ Case = 'missing module'; Entry = "@{ Command = 'Invoke-XJob'; UsesBrowser = `$false }"; Expected = '*Module*' }
    ) {
        param($Case, $Entry, $Expected)
        $path = Write-DataFile -Body "@{ Jobs = @{ X = $Entry } }"
        InModuleScope JobHost -Parameters @{ Path = $path; Expected = $Expected } {
            param($Path, $Expected)
            { Import-JobCatalog -Path $Path -AppRoot '/app' } | Should -Throw $Expected
        }
    }

    It 'lists defined jobs when an unknown job name is requested' {
        InModuleScope JobHost {
            $catalog = @{ Alpha = [pscustomobject]@{}; Beta = [pscustomobject]@{} }
            { Get-JobCatalogEntry -Catalog $catalog -JobName 'Gamma' } | Should -Throw '*Gamma*Alpha, Beta*'
        }
    }

    It 'reports every missing file of a job before it starts' {
        InModuleScope JobHost -Parameters @{ Root = $TestDrive } {
            param($Root)
            $module = Join-Path $Root 'exists.psm1'
            Set-Content -LiteralPath $module -Value '' -Encoding UTF8
            $entry = [pscustomobject]@{ Name = 'X'; Module = $module; UsesBrowser = $true; Operations = (Join-Path $Root 'ops.psd1'); Scripts = @((Join-Path $Root 'a.js')) }

            { Assert-JobCatalogEntryFiles -Entry $entry } | Should -Throw '*ops.psd1*a.js*'
        }
    }
}
