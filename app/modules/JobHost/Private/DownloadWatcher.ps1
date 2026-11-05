# Downloads サービス: ブラウザのダウンロード完了を、ダウンロード先ディレクトリの観察で判定する。
#
#   WaitForFile -Directory -Filter -NamePattern -TimeoutSeconds -StableSeconds -RejectEmpty
#
# 完了とみなす条件（すべて満たすこと）:
#   1. 書き込み途中のファイル（*.crdownload / *.tmp / *.download）が無い
#   2. 条件に合う候補ファイルがちょうど1つ（2つ以上は取り違え防止のため即エラー）
#   3. StableSeconds 待ってもサイズが変わらず、排他で開ける
# ダウンロード先は「そのダウンロード専用の空ディレクトリ」であることを前提にする（呼び出し側で空にしておく）。

$script:HostDownloadsShape = @{
    WaitForFile = @('Directory', 'Filter', 'NamePattern', 'TimeoutSeconds', 'StableSeconds', 'RejectEmpty')
}

$script:PartialDownloadPatterns = @('*.crdownload', '*.tmp', '*.download')

function Get-PartialDownloadFiles {
    param([Parameter(Mandatory)][string]$Directory)

    return @(
        Get-ChildItem -LiteralPath $Directory -File |
            Where-Object {
                $name = $_.Name
                @($script:PartialDownloadPatterns | Where-Object { $name -like $_ }).Count -gt 0
            }
    )
}

function Get-DownloadCandidates {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Filter,
        [AllowEmptyString()][string]$NamePattern = ''
    )

    return @(
        Get-ChildItem -LiteralPath $Directory -File -Filter $Filter |
            Where-Object { [string]::IsNullOrEmpty($NamePattern) -or $_.Name -match $NamePattern } |
            Sort-Object Name
    )
}

function Test-FileOpenableExclusively {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        $stream.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

function Select-SingleDownloadCandidate {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Candidates,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][bool]$RejectEmpty
    )

    if ($Candidates.Count -gt 1) {
        throw "ダウンロード先に候補ファイルが複数あります。取り違えを防ぐため停止します。Directory=$Directory Files=$(@($Candidates | ForEach-Object { $_.Name }) -join ', ')"
    }

    if ($Candidates.Count -eq 0) { return $null }

    $candidate = $Candidates[0]
    if ($RejectEmpty -and $candidate.Length -eq 0) {
        throw "ダウンロードしたファイルが 0 バイトです: $($candidate.FullName)"
    }

    return $candidate
}

function Wait-HostCompletedDownload {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Filter,
        [AllowEmptyString()][string]$NamePattern = '',
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][int]$StableSeconds,
        [bool]$RejectEmpty = $false,
        [Parameter(Mandatory)][object]$Clock
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "ダウンロード先ディレクトリが見つかりません: $Directory"
    }

    $now = Get-PortMember -Port $Clock -PortName 'Clock' -Member 'Now'
    $sleep = Get-PortMember -Port $Clock -PortName 'Clock' -Member 'Sleep'
    $deadline = ([datetime](& $now)).AddSeconds($TimeoutSeconds)

    while ([datetime](& $now) -lt $deadline) {
        if (@(Get-PartialDownloadFiles -Directory $Directory).Count -eq 0) {
            $candidate = Select-SingleDownloadCandidate -Candidates @(Get-DownloadCandidates -Directory $Directory -Filter $Filter -NamePattern $NamePattern) -Directory $Directory -RejectEmpty $RejectEmpty
            if ($null -ne $candidate) {
                $sizeBefore = $candidate.Length
                & $sleep -Milliseconds ($StableSeconds * 1000)

                if (@(Get-PartialDownloadFiles -Directory $Directory).Count -eq 0) {
                    $settled = Select-SingleDownloadCandidate -Candidates @(Get-DownloadCandidates -Directory $Directory -Filter $Filter -NamePattern $NamePattern) -Directory $Directory -RejectEmpty $RejectEmpty
                    if ($null -ne $settled -and $settled.FullName -eq $candidate.FullName -and $settled.Length -eq $sizeBefore -and (Test-FileOpenableExclusively -Path $settled.FullName)) {
                        return [pscustomobject]@{
                            Name = $settled.Name
                            FullName = $settled.FullName
                            Length = $settled.Length
                        }
                    }
                }
            }
        }

        & $sleep -Milliseconds 500
    }

    throw "ダウンロードの完了を確認できませんでした（$TimeoutSeconds 秒）。Directory=$Directory Filter=$Filter Pattern=$NamePattern"
}

function New-HostDownloadService {
    param([Parameter(Mandatory)][object]$Clock)

    $wait = Get-Command -Name Wait-HostCompletedDownload -CommandType Function

    return [pscustomobject]@{
        WaitForFile = {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)][string]$Directory,
                [Parameter(Mandatory)][string]$Filter,
                [AllowEmptyString()][string]$NamePattern = '',
                [Parameter(Mandatory)][int]$TimeoutSeconds,
                [Parameter(Mandatory)][int]$StableSeconds,
                [bool]$RejectEmpty = $false
            )
            & $wait -Directory $Directory -Filter $Filter -NamePattern $NamePattern -TimeoutSeconds $TimeoutSeconds -StableSeconds $StableSeconds -RejectEmpty $RejectEmpty -Clock $Clock
        }.GetNewClosure()
    }
}
