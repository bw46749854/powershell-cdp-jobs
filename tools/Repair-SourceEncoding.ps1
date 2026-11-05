<#
.SYNOPSIS
ソースファイルの文字コードと改行を、リポジトリの規約（.editorconfig）に揃える。

.DESCRIPTION
  - *.ps1 / *.psm1 / *.psd1 : UTF-8（BOM 付き）、LF
  - *.bat                   : UTF-8（BOM なし）、CRLF
  - その他のテキスト        : UTF-8（BOM なし）、LF
Windows PowerShell 5.1 は BOM なしの UTF-8 を ANSI（日本語環境では CP932）として読むため、
日本語を含む PowerShell ファイルの BOM が落ちると文字化けして動かなくなる。
エディタの設定で BOM が落ちたときに、このスクリプトで直す。設計境界テストが同じ規約を検査する。

.PARAMETER Check
変更せず、規約に合わないファイルを一覧して終了コード 1 を返す。
#>
param([switch]$Check)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$textExtensions = @('.ps1', '.psm1', '.psd1', '.bat', '.js', '.json', '.md', '.html', '.css', '.yml', '.yaml', '.txt', '.csv')
$excludedPattern = '[\\/](\.git|node_modules|vendor|work|tests[\\/]out)[\\/]'

$utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$problems = New-Object System.Collections.Generic.List[string]

$files = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File |
    Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() } |
    Where-Object { $_.FullName -notmatch $excludedPattern }

foreach ($file in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = $utf8.GetString($bytes)
    if ($hasBom) { $text = $text.Substring(1) }

    $extension = $file.Extension.ToLowerInvariant()
    $wantBom = $extension -in @('.ps1', '.psm1', '.psd1')
    $normalized = $text -replace "`r`n", "`n"
    if ($extension -eq '.bat') { $normalized = $normalized -replace "`n", "`r`n" }

    if ($hasBom -eq $wantBom -and $normalized -ceq $text) { continue }

    $relative = $file.FullName.Substring($repositoryRoot.Length + 1)
    if ($Check) {
        [void]$problems.Add($relative)
        continue
    }

    $encoding = if ($wantBom) { $utf8Bom } else { $utf8 }
    [System.IO.File]::WriteAllText($file.FullName, $normalized, $encoding)
    Write-Host "修正しました: $relative"
}

if ($Check -and $problems.Count -gt 0) {
    Write-Host '文字コード・改行の規約に合わないファイル:'
    $problems | ForEach-Object { Write-Host "  $_" }
    exit 1
}
