# 実行時設定（app/config/settings.psd1）の読み込み。
#
#   Common : 全ジョブ共通（ブラウザ接続、ログ）
#   Jobs   : ジョブごとの設定（Jobs.<ジョブ名>）
#
# キー名が *Path / *Directory の値はパスとして扱い、プロジェクトルート（app の親）基準で絶対パスにする。
# ジョブ固有の値の意味（必須か、整数か等）は各ジョブがジョブ開始時に検証する。

function Resolve-HostSettingPaths {
    param(
        [Parameter(Mandatory)][hashtable]$Table,
        [Parameter(Mandatory)][string]$BaseDirectory
    )

    foreach ($key in @($Table.Keys)) {
        $value = $Table[$key]
        if ($value -is [hashtable]) {
            Resolve-HostSettingPaths -Table $value -BaseDirectory $BaseDirectory
            continue
        }

        if (($key -like '*Path' -or $key -like '*Directory') -and $value -is [string]) {
            $Table[$key] = Resolve-HostPath -Path $value -BaseDirectory $BaseDirectory
        }
    }
}

function Copy-HostSettingValue {
    <#
    .SYNOPSIS
    設定値の深いコピー（ジョブ実行中の上書きが、読み込んだ設定全体へ波及しないようにする）。
    #>
    param([AllowNull()][object]$Value)

    if ($Value -is [hashtable]) {
        $copy = @{}
        foreach ($key in @($Value.Keys)) { $copy[$key] = Copy-HostSettingValue -Value $Value[$key] }
        return $copy
    }

    if ($Value -is [System.Array]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) { [void]$items.Add((Copy-HostSettingValue -Value $item)) }
        return , $items.ToArray()
    }

    return $Value
}

function Import-HostSettings {
    <#
    .SYNOPSIS
    設定ファイルを読み、最上位の形を検証し、パスを解決して返す。
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "設定ファイルが見つかりません: $Path"
    }

    $settings = Import-PowerShellDataFile -LiteralPath $Path
    foreach ($key in @('Common', 'Jobs')) {
        if (-not $settings.ContainsKey($key) -or -not ($settings[$key] -is [hashtable])) {
            throw "設定ファイルに $key（hashtable）がありません: $Path"
        }
    }

    Resolve-HostSettingPaths -Table $settings -BaseDirectory $ProjectRoot
    return $settings
}

function Get-HostJobSettings {
    <#
    .SYNOPSIS
    ジョブ設定（Jobs.<JobName>）の深いコピーを返し、上書き値（連携ジョブから渡されるパス等）を適用する。
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][string]$JobName,
        [hashtable]$Overrides = @{},
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    if (-not $Settings.Jobs.ContainsKey($JobName) -or -not ($Settings.Jobs[$JobName] -is [hashtable])) {
        throw "設定ファイルに Jobs.$JobName（hashtable）がありません。"
    }

    $jobSettings = Copy-HostSettingValue -Value $Settings.Jobs[$JobName]
    if ($Overrides.Count -gt 0) {
        $overrideCopy = Copy-HostSettingValue -Value $Overrides
        Resolve-HostSettingPaths -Table $overrideCopy -BaseDirectory $ProjectRoot
        foreach ($key in @($overrideCopy.Keys)) {
            $jobSettings[$key] = $overrideCopy[$key]
        }
    }

    return $jobSettings
}
