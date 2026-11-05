function Invoke-HostedJob {
    <#
    .SYNOPSIS
    ジョブ名から実装を引き当てて実行し、ジョブ結果を返す（入口スクリプトと連携ジョブが使う唯一の公開関数）。

    .DESCRIPTION
    1. 設定（settings.psd1）とジョブ定義（jobs.psd1）を読み、ジョブのファイルが揃っているか確認する
    2. Context（設定とサービス）を組み立てる
    3. ジョブのモジュールを読み込み、ジョブコマンドに Context を渡して実行する
    4. 結果が結果プロトコル（JobKit の New-JobResult）どおりか検証して返す
    失敗はログに残したうえで例外として呼び出し元へ伝える。ブラウザ接続などは必ず閉じる。

    .PARAMETER AppRoot
    app ディレクトリ。設定ファイルの既定位置とジョブ定義の相対パスの基準になる。
    .PARAMETER SettingsOverrides
    Jobs.<JobName> の値を上書きする（連携ジョブが子ジョブへ成果物のパスを渡すときに使う）。
    .PARAMETER ServiceOverrides
    テスト用のサービス差し替え（Clock / ConsoleWriter / Transport）。本番では指定しない。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppRoot,
        [Parameter(Mandatory)][string]$JobName,
        [string]$SettingsPath = '',
        [string]$CatalogPath = '',
        [hashtable]$SettingsOverrides = @{},
        [hashtable]$ServiceOverrides = @{}
    )

    $resolvedAppRoot = Get-HostTrimmedFullPath -Path (Resolve-Path -LiteralPath $AppRoot).Path
    $projectRoot = Split-Path -Parent $resolvedAppRoot

    if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path (Join-Path $resolvedAppRoot 'config') 'settings.psd1' }
    if ([string]::IsNullOrWhiteSpace($CatalogPath)) { $CatalogPath = Join-Path (Join-Path $resolvedAppRoot 'config') 'jobs.psd1' }
    $SettingsPath = [System.IO.Path]::GetFullPath($SettingsPath)
    $CatalogPath = [System.IO.Path]::GetFullPath($CatalogPath)

    $context = $null
    try {
        $settings = Import-HostSettings -Path $SettingsPath -ProjectRoot $projectRoot
        $catalog = Import-JobCatalog -Path $CatalogPath -AppRoot $resolvedAppRoot
        $entry = Get-JobCatalogEntry -Catalog $catalog -JobName $JobName
        Assert-JobCatalogEntryFiles -Entry $entry

        $context = New-HostRunContext `
            -AppRoot $resolvedAppRoot `
            -ProjectRoot $projectRoot `
            -SettingsPath $SettingsPath `
            -CatalogPath $CatalogPath `
            -Settings $settings `
            -Entry $entry `
            -SettingsOverrides $SettingsOverrides `
            -Overrides $ServiceOverrides

        Import-Module -Name $entry.Module -Force -DisableNameChecking
        $command = Get-Command -Name $entry.Command -CommandType Function -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            throw "ジョブ定義の Command が見つかりません: Jobs.$JobName.Command = $($entry.Command)（$($entry.Module)）"
        }

        & $context.Services.Log.Section -Title "$JobName 開始"
        $output = @(& $command -Context $context)
        $result = Assert-JobResult -Output $output -Job $JobName
        & $context.Services.Log.Section -Title "$JobName 正常終了"
        return $result
    }
    catch {
        $message = "$JobName は異常終了しました: $($_.Exception.Message)"
        if ($null -ne $context) {
            try { & $context.Services.Log.Error -Message $message } catch { Write-Host $message }
        }
        else {
            Write-Host $message
        }
        throw
    }
    finally {
        Close-HostRunContext -Context $context
    }
}
