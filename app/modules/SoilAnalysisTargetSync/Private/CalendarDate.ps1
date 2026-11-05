# CSV の日時文字列を「暦日」（時刻を捨てた日付）にする（純粋関数）。
#
# 判定は CSV に表示された日付そのものを使う。時差のある ISO 8601（例: 2026-04-10T23:30:00+09:00）は
# UTC や実行 PC のタイムゾーンへ換算せず、表示どおりの日付（2026-04-10）として扱う。
#
# 受け付ける形式（契約内の形式だけ。推測で読める形を増やさない）
#   ISO 8601 + 時差 / Z      2026-04-10T08:00:00+09:00、2026-04-10T08:00:00.123Z
#   ハイフン / スラッシュ    2026-04-10、2026/4/10、2026-04-10 08:00:00、2026/4/10 8:00:00
#   和暦ではない漢字表記     2026年4月10日、2026年4月10日 8:00:00
#   先頭が上記の日付         2026-04-10 08:00（秒なし）のように末尾が契約外でも、先頭の日付部分が読めれば採用する

$script:CalendarOffsetFormats = @(
    "yyyy-MM-dd'T'HH:mm:sszzz", "yyyy-M-d'T'H:mm:sszzz",
    "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFzzz", "yyyy-M-d'T'H:mm:ss.FFFFFFFzzz",
    "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-M-d'T'H:mm:ss'Z'",
    "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'", "yyyy-M-d'T'H:mm:ss.FFFFFFF'Z'"
)

$script:CalendarLocalFormats = @(
    'yyyy-M-d', 'yyyy-M-d H:mm:ss', 'yyyy-M-d H:mm',
    'yyyy/M/d', 'yyyy/M/d H:mm:ss', 'yyyy/M/d H:mm',
    'yyyy年M月d日', 'yyyy年M月d日 H:mm:ss', 'yyyy年M月d日 H:mm'
)

$script:CalendarLeadingDatePattern = '^(\d{4}-\d{1,2}-\d{1,2}|\d{4}/\d{1,2}/\d{1,2}|\d{4}年\d{1,2}月\d{1,2}日)'

function Test-CalendarDateMissing {
    <#
    .SYNOPSIS
    値が「未記入」（空、または「-」）かを返す。
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)

    return ([string]::IsNullOrWhiteSpace($Text) -or $Text.Trim() -eq '-')
}

function ConvertTo-CalendarDate {
    <#
    .SYNOPSIS
    日時文字列を暦日（[datetime] の Date）にする。契約内の形式で読めなければ $null。
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)

    if (Test-CalendarDateMissing -Text $Text) { return $null }

    $value = [regex]::Replace($Text.Trim(), '\s+', ' ')
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $none = [System.Globalization.DateTimeStyles]::None

    $offset = [System.DateTimeOffset]::MinValue
    if ([System.DateTimeOffset]::TryParseExact($value, [string[]]$script:CalendarOffsetFormats, $invariant, $none, [ref]$offset)) {
        return $offset.DateTime.Date
    }

    $local = [datetime]::MinValue
    if ([datetime]::TryParseExact($value, [string[]]$script:CalendarLocalFormats, $invariant, $none, [ref]$local)) {
        return $local.Date
    }

    $match = [regex]::Match($value, $script:CalendarLeadingDatePattern)
    if ($match.Success -and [datetime]::TryParseExact($match.Groups[1].Value, [string[]]@('yyyy-M-d', 'yyyy/M/d', 'yyyy年M月d日'), $invariant, $none, [ref]$local)) {
        return $local.Date
    }

    return $null
}
