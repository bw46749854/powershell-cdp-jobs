# 実行コンテキスト（Context）の組み立てと後始末。
#
# Context はジョブコマンドへの唯一の引数で、ジョブが使ってよいものの全量を表す。
#   JobName / RunId
#   AppRoot / ProjectRoot / SettingsPath / CatalogPath
#   Entry      ジョブ定義（jobs.psd1 の解決済みエントリ）
#   Settings   このジョブの設定（Jobs.<JobName> のコピーに上書き値を適用したもの）
#   Common     共通設定
#   Services   Log / Files / Downloads / Lists / Clock / Jobs / Browser（ブラウザを使わないジョブは $null）
# 業務の途中状態（ループ変数や判定結果）は Context に入れない。

function New-HostRunId {
    param([Parameter(Mandatory)][object]$Clock)

    $now = & (Get-PortMember -Port $Clock -PortName 'Clock' -Member 'Now')
    return ([datetime]$now).ToString('yyyyMMdd_HHmmss_fff')
}

function New-HostRunContext {
    <#
    .PARAMETER Overrides
    テスト用: サービスの差し替え（Clock / ConsoleWriter / Transport）。本番では指定しない。
    #>
    param(
        [Parameter(Mandatory)][string]$AppRoot,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][object]$Entry,
        [hashtable]$SettingsOverrides = @{},
        [hashtable]$Overrides = @{}
    )

    $clock = Get-PropertyValue -InputObject $Overrides -Name 'Clock'
    if ($null -eq $clock) { $clock = New-HostClock }
    Assert-PortShape -Port $clock -PortName 'Clock' -Members $script:HostClockShape

    $runId = New-HostRunId -Clock $clock
    $log = New-HostLog `
        -Logging (Get-PropertyValue -InputObject $Settings.Common -Name 'Logging') `
        -JobName $Entry.Name `
        -RunId $runId `
        -Clock $clock `
        -ConsoleWriter (Get-PropertyValue -InputObject $Overrides -Name 'ConsoleWriter')

    $jobSettings = Get-HostJobSettings -Settings $Settings -JobName $Entry.Name -Overrides $SettingsOverrides -ProjectRoot $ProjectRoot

    $browser = $null
    if ($Entry.UsesBrowser) {
        $browser = New-HostBrowserService -Common $Settings.Common -Entry $Entry -Log $log -Clock $clock -Transport (Get-PropertyValue -InputObject $Overrides -Name 'Transport')
    }

    $services = [pscustomobject]@{
        Log = $log
        Clock = $clock
        Files = New-HostFileService
        Downloads = New-HostDownloadService -Clock $clock
        Lists = New-HostListService -Clock $clock -Log $log
        Jobs = New-HostJobsService -AppRoot $AppRoot -ProjectRoot $ProjectRoot -SettingsPath $SettingsPath -CatalogPath $CatalogPath -Settings $Settings
        Browser = $browser
    }

    return [pscustomobject]@{
        JobName = $Entry.Name
        RunId = $runId
        AppRoot = $AppRoot
        ProjectRoot = $ProjectRoot
        SettingsPath = $SettingsPath
        CatalogPath = $CatalogPath
        Entry = $Entry
        Settings = $jobSettings
        Common = $Settings.Common
        Services = $services
    }
}

function Close-HostRunContext {
    <#
    .SYNOPSIS
    ブラウザ接続などを閉じる。後始末の失敗でジョブ本来のエラーを上書きしない。
    #>
    param([AllowNull()][object]$Context)

    if ($null -eq $Context) { return }

    $browser = $Context.Services.Browser
    if ($null -ne $browser) {
        try { & $browser.Close } catch { }
    }
}
