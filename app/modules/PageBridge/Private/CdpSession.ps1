# CDP セッション: 1つのタブ（page ターゲット）との WebSocket 接続と、コマンドの送受信。
# 状態はセッションオブジェクトに閉じ込め、モジュール全体の「現在のセッション」は持たない。
#
# コマンドは id で応答と対応付ける。id を持たないイベントや別 id の応答は読み捨てる。
# 期限はコマンド全体（送信 + 応答待ち）に対して1つだけ持ち、時刻は Clock ポートから得る。

$script:BridgeClockShape = @{
    Now = @()
    Sleep = @('Milliseconds')
}

function New-BridgeSystemClock {
    <#
    .SYNOPSIS
    実時間の Clock ポート（テストでは偽物の時計に差し替える）。
    #>
    return [pscustomobject]@{
        Now = { [CmdletBinding()] param() Get-Date }
        Sleep = { [CmdletBinding()] param([Parameter(Mandatory)][int]$Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    }
}

function Get-BridgeRemainingMilliseconds {
    param(
        [Parameter(Mandatory)][datetime]$Deadline,
        [Parameter(Mandatory)][object]$Clock
    )

    $now = & (Get-PortMember -Port $Clock -PortName 'Clock' -Member 'Now')
    $remaining = [int][Math]::Ceiling(($Deadline - [datetime]$now).TotalMilliseconds)
    if ($remaining -lt 0) { return 0 }
    return $remaining
}

function Open-CdpSession {
    <#
    .SYNOPSIS
    page ターゲットの WebSocket URL に接続し、セッションオブジェクトを返す。
    #>
    param(
        [Parameter(Mandatory)][object]$Transport,
        [Parameter(Mandatory)][string]$WebSocketUrl,
        [Parameter(Mandatory)][int]$ConnectTimeoutSeconds,
        [Parameter(Mandatory)][int]$CommandTimeoutSeconds,
        [Parameter(Mandatory)][object]$Clock
    )

    Assert-PortShape -Port $Transport -PortName 'CdpTransport' -Members $script:CdpTransportShape
    Assert-PortShape -Port $Clock -PortName 'Clock' -Members $script:BridgeClockShape

    $connect = Get-PortMember -Port $Transport -PortName 'CdpTransport' -Member 'Connect'
    $handle = & $connect -Uri $WebSocketUrl -TimeoutMilliseconds ($ConnectTimeoutSeconds * 1000)

    return [pscustomobject]@{
        Transport = $Transport
        Handle = $handle
        WebSocketUrl = $WebSocketUrl
        CommandTimeoutSeconds = $CommandTimeoutSeconds
        Clock = $Clock
        NextId = 0
        Closed = $false
    }
}

function Close-CdpSession {
    <#
    .SYNOPSIS
    セッションを閉じる。何度呼んでもよく、失敗しても例外にしない（後始末で元のエラーを隠さない）。
    #>
    param([AllowNull()][object]$Session)

    if ($null -eq $Session -or $Session.Closed) { return }

    $Session.Closed = $true
    try {
        $close = Get-PortMember -Port $Session.Transport -PortName 'CdpTransport' -Member 'Close'
        & $close -Handle $Session.Handle -TimeoutMilliseconds 3000
    }
    catch {
        # 後始末の失敗は無視する。
    }
}

function Stop-CdpSessionAfterFailure {
    param([Parameter(Mandatory)][object]$Session)

    # 応答の対応付けが崩れた可能性があるセッションは再利用しない。
    $Session.Closed = $true
    try {
        $abort = Get-PortMember -Port $Session.Transport -PortName 'CdpTransport' -Member 'Abort'
        & $abort -Handle $Session.Handle
    }
    catch {
        # 後始末の失敗は無視する。
    }
}

function Send-CdpCommand {
    <#
    .SYNOPSIS
    CDP コマンドを送信し、同じ id の応答の result を返す。
    .PARAMETER TimeoutSeconds
    0 以下ならセッションの既定値（CommandTimeoutSeconds）を使う。
    #>
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Method,
        [hashtable]$Params = @{},
        [int]$TimeoutSeconds = 0
    )

    if ($Session.Closed) {
        throw (New-BridgeException -Category 'session-lost' -Message "ブラウザとのセッションは既に閉じています。method=$Method")
    }

    if ($TimeoutSeconds -lt 1) { $TimeoutSeconds = [int]$Session.CommandTimeoutSeconds }

    $Session.NextId = [int]$Session.NextId + 1
    $id = [int]$Session.NextId
    $now = Get-PortMember -Port $Session.Clock -PortName 'Clock' -Member 'Now'
    $deadline = ([datetime](& $now)).AddSeconds($TimeoutSeconds)
    $send = Get-PortMember -Port $Session.Transport -PortName 'CdpTransport' -Member 'Send'
    $receive = Get-PortMember -Port $Session.Transport -PortName 'CdpTransport' -Member 'Receive'
    $payload = ConvertTo-Json -InputObject @{ id = $id; method = $Method; params = $Params } -Compress -Depth 30

    try {
        & $send -Handle $Session.Handle -Text $payload -TimeoutMilliseconds (Get-BridgeRemainingMilliseconds -Deadline $deadline -Clock $Session.Clock)

        while ($true) {
            $remaining = Get-BridgeRemainingMilliseconds -Deadline $deadline -Clock $Session.Clock
            if ($remaining -le 0) {
                throw (New-BridgeException -Category 'timeout' -Message "ブラウザの応答がタイムアウトしました。method=$Method id=$id timeoutSeconds=$TimeoutSeconds")
            }

            $text = & $receive -Handle $Session.Handle -TimeoutMilliseconds $remaining
            if ($null -eq $text) {
                throw (New-BridgeException -Category 'session-lost' -Message "ブラウザ側で WebSocket が閉じられました。method=$Method id=$id")
            }

            try {
                $message = ConvertFrom-Json -InputObject $text
            }
            catch {
                throw (New-BridgeException -Category 'protocol' -Message "ブラウザの応答を JSON として解釈できません。method=$Method id=$id / $($_.Exception.Message)")
            }

            if ((Get-PropertyValue -InputObject $message -Name 'id') -ne $id) {
                continue
            }

            $commandError = Get-PropertyValue -InputObject $message -Name 'error'
            if ($null -ne $commandError) {
                $errorMessage = Get-PropertyValue -InputObject $commandError -Name 'message' -Default ([string]$commandError)
                throw (New-BridgeException -Category 'command' -Message "ブラウザがコマンドを拒否しました。method=$Method id=$id message=$errorMessage")
            }

            return (Get-PropertyValue -InputObject $message -Name 'result')
        }
    }
    catch {
        if (Test-BridgeFatalCategory -Category (Get-BridgeErrorCategory -ErrorObject $_)) {
            Stop-CdpSessionAfterFailure -Session $Session
        }
        throw
    }
}
