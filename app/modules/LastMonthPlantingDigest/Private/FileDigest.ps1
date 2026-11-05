# 1ファイル分の集約（純粋関数）。ファイル名とバイト列を受け取り、先月の定植行と失敗を返す。
#
#   ファイル名 → 区画コード    （形式に合わなければファイルを飛ばす）
#   バイト列   → テキスト       （対応外の文字コードならファイルを飛ばす）
#   テキスト   → 表             （引用符の閉じ忘れなどで解析できなければファイルを飛ばす）
#   見出し     → 完全一致の確認 （一致しなければファイルを飛ばす）
#   各行       → 形の崩れ・定植日の読めない行は、その行だけ失敗にする / 先月の定植なら出力行にする
# ファイル I/O を持たないため、文字コードや形式の組み合わせを実ファイルなしで確かめられる。

function Invoke-FileDigest {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory)][object]$Range,
        [Parameter(Mandatory)][string[]]$RequiredHeaders,
        [Parameter(Mandatory)][string]$FileNamePattern
    )

    $name = Get-PlotCodeFromFileName -FileName $FileName -Pattern $FileNamePattern
    if (-not $name.IsValid) {
        return New-FileDigestResult -Skipped $true -Failures @(New-DigestFailure -FileName $FileName -Reason $name.Reason)
    }
    $plotCode = $name.PlotCode

    try {
        $decoded = ConvertFrom-CsvFileBytes -Bytes $Bytes
    }
    catch {
        return New-FileDigestResult -Skipped $true -PlotCode $plotCode -Failures @(New-DigestFailure -FileName $FileName -PlotCode $plotCode -Reason "文字コードを読めないためファイルを飛ばしました: $($_.Exception.Message)")
    }

    try {
        $delimiter = Get-DelimiterFromText -Text $decoded.Text
        $table = Import-DelimitedTable -Text $decoded.Text -Delimiter $delimiter
    }
    catch {
        return New-FileDigestResult -Skipped $true -PlotCode $plotCode -EncodingName $decoded.EncodingName -Failures @(New-DigestFailure -FileName $FileName -PlotCode $plotCode -Reason "CSV として解析できないためファイルを飛ばしました: $($_.Exception.Message)")
    }
    $delimiterName = if ($delimiter -eq "`t") { 'タブ区切り' } else { 'カンマ区切り' }

    $headers = Test-ExactHeaders -Headers @($table.Headers) -Expected $RequiredHeaders
    if (-not $headers.IsValid) {
        return New-FileDigestResult -Skipped $true -PlotCode $plotCode -EncodingName $decoded.EncodingName -DelimiterName $delimiterName -Failures @(New-DigestFailure -FileName $FileName -PlotCode $plotCode -Reason "$($headers.Reason)（ファイルを飛ばしました）")
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $failures = New-Object System.Collections.Generic.List[object]
    $readRowCount = 0
    foreach ($entry in @($table.Rows)) {
        $readRowCount++
        $line = [string]$entry.LineNumber

        if ($entry.IsMalformed) {
            [void]$failures.Add((New-DigestFailure -FileName $FileName -PlotCode $plotCode -LineNumber $line -Reason "行の形が崩れているため飛ばしました: $($entry.MalformedReason)"))
            continue
        }

        $plantedText = [string](Get-PropertyValue -InputObject $entry.Data -Name $script:PlantedHeader -Default '')
        $planted = ConvertTo-PlantingDate -Text $plantedText
        if ($null -eq $planted) {
            [void]$failures.Add((New-DigestFailure -FileName $FileName -PlotCode $plotCode -LineNumber $line -Reason "定植日を日付として読めないため行を飛ばしました: '$plantedText'"))
            continue
        }

        if (Test-DateInRange -Date $planted -Range $Range) {
            $crop = [string](Get-PropertyValue -InputObject $entry.Data -Name $script:CropHeader -Default '')
            $variety = [string](Get-PropertyValue -InputObject $entry.Data -Name $script:VarietyHeader -Default '')
            [void]$rows.Add((New-DigestRow -PlotCode $plotCode -Crop $crop -Variety $variety -Planted $plantedText.Trim()))
        }
    }

    return New-FileDigestResult -Rows $rows.ToArray() -Failures $failures.ToArray() -ReadRowCount $readRowCount -PlotCode $plotCode -EncodingName $decoded.EncodingName -DelimiterName $delimiterName
}
