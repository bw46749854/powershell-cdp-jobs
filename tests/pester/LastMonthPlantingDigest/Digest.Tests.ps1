BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/JobHost/JobHost.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/LastMonthPlantingDigest/LastMonthPlantingDigest.psm1') -Force

    $script:Pattern = '^.+_(GH\d-[A-Z]\d{2})\.csv$'
    $script:Headers = @('作物名', '品種', '定植日')

    function Get-Utf8Bytes {
        param([string]$Text, [bool]$Bom = $true)
        $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $Bom
        return [byte[]]($encoding.GetPreamble() + $encoding.GetBytes($Text))
    }

    function Invoke-TestDigest {
        param([string]$FileName, [byte[]]$Bytes)
        InModuleScope LastMonthPlantingDigest -Parameters @{ FileName = $FileName; Bytes = $Bytes; Pattern = $script:Pattern; Headers = $script:Headers } {
            param($FileName, $Bytes, $Pattern, $Headers)
            $range = New-LastMonthRange -Now ([datetime]'2026-04-15')
            Invoke-FileDigest -FileName $FileName -Bytes $Bytes -Range $range -RequiredHeaders $Headers -FileNamePattern $Pattern
        }
    }
}

Describe 'Invoke-FileDigest' {
    It 'keeps only plantings of the previous month and records unreadable rows with their line numbers' {
        $text = "作物名,品種,定植日`r`nトマト,桃太郎,2026-03-12`r`nレタス,シスコ,2026-02-28`r`nナス,千両`r`nピーマン,京波,未定`r`nキュウリ,夏すずみ, 2026/3/31 `r`n"

        $digest = Invoke-TestDigest -FileName 'planting_20260415_GH2-B01.csv' -Bytes (Get-Utf8Bytes -Text $text)

        $digest.Skipped | Should -BeFalse
        $digest.PlotCode | Should -Be 'GH2-B01'
        $digest.ReadRowCount | Should -Be 5
        @($digest.Rows | ForEach-Object { "$($_.'区画コード')/$($_.'作物名')/$($_.'品種')/$($_.'定植日')" }) | Should -Be @('GH2-B01/トマト/桃太郎/2026-03-12', 'GH2-B01/キュウリ/夏すずみ/2026/3/31')
        @($digest.Failures | ForEach-Object { $_.LineNumber }) | Should -Be @('4', '5')
        $digest.Failures[1].Reason | Should -Match "定植日を日付として読めない.*'未定'"
    }

    It 'skips the whole file for problems that make every row unreliable' -TestCases @(
        @{ Case = 'file name'; FileName = 'planting_20260415.csv'; Text = "作物名,品種,定植日`r`nトマト,桃太郎,2026-03-12"; Expected = '*形式に合いません*' }
        @{ Case = 'headers'; FileName = 'planting_20260415_GH2-B01.csv'; Text = "作物名,定植日,品種`r`nトマト,2026-03-12,桃太郎"; Expected = '*見出しが一致しません*順序一致=False*ファイルを飛ばしました*' }
        @{ Case = 'parsing'; FileName = 'planting_20260415_GH2-B01.csv'; Text = "作物名,品種,定植日`r`n""トマト,桃太郎,2026-03-12"; Expected = '*CSV として解析できない*引用符*' }
    ) {
        param($Case, $FileName, $Text, $Expected)
        $digest = Invoke-TestDigest -FileName $FileName -Bytes (Get-Utf8Bytes -Text $Text)
        $digest.Skipped | Should -BeTrue
        @($digest.Rows).Count | Should -Be 0
        $digest.Failures[0].Reason | Should -BeLike $Expected
    }

    It 'skips a file in an unsupported encoding' {
        $digest = Invoke-TestDigest -FileName 'planting_20260415_GH2-B01.csv' -Bytes ([byte[]]@(0x8D, 0xEC, 0x95, 0xA8, 0x96, 0xBC))
        $digest.Skipped | Should -BeTrue
        $digest.Failures[0].Reason | Should -Match '文字コードを読めない'
    }

    It 'reads tab separated files' {
        $digest = Invoke-TestDigest -FileName 'planting_20260415_GH2-B01.csv' -Bytes (Get-Utf8Bytes -Text "作物名`t品種`t定植日`nトマト`t桃太郎`t2026-03-12" -Bom $false)
        $digest.DelimiterName | Should -Be 'タブ区切り'
        @($digest.Rows).Count | Should -Be 1
    }
}

