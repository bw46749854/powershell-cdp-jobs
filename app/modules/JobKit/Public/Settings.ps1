# ジョブ設定（settings.psd1 の Jobs.<JobName>）を「型付きで」読むための関数。
# 各ジョブはジョブ開始時に必要な設定を一括で読み、欠落・型違いを処理開始前に検出する。

function Read-JobSetting {
    <#
    .SYNOPSIS
    設定値を1つ、指定した種類として検証して返す。
    .PARAMETER Kind
    Text      : 空白でない文字列
    Integer   : 整数（Minimum 以上）
    Pattern   : 空白でない、正規表現として解釈できる文字列
    TextList  : 空白でない文字列の配列（1件以上。単独の文字列は不可）
    Flag      : 真偽値
    .PARAMETER Scope
    エラーメッセージ用の設定位置（例: Jobs.<ジョブ名>）。
    .NOTES
    TextList の戻り値は配列のため、呼び出し側は @() で受けること。
    #>
    param(
        [AllowNull()][object]$Settings,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Text', 'Integer', 'Pattern', 'TextList', 'Flag')][string]$Kind,
        [Parameter(Mandatory)][string]$Scope,
        [int]$Minimum = [int]::MinValue
    )

    $location = "$Scope.$Name"
    if (-not (Test-PropertyPresent -InputObject $Settings -Name $Name)) {
        throw "設定 $location がありません。"
    }

    # 空配列が $null に展開されないよう、関数を経由せず生の値を読む。
    if ($Settings -is [System.Collections.IDictionary]) {
        $value = $Settings[$Name]
    }
    else {
        $value = $Settings.PSObject.Properties[$Name].Value
    }

    switch ($Kind) {
        'Text' {
            if (-not ($value -is [string]) -or [string]::IsNullOrWhiteSpace($value)) {
                throw "設定 $location は空でない文字列で指定してください。"
            }
            return $value
        }
        'Integer' {
            if (-not ($value -is [int] -or $value -is [long])) {
                throw "設定 $location は整数で指定してください。"
            }
            if ($value -lt $Minimum) {
                throw "設定 $location は $Minimum 以上で指定してください（実際: $value）。"
            }
            return [int]$value
        }
        'Pattern' {
            if (-not ($value -is [string]) -or [string]::IsNullOrWhiteSpace($value)) {
                throw "設定 $location は空でない正規表現で指定してください。"
            }
            try {
                [void][regex]::new($value)
            }
            catch {
                throw "設定 $location は正規表現として解釈できません: $($_.Exception.Message)"
            }
            return $value
        }
        'TextList' {
            if ($value -is [string] -or -not ($value -is [System.Array])) {
                throw "設定 $location は文字列の配列 @(...) で指定してください。"
            }
            $items = @($value)
            if ($items.Count -eq 0) {
                throw "設定 $location が空です。"
            }
            foreach ($item in $items) {
                if (-not ($item -is [string]) -or [string]::IsNullOrWhiteSpace($item)) {
                    throw "設定 $location に空、または文字列でない要素があります。"
                }
            }
            return $items
        }
        'Flag' {
            if (-not ($value -is [bool])) {
                throw "設定 $location は `$true / `$false で指定してください。"
            }
            return $value
        }
    }
}
