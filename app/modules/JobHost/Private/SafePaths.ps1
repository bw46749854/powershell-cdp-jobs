# 削除・上書きを伴うファイル操作の安全規則。
#
# 作業ディレクトリは中身を消すことがあるため、次の場所は作業ディレクトリとして受け付けない。
#   - 空のパス
#   - ドライブ / ファイルシステムのルート
#   - ユーザープロファイル（ホーム）そのもの
#   - ユーザープロファイル直下の子ディレクトリ（例: Desktop, Downloads, Documents）
# ファイルの削除・出力は、許可したディレクトリの配下にあることを確認してから行う。

function Get-HostTrimmedFullPath {
    param([Parameter(Mandatory)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    }

    return $full
}

function Assert-SafeDirectoryPath {
    <#
    .SYNOPSIS
    作業ディレクトリとして安全なパスか検証し、正規化した絶対パスを返す（作成はしない）。
    #>
    param(
        [AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$Purpose
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Purpose ディレクトリが指定されていません。"
    }

    $full = Get-HostTrimmedFullPath -Path $Path
    $comparison = Get-HostPathComparison
    $root = [System.IO.Path]::GetPathRoot($full)

    if ($full.Equals($root.TrimEnd([char[]]@('\', '/')), $comparison) -or $full.Equals($root, $comparison)) {
        throw "$Purpose ディレクトリにドライブのルートは指定できません: $full"
    }

    $homeDirectory = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    if (-not [string]::IsNullOrWhiteSpace($homeDirectory)) {
        $homeFull = Get-HostTrimmedFullPath -Path $homeDirectory
        if ($full.Equals($homeFull, $comparison)) {
            throw "$Purpose ディレクトリにユーザープロファイルそのものは指定できません: $full"
        }

        $parent = Split-Path -Parent $full
        if (-not [string]::IsNullOrWhiteSpace($parent) -and (Get-HostTrimmedFullPath -Path $parent).Equals($homeFull, $comparison)) {
            throw "$Purpose ディレクトリにユーザープロファイル直下のフォルダーは指定できません（配下に専用フォルダーを作ってください）: $full"
        }
    }

    return $full
}

function Initialize-SafeDirectory {
    <#
    .SYNOPSIS
    安全なパスであることを確認してからディレクトリを作成（既存ならそのまま）し、絶対パスを返す。
    #>
    param(
        [AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$Purpose
    )

    $full = Assert-SafeDirectoryPath -Path $Path -Purpose $Purpose
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $full -Force)
    }

    return $full
}

function Test-PathWithinDirectory {
    <#
    .SYNOPSIS
    Path が Directory の配下（Directory 自身は含まない）にあるかを返す。
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Directory
    )

    $directoryFull = Get-HostTrimmedFullPath -Path $Directory
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $prefix = $directoryFull + [System.IO.Path]::DirectorySeparatorChar

    return $pathFull.StartsWith($prefix, (Get-HostPathComparison))
}

function Assert-PathWithinDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Purpose
    )

    if (-not (Test-PathWithinDirectory -Path $Path -Directory $Directory)) {
        throw "$Purpose の対象が許可ディレクトリの配下にありません。Path=$Path Directory=$Directory"
    }
}
