# 結果・失敗の記録の形と、保存名の規則（純粋関数）。

$script:PlantingFailureColumns = @('RowId', 'PlotCode', 'Reason', 'Timestamp')

function Get-PlantingRowKey {
    <#
    .SYNOPSIS
    一覧の行を一意に表すキー（行識別子 + 区画コード）。どちらかが空なら空文字（処理しない）。
    #>
    param([AllowNull()][object]$Row)

    $rowId = [string](Get-PropertyValue -InputObject $Row -Name 'rowId' -Default '')
    $plotCode = [string](Get-PropertyValue -InputObject $Row -Name 'plotCode' -Default '')
    if ([string]::IsNullOrWhiteSpace($rowId) -or [string]::IsNullOrWhiteSpace($plotCode)) { return '' }
    return "$rowId|$plotCode"
}

function New-PlantingExportSuccess {
    param([Parameter(Mandatory)][string]$RowId, [Parameter(Mandatory)][string]$PlotCode, [Parameter(Mandatory)][string]$CsvPath)

    return [pscustomobject]@{ RowId = $RowId; PlotCode = $PlotCode; CsvPath = $CsvPath }
}

function New-PlantingExportFailure {
    param(
        [AllowEmptyString()][string]$RowId,
        [AllowEmptyString()][string]$PlotCode,
        [Parameter(Mandatory)][string]$Reason,
        [AllowEmptyString()][string]$Timestamp = ''
    )

    return [pscustomobject]@{ RowId = $RowId; PlotCode = $PlotCode; Reason = $Reason; Timestamp = $Timestamp }
}

function ConvertTo-SafeFileNamePart {
    <#
    .SYNOPSIS
    ファイル名の一部に使えるよう、使えない文字と空白（全角空白・NBSP を含む）を「_」にする。
    #>
    param([AllowEmptyString()][string]$Value)

    $safe = $Value.Trim()
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$character, '_')
    }
    $safe = [regex]::Replace($safe, '[\s 　]+', '_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'UNKNOWN' }
    return $safe
}

function Get-PlantingRecordFileName {
    <#
    .SYNOPSIS
    ダウンロードしたファイル名に区画コードを付けた保存名を返す。
    .DESCRIPTION
    ブラウザは同名ファイルがあると「planting_20260415 (1).csv」のように番号を付けるため、
    その番号を取り除いてから区画コードを付ける。
      planting_20260415.csv      → planting_20260415_GH2-B01.csv
      planting_20260415 (1).csv  → planting_20260415_GH2-B01.csv
    #>
    param(
        [Parameter(Mandatory)][string]$DownloadedName,
        [Parameter(Mandatory)][string]$PlotCode
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($DownloadedName)
    $extension = [System.IO.Path]::GetExtension($DownloadedName)
    $normalized = [regex]::Replace($baseName, '\s\(\d+\)$', '')
    return '{0}_{1}{2}' -f $normalized, (ConvertTo-SafeFileNamePart -Value $PlotCode), $extension
}
