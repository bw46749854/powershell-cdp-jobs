# CSV ファイルのバイト列をテキストにする（純粋関数）。
#
# 受け付ける文字コード: BOM 付き UTF-8 / UTF-16（LE・BE）/ UTF-32（LE・BE）、BOM なし UTF-8
# それ以外（Shift_JIS など）は読み違えを防ぐため変換せず、推定した文字コードを添えて例外にする。
# BOM の判定順は UTF-32 LE（FF FE 00 00）を UTF-16 LE（FF FE）より先にする（先頭2バイトが同じため）。

$script:TextBoms = @(
    @{ Name = 'UTF-32 LE（BOM 付き）'; Bytes = [byte[]]@(0xFF, 0xFE, 0x00, 0x00); Encoding = { New-Object System.Text.UTF32Encoding -ArgumentList $false, $true, $true } }
    @{ Name = 'UTF-32 BE（BOM 付き）'; Bytes = [byte[]]@(0x00, 0x00, 0xFE, 0xFF); Encoding = { New-Object System.Text.UTF32Encoding -ArgumentList $true, $true, $true } }
    @{ Name = 'UTF-8（BOM 付き）'; Bytes = [byte[]]@(0xEF, 0xBB, 0xBF); Encoding = { New-Object System.Text.UTF8Encoding -ArgumentList $false, $true } }
    @{ Name = 'UTF-16 LE（BOM 付き）'; Bytes = [byte[]]@(0xFF, 0xFE); Encoding = { New-Object System.Text.UnicodeEncoding -ArgumentList $false, $true, $true } }
    @{ Name = 'UTF-16 BE（BOM 付き）'; Bytes = [byte[]]@(0xFE, 0xFF); Encoding = { New-Object System.Text.UnicodeEncoding -ArgumentList $true, $true, $true } }
)

function Test-BytesStartWith {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory)][byte[]]$Prefix
    )

    if ($Bytes.Length -lt $Prefix.Length) { return $false }
    for ($index = 0; $index -lt $Prefix.Length; $index++) {
        if ($Bytes[$index] -ne $Prefix[$index]) { return $false }
    }
    return $true
}

function Get-TextEncodingGuess {
    <#
    .SYNOPSIS
    読めなかったバイト列の文字コードを推定する（エラーメッセージ用。変換には使わない）。
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    try {
        $shiftJis = [System.Text.Encoding]::GetEncoding(932, [System.Text.EncoderFallback]::ExceptionFallback, [System.Text.DecoderFallback]::ExceptionFallback)
        $roundTrip = $shiftJis.GetBytes($shiftJis.GetString($Bytes))
        if ([System.Convert]::ToBase64String($roundTrip) -eq [System.Convert]::ToBase64String($Bytes)) {
            return 'Shift_JIS（CP932）の可能性'
        }
    }
    catch {
        # 推定できないだけなので、次の候補へ進む。
    }

    return '不明'
}

function ConvertFrom-CsvFileBytes {
    <#
    .SYNOPSIS
    バイト列をテキストにし、判定した文字コード名と一緒に返す。
    .OUTPUTS
    Text / EncodingName
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    if ($Bytes.Length -eq 0) { throw '空のファイルです。' }

    foreach ($bom in $script:TextBoms) {
        if (Test-BytesStartWith -Bytes $Bytes -Prefix $bom.Bytes) {
            $encoding = & $bom.Encoding
            $text = $encoding.GetString($Bytes, $bom.Bytes.Length, $Bytes.Length - $bom.Bytes.Length)
            return [pscustomobject]@{ Text = $text; EncodingName = $bom.Name }
        }
    }

    try {
        $text = (New-Object System.Text.UTF8Encoding -ArgumentList $false, $true).GetString($Bytes)
        return [pscustomobject]@{ Text = $text; EncodingName = 'UTF-8（BOM なし）' }
    }
    catch {
        $guess = Get-TextEncodingGuess -Bytes $Bytes
        throw "対応していない文字コードです（対応: UTF-8、BOM 付きの UTF-16 / UTF-32）。推定: $guess"
    }
}
