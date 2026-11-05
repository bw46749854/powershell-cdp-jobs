BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/LastMonthPlantingDigest/LastMonthPlantingDigest.psm1') -Force

    function Get-EncodedBytes {
        param([string]$Text, [string]$Kind)
        $encoding = switch ($Kind) {
            'utf8' { New-Object System.Text.UTF8Encoding -ArgumentList $false }
            'utf8bom' { New-Object System.Text.UTF8Encoding -ArgumentList $true }
            'utf16le' { New-Object System.Text.UnicodeEncoding -ArgumentList $false, $true }
            'utf16be' { New-Object System.Text.UnicodeEncoding -ArgumentList $true, $true }
            'utf32le' { New-Object System.Text.UTF32Encoding -ArgumentList $false, $true }
            'utf32be' { New-Object System.Text.UTF32Encoding -ArgumentList $true, $true }
        }
        $preamble = $encoding.GetPreamble()
        return [byte[]]($preamble + $encoding.GetBytes($Text))
    }
}

Describe 'ConvertFrom-CsvFileBytes' {
    It 'decodes <Kind> and reports the encoding' -TestCases @(
        @{ Kind = 'utf8'; Name = 'UTF-8（BOM なし）' }
        @{ Kind = 'utf8bom'; Name = 'UTF-8（BOM 付き）' }
        @{ Kind = 'utf16le'; Name = 'UTF-16 LE（BOM 付き）' }
        @{ Kind = 'utf16be'; Name = 'UTF-16 BE（BOM 付き）' }
        @{ Kind = 'utf32le'; Name = 'UTF-32 LE（BOM 付き）' }
        @{ Kind = 'utf32be'; Name = 'UTF-32 BE（BOM 付き）' }
    ) {
        param($Kind, $Name)
        $bytes = Get-EncodedBytes -Text '作物名,品種,定植日' -Kind $Kind
        InModuleScope LastMonthPlantingDigest -Parameters @{ Bytes = $bytes; Name = $Name } {
            param($Bytes, $Name)
            $decoded = ConvertFrom-CsvFileBytes -Bytes $Bytes
            $decoded.Text | Should -Be '作物名,品種,定植日'
            $decoded.EncodingName | Should -Be $Name
        }
    }

    It 'refuses bytes that are not valid UTF-8 and names a likely encoding' {
        $shiftJis = [byte[]]@(0x8D, 0xEC, 0x95, 0xA8, 0x96, 0xBC)
        InModuleScope LastMonthPlantingDigest -Parameters @{ Bytes = $shiftJis } {
            param($Bytes)
            { ConvertFrom-CsvFileBytes -Bytes $Bytes } | Should -Throw '*対応していない文字コード*推定:*'
        }
    }

    It 'refuses an empty file' {
        InModuleScope LastMonthPlantingDigest {
            { ConvertFrom-CsvFileBytes -Bytes ([byte[]]@()) } | Should -Throw '*空のファイル*'
        }
    }
}