Describe 'Invoke-PlantingDigestFlow' {
    BeforeEach {
        $directory = Join-Path $TestDrive ('digest' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        New-Item -ItemType Directory -Path $directory | Out-Null
        $log = New-RecordingLog
        $ports = [pscustomobject]@{
            Log = $log
            Clock = New-ManualClock -Start ([datetime]'2026-04-15T09:30:00')
            Files = (InModuleScope JobHost { New-HostFileService })
        }
        $settings = [pscustomobject]@{
            TargetDirectory = $directory
            OutputCsvFileName = 'planting_last_month.csv'
            FailureCsvFileName = 'planting_last_month_failures.csv'
            FileNamePattern = $script:Pattern
            RequiredHeaders = $script:Headers
        }
    }

    It 'collects every file into one CSV, excludes its own outputs, and lists what was skipped' {
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'planting_20260415_GH2-B02.csv'), (Get-Utf8Bytes -Text "作物名,品種,定植日`r`nレタス,シスコ,2026-03-02"))
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'planting_20260415_GH2-B01.csv'), (Get-Utf8Bytes -Text "作物名,品種,定植日`r`nトマト,桃太郎,2026-03-12`r`nナス,千両,2026-01-20"))
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'memo.csv'), (Get-Utf8Bytes -Text "x"))
        Set-Content -LiteralPath (Join-Path $directory 'planting_last_month.csv') -Value 'old output'
        Set-Content -LiteralPath (Join-Path $directory 'planting_last_month_failures.csv') -Value 'old failures'

        $outcome = InModuleScope LastMonthPlantingDigest -Parameters @{ Ports = $ports; Settings = $settings } {
            param($Ports, $Settings)
            Invoke-PlantingDigestFlow -Ports $Ports -Settings $Settings
        }

        $outcome.InputFileCount | Should -Be 3
        $outcome.ProcessedFileCount | Should -Be 2
        $outcome.SkippedFileCount | Should -Be 1
        $rows = @(Import-Csv -LiteralPath $outcome.OutputPath -Encoding UTF8)
        @($rows | ForEach-Object { $_.'区画コード' + ':' + $_.'作物名' }) | Should -Be @('GH2-B01:トマト', 'GH2-B02:レタス')
        $failures = @(Import-Csv -LiteralPath $outcome.FailurePath -Encoding UTF8)
        $failures.Count | Should -Be 1
        $failures[0].FileName | Should -Be 'memo.csv'
        $failures[0].Timestamp | Should -Be '2026-04-15 09:30:00'
    }

    It 'writes a header-only result and removes a stale failure list when there is nothing to report' {
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'planting_20260415_GH2-B01.csv'), (Get-Utf8Bytes -Text "作物名,品種,定植日`r`nトマト,桃太郎,2026-02-12"))
        Set-Content -LiteralPath (Join-Path $directory 'planting_last_month_failures.csv') -Value 'old failures'

        $outcome = InModuleScope LastMonthPlantingDigest -Parameters @{ Ports = $ports; Settings = $settings } {
            param($Ports, $Settings)
            Invoke-PlantingDigestFlow -Ports $Ports -Settings $Settings
        }

        (Get-Content -LiteralPath $outcome.OutputPath -Encoding UTF8 -Raw).Trim() | Should -Be '"区画コード","作物名","品種","定植日"'
        Test-Path -LiteralPath $outcome.FailurePath | Should -BeFalse
    }
}

Describe 'Read-PlantingDigestSettings' {
    BeforeAll {
        $script:DigestSettings = @{
            TargetDirectory = '/work/monthly/downloads'
            OutputCsvFileName = 'planting_last_month.csv'
            FailureCsvFileName = 'planting_last_month_failures.csv'
            FileNamePattern = $script:Pattern
            RequiredHeaders = $script:Headers
        }
    }

    It 'requires the headers that become output columns' {
        $settings = $script:DigestSettings.Clone()
        $settings.RequiredHeaders = @('作物名', '品種', '植付日')
        InModuleScope LastMonthPlantingDigest -Parameters @{ Settings = $settings } {
            param($Settings)
            { Read-PlantingDigestSettings -Settings $Settings } | Should -Throw '*「定植日」が必要*'
        }
    }

    It 'requires a capturing group for the plot code in the file name pattern' {
        $settings = $script:DigestSettings.Clone()
        $settings.FileNamePattern = '^.+\.csv$'
        InModuleScope LastMonthPlantingDigest -Parameters @{ Settings = $settings } {
            param($Settings)
            { Read-PlantingDigestSettings -Settings $Settings } | Should -Throw '*グループ*'
        }
    }

    It 'returns the job result with counts' {
        $directory = Join-Path $TestDrive 'job'
        New-Item -ItemType Directory -Path $directory | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'planting_20260415_GH2-B01.csv'), (Get-Utf8Bytes -Text "作物名,品種,定植日`r`nトマト,桃太郎,2026-03-12"))
        $settings = $script:DigestSettings.Clone()
        $settings.TargetDirectory = $directory
        $context = [pscustomobject]@{
            Settings = $settings
            Services = [pscustomobject]@{ Log = (New-RecordingLog); Clock = (New-ManualClock); Files = (InModuleScope JobHost { New-HostFileService }) }
        }

        $result = Invoke-LastMonthPlantingDigestJob -Context $context
        $result.Job | Should -Be 'LastMonthPlantingDigest'
        $result.Summary.Plantings | Should -Be 1
        $result.Summary.RangeStart | Should -Be '2026-03-01'
        Test-Path -LiteralPath $result.Outputs.OutputCsvPath | Should -BeTrue
    }
}
