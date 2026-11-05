# Context のサービスから、このジョブが使うポートを組み立てる（このジョブの合成ルート）。

$script:SoilAnalysisServiceShapes = @{
    Log = @{ Info = @('Message'); Warn = @('Message'); Section = @('Title') }
    Clock = @{ Now = @() }
    Files = @{ EnsureDirectory = @('Path', 'Purpose'); Exists = @('Path'); ReadText = @('Path'); SaveCsv = @('Path', 'Rows', 'Columns', 'Within', 'WhenEmpty') }
}

function Assert-SoilAnalysisPorts {
    param([Parameter(Mandatory)][object]$Ports)

    foreach ($name in @($script:SoilAnalysisServiceShapes.Keys | Sort-Object)) {
        Assert-PortShape -Port (Get-PropertyValue -InputObject $Ports -Name $name) -PortName $name -Members $script:SoilAnalysisServiceShapes[$name]
    }
    Assert-PortShape -Port (Get-PropertyValue -InputObject $Ports -Name 'Page') -PortName 'Page' -Members $script:SoilAnalysisPageShape
}

function New-SoilAnalysisPorts {
    param([Parameter(Mandatory)][object]$Context)

    $services = $Context.Services
    if ($null -eq $services.Browser) {
        throw 'SoilAnalysisTargetSync はブラウザを使うジョブです。ジョブ定義（jobs.psd1）の UsesBrowser を確認してください。'
    }

    return [pscustomobject]@{
        Log = $services.Log
        Clock = $services.Clock
        Files = $services.Files
        Page = New-SoilAnalysisPage -Browser $services.Browser
    }
}
