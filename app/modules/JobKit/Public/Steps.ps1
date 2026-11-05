function Invoke-LoggedStep {
    <#
    .SYNOPSIS
    「これから何をするか」をログに出してから処理を実行し、その戻り値を返す。
    .DESCRIPTION
    手順の多いフローで、ログ文言と処理を1行ずつ対応させて読めるようにするための小さな部品。
    Log は Info メンバーを持つログポート。
    #>
    param(
        [Parameter(Mandatory)][object]$Log,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $info = Get-PortMember -Port $Log -PortName 'Log' -Member 'Info'
    & $info -Message $Message
    return & $Action
}
