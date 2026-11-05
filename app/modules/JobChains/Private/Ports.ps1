# Context のサービスから、連携ジョブが使うポートを組み立てる（合成ルート）。
# 連携ジョブはブラウザを使わない。子ジョブの起動（Jobs）と成果物の存在確認（Files）だけを使う。

$script:JobChainServiceShapes = @{
    Log = @{ Info = @('Message'); Section = @('Title') }
    Clock = @{ Now = @() }
    Files = @{ EnsureDirectory = @('Path', 'Purpose'); Exists = @('Path'); ListFiles = @('Directory', 'Filter') }
    Jobs = @{ Run = @('JobName', 'Overrides'); GetSettings = @('JobName') }
}

function Assert-JobChainPorts {
    param([Parameter(Mandatory)][object]$Ports)

    foreach ($name in @($script:JobChainServiceShapes.Keys | Sort-Object)) {
        Assert-PortShape -Port (Get-PropertyValue -InputObject $Ports -Name $name) -PortName $name -Members $script:JobChainServiceShapes[$name]
    }
}

function New-JobChainPorts {
    param([Parameter(Mandatory)][object]$Context)

    $services = $Context.Services
    return [pscustomobject]@{
        Log = $services.Log
        Clock = $services.Clock
        Files = $services.Files
        Jobs = $services.Jobs
    }
}
