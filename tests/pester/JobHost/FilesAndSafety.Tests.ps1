BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/JobHost/JobHost.psm1') -Force
}

Describe 'Safe directory rules' {
    It 'refuses locations whose contents must never be cleared' -TestCases @(
        @{ Case = 'empty'; Path = ''; Expected = '*指定されていません*' }
        @{ Case = 'filesystem root'; Path = '#root'; Expected = '*ルート*' }
        @{ Case = 'user profile'; Path = '#home'; Expected = '*ユーザープロファイルそのもの*' }
        @{ Case = 'direct child of the profile'; Path = '#home-child'; Expected = '*ユーザープロファイル直下*' }
    ) {
        param($Case, $Path, $Expected)
        $homeDirectory = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
        $resolved = switch ($Path) {
            '#root' { [System.IO.Path]::GetPathRoot($TestDrive) }
            '#home' { $homeDirectory }
            '#home-child' { Join-Path $homeDirectory 'Downloads' }
            default { $Path }
        }

        InModuleScope JobHost -Parameters @{ Path = $resolved; Expected = $Expected } {
            param($Path, $Expected)
            { Assert-SafeDirectoryPath -Path $Path -Purpose '作業' } | Should -Throw $Expected
        }
    }

    It 'accepts a dedicated folder below the profile child and returns a normalized path' {
        $homeDirectory = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
        $nested = Join-Path (Join-Path $homeDirectory 'Downloads') 'greenhouse-work'
        InModuleScope JobHost -Parameters @{ Path = ($nested + [System.IO.Path]::DirectorySeparatorChar) ; Nested = $nested } {
            param($Path, $Nested)
            Assert-SafeDirectoryPath -Path $Path -Purpose '作業' | Should -Be $Nested
        }
    }

    It 'checks containment by path segments, not by string prefix' {
        InModuleScope JobHost -Parameters @{ Root = $TestDrive } {
            param($Root)
            $base = Join-Path $Root 'out'
            Test-PathWithinDirectory -Path (Join-Path $base 'a.csv') -Directory $base | Should -BeTrue
            Test-PathWithinDirectory -Path (Join-Path (Join-Path $base 'sub') 'a.csv') -Directory $base | Should -BeTrue
            Test-PathWithinDirectory -Path (Join-Path ($base + '2') 'a.csv') -Directory $base | Should -BeFalse
            Test-PathWithinDirectory -Path $base -Directory $base | Should -BeFalse
            Test-PathWithinDirectory -Path (Join-Path (Join-Path $base '..') 'a.csv') -Directory $base | Should -BeFalse
        }
    }
}

