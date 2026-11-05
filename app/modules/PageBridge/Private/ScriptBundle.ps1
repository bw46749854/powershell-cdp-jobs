# ページスクリプト（app/browser 配下）の注入。
#
# ジョブ定義（jobs.psd1）に並べた順にファイルを連結し、最後に kernel の ack を評価する。
# ack はヘルパーが公開しているメソッド一覧を返すので、操作カタログの全メソッドが
# 実装されているかを「注入した時点」で検証できる（カタログとスクリプトのずれを早期に検出する）。

function Read-PageScriptText {
    param([Parameter(Mandatory)][string[]]$Paths)

    $parts = New-Object System.Collections.Generic.List[string]
    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw (New-BridgeException -Category 'configuration' -Message "ページスクリプトが見つかりません: $path")
        }

        # BOM の有無にかかわらず UTF-8 として読む（Windows PowerShell 5.1 の既定 ANSI 読み込みを避ける）。
        $text = [System.IO.File]::ReadAllText($path, $encoding)
        [void]$parts.Add("// ---- $([System.IO.Path]::GetFileName($path)) ----")
        [void]$parts.Add($text.TrimStart([char]0xFEFF))
    }

    return ($parts -join "`n")
}

function New-PageBundleExpression {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)][string]$Helper,
        [Parameter(Mandatory)][string]$JobName
    )

    $helperLiteral = ConvertTo-JavaScriptLiteral -Value $Helper
    $sourceName = ($JobName -replace '[^A-Za-z0-9_-]', '_')

    return @"
$ScriptText
;(window.__pagekit && typeof window.__pagekit.ack === 'function')
  ? window.__pagekit.ack($helperLiteral)
  : { ok: false, helper: $helperLiteral, reason: 'kernel_missing', methods: [] };
//# sourceURL=pagekit/$sourceName.bundle.js
"@
}

function Assert-PageBundleAck {
    <#
    .SYNOPSIS
    注入結果（ack）を検証する。カタログのメソッドがヘルパーに無ければ設定不備として停止する。
    #>
    param(
        [AllowNull()][object]$Ack,
        [Parameter(Mandatory)][object]$Catalog
    )

    if ($null -eq $Ack -or (Get-PropertyValue -InputObject $Ack -Name 'ok') -ne $true) {
        $json = ConvertTo-Json -InputObject $Ack -Compress -Depth 8
        throw (New-BridgeException -Category 'configuration' -Message "ページスクリプトの注入に失敗しました（kernel が読み込まれていない可能性があります）。ack=$json")
    }

    if ([string](Get-PropertyValue -InputObject $Ack -Name 'helper') -ne $Catalog.Helper) {
        throw (New-BridgeException -Category 'configuration' -Message "注入したヘルパー名が操作カタログと一致しません。expected=$($Catalog.Helper) actual=$($Ack.helper)")
    }

    $methods = @(Get-PropertyValue -InputObject $Ack -Name 'methods' -Default @())
    $missing = @(
        $Catalog.Operations.Values |
            Where-Object { $methods -cnotcontains $_.Method } |
            ForEach-Object { "$($_.Name)=$($_.Method)" } |
            Sort-Object
    )
    if ($missing.Count -gt 0) {
        throw (New-BridgeException -Category 'configuration' -Message "操作カタログのメソッドがページヘルパー '$($Catalog.Helper)' にありません: $($missing -join ', ')")
    }
}
