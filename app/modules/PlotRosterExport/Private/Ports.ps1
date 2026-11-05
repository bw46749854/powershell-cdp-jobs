# Context のサービスから、このジョブが使うポートを組み立てる（このジョブの合成ルート）。
# Flow は Context を受け取らず、ここで作ったポートだけを使う。
# 形（メンバー名とパラメーター名）は Assert-PlotRosterExportPorts で検証し、テストの偽物にも同じ検証を通す。

$script:PlotRosterServiceShapes = @{
    Log = @{ Info = @('Message'); Section = @('Title'); Data = @('Label', 'Data') }
    Clock = @{ Now = @() }
    Files = @{ EnsureDirectory = @('Path', 'Purpose'); ClearDirectory = @('Path', 'Purpose'); MoveToUnique = @('Path', 'DestinationDirectory', 'FileName') }
    Downloads = @{ WaitForFile = @('Directory', 'Filter', 'NamePattern', 'TimeoutSeconds', 'StableSeconds', 'RejectEmpty') }
}

function Assert-PlotRosterExportPorts {
    param([Parameter(Mandatory)][object]$Ports)

    foreach ($name in @($script:PlotRosterServiceShapes.Keys | Sort-Object)) {
        Assert-PortShape -Port (Get-PropertyValue -InputObject $Ports -Name $name) -PortName $name -Members $script:PlotRosterServiceShapes[$name]
    }
    Assert-PortShape -Port (Get-PropertyValue -InputObject $Ports -Name 'Page') -PortName 'Page' -Members $script:PlotRosterPageShape
}

function New-PlotRosterExportPorts {
    param([Parameter(Mandatory)][object]$Context)

    $services = $Context.Services
    if ($null -eq $services.Browser) {
        throw 'PlotRosterExport はブラウザを使うジョブです。ジョブ定義（jobs.psd1）の UsesBrowser を確認してください。'
    }

    return [pscustomobject]@{
        Log = $services.Log
        Clock = $services.Clock
        Files = $services.Files
        Downloads = $services.Downloads
        Page = New-PlotRosterPage -Browser $services.Browser
    }
}
