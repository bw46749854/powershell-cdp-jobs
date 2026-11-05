# 処理の順序（全体）。判定・突き合わせは純粋関数、画面とファイルはポートに任せ、ここは順序と停止条件だけを書く。
#
#   1. 入力 CSV を読み、計画を作る              ← CSV データエラーがあればブラウザに触れずに停止
#   2. 画面に接続し、画面と一覧の契約を確認する  ← 件数が CSV と一致しなければチェック操作を始めない
#   3. 一覧を上から走査し、対象を ON / OFF に揃える（Flow.Scan.ps1）
#   4. 走査結果と CSV を突き合わせる              ← 食い違いは失敗記録にする
#   5. 「土壌分析を依頼」が有効になったことを確認する（クリックはしない）
#   6. CSV データエラー一覧・失敗一覧を出力し、1件でもあれば異常終了する
# どこで例外になっても、まだ出力していなければ「致命的エラー」の失敗記録を付けて出力してから例外を伝える。

function Read-SoilAnalysisPlan {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings
    )

    if (-not (& $Ports.Files.Exists -Path $Settings.InputCsvPath)) {
        throw "入力 CSV が見つかりません: $($Settings.InputCsvPath)"
    }

    $text = & $Ports.Files.ReadText -Path $Settings.InputCsvPath
    $records = @(ConvertFrom-RosterCsvText -Text $text)
    return New-SoilAnalysisPlan -Records $records -DaysThreshold $Settings.DaysThreshold
}

function Open-SoilAnalysisScreen {
    <#
    .SYNOPSIS
    画面に接続して契約を確認し、件数が CSV と整合すれば一覧の件数を返す。
    #>
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][object]$Ledger
    )

    $page = $Ports.Page
    $log = $Ports.Log

    [void](& $page.Connect)
    [void](& $page.Load)
    [void](& $page.AssertScreen)
    $list = & $page.AssertList
    $scope = & $page.PrepareScope
    if ((Get-PropertyValue -InputObject $scope -Name 'ok') -ne $true) {
        throw "チェック操作に使う一覧の範囲を決められません。理由=$(Get-PropertyValue -InputObject $scope -Name 'reason')"
    }

    $total = [int](Get-PropertyValue -InputObject $list.details -Name 'plotCount' -Default 0)
    $csvCount = @($Plan.Records).Count
    $targetCount = @($Plan.Targets).Count
    $problem = $null
    if ($total -lt 1) {
        $problem = New-SyncFailureRecord -Code 'UI_TOTAL_COUNT_INVALID' -Reason "一覧の件数が 1 件未満です。件数表示=$total"
    }
    elseif ($csvCount -ne $total) {
        $problem = New-SyncFailureRecord -Code 'CSV_UI_COUNT_MISMATCH' -Reason "CSV の行数と一覧の件数が一致しません。CSV=$csvCount 一覧=$total"
    }
    elseif ($targetCount -ne $total) {
        $problem = New-SyncFailureRecord -Code 'TARGET_UI_COUNT_MISMATCH' -Reason "整合の対象件数と一覧の件数が一致しません。対象=$targetCount 一覧=$total"
    }

    if ($null -ne $problem) {
        Add-SoilAnalysisFailure -Ledger $Ledger -Failures @($problem)
        throw "$($problem.Reason)。誤操作を防ぐため、チェック操作を始めません。"
    }

    & $log.Info -Message '一覧画面の確認: OK'
    & $log.Info -Message "CSV と一覧の件数: OK（CSV $csvCount 件 / 一覧 $total 件）"
    & $log.Info -Message '照合方法: 絞り込み欄は使わず、一覧を上から全件走査します。'
    [void](& $page.ScrollToTop)
    return $total
}

