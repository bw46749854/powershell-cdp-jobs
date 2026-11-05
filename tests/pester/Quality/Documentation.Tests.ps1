BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $script:MarkdownFiles = @(
        @(Get-Item -LiteralPath (Join-Path $root 'README.md'), (Join-Path $root 'ARCHITECTURE.md'), (Join-Path $root 'mock/README.md'), (Join-Path $root 'tools/vendor/README.md')) +
        @(Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Recurse -File -Filter '*.md') |
            Sort-Object FullName |
            ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Length + 1).Replace('\', '/') } }
    )
    $script:JobNames = @((Import-PowerShellDataFile -LiteralPath (Join-Path $root 'app/config/jobs.psd1')).Jobs.Keys | Sort-Object)
}

# 文書の網羅と正しさを確かめる（docs/README.md「文書を保守する約束」）。
# 掲載漏れで失敗したら、文書を直してからテストを通す（テストの対象から外さない）。

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    $script:Root = Get-RepositoryPath '.'

    function Get-MarkdownText {
        param([Parameter(Mandatory)][string]$Path)
        $text = [System.IO.File]::ReadAllText($Path)
        # コードブロックの中はリンクとして扱わない
        return [regex]::Replace($text, '(?ms)^```.*?^```', '')
    }

    function Get-MarkdownLinks {
        param([Parameter(Mandatory)][string]$Path)
        # インラインのコード（`…`）の中もリンクとして扱わない
        $text = [regex]::Replace((Get-MarkdownText -Path $Path), '`[^`\r\n]*`', '')
        return @([regex]::Matches($text, '\[[^\]]*\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '^(https?|mailto):' })
    }

    function ConvertTo-HeadingSlug {
        # GitHub の見出しのアンカーと同じ規則（小文字にし、文字・数字・空白・- ・_ 以外を除き、空白を - にする）
        param([Parameter(Mandatory)][string]$Heading)
        $slug = [regex]::Replace($Heading.Trim().ToLowerInvariant(), '[^\p{L}\p{N}\p{M} _-]', '')
        return $slug.Replace(' ', '-')
    }

    function Get-HeadingSlugs {
        param([Parameter(Mandatory)][string]$Path)
        $counts = @{}
        return @(foreach ($match in [regex]::Matches((Get-MarkdownText -Path $Path), '(?m)^#{1,6}\s+(.+?)\s*$')) {
                $slug = ConvertTo-HeadingSlug -Heading $match.Groups[1].Value
                if ($counts.ContainsKey($slug)) { $counts[$slug]++; "$slug-$($counts[$slug])" } else { $counts[$slug] = 0; $slug }
            })
    }

    function Resolve-LinkTarget {
        param([Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$Link)
        $pathPart = $Link.Split('#')[0]
        if ([string]::IsNullOrEmpty($pathPart)) { return $From }
        return [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $From) ([System.Uri]::UnescapeDataString($pathPart))))
    }

    function Get-LinkedTargets {
        param([Parameter(Mandatory)][string]$Path)
        return @(Get-MarkdownLinks -Path $Path | ForEach-Object { Resolve-LinkTarget -From $Path -Link $_ })
    }

    function Get-MarkdownSection {
        # 見出しの文言がちょうど Heading の節（次の同じか上の階層の見出しまで）
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Heading)
        $text = Get-MarkdownText -Path $Path
        $match = [regex]::Match($text, '(?ms)^(#{1,6})\s+' + [regex]::Escape($Heading) + '\s*$(.*?)(?=^#{1,6}\s)')
        if (-not $match.Success) { $match = [regex]::Match($text, '(?ms)^(#{1,6})\s+' + [regex]::Escape($Heading) + '\s*$(.*)') }
        if (-not $match.Success) { return $null }
        return $match.Groups[2].Value
    }

    function ConvertTo-KebabCase {
        param([Parameter(Mandatory)][string]$Name)
        return ([regex]::Replace($Name, '(?<=[a-z0-9])([A-Z])', '-$1')).ToLowerInvariant()
    }

    $script:Catalog = Import-PowerShellDataFile -LiteralPath (Get-RepositoryPath 'app/config/jobs.psd1')
}

Describe 'Markdown <Name>' -ForEach $script:MarkdownFiles {
    It 'links only to files and headings that exist' {
        $broken = foreach ($link in @(Get-MarkdownLinks -Path $Path)) {
            $target = Resolve-LinkTarget -From $Path -Link $link
            if (-not (Test-Path -LiteralPath $target)) { "$link（ファイルが無い）"; continue }
            if ($link.Contains('#')) {
                $anchor = [System.Uri]::UnescapeDataString($link.Substring($link.IndexOf('#') + 1))
                if ((Test-Path -LiteralPath $target -PathType Leaf) -and $target -like '*.md' -and @(Get-HeadingSlugs -Path $target) -notcontains $anchor) { "$link（見出しが無い）" }
            }
        }
        @($broken) | Should -BeNullOrEmpty
    }
}

