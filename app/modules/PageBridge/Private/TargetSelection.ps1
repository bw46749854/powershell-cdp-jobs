# 操作対象タブの選択。
# 1. ブラウザの /json からタブ一覧を得る
# 2. 拡張機能・開発者ツール・ブラウザ内部ページなど、業務画面になり得ないものを除く
# 3. 残った各タブで「画面識別」を実行し、一致したタブがちょうど1つの場合だけ選ぶ
# 0件・複数件は誤操作防止のため停止する（どのタブを操作すべきか決められない）。

function ConvertFrom-CdpTargetListText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    try {
        # 5.1 の ConvertFrom-Json は JSON の配列を「配列1つ」として出力するため、ForEach-Object で要素に展開する
        return @(ConvertFrom-Json -InputObject $Text | ForEach-Object { $_ })
    }
    catch {
        throw (New-BridgeException -Category 'browser-unreachable' -Message "ブラウザのタブ一覧を JSON として解釈できません: $($_.Exception.Message)")
    }
}

function Get-CdpPageTargets {
    <#
    .SYNOPSIS
    デバッグ用エンドポイント（例: http://localhost:9222/json）からタブ一覧を取得する。
    #>
    param(
        [Parameter(Mandatory)][object]$Transport,
        [Parameter(Mandatory)][string]$DebuggerUrl,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $getText = Get-PortMember -Port $Transport -PortName 'CdpTransport' -Member 'GetText'
    try {
        $text = & $getText -Uri $DebuggerUrl -TimeoutSeconds $TimeoutSeconds
    }
    catch {
        throw (New-BridgeException -Category 'browser-unreachable' -Message "ブラウザのデバッグ用ポートに接続できません（$DebuggerUrl）。Edge / Chrome を --remote-debugging-port 付きで起動してください。詳細: $($_.Exception.Message)" -InnerException $_.Exception)
    }

    return @(ConvertFrom-CdpTargetListText -Text $text)
}

function Test-OperablePageTarget {
    <#
    .SYNOPSIS
    業務画面として操作し得るタブかを返す。
    #>
    param([AllowNull()][object]$Target)

    if ($null -eq $Target) { return $false }

    $type = [string](Get-PropertyValue -InputObject $Target -Name 'type' -Default '')
    $webSocketUrl = [string](Get-PropertyValue -InputObject $Target -Name 'webSocketDebuggerUrl' -Default '')
    $url = [string](Get-PropertyValue -InputObject $Target -Name 'url' -Default '')
    $title = [string](Get-PropertyValue -InputObject $Target -Name 'title' -Default '')

    if ($type -ne 'page') { return $false }
    if ([string]::IsNullOrWhiteSpace($webSocketUrl)) { return $false }
    foreach ($prefix in @('chrome-extension://', 'devtools://', 'chrome://', 'edge://')) {
        if ($url.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    if ($title -like 'Service Worker*') { return $false }

    return $true
}

function Write-TargetSelectionDiagnostics {
    param(
        [Parameter(Mandatory)][string]$Headline,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Outcomes,
        [Parameter(Mandatory)][object]$Log
    )

    $warn = Get-PortMember -Port $Log -PortName 'Log' -Member 'Warn'
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add($Headline)
    foreach ($outcome in $Outcomes) {
        $status = if ($outcome.Matched) { '一致' } else { '不一致' }
        [void]$lines.Add("  - [$status] $($outcome.Title) <$($outcome.Url)>")
        if (-not [string]::IsNullOrWhiteSpace($outcome.Reason)) {
            [void]$lines.Add("      理由: $($outcome.Reason)")
        }
    }

    & $warn -Message ($lines -join [Environment]::NewLine)
}

function Select-IdentifiedPageTarget {
    <#
    .SYNOPSIS
    画面識別に一致するタブをちょうど1つ選ぶ。
    .PARAMETER Probe
    param($Target) を受け取り @{ Matched; Reason } を返す scriptblock。
    失敗時は例外の Data['pagebridge.probe.stage'] に段階を入れて投げる。
      'connect'  : タブへ接続できなかった → そのタブは「不一致」として扱い、他のタブの判定を続ける
      'identify' : 接続後の画面識別が失敗した → スクリプトかカタログの不具合として即停止する
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Targets,
        [Parameter(Mandatory)][scriptblock]$Probe,
        [Parameter(Mandatory)][object]$Log
    )

    $candidates = @($Targets | Where-Object { Test-OperablePageTarget -Target $_ })
    if ($candidates.Count -eq 0) {
        throw (New-BridgeException -Category 'contract' -Message '操作できるタブが見つかりません。対象の画面を開いてから再実行してください。')
    }

    $outcomes = New-Object System.Collections.Generic.List[object]
    foreach ($target in $candidates) {
        $outcome = [pscustomobject]@{
            Target = $target
            Title = [string](Get-PropertyValue -InputObject $target -Name 'title' -Default '')
            Url = [string](Get-PropertyValue -InputObject $target -Name 'url' -Default '')
            Matched = $false
            Reason = ''
        }

        try {
            $result = & $Probe -Target $target
            $outcome.Matched = ((Get-PropertyValue -InputObject $result -Name 'Matched') -eq $true)
            $outcome.Reason = [string](Get-PropertyValue -InputObject $result -Name 'Reason' -Default '')
        }
        catch {
            $stage = ''
            if ($_.Exception.Data.Contains('pagebridge.probe.stage')) { $stage = [string]$_.Exception.Data['pagebridge.probe.stage'] }
            $outcome.Reason = $_.Exception.Message
            [void]$outcomes.Add($outcome)

            if ($stage -eq 'identify') {
                # 接続できたタブで画面識別そのものが失敗するのは、ページスクリプトか操作カタログの不具合。
                Write-TargetSelectionDiagnostics -Headline '画面識別の実行中にエラーが発生しました。' -Outcomes $outcomes.ToArray() -Log $Log
                throw (New-BridgeException -Category 'configuration' -Message "画面識別の実行中にエラーが発生しました。ページスクリプトと操作カタログを確認してください。詳細: $($_.Exception.Message)" -InnerException $_.Exception)
            }

            continue
        }

        [void]$outcomes.Add($outcome)
    }

    $matched = @($outcomes | Where-Object { $_.Matched })
    if ($matched.Count -eq 0) {
        Write-TargetSelectionDiagnostics -Headline '対象の画面と一致するタブが見つかりません。' -Outcomes $outcomes.ToArray() -Log $Log
        throw (New-BridgeException -Category 'contract' -Message '対象の画面と一致するタブが見つかりません。ジョブの対象画面を開いてから再実行してください。')
    }

    if ($matched.Count -gt 1) {
        Write-TargetSelectionDiagnostics -Headline '対象の画面と一致するタブが複数あります。' -Outcomes $outcomes.ToArray() -Log $Log
        throw (New-BridgeException -Category 'contract' -Message '対象の画面と一致するタブが複数あります。どのタブを操作すべきか決められないため停止します。同じ画面のタブは1つだけ残してください。')
    }

    return $matched[0].Target
}

function Test-PageTargetIdentity {
    <#
    .SYNOPSIS
    1つのタブに一時的に接続し、スクリプトを注入して画面識別を実行する。
    .DESCRIPTION
    接続前の失敗は stage=connect、接続後の失敗は stage=identify として例外に印を付ける
    （Select-IdentifiedPageTarget が続行可否を判断するため）。
    #>
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][object]$Context
    )

    try {
        $session = Open-CdpSession `
            -Transport $Context.Transport `
            -WebSocketUrl ([string]$Target.webSocketDebuggerUrl) `
            -ConnectTimeoutSeconds $Context.ConnectTimeoutSeconds `
            -CommandTimeoutSeconds $Context.CommandTimeoutSeconds `
            -Clock $Context.Clock
    }
    catch {
        $_.Exception.Data['pagebridge.probe.stage'] = 'connect'
        throw
    }

    try {
        $state = New-PageGatewayState -Session $session -Catalog $Context.Catalog -ScriptPaths $Context.ScriptPaths -JobName $Context.JobName -Log $Context.Log
        [void](Invoke-PageBundleInjection -State $state)
        $identity = Invoke-PageOperation -State $state -Operation $Context.Catalog.IdentityOperation

        if ($identity.ok -eq $true) {
            return [pscustomobject]@{ Matched = $true; Reason = '画面識別に一致しました。' }
        }

        $failed = @($identity.checks | Where-Object { $_.ok -ne $true -and $_.severity -eq 'fatal' } | ForEach-Object { "$($_.name)「$($_.message)」" })
        return [pscustomobject]@{ Matched = $false; Reason = "画面識別に一致しません。満たしていない条件: $($failed -join ' / ')" }
    }
    catch {
        $_.Exception.Data['pagebridge.probe.stage'] = 'identify'
        throw
    }
    finally {
        Close-CdpSession -Session $session
    }
}
