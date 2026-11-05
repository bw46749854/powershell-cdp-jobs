# 出力 CSV の行の形と列順（純粋関数）。
# 入力 CSV の見出しのうち、業務上の意味を持つ3列（作物名・品種・定植日）はここで固定する。

$script:CropHeader = '作物名'
$script:VarietyHeader = '品種'
$script:PlantedHeader = '定植日'
$script:DigestColumns = @('区画コード', '作物名', '品種', '定植日')
$script:DigestFailureColumns = @('FileName', 'PlotCode', 'LineNumber', 'Reason', 'Timestamp')

function New-DigestRow {
    param(
        [Parameter(Mandatory)][string]$PlotCode,
        [AllowEmptyString()][string]$Crop = '',
        [AllowEmptyString()][string]$Variety = '',
        [AllowEmptyString()][string]$Planted = ''
    )

    return [pscustomobject]@{ '区画コード' = $PlotCode; '作物名' = $Crop; '品種' = $Variety; '定植日' = $Planted }
}

function New-DigestFailure {
    param(
        [AllowEmptyString()][string]$FileName = '',
        [AllowEmptyString()][string]$PlotCode = '',
        [AllowEmptyString()][string]$LineNumber = '',
        [Parameter(Mandatory)][string]$Reason,
        [AllowEmptyString()][string]$Timestamp = ''
    )

    return [pscustomobject]@{ FileName = $FileName; PlotCode = $PlotCode; LineNumber = $LineNumber; Reason = $Reason; Timestamp = $Timestamp }
}

function New-FileDigestResult {
    <#
    .SYNOPSIS
    1ファイル分の集約結果。Skipped はファイル全体を飛ばした（ファイル名・文字コード・解析・見出しの問題）ことを表す。
    #>
    param(
        [AllowEmptyCollection()][object[]]$Rows = @(),
        [AllowEmptyCollection()][object[]]$Failures = @(),
        [bool]$Skipped = $false,
        [int]$ReadRowCount = 0,
        [AllowEmptyString()][string]$PlotCode = '',
        [AllowEmptyString()][string]$EncodingName = '',
        [AllowEmptyString()][string]$DelimiterName = ''
    )

    return [pscustomobject]@{
        Rows = @($Rows)
        Failures = @($Failures)
        Skipped = $Skipped
        ReadRowCount = $ReadRowCount
        PlotCode = $PlotCode
        EncodingName = $EncodingName
        DelimiterName = $DelimiterName
    }
}