Describe 'Documentation coverage' {
    It 'indexes every guide, job, module and browser document in docs/README.md' {
        $linked = @(Get-LinkedTargets -Path (Get-RepositoryPath 'docs/README.md'))
        foreach ($folder in @('guides', 'jobs', 'modules', 'browser')) {
            foreach ($file in @(Get-ChildItem -LiteralPath (Get-RepositoryPath "docs/$folder") -Filter '*.md')) {
                $linked | Should -Contain $file.FullName -Because "docs/README.md に docs/$folder/$($file.Name) が無い"
            }
        }
        $linked | Should -Contain (Get-RepositoryPath 'docs/decisions/README.md')
    }

    It 'indexes every decision record in docs/decisions/README.md' {
        $linked = @(Get-LinkedTargets -Path (Get-RepositoryPath 'docs/decisions/README.md'))
        foreach ($file in @(Get-ChildItem -LiteralPath (Get-RepositoryPath 'docs/decisions') -Filter '0*.md')) {
            $linked | Should -Contain $file.FullName -Because $file.Name
        }
    }

    It 'has a document for job <_> that the README lists' -TestCases $script:JobNames {
        $document = Get-RepositoryPath ("docs/jobs/{0}.md" -f (ConvertTo-KebabCase -Name $_))
        Test-Path -LiteralPath $document | Should -BeTrue
        @(Get-LinkedTargets -Path (Get-RepositoryPath 'README.md')) | Should -Contain $document
    }

    It 'lists every file of every module in its document' {
        foreach ($module in @(Get-ChildItem -LiteralPath (Get-RepositoryPath 'app/modules') -Directory)) {
            $documents = @(Get-RepositoryPath "docs/modules/$($module.Name).md" | Where-Object { Test-Path -LiteralPath $_ })
            foreach ($job in @($script:Catalog.Jobs.Keys)) {
                if ($script:Catalog.Jobs[$job].Module -eq "modules/$($module.Name)/$($module.Name).psm1") {
                    $documents += Get-RepositoryPath ("docs/jobs/{0}.md" -f (ConvertTo-KebabCase -Name $job))
                }
            }
            $documents.Count | Should -BeGreaterThan 0 -Because "$($module.Name) の文書が無い"
            $linked = @($documents | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-LinkedTargets -Path $_ })
            foreach ($file in @(Get-ChildItem -LiteralPath $module.FullName -Recurse -File)) {
                $linked | Should -Contain $file.FullName -Because "$($module.Name) の文書に $($file.FullName.Substring($module.FullName.Length + 1)) が無い"
            }
        }
    }

    It 'describes every setting in docs/guides/configuration.md' {
        $guide = Get-RepositoryPath 'docs/guides/configuration.md'
        $settings = Import-PowerShellDataFile -LiteralPath (Get-RepositoryPath 'app/config/settings.psd1')
        $sections = @{}
        foreach ($name in @($settings.Common.Keys)) { $sections["Common.$name"] = $settings.Common[$name] }
        foreach ($name in @($settings.Jobs.Keys)) { $sections["Jobs.$name"] = $settings.Jobs[$name] }

        foreach ($heading in @($sections.Keys | Sort-Object)) {
            $section = Get-MarkdownSection -Path $guide -Heading $heading
            $section | Should -Not -BeNullOrEmpty -Because "configuration.md に「### $heading」の節が無い"
            foreach ($key in @($sections[$heading].Keys)) {
                $section | Should -Match ('`' + [regex]::Escape($key) + '`') -Because "configuration.md の $heading に $key が無い"
            }
        }
    }

    It 'lists every page script in docs/browser/page-contracts.md' {
        $linked = @(Get-LinkedTargets -Path (Get-RepositoryPath 'docs/browser/page-contracts.md'))
        foreach ($file in @(Get-ChildItem -LiteralPath (Get-RepositoryPath 'app/browser') -Recurse -File -Filter '*.js')) {
            $linked | Should -Contain $file.FullName -Because $file.Name
        }
    }

    It 'says when to update each guide, job, module, browser and mock document' {
        $documents = @(foreach ($folder in @('guides', 'jobs', 'modules', 'browser')) { Get-ChildItem -LiteralPath (Get-RepositoryPath "docs/$folder") -Filter '*.md' }) + @(Get-Item -LiteralPath (Get-RepositoryPath 'mock/README.md'))
        foreach ($document in $documents) {
            [System.IO.File]::ReadAllText($document.FullName) | Should -Match '(?m)^## この文書を更新するとき\s*$' -Because $document.Name
        }
    }
}

Describe 'Help for public functions' {
    It 'gives every exported function a synopsis' {
        foreach ($file in @(Get-ChildItem -LiteralPath (Get-RepositoryPath 'app/modules') -Recurse -File -Filter '*.ps1' | Where-Object { $_.Directory.Name -eq 'Public' })) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            foreach ($function in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))) {
                $help = $function.GetHelpContent()
                ($null -ne $help -and -not [string]::IsNullOrWhiteSpace($help.Synopsis)) | Should -BeTrue -Because "$($function.Name)（$($file.Name)）に .SYNOPSIS が無い"
            }
        }
    }
}
