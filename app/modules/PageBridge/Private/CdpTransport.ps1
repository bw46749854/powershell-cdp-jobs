# CDP の具体的な通信手段（HTTP と WebSocket）。
# このファイルだけが System.Net.Http / System.Net.WebSockets を直接使う。
# 上位（CdpSession 以降）はトランスポートポートの形にだけ依存し、テストでは偽物に差し替える。
#
# トランスポートポートの形:
#   GetText  -Uri -TimeoutSeconds            → 応答本文（文字列）
#   Connect  -Uri -TimeoutMilliseconds       → 接続ハンドル
#   Send     -Handle -Text -TimeoutMilliseconds
#   Receive  -Handle -TimeoutMilliseconds    → 受信メッセージ（文字列）。相手が閉じた場合は $null
#   Close    -Handle -TimeoutMilliseconds    → 正常クローズ（失敗しても例外にしない）
#   Abort    -Handle                         → 強制切断と破棄（失敗しても例外にしない）
#
# ポートのメンバーは「モジュール関数への1行の委譲」にする。
# GetNewClosure() で作った scriptblock からはモジュール内の非公開関数を名前で解決できないため、
# 構築時に CommandInfo を取得して閉じ込める。

$script:CdpTransportShape = @{
    GetText = @('Uri', 'TimeoutSeconds')
    Connect = @('Uri', 'TimeoutMilliseconds')
    Send = @('Handle', 'Text', 'TimeoutMilliseconds')
    Receive = @('Handle', 'TimeoutMilliseconds')
    Close = @('Handle', 'TimeoutMilliseconds')
    Abort = @('Handle')
}

function Wait-BridgeTask {
    <#
    .SYNOPSIS
    .NET の Task を期限付きで待つ。期限切れは timeout、通信系の失敗は session-lost に分類する。
    #>
    param(
        [Parameter(Mandatory)][System.Threading.Tasks.Task]$Task,
        [Parameter(Mandatory)][int]$TimeoutMilliseconds,
        [Parameter(Mandatory)][string]$Description
    )

    if ($TimeoutMilliseconds -lt 1) { $TimeoutMilliseconds = 1 }

    try {
        $completed = $Task.Wait($TimeoutMilliseconds)
    }
    catch {
        $message = Get-InnermostExceptionMessage -Exception $_.Exception
        $category = Get-BridgeErrorCategory -ErrorObject $_
        if ([string]::IsNullOrEmpty($category)) { $category = 'session-lost' }
        throw (New-BridgeException -Category $category -Message "ブラウザとの通信に失敗しました: $Description / $message" -InnerException $_.Exception)
    }

    if (-not $completed) {
        throw (New-BridgeException -Category 'timeout' -Message "ブラウザとの通信がタイムアウトしました: $Description / timeoutMilliseconds=$TimeoutMilliseconds")
    }
}

function Get-CdpHttpText {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][int]$TimeoutSeconds)

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $client = New-Object System.Net.Http.HttpClient -ArgumentList $handler
    try {
        $client.Timeout = [TimeSpan]::FromSeconds([Math]::Max($TimeoutSeconds, 1) + 1)
        $task = $client.GetStringAsync($Uri)
        Wait-BridgeTask -Task $task -TimeoutMilliseconds ($TimeoutSeconds * 1000) -Description "GET $Uri"
        return $task.Result
    }
    finally {
        $client.Dispose()
    }
}

function Stop-CdpSocket {
    <#
    .SYNOPSIS
    WebSocket を強制切断して破棄する。後始末なので失敗しても例外にしない。
    #>
    param([AllowNull()][object]$Handle)

    if ($null -eq $Handle) { return }

    try { $Handle.Cancellation.Cancel() } catch { }
    try { $Handle.Socket.Abort() } catch { }
    try { $Handle.Socket.Dispose() } catch { }
    try { $Handle.Cancellation.Dispose() } catch { }
}

function Connect-CdpSocket {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][int]$TimeoutMilliseconds)

    $socket = New-Object System.Net.WebSockets.ClientWebSocket
    $socket.Options.Proxy = $null
    $handle = [pscustomobject]@{
        Socket = $socket
        Cancellation = New-Object System.Threading.CancellationTokenSource
    }

    try {
        $task = $socket.ConnectAsync([Uri]$Uri, $handle.Cancellation.Token)
        Wait-BridgeTask -Task $task -TimeoutMilliseconds $TimeoutMilliseconds -Description 'WebSocket 接続'
    }
    catch {
        Stop-CdpSocket -Handle $handle
        throw
    }

    return $handle
}

function Send-CdpSocketText {
    param([Parameter(Mandatory)][object]$Handle, [Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][int]$TimeoutMilliseconds)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $bytes)
    try {
        $task = $Handle.Socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $Handle.Cancellation.Token)
        Wait-BridgeTask -Task $task -TimeoutMilliseconds $TimeoutMilliseconds -Description 'WebSocket 送信'
    }
    catch {
        # 送信途中で失敗・期限切れになった接続は再利用できないため破棄する。
        Stop-CdpSocket -Handle $Handle
        throw
    }
}

function Receive-CdpSocketText {
    param([Parameter(Mandatory)][object]$Handle, [Parameter(Mandatory)][int]$TimeoutMilliseconds)

    # 1メッセージが複数フレームに分かれても、全フレームを結合してから UTF-8 として解釈する。
    $buffer = New-Object byte[] 65536
    $stream = New-Object System.IO.MemoryStream
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        do {
            $remaining = $TimeoutMilliseconds - [int]$watch.ElapsedMilliseconds
            if ($remaining -lt 1) {
                throw (New-BridgeException -Category 'timeout' -Message "ブラウザからの応答待ちがタイムアウトしました。timeoutMilliseconds=$TimeoutMilliseconds")
            }

            $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList (, $buffer)
            $task = $Handle.Socket.ReceiveAsync($segment, $Handle.Cancellation.Token)
            Wait-BridgeTask -Task $task -TimeoutMilliseconds $remaining -Description 'WebSocket 受信'
            $result = $task.Result

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                return $null
            }

            $stream.Write($buffer, 0, $result.Count)
        }
        while (-not $result.EndOfMessage)

        return [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
    }
    catch {
        Stop-CdpSocket -Handle $Handle
        throw
    }
    finally {
        $stream.Dispose()
    }
}

function Close-CdpSocket {
    param([AllowNull()][object]$Handle, [Parameter(Mandatory)][int]$TimeoutMilliseconds)

    if ($null -eq $Handle) { return }

    try {
        if ($Handle.Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $task = $Handle.Socket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [System.Threading.CancellationToken]::None)
            [void]$task.Wait($TimeoutMilliseconds)
        }
    }
    catch {
        # クローズ失敗は後始末の問題であり、本来のエラーを上書きしない。
    }
    finally {
        Stop-CdpSocket -Handle $Handle
    }
}
