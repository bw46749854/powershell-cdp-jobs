# 文字コード・改行・起動ファイルの約束を確かめる（.editorconfig / .gitattributes / docs/guides/powershell-compatibility.md）。
#
#   *.ps1 / *.psm1 / *.psd1 : UTF-8（BOM 付き）、LF   … Windows PowerShell 5.1 は BOM の無い UTF-8 を ANSI として読む
#   *.bat                   : ASCII だけ、CRLF       … cmd.exe は OEM コードページで読み、LF だけの行で誤動作することがある
#   それ以外のテキスト      : UTF-8（BOM なし）、LF

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    $script:Root = Get-RepositoryPath '.'
}

Describe 'Source encoding and line endings' {
    It 'passes tools/Repair-SourceEncoding.ps1 -Check' {
        $output = & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Get-RepositoryPath 'tools/Repair-SourceEncoding.ps1') -Check 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }

    It 'keeps batch files ASCII-only with CRLF line endings' {
        $batchFiles = @(Get-ChildItem -LiteralPath $script:Root -Recurse -File -Filter '*.bat' | Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git|work)[\\/]' })
        $batchFiles.Count | Should -BeGreaterThan 0
        foreach ($file in $batchFiles) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            @($bytes | Where-Object { $_ -gt 0x7F }).Count | Should -Be 0 -Because "$($file.Name) は ASCII だけで書く（日本語はファイル名だけにする）"
            for ($index = 0; $index -lt $bytes.Length; $index++) {
                if ($bytes[$index] -eq 0x0A) {
                    ($index -gt 0 -and $bytes[$index - 1] -eq 0x0D) | Should -BeTrue -Because "$($file.Name) の改行は CRLF"
                }
            }
        }
    }

    It 'declares the same encoding rules to editors and to git' {
        $editorConfig = Get-Content -LiteralPath (Join-Path $script:Root '.editorconfig') -Raw -Encoding UTF8
        $editorConfig | Should -Match '(?s)\[\*\.\{ps1,psm1,psd1\}\][^\[]*charset\s*=\s*utf-8-bom'
        $editorConfig | Should -Match '(?s)\[\*\.bat\][^\[]*end_of_line\s*=\s*crlf'
        $gitAttributes = Get-Content -LiteralPath (Join-Path $script:Root '.gitattributes') -Raw -Encoding UTF8
        $gitAttributes | Should -Match '\*\.bat\s+text\s+eol=crlf'
    }
}
