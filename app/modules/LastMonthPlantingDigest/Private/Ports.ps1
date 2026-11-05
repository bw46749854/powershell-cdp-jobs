# Context のサービスから、このジョブが使うポートを組み立てる（このジョブの合成ルート）。
# ブラウザは使わない。

$script:DigestServiceShapes = @{
    Log = @{ Info = @('Message'); Warn = @('Message'); Section = @('Title') }
    Clock = @{ Now = @() }
    Files = @{ EnsureDirectory = @('Path', 'Purpose'); ListFiles = @('Directory', 'Filter'); ReadBytes = @('Path'); SaveCsv = @('Path', 'Rows', 'Columns', 'Within', 'WhenEmpty') }
}

function Assert-PlantingDigestPorts {
    param([Parameter(Mandatory)][object]$Ports)

    foreach ($name in @($script:DigestServiceShapes.Keys | Sort-Object)) {
        Assert-PortShape -Port (Get-PropertyValue -InputObject $Ports -Name $name) -PortName $name -Members $script:DigestServiceShapes[$name]
    }
}

function New-PlantingDigestPorts {
    param([Parameter(Mandatory)][object]$Context)

    $services = $Context.Services
    return [pscustomobject]@{
        Log = $services.Log
        Clock = $services.Clock
        Files = $services.Files
    }
}
