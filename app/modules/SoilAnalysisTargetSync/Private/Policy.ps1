# 土壌分析の対象（ON）/ 対象外（OFF）を決める業務ルール（純粋関数）。
#
#   1. 土壌分析の完了が未記入（空・「-」）                        → ON
#   2. 土壌分析の完了が日付として読めない                          → CSV データエラー
#   3. 最終計測日時が日付として読めない                            → CSV データエラー
#   4. 最終計測日時が土壌分析の完了より前（日数がマイナス）        → CSV データエラー
#      （分析結果は計測器から送られてくるため、完了日より前に最終計測があるのは記録の矛盾）
#   5. 最終計測日時 − 土壌分析の完了 が DaysThreshold 日以上        → ON
#   6. それ以外                                                     → OFF
# 日数は暦日どうしの差（時刻は見ない）。

function New-AnalysisDecision {
    param(
        [Parameter(Mandatory)][ValidateSet('On', 'Off', 'Error')][string]$Decision,
        [AllowNull()][object]$ElapsedDays,
        [Parameter(Mandatory)][string]$Reason,
        [AllowEmptyString()][string]$ErrorCode = ''
    )

    return [pscustomobject]@{
        Decision = $Decision
        ElapsedDays = $ElapsedDays
        Reason = $Reason
        ErrorCode = $ErrorCode
    }
}

function Get-AnalysisDecision {
    <#
    .SYNOPSIS
    1区画分の判定結果（Decision = On / Off / Error）を返す。
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$AnalysisCompleted,
        [AllowNull()][AllowEmptyString()][string]$LastMeasured,
        [Parameter(Mandatory)][int]$DaysThreshold
    )

    if (Test-CalendarDateMissing -Text $AnalysisCompleted) {
        return New-AnalysisDecision -Decision On -ElapsedDays $null -Reason '土壌分析の完了なし'
    }

    $completed = ConvertTo-CalendarDate -Text $AnalysisCompleted
    if ($null -eq $completed) {
        return New-AnalysisDecision -Decision Error -ElapsedDays $null -ErrorCode 'ANALYSIS_DATE_INVALID' -Reason '土壌分析の完了を日付として読めません'
    }

    $measured = ConvertTo-CalendarDate -Text $LastMeasured
    if ($null -eq $measured) {
        return New-AnalysisDecision -Decision Error -ElapsedDays $null -ErrorCode 'MEASURED_DATE_INVALID' -Reason '土壌分析の完了は日付ですが、最終計測日時を日付として読めません'
    }

    $days = [int]($measured - $completed).TotalDays
    if ($days -lt 0) {
        return New-AnalysisDecision -Decision Error -ElapsedDays $days -ErrorCode 'DATE_ORDER_INCONSISTENT' -Reason '最終計測日時が土壌分析の完了より前で、日付の前後関係が矛盾しています'
    }

    if ($days -ge $DaysThreshold) {
        return New-AnalysisDecision -Decision On -ElapsedDays $days -Reason "最終計測日時との差が $days 日"
    }

    return New-AnalysisDecision -Decision Off -ElapsedDays $days -Reason "最終計測日時との差が $days 日のため対象外"
}

function Get-AnalysisRuleDescription {
    <#
    .SYNOPSIS
    ログに出す判定ルールの説明（ルールを変えたら、この説明とテストを同時に直す）。
    #>
    param([Parameter(Mandatory)][int]$DaysThreshold)

    return @(
        '土壌分析の完了が「-」または空欄 → ON',
        '土壌分析の完了を日付として読めない → CSV データエラー（ブラウザ操作の前に停止）',
        '最終計測日時を日付として読めない → CSV データエラー（ブラウザ操作の前に停止）',
        '最終計測日時が土壌分析の完了より前 → CSV データエラー（ブラウザ操作の前に停止）',
        "最終計測日時と土壌分析の完了の差が $DaysThreshold 日以上 → ON",
        '上記以外 → OFF'
    )
}
