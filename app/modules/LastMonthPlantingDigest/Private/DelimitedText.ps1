# 区切り文字付きテキスト（CSV / TSV）の解析（純粋関数）。
#
# 引用符で囲んだ項目内の区切り文字・改行・二重引用符（""）を扱い、各行の開始行番号を記録する。
# 行番号は失敗一覧に載せ、元の CSV のどの行が問題かを特定できるようにする。

function Get-DelimiterFromText {
    <#
    .SYNOPSIS
    1行目にタブがあればタブ、無ければカンマを区切り文字とする。
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { throw '内容が空です。' }

    $firstLine = ($Text -split "`r?`n", 2)[0]
    if ([string]::IsNullOrWhiteSpace($firstLine)) { throw '1行目（見出し行）が空です。' }
    if ($firstLine.Contains("`t")) { return "`t" }
    return ','
}

function ConvertFrom-DelimitedRecords {
    <#
    .SYNOPSIS
    テキストをレコード（LineNumber / Fields）の配列にする。引用符が閉じていなければ例外。
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Delimiter
    )

    if ($Delimiter -ne "`t" -and $Delimiter -ne ',') { throw "対応していない区切り文字です: '$Delimiter'" }
    $separator = [char]$Delimiter

    $records = New-Object System.Collections.Generic.List[object]
    $fields = New-Object System.Collections.Generic.List[string]
    $field = New-Object System.Text.StringBuilder
    $inQuotes = $false
    $line = 1
    $recordStart = 1
    $index = 0

    while ($index -lt $Text.Length) {
        $character = $Text[$index]

        if ($character -eq '"') {
            if ($inQuotes -and ($index + 1) -lt $Text.Length -and $Text[$index + 1] -eq '"') {
                [void]$field.Append('"')
                $index += 2
                continue
            }
            $inQuotes = -not $inQuotes
            $index++
            continue
        }

        if (-not $inQuotes -and $character -eq $separator) {
            [void]$fields.Add($field.ToString())
            [void]$field.Clear()
            $index++
            continue
        }

        if (-not $inQuotes -and ($character -eq "`r" -or $character -eq "`n")) {
            [void]$fields.Add($field.ToString())
            [void]$field.Clear()
            [void]$records.Add([pscustomobject]@{ LineNumber = $recordStart; Fields = $fields.ToArray() })
            $fields = New-Object System.Collections.Generic.List[string]

            if ($character -eq "`r" -and ($index + 1) -lt $Text.Length -and $Text[$index + 1] -eq "`n") { $index += 2 } else { $index++ }
            $line++
            $recordStart = $line
            continue
        }

        if ($character -eq "`n") { $line++ }
        [void]$field.Append($character)
        $index++
    }

    if ($inQuotes) { throw "引用符が閉じていません（$recordStart 行目から）。" }

    if ($field.Length -gt 0 -or $fields.Count -gt 0) {
        [void]$fields.Add($field.ToString())
        [void]$records.Add([pscustomobject]@{ LineNumber = $recordStart; Fields = $fields.ToArray() })
    }

    return $records.ToArray()
}

function Import-DelimitedTable {
    <#
    .SYNOPSIS
    1行目を見出しとして、各行を「見出し → 値」の行にする。形の崩れた行は IsMalformed で示す（例外にしない）。
    .OUTPUTS
    Headers / Rows（LineNumber, IsMalformed, MalformedReason, Data）
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Delimiter
    )

    $records = @(ConvertFrom-DelimitedRecords -Text $Text -Delimiter $Delimiter)
    if ($records.Count -eq 0) { throw '見出し行がありません。' }

    $headers = @($records[0].Fields)
    $headers[0] = $headers[0].TrimStart([char]0xFEFF)
    $duplicated = @($headers | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })

    $rows = New-Object System.Collections.Generic.List[object]
    for ($recordIndex = 1; $recordIndex -lt $records.Count; $recordIndex++) {
        $record = $records[$recordIndex]
        $fields = @($record.Fields)
        if ($fields.Count -eq 1 -and [string]::IsNullOrWhiteSpace($fields[0])) { continue }

        $reason = $null
        if ($duplicated.Count -gt 0) {
            $reason = "見出しが重複しています: $(@($duplicated | ForEach-Object { "'$_'" }) -join ', ')"
        }
        elseif ($fields.Count -ne $headers.Count) {
            $reason = "見出しの列数=$($headers.Count)、この行の列数=$($fields.Count)"
        }

        if ($null -ne $reason) {
            [void]$rows.Add([pscustomobject]@{ LineNumber = $record.LineNumber; IsMalformed = $true; MalformedReason = $reason; Data = $null })
            continue
        }

        $data = [ordered]@{}
        for ($column = 0; $column -lt $headers.Count; $column++) { $data[$headers[$column]] = $fields[$column] }
        [void]$rows.Add([pscustomobject]@{ LineNumber = $record.LineNumber; IsMalformed = $false; MalformedReason = $null; Data = [pscustomobject]$data })
    }

    return [pscustomobject]@{ Headers = $headers; Rows = $rows.ToArray() }
}
