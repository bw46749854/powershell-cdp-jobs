# Clock サービス（現在時刻と待機）。時刻と sleep はすべてここを通し、テストでは手動の時計に差し替える。

$script:HostClockShape = @{
    Now = @()
    Sleep = @('Milliseconds')
}

function New-HostClock {
    return [pscustomobject]@{
        Now = { [CmdletBinding()] param() Get-Date }
        Sleep = { [CmdletBinding()] param([Parameter(Mandatory)][int]$Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    }
}
