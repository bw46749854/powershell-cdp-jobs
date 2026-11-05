# 実ブラウザ用のトランスポート（CDP の HTTP / WebSocket 通信）を作る公開関数。
# 通信の実装は Private/CdpTransport.ps1。テストでは同じ形の偽物（tests/support の New-FakeCdpTransport）に差し替える。

function New-CdpTransport {
    <#
    .SYNOPSIS
    実ブラウザ用のトランスポートポートを作る。
    .DESCRIPTION
    CDP の待ち受けはローカル（localhost）なので、HTTP / WebSocket ともにプロキシを使わない。
    #>
    Add-Type -AssemblyName System.Net.Http

    $getText = Get-Command -Name Get-CdpHttpText -CommandType Function
    $connect = Get-Command -Name Connect-CdpSocket -CommandType Function
    $send = Get-Command -Name Send-CdpSocketText -CommandType Function
    $receive = Get-Command -Name Receive-CdpSocketText -CommandType Function
    $close = Get-Command -Name Close-CdpSocket -CommandType Function
    $abort = Get-Command -Name Stop-CdpSocket -CommandType Function

    return [pscustomobject]@{
        GetText = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][int]$TimeoutSeconds)
            & $getText -Uri $Uri -TimeoutSeconds $TimeoutSeconds
        }.GetNewClosure()
        Connect = {
            [CmdletBinding()] param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][int]$TimeoutMilliseconds)
            & $connect -Uri $Uri -TimeoutMilliseconds $TimeoutMilliseconds
        }.GetNewClosure()
        Send = {
            [CmdletBinding()] param([Parameter(Mandatory)][object]$Handle, [Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][int]$TimeoutMilliseconds)
            & $send -Handle $Handle -Text $Text -TimeoutMilliseconds $TimeoutMilliseconds
        }.GetNewClosure()
        Receive = {
            [CmdletBinding()] param([Parameter(Mandatory)][object]$Handle, [Parameter(Mandatory)][int]$TimeoutMilliseconds)
            & $receive -Handle $Handle -TimeoutMilliseconds $TimeoutMilliseconds
        }.GetNewClosure()
        Close = {
            [CmdletBinding()] param([AllowNull()][object]$Handle, [Parameter(Mandatory)][int]$TimeoutMilliseconds)
            & $close -Handle $Handle -TimeoutMilliseconds $TimeoutMilliseconds
        }.GetNewClosure()
        Abort = {
            [CmdletBinding()] param([AllowNull()][object]$Handle)
            & $abort -Handle $Handle
        }.GetNewClosure()
    }
}
