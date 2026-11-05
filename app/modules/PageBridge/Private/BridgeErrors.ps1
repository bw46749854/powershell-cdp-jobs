# エラー分類。メッセージ文言ではなく「分類」で続行可否を判断できるようにする。
#
# 分類は Exception.Data に格納する。PowerShell の例外ラップ（MethodInvocationException 等）を
# 越えても読めるよう、判定時は InnerException を辿る。

$script:BridgeCategoryKey = 'pagebridge.category'

# ブラウザとの通信を続けられない分類。行単位の処理を続けても意味がない（危険な）状態。
$script:BridgeFatalCategories = @(
    'session-lost',
    'timeout',
    'helper-missing',
    'protocol'
)

function New-BridgeException {
    <#
    .SYNOPSIS
    分類付きの例外を作る。throw (New-BridgeException ...) の形で使う。
    .PARAMETER Category
    browser-unreachable / session-lost / timeout / helper-missing / protocol / command /
    javascript / wait-timeout / contract / configuration
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('browser-unreachable', 'session-lost', 'timeout', 'helper-missing', 'protocol', 'command', 'javascript', 'wait-timeout', 'contract', 'configuration')]
        [string]$Category,

        [Parameter(Mandatory)][string]$Message,

        [AllowNull()][System.Exception]$InnerException = $null
    )

    if ($Category -eq 'timeout') {
        $exception = New-Object System.TimeoutException -ArgumentList $Message, $InnerException
    }
    else {
        $exception = New-Object System.InvalidOperationException -ArgumentList $Message, $InnerException
    }

    $exception.Data[$script:BridgeCategoryKey] = $Category
    return $exception
}

function Get-BridgeErrorCategory {
    <#
    .SYNOPSIS
    ErrorRecord または Exception から分類を返す。分類が無ければ空文字。
    .DESCRIPTION
    明示的に付けた分類を優先し、無ければ .NET の例外型から推定する
    （WebSocket の切断や破棄済みオブジェクトは session-lost）。
    #>
    param([AllowNull()][object]$ErrorObject)

    $exception = $ErrorObject
    if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
        $exception = $ErrorObject.Exception
    }

    $inferred = ''
    $depth = 0
    while ($null -ne $exception -and $exception -is [System.Exception] -and $depth -lt 16) {
        if ($exception.Data.Contains($script:BridgeCategoryKey)) {
            return [string]$exception.Data[$script:BridgeCategoryKey]
        }

        if ([string]::IsNullOrEmpty($inferred)) {
            if ($exception -is [System.Net.WebSockets.WebSocketException] -or
                $exception -is [System.ObjectDisposedException] -or
                $exception -is [System.OperationCanceledException]) {
                $inferred = 'session-lost'
            }
            elseif ($exception -is [System.TimeoutException]) {
                $inferred = 'timeout'
            }
        }

        $exception = $exception.InnerException
        $depth++
    }

    return $inferred
}

function Test-BridgeFatalCategory {
    param([AllowEmptyString()][string]$Category)

    return ($script:BridgeFatalCategories -contains $Category)
}

function Get-InnermostExceptionMessage {
    param([Parameter(Mandatory)][System.Exception]$Exception)

    $current = $Exception
    while ($null -ne $current.InnerException) {
        $current = $current.InnerException
    }

    return $current.Message
}
