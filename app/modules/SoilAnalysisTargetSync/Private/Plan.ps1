# 入力 CSV の記録から「どの区画を ON / OFF に揃えるか」の計画を作る（純粋関数）。
#
# ブラウザを操作する前に、CSV だけで判断できる問題（判定不能・区画コードの空欄や重複）をすべて洗い出す。
# CSV データエラーが1件でもあれば、計画の対象（Targets）は作らない（誤った状態に揃えないため）。

function New-SoilAnalysisTarget {
    param(
        [Parameter(Mandatory)][object]$Classified,
        [Parameter(Mandatory)][bool]$Desired
    )

    return [pscustomobject]@{
        Record = $Classified.Record
        PlotCode = [string]$Classified.Record.PlotCode
        Desired = $Desired
        Reason = $Classified.Decision.Reason
        ElapsedDays = $Classified.Decision.ElapsedDays
    }
}

function New-SoilAnalysisPlan {
    <#
    .OUTPUTS
    Records / OnRecords / OffRecords / CsvErrors / Targets
    Targets は { Record; PlotCode; Desired; Reason; ElapsedDays } の配列（CSV データエラーがあれば空）。
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records,
        [Parameter(Mandatory)][int]$DaysThreshold
    )

    $on = New-Object System.Collections.Generic.List[object]
    $off = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[object]

    foreach ($record in $Records) {
        if ([string]::IsNullOrWhiteSpace($record.PlotCode)) {
            [void]$errors.Add((New-CsvErrorRecord -Record $record -Code 'PLOT_CODE_BLANK' -Reason '区画コードが空欄です'))
            continue
        }

        $decision = Get-AnalysisDecision -AnalysisCompleted $record.AnalysisCompleted -LastMeasured $record.LastMeasured -DaysThreshold $DaysThreshold
        $classified = [pscustomobject]@{ Record = $record; Decision = $decision }
        switch ($decision.Decision) {
            'Error' { [void]$errors.Add((New-CsvErrorRecord -Record $record -Code $decision.ErrorCode -Reason $decision.Reason -ElapsedDays $decision.ElapsedDays)) }
            'On' { [void]$on.Add($classified) }
            'Off' { [void]$off.Add($classified) }
        }
    }

    $duplicateGroups = @($Records | Where-Object { -not [string]::IsNullOrWhiteSpace($_.PlotCode) } | Group-Object -Property PlotCode | Where-Object { $_.Count -gt 1 })
    foreach ($group in $duplicateGroups) {
        foreach ($record in $group.Group) {
            [void]$errors.Add((New-CsvErrorRecord -Record $record -Code 'PLOT_CODE_DUPLICATED' -Reason "区画コードが CSV 内で重複しています（$($group.Name) が $($group.Count) 件）"))
        }
    }

    $targets = New-Object System.Collections.Generic.List[object]
    if ($errors.Count -eq 0) {
        foreach ($item in $on) { [void]$targets.Add((New-SoilAnalysisTarget -Classified $item -Desired $true)) }
        foreach ($item in $off) { [void]$targets.Add((New-SoilAnalysisTarget -Classified $item -Desired $false)) }
    }

    return [pscustomobject]@{
        Records = @($Records)
        OnRecords = @($on | ForEach-Object { $_.Record })
        OffRecords = @($off | ForEach-Object { $_.Record })
        CsvErrors = $errors.ToArray()
        Targets = $targets.ToArray()
    }
}

function Get-SoilAnalysisPlanFindings {
    <#
    .SYNOPSIS
    計画の件数の整合（ON + OFF = CSV 行数、対象 = CSV 行数）を確かめ、崩れていれば失敗記録を返す。
    .DESCRIPTION
    CSV データエラーが無いのに件数が合わないのは、判定ロジック自体の不具合を意味する。
    #>
    param([Parameter(Mandatory)][object]$Plan)

    $findings = New-Object System.Collections.Generic.List[object]
    $recordCount = @($Plan.Records).Count
    $classified = @($Plan.OnRecords).Count + @($Plan.OffRecords).Count

    if ($classified -ne $recordCount) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'CSV_CLASSIFICATION_COUNT_MISMATCH' -Reason "ON / OFF の判定件数が CSV の行数と一致しません。ON=$(@($Plan.OnRecords).Count) OFF=$(@($Plan.OffRecords).Count) CSV=$recordCount"))
    }
    elseif (@($Plan.Targets).Count -ne $recordCount) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'TARGET_COUNT_MISMATCH' -Reason "整合の対象件数が CSV の行数と一致しません。対象=$(@($Plan.Targets).Count) CSV=$recordCount"))
    }

    $duplicates = @($Plan.Targets | Group-Object -Property PlotCode | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($duplicates.Count -gt 0) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'TARGET_DUPLICATED' -Reason "整合の対象に同じ区画コードが複数あります: $($duplicates -join ', ')"))
    }

    return $findings.ToArray()
}

function New-SoilAnalysisTargetIndex {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Targets)

    $index = @{}
    foreach ($target in $Targets) { $index[[string]$target.PlotCode] = $target }
    return $index
}