function Confirm-SoilAnalysisMenu {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][object]$Ledger
    )

    $log = $Ports.Log
    if (@($Plan.Targets | Where-Object { $_.Desired }).Count -eq 0) {
        & $log.Info -Message 'ON に揃える区画が無いため、「土壌分析を依頼」の有効化は確認しません。'
        return
    }

    try {
        [void](& $Ports.Page.AssertAnalysisMenuEnabled)
        & $log.Info -Message '「土壌分析を依頼」が有効になったことを確認しました（クリックはしていません）。'
    }
    catch {
        Add-SoilAnalysisFailure -Ledger $Ledger -Failures @(New-SyncFailureRecord -Code 'REQUEST_MENU_NOT_ENABLED' -Reason "「土壌分析を依頼」の有効化を確認できませんでした。詳細=$($_.Exception.Message)")
    }
}

function Write-SoilAnalysisStartLog {
    param([Parameter(Mandatory)][object]$Ports, [Parameter(Mandatory)][object]$Settings)

    $log = $Ports.Log
    & $log.Info -Message '実行内容: 区画一覧 CSV の判定に従い、土壌分析の対象チェックを ON / OFF に揃えます。'
    & $log.Info -Message '重要: 「土壌分析を依頼」はクリックしません（依頼は担当者が画面で行います）。'
    & $log.Info -Message "入力 CSV: $($Settings.InputCsvPath)"
    & $log.Info -Message "出力先  : $($Settings.OutputDirectory)"
    & $log.Info -Message '判定ルール:'
    foreach ($line in @(Get-AnalysisRuleDescription -DaysThreshold $Settings.DaysThreshold)) {
        & $log.Info -Message "  - $line"
    }
}

function Write-SoilAnalysisPlanSummary {
    param([Parameter(Mandatory)][object]$Ports, [Parameter(Mandatory)][object]$Plan)

    $log = $Ports.Log
    & $log.Info -Message "CSV の行数        : $(@($Plan.Records).Count) 件"
    & $log.Info -Message "CSV データエラー  : $(@($Plan.CsvErrors).Count) 件"
    & $log.Info -Message "ON に揃える区画   : $(@($Plan.OnRecords).Count) 件"
    & $log.Info -Message "OFF に揃える区画  : $(@($Plan.OffRecords).Count) 件"
}

function Write-SoilAnalysisSummary {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][object]$Scan,
        [Parameter(Mandatory)][object]$Breakdown,
        [Parameter(Mandatory)][int]$Total,
        [Parameter(Mandatory)][object]$Ledger
    )

    $log = $Ports.Log
    & $log.Section -Title 'SoilAnalysisTargetSync 処理結果'
    & $log.Info -Message "CSV の行数   : $(@($Plan.Records).Count) 件 / 一覧の件数: $Total 件"
    & $log.Info -Message "一覧で確認   : $($Scan.Seen.Count) / $Total 件（終了理由: $($Scan.StopReason)）"
    & $log.Info -Message "整合の成功   : $($Scan.Successes.Count) / $(@($Plan.Targets).Count) 件（ON $(@($Breakdown.On).Count) / OFF $(@($Breakdown.Off).Count)）"
    & $log.Info -Message "  変更した   : $(@($Breakdown.Changed).Count) 件"
    & $log.Info -Message "  変更不要   : $(@($Breakdown.AlreadyAligned).Count) 件"
    & $log.Info -Message "失敗         : $($Ledger.Failures.Count) 件"
    & $log.Info -Message '「土壌分析を依頼」のクリック: 実行していません'
}

