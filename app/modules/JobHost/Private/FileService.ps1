# Files サービス。ジョブが使うファイル操作の唯一の窓口。
#
#   EnsureDirectory  -Path -Purpose                     安全確認のうえ作成し、絶対パスを返す
#   ClearDirectory   -Path -Purpose                     安全確認のうえ中身を空にする
#   RemoveFile       -Path -Within                      Within 配下のファイルだけ削除（削除したら $true）
#   ListFiles        -Directory -Filter                 ファイル一覧（Name / FullName / Length / LastWriteTime、名前順）
#   Exists           -Path                              ファイルが存在するか
#   ReadBytes        -Path                              バイト列
#   ReadText         -Path                              UTF-8 テキスト（BOM の有無を問わない）
#   SaveCsv          -Path -Rows -Columns -Within -WhenEmpty
#                    CSV（UTF-8 BOM 付き）を書く。0件のとき Remove = 旧ファイルを消す / HeaderOnly = ヘッダーだけ書く
#   MoveToUnique     -Path -DestinationDirectory -FileName
#                    移動先に同名があれば「名前 (1).拡張子」…のように重ならない名前にして移動し、移動先を返す

$script:HostFilesShape = @{
    EnsureDirectory = @('Path', 'Purpose')
    ClearDirectory = @('Path', 'Purpose')
    RemoveFile = @('Path', 'Within')
    ListFiles = @('Directory', 'Filter')
    Exists = @('Path')
    ReadBytes = @('Path')
    ReadText = @('Path')
    SaveCsv = @('Path', 'Rows', 'Columns', 'Within', 'WhenEmpty')
    MoveToUnique = @('Path', 'DestinationDirectory', 'FileName')
}

function Clear-SafeDirectory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Purpose)

    $directory = Initialize-SafeDirectory -Path $Path -Purpose $Purpose
    foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
        Assert-PathWithinDirectory -Path $item.FullName -Directory $directory -Purpose "$Purpose の削除"
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
}

function Remove-SafeFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Within)

    $allowed = Assert-SafeDirectoryPath -Path $Within -Purpose '削除許可'
    Assert-PathWithinDirectory -Path $Path -Directory $allowed -Purpose 'ファイル削除'

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        throw "削除対象がファイルではありません: $Path"
    }

    Remove-Item -LiteralPath $Path -Force
    return $true
}

function Get-HostFileList {
    param([Parameter(Mandatory)][string]$Directory, [string]$Filter = '*')

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "ディレクトリが見つかりません: $Directory"
    }

    return @(
        Get-ChildItem -LiteralPath $Directory -File -Filter $Filter |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Name
                    FullName = $_.FullName
                    Length = $_.Length
                    LastWriteTime = $_.LastWriteTime
                }
            }
    )
}

function Read-HostText {
    param([Parameter(Mandatory)][string]$Path)

    $text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding -ArgumentList $false))
    return $text.TrimStart([char]0xFEFF)
}

function Save-HostCsv {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][string[]]$Columns,
        [Parameter(Mandatory)][string]$Within,
        [Parameter(Mandatory)][ValidateSet('Remove', 'HeaderOnly')][string]$WhenEmpty
    )

    $directory = Initialize-SafeDirectory -Path $Within -Purpose 'CSV 出力'
    Assert-PathWithinDirectory -Path $Path -Directory $directory -Purpose 'CSV 出力'

    $items = @($Rows)
    if ($items.Count -eq 0 -and $WhenEmpty -eq 'Remove') {
        $removed = Remove-SafeFile -Path $Path -Within $directory
        return [pscustomobject]@{ Path = $Path; Written = $false; Removed = $removed; Count = 0 }
    }

    $text = ConvertTo-CsvText -Rows $items -Columns $Columns
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
    return [pscustomobject]@{ Path = $Path; Written = $true; Removed = $false; Count = $items.Count }
}

function Test-HostFileName {
    param([AllowEmptyString()][string]$FileName)

    if ([string]::IsNullOrWhiteSpace($FileName)) { return $false }
    return ($FileName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -lt 0) -and ($FileName.IndexOfAny([char[]]@('\', '/')) -lt 0)
}

function Get-HostUniqueFilePath {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$FileName)

    $candidate = Join-Path $Directory $FileName
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)
    for ($index = 1; $index -le 999; $index++) {
        $candidate = Join-Path $Directory ('{0} ({1}){2}' -f $baseName, $index, $extension)
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    }

    throw "重ならないファイル名を作れませんでした: $(Join-Path $Directory $FileName)"
}

function Move-HostFileToUniquePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][string]$FileName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "移動元のファイルが見つかりません: $Path"
    }
    if (-not (Test-HostFileName -FileName $FileName)) {
        throw "ファイル名に使えない文字が含まれています: $FileName"
    }

    $directory = Initialize-SafeDirectory -Path $DestinationDirectory -Purpose '移動先'
    $destination = Get-HostUniqueFilePath -Directory $directory -FileName $FileName
    Move-Item -LiteralPath $Path -Destination $destination
    return $destination
}

function New-HostFileService {
    $ensure = Get-Command -Name Initialize-SafeDirectory -CommandType Function
    $clear = Get-Command -Name Clear-SafeDirectory -CommandType Function
    $remove = Get-Command -Name Remove-SafeFile -CommandType Function
    $list = Get-Command -Name Get-HostFileList -CommandType Function
    $readText = Get-Command -Name Read-HostText -CommandType Function
    $saveCsv = Get-Command -Name Save-HostCsv -CommandType Function
    $move = Get-Command -Name Move-HostFileToUniquePath -CommandType Function

    return [pscustomobject]@{
        EnsureDirectory = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Purpose)
            & $ensure -Path $Path -Purpose $Purpose
        }.GetNewClosure()
        ClearDirectory = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Purpose)
            & $clear -Path $Path -Purpose $Purpose
        }.GetNewClosure()
        RemoveFile = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Within)
            & $remove -Path $Path -Within $Within
        }.GetNewClosure()
        ListFiles = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Directory, [string]$Filter = '*')
            & $list -Directory $Directory -Filter $Filter
        }.GetNewClosure()
        Exists = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
            Test-Path -LiteralPath $Path -PathType Leaf
        }.GetNewClosure()
        ReadBytes = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
            , [System.IO.File]::ReadAllBytes($Path)
        }.GetNewClosure()
        ReadText = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
            & $readText -Path $Path
        }.GetNewClosure()
        SaveCsv = {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
                [Parameter(Mandatory)][string[]]$Columns,
                [Parameter(Mandatory)][string]$Within,
                [Parameter(Mandatory)][ValidateSet('Remove', 'HeaderOnly')][string]$WhenEmpty
            )
            & $saveCsv -Path $Path -Rows $Rows -Columns $Columns -Within $Within -WhenEmpty $WhenEmpty
        }.GetNewClosure()
        MoveToUnique = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$DestinationDirectory, [Parameter(Mandatory)][string]$FileName)
            & $move -Path $Path -DestinationDirectory $DestinationDirectory -FileName $FileName
        }.GetNewClosure()
    }
}
