BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/JobHost/JobHost.psm1') -Force

    function New-ScriptedClock {
        <#
        Sleep のたびに、指定した順番でファイル操作（ブラウザのダウンロード進行）を再現する時計。
        #>
        param([scriptblock[]]$OnSleep = @())

        $state = [pscustomobject]@{ Now = [datetime]'2026-04-15T09:30:00'; Count = 0; Sleeps = (New-CallRecorder) }
        return [pscustomobject]@{
            State = $state
            Now = { [CmdletBinding()] param() $state.Now }.GetNewClosure()
            Sleep = {
                [CmdletBinding()] param([Parameter(Mandatory)][int]$Milliseconds)
                [void]$state.Sleeps.Add($Milliseconds)
                if ($state.Count -lt $OnSleep.Count) { & $OnSleep[$state.Count] }
                $state.Count++
                $state.Now = $state.Now.AddMilliseconds($Milliseconds)
            }.GetNewClosure()
        }
    }
}

Describe 'Downloads service' {
    BeforeEach {
        $directory = Join-Path $TestDrive ('d' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $directory | Out-Null
    }

    It 'waits until the partial file disappears and the size stays the same' {
        $partial = Join-Path $directory 'planting_20260415.csv.crdownload'
        $final = Join-Path $directory 'planting_20260415.csv'
        Set-Content -LiteralPath $partial -Value 'x'
        $clock = New-ScriptedClock -OnSleep @(
            { },
            { Remove-Item -LiteralPath $partial; Set-Content -LiteralPath $final -Value '作物名,品種,定植日' }.GetNewClosure()
        )
        $downloads = InModuleScope JobHost -Parameters @{ Clock = $clock } { param($Clock) New-HostDownloadService -Clock $Clock }

        $file = & $downloads.WaitForFile -Directory $directory -Filter 'planting_*.csv' -TimeoutSeconds 30 -StableSeconds 2

        $file.Name | Should -Be 'planting_20260415.csv'
        @($clock.State.Sleeps) | Should -Be @(500, 500, 2000)
    }

    It 'ignores files that do not match the name pattern' {
        Set-Content -LiteralPath (Join-Path $directory 'notes.csv') -Value 'x'
        Set-Content -LiteralPath (Join-Path $directory 'plots_export.csv') -Value 'x'
        $downloads = InModuleScope JobHost -Parameters @{ Clock = (New-ScriptedClock) } { param($Clock) New-HostDownloadService -Clock $Clock }

        (& $downloads.WaitForFile -Directory $directory -Filter '*.csv' -NamePattern '^plots_.+\.csv$' -TimeoutSeconds 10 -StableSeconds 1).Name |
            Should -Be 'plots_export.csv'
    }

    It 'stops immediately when more than one candidate exists' {
        Set-Content -LiteralPath (Join-Path $directory 'planting_1.csv') -Value 'a'
        Set-Content -LiteralPath (Join-Path $directory 'planting_2.csv') -Value 'b'
        $downloads = InModuleScope JobHost -Parameters @{ Clock = (New-ScriptedClock) } { param($Clock) New-HostDownloadService -Clock $Clock }

        { & $downloads.WaitForFile -Directory $directory -Filter 'planting_*.csv' -TimeoutSeconds 10 -StableSeconds 1 } |
            Should -Throw '*候補ファイルが複数*planting_1.csv, planting_2.csv*'
    }

    It 'rejects an empty download only when asked to' {
        Set-Content -LiteralPath (Join-Path $directory 'plots.csv') -Value '' -NoNewline
        $downloads = InModuleScope JobHost -Parameters @{ Clock = (New-ScriptedClock) } { param($Clock) New-HostDownloadService -Clock $Clock }

        { & $downloads.WaitForFile -Directory $directory -Filter '*.csv' -TimeoutSeconds 10 -StableSeconds 1 -RejectEmpty $true } | Should -Throw '*0 バイト*'
        (& $downloads.WaitForFile -Directory $directory -Filter '*.csv' -TimeoutSeconds 10 -StableSeconds 1).Length | Should -Be 0
    }

    It 'keeps waiting while the file is still growing, then times out' {
        $path = Join-Path $directory 'growing.csv'
        Set-Content -LiteralPath $path -Value 'a' -NoNewline
        $grow = { Add-Content -LiteralPath $path -Value 'b' -NoNewline }.GetNewClosure()
        $clock = New-ScriptedClock -OnSleep @($grow, $grow, $grow, $grow, $grow, $grow, $grow, $grow, $grow, $grow, $grow, $grow)
        $downloads = InModuleScope JobHost -Parameters @{ Clock = $clock } { param($Clock) New-HostDownloadService -Clock $Clock }

        { & $downloads.WaitForFile -Directory $directory -Filter '*.csv' -TimeoutSeconds 5 -StableSeconds 1 } | Should -Throw '*完了を確認できませんでした（5 秒）*'
    }
}

Describe 'Lists service (scrolling traversal)' {
    BeforeEach {
        $clock = New-ManualClock
        $log = New-RecordingLog
        $lists = InModuleScope JobHost -Parameters @{ Clock = $clock; Log = $log } { param($Clock, $Log) New-HostListService -Clock $Clock -Log $Log }
        $script:visited = New-CallRecorder
        $visitedRef = $script:visited
        $script:Visit = { param($Row) [void]$visitedRef.Add($Row.key) }.GetNewClosure()
        $script:KeyOf = { param($Row) $Row.key }
    }

    It 'visits each row once across scroll positions and stops at the expected count' {
        $pages = New-Object System.Collections.Queue
        $pages.Enqueue(@(@{ key = 'a' }, @{ key = 'b' }))
        $pages.Enqueue(@(@{ key = 'a' }, @{ key = 'b' }))
        $pages.Enqueue(@(@{ key = 'b' }, @{ key = 'c' }))
        $read = { $pages.Dequeue() }.GetNewClosure()
        $scroll = { @{ moved = $true } }

        $result = & $lists.Traverse -ExpectedCount 3 -ReadVisible $read -KeyOf $script:KeyOf -Visit $script:Visit -ScrollNext $scroll -MaxLoops 10 -StallLimit 2 -EmptyMessage 'empty'

        @($script:visited) | Should -Be @('a', 'b', 'c')
        $result.StopReason | Should -Be 'expected-count'
        $result.VisitedCount | Should -Be 3
        @($clock.State.Sleeps) | Should -Be @(700)
    }

    It 'stops at the end of the list after the scroll position stops changing' {
        $read = { @(@{ key = 'a' }) }
        $scroll = { @{ moved = $false } }

        $result = & $lists.Traverse -ExpectedCount 5 -ReadVisible $read -KeyOf $script:KeyOf -Visit $script:Visit -ScrollNext $scroll -MaxLoops 50 -StallLimit 2 -EmptyMessage 'empty'

        $result.StopReason | Should -Be 'end-of-list'
        $result.VisitedCount | Should -Be 1
        (Get-LogMessages -Log $log) | Should -Contain 'スクロール位置が変わりませんでした（2 / 2 回）。'
    }

    It 'reports a loop limit when it never reaches the end' {
        $read = { @(@{ key = 'a' }) }
        $scroll = { @{ changed = $true } }

        (& $lists.Traverse -ExpectedCount 5 -ReadVisible $read -KeyOf $script:KeyOf -Visit $script:Visit -ScrollNext $scroll -MaxLoops 4 -StallLimit 2 -EmptyMessage 'empty').StopReason |
            Should -Be 'loop-limit'
    }

    It 'treats an empty visible list as an error rather than the end' {
        { & $lists.Traverse -ExpectedCount 1 -ReadVisible { @() } -KeyOf $script:KeyOf -Visit $script:Visit -ScrollNext { } -MaxLoops 3 -StallLimit 2 -EmptyMessage '区画行を取得できませんでした。' } |
            Should -Throw '区画行を取得できませんでした。'
    }

    It 'marks a row as visited even when visiting it fails, and lets the failure propagate' {
        $read = { @(@{ key = 'a' }) }
        $failingVisit = { param($Row) throw 'row failed' }

        { & $lists.Traverse -ExpectedCount 1 -ReadVisible $read -KeyOf $script:KeyOf -Visit $failingVisit -ScrollNext { } -MaxLoops 3 -StallLimit 2 -EmptyMessage 'empty' } |
            Should -Throw 'row failed'
    }

    It 'skips rows without a key' {
        $read = { @(@{ key = '' }, @{ key = 'a' }) }
        $result = & $lists.Traverse -ExpectedCount 1 -ReadVisible $read -KeyOf $script:KeyOf -Visit $script:Visit -ScrollNext { } -MaxLoops 3 -StallLimit 2 -EmptyMessage 'empty'
        @($script:visited) | Should -Be @('a')
        $result.StopReason | Should -Be 'expected-count'
    }
}

Describe 'Log service' {
    It 'writes formatted lines, filters by level, and appends to a BOM file when enabled' {
        $lines = New-CallRecorder
        $writer = { param($Level, $Line) [void]$lines.Add("$Level|$Line") }.GetNewClosure()
        $logDirectory = Join-Path $TestDrive 'logs'

        $log = InModuleScope JobHost -Parameters @{ Writer = $writer; Directory = $logDirectory } {
            param($Writer, $Directory)
            New-HostLog -Logging @{ Level = 'Warning'; Console = $true; File = $true; Directory = $Directory } -JobName 'Sample' -RunId 'R1' -Clock (New-HostClock) -ConsoleWriter $Writer
        }

        & $log.Info -Message 'hidden'
        & $log.Warn -Message '注意'
        & $log.Error -Message '失敗'

        @($lines).Count | Should -Be 2
        $lines[0] | Should -Match '^Warning\|\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[WARNING\] \[R1\] 注意$'
        $log.FilePath | Should -Be (Join-Path $logDirectory 'Sample_R1.log')
        $bytes = [System.IO.File]::ReadAllBytes($log.FilePath)
        @($bytes[0], $bytes[1], $bytes[2]) | Should -Be @(0xEF, 0xBB, 0xBF)
        @(Get-Content -LiteralPath $log.FilePath -Encoding UTF8).Count | Should -Be 2
    }

    It 'renders sections and data as readable lines' {
        $lines = New-CallRecorder
        $writer = { param($Level, $Line) [void]$lines.Add($Line) }.GetNewClosure()
        $log = InModuleScope JobHost -Parameters @{ Writer = $writer } {
            param($Writer)
            New-HostLog -Logging @{} -JobName 'Sample' -RunId 'R1' -Clock (New-HostClock) -ConsoleWriter $Writer
        }

        & $log.Section -Title '処理結果'
        & $log.Data -Label '操作結果' -Data @{ ok = $true }

        @($lines).Count | Should -Be 5
        $lines[2] | Should -Match '処理結果$'
        $lines[4] | Should -Match '操作結果 \{"ok":true\}$'
    }

    It 'rejects invalid logging settings' -TestCases @(
        @{ Logging = @{ Level = 'Verbose' }; Expected = '*Level*' }
        @{ Logging = @{ File = 'yes' }; Expected = '*Console / File*' }
        @{ Logging = @{ File = $true }; Expected = '*Directory が必要*' }
    ) {
        param($Logging, $Expected)
        InModuleScope JobHost -Parameters @{ Logging = $Logging; Expected = $Expected } {
            param($Logging, $Expected)
            { New-HostLog -Logging $Logging -JobName 'S' -RunId 'R' -Clock (New-HostClock) } | Should -Throw $Expected
        }
    }
}