Describe 'Delimited text' {
    It 'chooses tab only when the first line contains a tab' {
        InModuleScope LastMonthPlantingDigest {
            Get-DelimiterFromText -Text "a`tb`nc,d" | Should -Be "`t"
            Get-DelimiterFromText -Text "a,b`nc`td" | Should -Be ','
            { Get-DelimiterFromText -Text "`nab" } | Should -Throw '*1行目*'
            { Get-DelimiterFromText -Text '' } | Should -Throw '*空*'
        }
    }

    It 'handles quotes, escaped quotes, embedded line breaks, and records the start line of each record' {
        $text = "作物名,品種,定植日`r`n""トマト, 大玉"",""桃""""太郎"",2026-03-12`r`n""レ`r`nタス"",シスコ,2026-03-02`nナス,千両,2026-02-27"
        InModuleScope LastMonthPlantingDigest -Parameters @{ Text = $text } {
            param($Text)
            $records = @(ConvertFrom-DelimitedRecords -Text $Text -Delimiter ',')
            $records.Count | Should -Be 4
            $records[1].Fields | Should -Be @('トマト, 大玉', '桃"太郎', '2026-03-12')
            $records[2].Fields[0] | Should -Be "レ`r`nタス"
            @($records | ForEach-Object { $_.LineNumber }) | Should -Be @(1, 2, 3, 5)
        }
    }

    It 'fails on an unclosed quote with the starting line' {
        InModuleScope LastMonthPlantingDigest {
            { ConvertFrom-DelimitedRecords -Text "a,b`n""open,1" -Delimiter ',' } | Should -Throw '*引用符が閉じていません（2 行目から）*'
        }
    }

    It 'marks rows with a different field count or duplicated headers as malformed and skips blank lines' {
        InModuleScope LastMonthPlantingDigest {
            $table = Import-DelimitedTable -Text "$([char]0xFEFF)作物名,品種,定植日`n`nトマト,桃太郎`nナス,千両,2026-03-01`n" -Delimiter ','
            $table.Headers[0] | Should -Be '作物名'
            @($table.Rows).Count | Should -Be 2
            $table.Rows[0].IsMalformed | Should -BeTrue
            $table.Rows[0].LineNumber | Should -Be 3
            $table.Rows[0].MalformedReason | Should -Match '見出しの列数=3、この行の列数=2'
            $table.Rows[1].Data.'品種' | Should -Be '千両'

            $duplicated = Import-DelimitedTable -Text "作物名,作物名`nトマト,ナス" -Delimiter ','
            $duplicated.Rows[0].MalformedReason | Should -Match "見出しが重複しています: '作物名'"
        }
    }
}

Describe 'Digest policy' {
    It 'uses the previous calendar month, also across a year boundary' -TestCases @(
        @{ Now = '2026-04-15T09:30:00'; Start = '2026-03-01'; End = '2026-04-01' }
        @{ Now = '2026-01-01T00:00:00'; Start = '2025-12-01'; End = '2026-01-01' }
        @{ Now = '2026-03-31T23:59:59'; Start = '2026-02-01'; End = '2026-03-01' }
    ) {
        param($Now, $Start, $End)
        InModuleScope LastMonthPlantingDigest -Parameters @{ Now = [datetime]$Now; Start = $Start; End = $End } {
            param($Now, $Start, $End)
            $range = New-LastMonthRange -Now $Now
            $range.StartInclusive.ToString('yyyy-MM-dd') | Should -Be $Start
            $range.EndExclusive.ToString('yyyy-MM-dd') | Should -Be $End
            Test-DateInRange -Date ([datetime]$Start) -Range $range | Should -BeTrue
            Test-DateInRange -Date ([datetime]$End) -Range $range | Should -BeFalse
        }
    }

    It 'extracts the plot code from the file name case-sensitively' {
        InModuleScope LastMonthPlantingDigest {
            $pattern = '^.+_(GH\d-[A-Z]\d{2})\.csv$'
            (Get-PlotCodeFromFileName -FileName 'planting_20260415_GH2-B01.csv' -Pattern $pattern).PlotCode | Should -Be 'GH2-B01'
            (Get-PlotCodeFromFileName -FileName 'planting_20260415_gh2-b01.csv' -Pattern $pattern).IsValid | Should -BeFalse
            (Get-PlotCodeFromFileName -FileName 'notes.csv' -Pattern $pattern).Reason | Should -Match '形式に合いません: notes\.csv'
        }
    }

    It 'requires the exact headers and explains every difference' {
        InModuleScope LastMonthPlantingDigest {
            (Test-ExactHeaders -Headers @('作物名', '品種', '定植日') -Expected @('作物名', '品種', '定植日')).IsValid | Should -BeTrue

            $reordered = Test-ExactHeaders -Headers @('品種', '作物名', '定植日') -Expected @('作物名', '品種', '定植日')
            $reordered.IsValid | Should -BeFalse
            $reordered.SameOrder | Should -BeFalse
            $reordered.Reason | Should -Match '順序一致=False'

            $different = Test-ExactHeaders -Headers @('作物名', '品種', '植付日', '備考') -Expected @('作物名', '品種', '定植日')
            $different.Missing | Should -Be @('定植日')
            $different.Extra | Should -Be @('植付日', '備考')
        }
    }

    It 'reads planting dates in the agreed formats and with the Japanese culture as a fallback' -TestCases @(
        @{ Text = '2026-03-12'; Expected = '2026-03-12' }
        @{ Text = ' 2026/3/2 '; Expected = '2026-03-02' }
        @{ Text = '2026/03/02 08:15:00'; Expected = '2026-03-02' }
        @{ Text = '2026年3月2日'; Expected = '2026-03-02' }
    ) {
        param($Text, $Expected)
        InModuleScope LastMonthPlantingDigest -Parameters @{ Text = $Text; Expected = $Expected } {
            param($Text, $Expected)
            (ConvertTo-PlantingDate -Text $Text).ToString('yyyy-MM-dd') | Should -Be $Expected
        }
    }

    It 'returns null for planting dates that cannot be read' {
        InModuleScope LastMonthPlantingDigest {
            ConvertTo-PlantingDate -Text '' | Should -BeNullOrEmpty
            ConvertTo-PlantingDate -Text '未定' | Should -BeNullOrEmpty
            ConvertTo-PlantingDate -Text '2026-02-30' | Should -BeNullOrEmpty
        }
    }
}
