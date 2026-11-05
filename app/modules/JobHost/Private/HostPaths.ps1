# パス表記の正規化。設定ファイルは Windows の「\」でも「/」でも書けるようにし、
# 実行環境の区切り文字へ揃えてから解決する（Windows PowerShell 5.1 と PowerShell 7 の両方で同じ結果にする）。

function Test-HostIsWindows {
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function ConvertTo-HostPathSeparators {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    $separator = [System.IO.Path]::DirectorySeparatorChar
    return $Path.Replace('\', $separator).Replace('/', $separator)
}

function Resolve-HostPath {
    <#
    .SYNOPSIS
    環境変数（%NAME%）を展開し、区切り文字を揃え、相対パスなら BaseDirectory を基準に絶対パスにする。
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$BaseDirectory
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $expanded = ConvertTo-HostPathSeparators -Path ([System.Environment]::ExpandEnvironmentVariables($Path))
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path $BaseDirectory $expanded
    }

    return [System.IO.Path]::GetFullPath($expanded)
}

function Get-HostPathComparison {
    if (Test-HostIsWindows) { return [System.StringComparison]::OrdinalIgnoreCase }
    return [System.StringComparison]::Ordinal
}