Describe 'Files service' {
    BeforeEach {
        $files = InModuleScope JobHost { New-HostFileService }
        $work = Join-Path $TestDrive ('w' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    }

    It 'creates directories and clears only their contents' {
        $directory = & $files.EnsureDirectory -Path $work -Purpose '作業'
        Test-Path -LiteralPath $directory -PathType Container | Should -BeTrue
        New-Item -ItemType File -Path (Join-Path $directory 'a.csv') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $directory 'sub') | Out-Null
        New-Item -ItemType File -Path (Join-Path (Join-Path $directory 'sub') 'b.csv') | Out-Null

        & $files.ClearDirectory -Path $directory -Purpose '作業'

        @(Get-ChildItem -LiteralPath $directory -Force).Count | Should -Be 0
        Test-Path -LiteralPath $directory | Should -BeTrue
    }

    It 'removes a file only inside the allowed directory' {
        $directory = & $files.EnsureDirectory -Path $work -Purpose '作業'
        $inside = Join-Path $directory 'old.csv'
        Set-Content -LiteralPath $inside -Value 'x'
        $outside = Join-Path $TestDrive 'outside.csv'
        Set-Content -LiteralPath $outside -Value 'x'

        & $files.RemoveFile -Path $inside -Within $directory | Should -BeTrue
        & $files.RemoveFile -Path $inside -Within $directory | Should -BeFalse
        { & $files.RemoveFile -Path $outside -Within $directory } | Should -Throw '*許可ディレクトリの配下にありません*'
        Test-Path -LiteralPath $outside | Should -BeTrue

        New-Item -ItemType Directory -Path (Join-Path $directory 'folder.csv') | Out-Null
        { & $files.RemoveFile -Path (Join-Path $directory 'folder.csv') -Within $directory } | Should -Throw '*ファイルではありません*'
    }

    It 'lists files by name with their size' {
        $directory = & $files.EnsureDirectory -Path $work -Purpose '作業'
        Set-Content -LiteralPath (Join-Path $directory 'b.csv') -Value 'bb' -NoNewline
        Set-Content -LiteralPath (Join-Path $directory 'a.csv') -Value 'a' -NoNewline
        Set-Content -LiteralPath (Join-Path $directory 'c.txt') -Value 'c' -NoNewline

        $listed = @(& $files.ListFiles -Directory $directory -Filter '*.csv')
        @($listed | ForEach-Object { $_.Name }) | Should -Be @('a.csv', 'b.csv')
        $listed[1].Length | Should -Be 2
    }

    It 'reads UTF-8 text with or without a BOM, and bytes as a single array' {
        $directory = & $files.EnsureDirectory -Path $work -Purpose '作業'
        $withBom = Join-Path $directory 'bom.txt'
        [System.IO.File]::WriteAllText($withBom, '区画コード', (New-Object System.Text.UTF8Encoding -ArgumentList $true))

        & $files.ReadText -Path $withBom | Should -Be '区画コード'
        $bytes = & $files.ReadBytes -Path $withBom
        $bytes.GetType().Name | Should -Be 'Byte[]'
        $bytes[0] | Should -Be 0xEF
    }

    It 'saves CSV with a BOM, CRLF line ends, the given column order, and quoted fields' {
        $directory = & $files.EnsureDirectory -Path $work -Purpose '作業'
        $path = Join-Path $directory 'out.csv'
        $rows = @(
            [pscustomobject]@{ B = 'say "hi"'; A = 1; Extra = 'ignored' },
            @{ A = $null; B = "two`nlines" }
        )

        $saved = & $files.SaveCsv -Path $path -Rows $rows -Columns @('A', 'B') -Within $directory -WhenEmpty 'Remove'

        $saved.Written | Should -BeTrue
        $saved.Count | Should -Be 2
        $bytes = [System.IO.File]::ReadAllBytes($path)
        @($bytes[0], $bytes[1], $bytes[2]) | Should -Be @(0xEF, 0xBB, 0xBF)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
        $text | Should -Be ("""A"",""B""`r`n""1"",""say """"hi""""""`r`n"""",""two`nlines""`r`n")
    }

    It 'removes a stale CSV or writes only the header when there are no rows' {
        $directory = & $files.EnsureDirectory -Path $work -Purpose '作業'
        $failures = Join-Path $directory 'failures.csv'
        Set-Content -LiteralPath $failures -Value 'stale'

        $removed = & $files.SaveCsv -Path $failures -Rows @() -Columns @('A') -Within $directory -WhenEmpty 'Remove'
        $removed.Removed | Should -BeTrue
        $removed.Written | Should -BeFalse
        Test-Path -LiteralPath $failures | Should -BeFalse

        $report = Join-Path $directory 'report.csv'
        $headerOnly = & $files.SaveCsv -Path $report -Rows @() -Columns @('区画コード', '作物名') -Within $directory -WhenEmpty 'HeaderOnly'
        $headerOnly.Written | Should -BeTrue
        (& $files.ReadText -Path $report) | Should -Be ("""区画コード"",""作物名""`r`n")
    }

    It 'refuses to write a CSV outside the allowed directory' {
        $directory = & $files.EnsureDirectory -Path $work -Purpose '作業'
        { & $files.SaveCsv -Path (Join-Path $TestDrive 'elsewhere.csv') -Rows @() -Columns @('A') -Within $directory -WhenEmpty 'HeaderOnly' } |
            Should -Throw '*許可ディレクトリの配下にありません*'
    }

    It 'moves a file to a unique name in the destination' {
        $source = & $files.EnsureDirectory -Path (Join-Path $work 'src') -Purpose '作業'
        $destination = Join-Path $work 'dest'
        foreach ($name in @('one', 'two', 'three')) {
            Set-Content -LiteralPath (Join-Path $source "$name.csv") -Value $name
        }

        $first = & $files.MoveToUnique -Path (Join-Path $source 'one.csv') -DestinationDirectory $destination -FileName 'plot.csv'
        $second = & $files.MoveToUnique -Path (Join-Path $source 'two.csv') -DestinationDirectory $destination -FileName 'plot.csv'
        $third = & $files.MoveToUnique -Path (Join-Path $source 'three.csv') -DestinationDirectory $destination -FileName 'plot.csv'

        Split-Path -Leaf $first | Should -Be 'plot.csv'
        Split-Path -Leaf $second | Should -Be 'plot (1).csv'
        Split-Path -Leaf $third | Should -Be 'plot (2).csv'
        (Get-Content -LiteralPath $third) | Should -Be 'three'
    }

    It 'rejects file names that could escape the destination' {
        $source = & $files.EnsureDirectory -Path $work -Purpose '作業'
        $file = Join-Path $source 'a.csv'
        Set-Content -LiteralPath $file -Value 'a'
        { & $files.MoveToUnique -Path $file -DestinationDirectory $work -FileName '../a.csv' } | Should -Throw '*使えない文字*'
    }
}
