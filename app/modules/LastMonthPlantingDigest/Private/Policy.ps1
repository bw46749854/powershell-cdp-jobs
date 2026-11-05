# 「先月の定植」を集める業務ルール（純粋関数）。
#
#   対象期間  : 実行日の前月1日 以上、当月1日 未満
#   区画コード: ファイル名から設定の FileNamePattern（1番目のグループ）で取り出す（大文字小文字を区別）
#   見出し    : 設定の RequiredHeaders と「同じ名前・同じ順序・過不足なし・重複なし」で完全一致すること
#   定植日    : 日付として読めない行は失敗として記録し、その行だけ飛ばす

$script:PlantingDateFormats = @(
    'yyyy-MM-dd', 'yyyy-M-d', 'yyyy/MM/dd', 'yyyy/M/d',
    'yyyy-MM-dd HH:mm:ss', 'yyyy-M-d H:mm:ss', 'yyyy/MM/dd HH:mm:ss', 'yyyy/M/d H:mm:ss',
    'yyyy年MM月dd日', 'yyyy年M月d日'
)

function New-LastMonthRange {
    param([Parameter(Mandatory)][datetime]$Now)

    $thisMonth = New-Object System.DateTime -ArgumentList $Now.Year, $Now.Month, 1
    return [pscustomobject]@{
        Today = $Now.Date
        StartInclusive = $thisMonth.AddMonths(-1)
        EndExclusive = $thisMonth
    }
}

function Test-DateInRange {
    param(
        [Parameter(Mandatory)][datetime]$Date,
        [Parameter(Mandatory)][object]$Range
    )

    return ($Date -ge $Range.StartInclusive -and $Date -lt $Range.EndExclusive)
}

function Get-PlotCodeFromFileName {
    <#
    .OUTPUTS
    IsValid / PlotCode / Reason
    #>
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Pattern
    )

    $match = [regex]::Match($FileName, $Pattern)
    if (-not $match.Success -or $match.Groups.Count -lt 2 -or [string]::IsNullOrEmpty($match.Groups[1].Value)) {
        return [pscustomobject]@{ IsValid = $false; PlotCode = ''; Reason = "ファイル名が形式に合いません: $FileName（形式: $Pattern）" }
    }

    return [pscustomobject]@{ IsValid = $true; PlotCode = $match.Groups[1].Value; Reason = '' }
}

function Format-ListForReason {
    param([AllowNull()][AllowEmptyCollection()][object[]]$Values)

    if ($null -eq $Values -or @($Values).Count -eq 0) { return '(なし)' }
    return (@($Values) | ForEach-Object { "'$_'" }) -join ', '
}

function Test-ExactHeaders {
    <#
    .SYNOPSIS
    見出しが期待どおりか（同じ名前・同じ順序・過不足なし・重複なし）を、理由の材料と一緒に返す。
    .OUTPUTS
    IsValid / Missing / Extra / Duplicated / SameOrder / Reason
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Headers,
        [Parameter(Mandatory)][string[]]$Expected
    )

    $missing = @($Expected | Where-Object { $Headers -cnotcontains $_ })
    $extra = @($Headers | Where-Object { $Expected -cnotcontains $_ })
    $duplicated = @($Headers | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    $sameOrder = $Headers.Count -eq $Expected.Count
    if ($sameOrder) {
        for ($index = 0; $index -lt $Expected.Count; $index++) {
            if ($Headers[$index] -cne $Expected[$index]) { $sameOrder = $false; break }
        }
    }

    $isValid = $sameOrder -and $missing.Count -eq 0 -and $extra.Count -eq 0 -and $duplicated.Count -eq 0
    $reason = ''
    if (-not $isValid) {
        $reason = "見出しが一致しません。実際=[$(Format-ListForReason $Headers)] 期待=[$(Format-ListForReason $Expected)] 不足=[$(Format-ListForReason $missing)] 余分=[$(Format-ListForReason $extra)] 重複=[$(Format-ListForReason $duplicated)] 順序一致=$sameOrder"
    }

    return [pscustomobject]@{ IsValid = $isValid; Missing = $missing; Extra = $extra; Duplicated = $duplicated; SameOrder = $sameOrder; Reason = $reason }
}

function ConvertTo-PlantingDate {
    <#
    .SYNOPSIS
    定植日の文字列を日付にする。決めた形式を優先し、読めなければ日本の書式として解釈を試みる。読めなければ $null。
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $value = $Text.Trim()
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('ja-JP')
    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
    $parsed = [datetime]::MinValue

    if ([datetime]::TryParseExact($value, [string[]]$script:PlantingDateFormats, $culture, $styles, [ref]$parsed)) { return $parsed.Date }
    if ([datetime]::TryParse($value, $culture, $styles, [ref]$parsed)) { return $parsed.Date }
    return $null
}
