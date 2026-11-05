# ページ内での JavaScript 実行（Runtime.evaluate）と、条件成立までのポーリング、ダウンロード先の設定。

$script:BridgeSentinelPattern = '\[pagekit:(?<kind>[a-z-]+)\]'

function ConvertTo-JavaScriptErrorException {
    <#
    .SYNOPSIS
    Runtime.evaluate の exceptionDetails を分類付き例外にする。
    .DESCRIPTION
    ページスクリプトは「ヘルパー未登録」などを [pagekit:helper-missing] の目印付きで throw する。
    目印があれば helper-missing（続行不能）に分類し、無ければ javascript（業務操作の失敗）とする。
    #>
    param([Parameter(Mandatory)][object]$ExceptionDetails)

    $message = [string](Get-PropertyValue -InputObject $ExceptionDetails -Name 'text' -Default '')
    $exception = Get-PropertyValue -InputObject $ExceptionDetails -Name 'exception'
    $description = [string](Get-PropertyValue -InputObject $exception -Name 'description' -Default '')
    $value = Get-PropertyValue -InputObject $exception -Name 'value'
    if (-not [string]::IsNullOrWhiteSpace($description)) {
        $message = $description
    }
    elseif ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
        $message = [string]$value
    }

    $category = 'javascript'
    $match = [regex]::Match($message, $script:BridgeSentinelPattern)
    if ($match.Success -and ($match.Groups['kind'].Value -in @('helper-missing', 'method-missing'))) {
        $category = 'helper-missing'
    }

    return (New-BridgeException -Category $category -Message "ページ内スクリプトでエラーが発生しました: $message")
}

function Invoke-CdpEvaluate {
    <#
    .SYNOPSIS
    式をページ内で評価し、値（JSON 化できる値）を返す。Promise は解決まで待つ。
    .NOTES
    配列の戻り値は PowerShell の仕様で展開される。配列を期待する呼び出し側は @() で受けること。
    #>
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Expression,
        [int]$TimeoutSeconds = 0
    )

    $params = @{
        expression = $Expression
        returnByValue = $true
        awaitPromise = $true
        userGesture = $true
    }

    $result = Send-CdpCommand -Session $Session -Method 'Runtime.evaluate' -Params $params -TimeoutSeconds $TimeoutSeconds
    $exceptionDetails = Get-PropertyValue -InputObject $result -Name 'exceptionDetails'
    if ($null -ne $exceptionDetails) {
        throw (ConvertTo-JavaScriptErrorException -ExceptionDetails $exceptionDetails)
    }

    $remoteObject = Get-PropertyValue -InputObject $result -Name 'result'
    return (Get-PropertyValue -InputObject $remoteObject -Name 'value')
}

function Wait-CdpEvaluation {
    <#
    .SYNOPSIS
    式を繰り返し評価し、Accept が $true を返した時点の値を返す。
    .DESCRIPTION
    画面描画中の一時的な JavaScript エラーは待機中だけ許容する。
    ただしセッション切断など続行不能な分類のエラーは、待っても回復しないため即座に再送出する。
    期限切れは wait-timeout（続行可否は呼び出し側が判断する）に分類する。
    #>
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Expression,
        [Parameter(Mandatory)][scriptblock]$Accept,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$Description,
        [int]$PollMilliseconds = 250
    )

    $clock = $Session.Clock
    $now = Get-PortMember -Port $clock -PortName 'Clock' -Member 'Now'
    $sleep = Get-PortMember -Port $clock -PortName 'Clock' -Member 'Sleep'
    $deadline = ([datetime](& $now)).AddSeconds($TimeoutSeconds)
    $hasValue = $false
    $lastValue = $null
    $lastError = ''

    while ([datetime](& $now) -lt $deadline) {
        $evaluated = $false
        $value = $null
        try {
            $remainingSeconds = [int][Math]::Ceiling(($deadline - [datetime](& $now)).TotalSeconds)
            if ($remainingSeconds -lt 1) { $remainingSeconds = 1 }

            $value = Invoke-CdpEvaluate -Session $Session -Expression $Expression -TimeoutSeconds $remainingSeconds
            $evaluated = $true
            $hasValue = $true
            $lastValue = $value
        }
        catch {
            if (Test-BridgeFatalCategory -Category (Get-BridgeErrorCategory -ErrorObject $_)) { throw }
            $lastError = $_.Exception.Message
        }

        # Accept 自体の例外（結果の形が契約と違う等）は待っても直らないため、そのまま呼び出し元へ伝える。
        if ($evaluated -and (& $Accept $value) -eq $true) {
            return $value
        }

        if ([datetime](& $now) -lt $deadline) {
            & $sleep -Milliseconds $PollMilliseconds
        }
    }

    $detail = ''
    if ($hasValue) {
        $detail = " / 最後の結果: $(ConvertTo-Json -InputObject $lastValue -Compress -Depth 12)"
    }
    elseif (-not [string]::IsNullOrEmpty($lastError)) {
        $detail = " / 最後のエラー: $lastError"
    }

    throw (New-BridgeException -Category 'wait-timeout' -Message "待機がタイムアウトしました: $Description（$TimeoutSeconds 秒）$detail")
}

function Set-CdpDownloadBehavior {
    <#
    .SYNOPSIS
    ダウンロードを確認なしで許可し、保存先を指定する。
    .DESCRIPTION
    Browser.setDownloadBehavior を優先し、page セッションで受け付けられない環境では
    Page.setDownloadBehavior で再試行する。どちらで設定したかを返す。
    #>
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][object]$Log
    )

    $params = @{ behavior = 'allow'; downloadPath = $Directory }
    try {
        [void](Send-CdpCommand -Session $Session -Method 'Browser.setDownloadBehavior' -Params $params)
        return 'Browser.setDownloadBehavior'
    }
    catch {
        if (Test-BridgeFatalCategory -Category (Get-BridgeErrorCategory -ErrorObject $_)) { throw }
        $warn = Get-PortMember -Port $Log -PortName 'Log' -Member 'Warn'
        & $warn -Message "Browser.setDownloadBehavior が使えないため Page.setDownloadBehavior で再試行します。詳細: $($_.Exception.Message)"
    }

    [void](Send-CdpCommand -Session $Session -Method 'Page.setDownloadBehavior' -Params $params)
    return 'Page.setDownloadBehavior'
}
