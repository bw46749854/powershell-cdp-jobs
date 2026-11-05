# Context のサービスから、このジョブが使うポートを組み立てる（このジョブの合成ルート）。

$script:PlantingServiceShapes = @{
    Log = @{ Info = @('Message'); Warn = @('Message'); Section = @('Title'); Data = @('Label', 'Data') }
    Clock = @{ Now = @(); Sleep = @('Milliseconds') }
    Files = @{ EnsureDirectory = @('Path', 'Purpose'); ClearDirectory = @('Path', 'Purpose'); MoveToUnique = @('Path', 'DestinationDirectory', 'FileName'); SaveCsv = @('Path', 'Rows', 'Columns', 'Within', 'WhenEmpty') }
    Downloads = @{ WaitForFile = @('Directory', 'Filter', 'NamePattern', 'TimeoutSeconds', 'StableSeconds', 'RejectEmpty') }
    Lists = @{ Traverse = @('ExpectedCount', 'ReadVisible', 'KeyOf', 'Visit', 'ScrollNext', 'MaxLoops', 'StallLimit', 'EmptyMessage') }
}

function Assert-PlantingExportPorts {
    param([Parameter(Mandatory)][object]$Ports)

    foreach ($name in @($script:PlantingServiceShapes.Keys | Sort-Object)) {
        Assert-PortShape -Port (Get-PropertyValue -InputObject $Ports -Name $name) -PortName $name -Members $script:PlantingServiceShapes[$name]
    }
    Assert-PortShape -Port (Get-PropertyValue -InputObject $Ports -Name 'Page') -PortName 'Page' -Members $script:PlantingPageShape
}

function New-PlantingExportPorts {
    param([Parameter(Mandatory)][object]$Context)

    $services = $Context.Services
    if ($null -eq $services.Browser) {
        throw 'PlantingRecordExport はブラウザを使うジョブです。ジョブ定義（jobs.psd1）の UsesBrowser を確認してください。'
    }

    return [pscustomobject]@{
        Log = $services.Log
        Clock = $services.Clock
        Files = $services.Files
        Downloads = $services.Downloads
        Lists = $services.Lists
        Page = New-PlantingPage -Browser $services.Browser
    }
}
