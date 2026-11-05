# ジョブ定義（app/config/jobs.psd1）の読み込みと検証。
#
# ジョブ定義は「ジョブ名 → どのモジュールのどのコマンドを、どのページスクリプトで動かすか」の対応表。
#   Module      : app からの相対パス（*.psm1）
#   Command     : ジョブコマンド名（Invoke-<Name>Job）
#   UsesBrowser : ブラウザを使うか（明示必須）
#   Browser     : UsesBrowser = $true のときだけ必須
#       Operations : 操作カタログ（*.psd1）
#       Scripts    : ページへ注入するスクリプト（読み込み順）
# 実行時の値（ディレクトリ、タイムアウト等）は settings.psd1 に置き、ここには書かない。

$script:CatalogEntryKeys = @('Module', 'Command', 'UsesBrowser', 'Browser')
$script:CatalogBrowserKeys = @('Operations', 'Scripts')

function Assert-JobCatalogEntry {
    param(
        [Parameter(Mandatory)][string]$JobName,
        [AllowNull()][object]$Entry,
        [Parameter(Mandatory)][string]$CatalogPath
    )

    $location = "Jobs.$JobName（$CatalogPath）"
    if ($JobName -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
        throw "ジョブ名は英数字で指定してください: $location"
    }

    if (-not ($Entry -is [hashtable])) {
        throw "ジョブ定義は hashtable で指定してください: $location"
    }

    foreach ($key in @($Entry.Keys)) {
        if ($script:CatalogEntryKeys -notcontains $key) {
            throw "ジョブ定義に未知のキー '$key' があります: $location"
        }
    }

    foreach ($key in @('Module', 'Command')) {
        if (-not ($Entry[$key] -is [string]) -or [string]::IsNullOrWhiteSpace($Entry[$key])) {
            throw "ジョブ定義の $key は空でない文字列で指定してください: $location"
        }
    }

    if ($Entry['Command'] -notmatch '^[A-Za-z][A-Za-z0-9]*-[A-Za-z][A-Za-z0-9]*$') {
        throw "ジョブ定義の Command は「動詞-名詞」形式のコマンド名で指定してください: $location"
    }

    if (-not ($Entry['UsesBrowser'] -is [bool])) {
        throw "ジョブ定義の UsesBrowser は `$true / `$false で明示してください: $location"
    }

    if (-not $Entry['UsesBrowser']) {
        if ($Entry.ContainsKey('Browser')) {
            throw "ブラウザを使わないジョブ（UsesBrowser = `$false）に Browser は指定できません: $location"
        }
        return
    }

    $browser = $Entry['Browser']
    if (-not ($browser -is [hashtable])) {
        throw "ブラウザを使うジョブには Browser（Operations と Scripts）が必要です: $location"
    }

    foreach ($key in @($browser.Keys)) {
        if ($script:CatalogBrowserKeys -notcontains $key) {
            throw "ジョブ定義の Browser に未知のキー '$key' があります: $location"
        }
    }

    if (-not ($browser['Operations'] -is [string]) -or [string]::IsNullOrWhiteSpace($browser['Operations'])) {
        throw "ジョブ定義の Browser.Operations は操作カタログのパスで指定してください: $location"
    }

    $scripts = $browser['Scripts']
    if ($scripts -is [string] -or -not ($scripts -is [System.Array]) -or @($scripts).Count -eq 0) {
        throw "ジョブ定義の Browser.Scripts はスクリプトのパスの配列 @(...) で指定してください: $location"
    }

    foreach ($scriptPath in @($scripts)) {
        if (-not ($scriptPath -is [string]) -or [string]::IsNullOrWhiteSpace($scriptPath)) {
            throw "ジョブ定義の Browser.Scripts に空の要素があります: $location"
        }
    }
}

function Import-JobCatalog {
    <#
    .SYNOPSIS
    ジョブ定義を読み、全ジョブを検証し、パスを app 基準の絶対パスにして返す。
    .OUTPUTS
    ジョブ名 → エントリ（Name, Module, Command, UsesBrowser, Operations, Scripts）の hashtable
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AppRoot
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "ジョブ定義ファイルが見つかりません: $Path"
    }

    $data = Import-PowerShellDataFile -LiteralPath $Path
    if (-not $data.ContainsKey('Jobs') -or -not ($data.Jobs -is [hashtable]) -or $data.Jobs.Count -eq 0) {
        throw "ジョブ定義ファイルに Jobs（1件以上の hashtable）がありません: $Path"
    }

    $catalog = @{}
    foreach ($jobName in @($data.Jobs.Keys | Sort-Object)) {
        $entry = $data.Jobs[$jobName]
        Assert-JobCatalogEntry -JobName $jobName -Entry $entry -CatalogPath $Path

        $operations = ''
        $scripts = @()
        if ($entry['UsesBrowser']) {
            $operations = Resolve-HostPath -Path $entry['Browser']['Operations'] -BaseDirectory $AppRoot
            $scripts = @($entry['Browser']['Scripts'] | ForEach-Object { Resolve-HostPath -Path $_ -BaseDirectory $AppRoot })
        }

        $catalog[$jobName] = [pscustomobject]@{
            Name = $jobName
            Module = Resolve-HostPath -Path $entry['Module'] -BaseDirectory $AppRoot
            Command = $entry['Command']
            UsesBrowser = [bool]$entry['UsesBrowser']
            Operations = $operations
            Scripts = $scripts
        }
    }

    return $catalog
}

function Get-JobCatalogEntry {
    param(
        [Parameter(Mandatory)][hashtable]$Catalog,
        [Parameter(Mandatory)][string]$JobName
    )

    if (-not $Catalog.ContainsKey($JobName)) {
        $known = @($Catalog.Keys | Sort-Object) -join ', '
        throw "ジョブ定義にないジョブ名です: $JobName（定義済み: $known）"
    }

    return $Catalog[$JobName]
}

function Assert-JobCatalogEntryFiles {
    <#
    .SYNOPSIS
    ジョブのモジュール・操作カタログ・スクリプトが実在するか検証する（ジョブ開始前に設定不備を検出する）。
    #>
    param([Parameter(Mandatory)][object]$Entry)

    $paths = @($Entry.Module)
    if ($Entry.UsesBrowser) { $paths += @($Entry.Operations) + @($Entry.Scripts) }

    $missing = @($paths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count -gt 0) {
        throw "ジョブ $($Entry.Name) のファイルが見つかりません: $($missing -join ', ')"
    }
}
