# 出力 CSV のテキスト化（純粋関数）。
# 全項目をダブルクォートで囲み、項目内の " は "" にする。改行は CRLF（表計算ソフトでの扱いを優先）。
# 文字コード（UTF-8 BOM 付き）は書き込み側（FileService の SaveCsv）で決める。

function ConvertTo-CsvField {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '""' }
    return '"' + ([string]$Value).Replace('"', '""') + '"'
}

function ConvertTo-CsvText {
    <#
    .SYNOPSIS
    行オブジェクトの配列を、指定した列順の CSV テキストにする。行が0件ならヘッダー行だけを返す。
    .PARAMETER Columns
    列名（行オブジェクトのプロパティ名、または hashtable のキー）。
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][string[]]$Columns
    )

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add((@($Columns | ForEach-Object { ConvertTo-CsvField -Value $_ }) -join ','))

    foreach ($row in $Rows) {
        $fields = foreach ($column in $Columns) {
            ConvertTo-CsvField -Value (Get-PropertyValue -InputObject $row -Name $column)
        }
        [void]$lines.Add((@($fields) -join ','))
    }

    return (($lines -join "`r`n") + "`r`n")
}
