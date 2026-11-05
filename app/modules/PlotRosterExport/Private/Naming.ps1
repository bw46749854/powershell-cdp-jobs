# 保存名の規則（純粋関数）。
# テンプレートの {0} に実行日の月日（MMdd）を入れる。例: plot_roster_{0}.csv → plot_roster_0415.csv

function Get-RosterExportFileName {
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][datetime]$Date
    )

    $fileName = [string]::Format($Template, $Date.ToString('MMdd'))

    if (-not $fileName.EndsWith('.csv', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "保存名は .csv で終わる必要があります: $fileName（テンプレート: $Template）"
    }

    $invalid = [char[]](@([System.IO.Path]::GetInvalidFileNameChars()) + @([char]'\', [char]'/'))
    if ($fileName.IndexOfAny($invalid) -ge 0) {
        throw "保存名にファイル名として使えない文字が含まれています: $fileName"
    }

    return $fileName
}
