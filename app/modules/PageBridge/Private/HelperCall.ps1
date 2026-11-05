# ページヘルパー呼び出しの JavaScript 式を組み立てる。
#
# ページ側のヘルパーは window.__pagekit.helpers[<Helper>] に登録される（app/browser/kernel/pagekit.js）。
# 呼び出しは常に async 関数で包んで await する。同期メソッドを await しても値は変わらないため、
# 「Promise を返すメソッドだけ特別扱いする」設定を持たずに済む。
#
# ヘルパーが無い（注入されていない・画面遷移で消えた）場合の扱いは、操作の Kind から一律に決める。

function ConvertTo-JavaScriptLiteral {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return 'null' }
    return (ConvertTo-Json -InputObject $Value -Compress -Depth 30)
}

function New-HelperAbsenceStatement {
    <#
    .SYNOPSIS
    ヘルパー未登録時に実行する JavaScript 文を、操作の Kind に応じて返す。
    #>
    param(
        [Parameter(Mandatory)][string]$Helper,
        [Parameter(Mandatory)][object]$Operation
    )

    $message = "[pagekit:helper-missing] ページヘルパー '$Helper' が登録されていません（操作: $($Operation.Name)）。"

    switch ($Operation.Kind) {
        { $_ -in @('Identity', 'Contract') } {
            $failure = [ordered]@{
                scope = $Operation.Scope
                ok = $false
                fatalCount = 1
                warningCount = 0
                checks = @(
                    [ordered]@{
                        name = 'helper.registered'
                        ok = $false
                        severity = 'fatal'
                        message = $message
                        details = [ordered]@{ helper = $Helper; method = $Operation.Method; reason = 'helper_missing' }
                    }
                )
                details = [ordered]@{ helper = $Helper; method = $Operation.Method; reason = 'helper_missing' }
            }
            return "return $(ConvertTo-JavaScriptLiteral -Value $failure);"
        }
        'Probe' {
            return 'return false;'
        }
        'Cleanup' {
            $warning = [ordered]@{ ok = $false; severity = 'warning'; reason = 'helper_missing'; message = $message }
            return "return $(ConvertTo-JavaScriptLiteral -Value $warning);"
        }
        default {
            return "throw new Error($(ConvertTo-JavaScriptLiteral -Value $message));"
        }
    }
}

function New-HelperCallExpression {
    <#
    .SYNOPSIS
    ヘルパーのメソッドを引数付きで呼ぶ JavaScript 式（async 即時関数）を返す。
    .PARAMETER Arguments
    各要素を JSON 化して位置引数として渡す。
    #>
    param(
        [Parameter(Mandatory)][string]$Helper,
        [Parameter(Mandatory)][object]$Operation,
        [AllowNull()][AllowEmptyCollection()][object[]]$Arguments = @()
    )

    if (-not (Test-JavaScriptIdentifier -Value $Helper)) {
        throw (New-BridgeException -Category 'configuration' -Message "Helper 名が JavaScript の識別子ではありません: $Helper")
    }
    if (-not (Test-JavaScriptIdentifier -Value $Operation.Method)) {
        throw (New-BridgeException -Category 'configuration' -Message "Method 名が JavaScript の識別子ではありません: $($Operation.Method)")
    }

    $literals = New-Object System.Collections.Generic.List[string]
    foreach ($argument in @($Arguments)) {
        [void]$literals.Add((ConvertTo-JavaScriptLiteral -Value $argument))
    }

    $helperLiteral = ConvertTo-JavaScriptLiteral -Value $Helper
    $methodLiteral = ConvertTo-JavaScriptLiteral -Value $Operation.Method
    $absence = New-HelperAbsenceStatement -Helper $Helper -Operation $Operation
    $methodMissing = ConvertTo-JavaScriptLiteral -Value "[pagekit:method-missing] ページヘルパー '$Helper' にメソッド '$($Operation.Method)' がありません。"

    return @"
(async () => {
  const kit = window.__pagekit;
  const helper = kit && kit.helpers ? kit.helpers[$helperLiteral] : undefined;
  if (!helper) { $absence }
  const method = helper[$methodLiteral];
  if (typeof method !== 'function') { throw new Error($methodMissing); }
  return await method.apply(helper, [$($literals -join ', ')]);
})()
"@
}
