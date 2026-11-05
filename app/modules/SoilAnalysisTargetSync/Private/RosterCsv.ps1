# 入力 CSV（区画一覧の CSV 出力）を内部の記録に変換する（純粋関数）。
#
# CSV の日本語見出しと内部の項目名の対応はこのファイルにだけ置く。
# 以降の処理（判定・突き合わせ・出力）は内部の項目名だけを使い、見出しの変更がここで止まるようにする。
#
#   区画コード       → PlotCode
#   担当者           → Owner
#   稼働状態         → Status
#   最終計測日時     → LastMeasured
#   土壌分析の依頼   → AnalysisRequested
#   土壌分析の完了   → AnalysisCompleted
# 上記以外の列（作物など）は読み捨てる。

$script:RosterCsvColumns = [ordered]@{
    '区画コード' = 'PlotCode'
    '担当者' = 'Owner'
    '稼働状態' = 'Status'
    '最終計測日時' = 'LastMeasured'
    '土壌分析の依頼' = 'AnalysisRequested'
    '土壌分析の完了' = 'AnalysisCompleted'
}

function Get-RosterCsvDelimiter {
    <#
    .SYNOPSIS
    1行目にタブがあればタブ区切り、無ければカンマ区切りとみなす。
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $firstLine = ($Text -split "`r?`n", 2)[0]
    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        throw '入力 CSV の1行目（見出し行）が空です。'
    }

    if ($firstLine.Contains("`t")) { return "`t" }
    return ','
}

function ConvertFrom-RosterCsvText {
    <#
    .SYNOPSIS
    CSV テキストを内部の記録（PlotCode ほか）の配列にする。見出し不足・データ行なしは例外にする。
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $delimiter = Get-RosterCsvDelimiter -Text $Text
    $rows = @(ConvertFrom-Csv -InputObject $Text -Delimiter $delimiter)
    if ($rows.Count -eq 0) {
        throw '入力 CSV にデータ行がありません。'
    }

    $headers = @($rows[0].PSObject.Properties | ForEach-Object { $_.Name })
    $missing = @($script:RosterCsvColumns.Keys | Where-Object { $headers -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw "入力 CSV に必須の列がありません: $($missing -join ', ')"
    }

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rows) {
        $record = [ordered]@{}
        foreach ($header in $script:RosterCsvColumns.Keys) {
            $value = $row.PSObject.Properties[$header].Value
            $record[$script:RosterCsvColumns[$header]] = if ($null -eq $value) { '' } else { [string]$value }
        }
        [void]$records.Add([pscustomobject]$record)
    }

    return $records.ToArray()
}