function Invoke-SoilAnalysisSyncFlow {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings
    )

    $log = $Ports.Log
    $ledger = New-SoilAnalysisLedger -Clock $Ports.Clock
    $reports = $null

    try {
        [void](& $Ports.Files.EnsureDirectory -Path $Settings.OutputDirectory -Purpose 'SoilAnalysisTargetSync の出力')
        Write-SoilAnalysisStartLog -Ports $Ports -Settings $Settings

        $plan = Read-SoilAnalysisPlan -Ports $Ports -Settings $Settings
        Add-SoilAnalysisCsvError -Ledger $ledger -CsvErrors @($plan.CsvErrors)
        if ($ledger.CsvErrors.Count -gt 0) {
            & $log.Warn -Message "CSV データエラーが $($ledger.CsvErrors.Count) 件あります。ブラウザ操作の前に停止します。"
            [void](Export-SoilAnalysisReports -Ledger $ledger -Ports $Ports -Settings $Settings)
            throw "CSV データエラーが $($ledger.CsvErrors.Count) 件あります。判定できない、または区画コードが一意でない行があるため、チェック操作を始めません。CSV データエラー一覧を確認してください。"
        }

        $planFindings = @(Get-SoilAnalysisPlanFindings -Plan $plan)
        if ($planFindings.Count -gt 0) {
            Add-SoilAnalysisFailure -Ledger $ledger -Failures $planFindings
            [void](Export-SoilAnalysisReports -Ledger $ledger -Ports $Ports -Settings $Settings)
            throw "判定結果の件数が CSV と整合しません。誤操作を防ぐため、チェック操作を始めません。"
        }

        Write-SoilAnalysisPlanSummary -Ports $Ports -Plan $plan
        if (@($plan.Targets).Count -eq 0) {
            $reports = Export-SoilAnalysisReports -Ledger $ledger -Ports $Ports -Settings $Settings
            & $log.Info -Message '整合の対象が 0 件のため、ブラウザは操作しません。'
            return [pscustomobject]@{ Plan = $plan; Scan = $null; Reports = $reports }
        }

        $total = Open-SoilAnalysisScreen -Ports $Ports -Plan $plan -Ledger $ledger
        $targetIndex = New-SoilAnalysisTargetIndex -Targets @($plan.Targets)
        $scan = Invoke-SoilAnalysisScan -Ports $Ports -Settings $Settings -TargetIndex $targetIndex -ExpectedTotal $total -Ledger $ledger

        Add-SoilAnalysisFailure -Ledger $ledger -Failures @(Get-SoilAnalysisScanFindings -State $scan -TargetIndex $targetIndex -ExpectedTotal $total -MaxLoops $Settings.MaxScanLoops)
        $breakdown = Get-SoilAnalysisSuccessBreakdown -Successes $scan.Successes.ToArray()
        Add-SoilAnalysisFailure -Ledger $ledger -Failures @(Get-SoilAnalysisSuccessFindings -Breakdown $breakdown -Plan $plan)
        Confirm-SoilAnalysisMenu -Ports $Ports -Plan $plan -Ledger $ledger

        Write-SoilAnalysisSummary -Ports $Ports -Plan $plan -Scan $scan -Breakdown $breakdown -Total $total -Ledger $ledger
        $reports = Export-SoilAnalysisReports -Ledger $ledger -Ports $Ports -Settings $Settings

        if (-not (Test-SoilAnalysisLedgerClean -Ledger $ledger)) {
            throw "処理は最後まで行いましたが、失敗が $($ledger.Failures.Count) 件あります。チェック整合失敗一覧を確認してください。"
        }

        & $log.Info -Message '正常終了: CSV の判定どおりに土壌分析の対象チェックを揃えました。'
        return [pscustomobject]@{ Plan = $plan; Scan = $scan; Reports = $reports }
    }
    catch {
        $failure = $_
        if (-not $ledger.Exported) {
            try {
                Add-SoilAnalysisFailure -Ledger $ledger -Failures @(New-SyncFailureRecord -Code 'FATAL_ERROR' -Reason "実行中に致命的なエラーが発生しました: $($failure.Exception.Message)")
                [void](Export-SoilAnalysisReports -Ledger $ledger -Ports $Ports -Settings $Settings)
            }
            catch {
                & $log.Warn -Message "異常終了時の失敗一覧の出力に失敗しました: $($_.Exception.Message)"
            }
        }
        throw $failure
    }
}
