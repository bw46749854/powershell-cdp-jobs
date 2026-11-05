BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/PageBridge/PageBridge.psm1') -Force

    $catalogPath = Join-Path $TestDrive 'catalog.psd1'
    Set-Content -LiteralPath $catalogPath -Encoding UTF8 -Value @'
@{
    Helper = 'sampleHelper'
    Operations = @{
        DetectScreen = @{ Method = 'detectScreen'; Kind = 'Identity'; Scope = 'sample.identity'; TimeoutSeconds = 2 }
        CheckScreen  = @{ Method = 'checkScreen'; Kind = 'Contract'; Scope = 'sample.screen'; Label = '一覧画面の契約' }
        ClickExport  = @{ Method = 'clickExport'; Kind = 'Action' }
        ReadRows     = @{ Method = 'readRows'; Kind = 'Query' }
        IsReady      = @{ Method = 'isReady'; Kind = 'Probe' }
    }
}
'@
    $script:Catalog = Import-PageOperationCatalog -Path $catalogPath

    $script:ScriptPath = Join-Path $TestDrive 'bundle.js'
    Set-Content -LiteralPath $script:ScriptPath -Value '/* simulated */' -Encoding UTF8

    $script:CatalogMethods = @('detectScreen', 'checkScreen', 'clickExport', 'readRows', 'isReady')

    function New-TestPage {
        param([string]$WebSocketUrl, [string]$Title = 'page', [string]$Url = 'http://localhost/page', [hashtable]$Methods)
        return New-SimulatedPage -WebSocketUrl $WebSocketUrl -Title $Title -Url $Url -Methods $Methods -Helper 'sampleHelper' -HelperMethods $script:CatalogMethods
    }

    function New-IdentityMethods {
        param([bool]$Matches)
        $result = if ($Matches) {
            New-ContractResult -Scope 'sample.identity'
        }
        else {
            New-ContractResult -Scope 'sample.identity' -Failures @(@{ name = 'identity.title'; message = '画面名が違う' })
        }
        return @{ detectScreen = { param($Arguments) $result }.GetNewClosure() }
    }

    function Open-TestConnection {
        param([Parameter(Mandatory)][object]$Transport, [object]$Log = (New-RecordingLog), [object]$Clock = (New-ManualClock))
        return Open-PageConnection `
            -DebuggerUrl 'http://localhost:9222/json' `
            -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 `
            -Catalog $script:Catalog -ScriptPaths @($script:ScriptPath) -JobName 'SampleJob' `
            -Log $Log -Transport $Transport -Clock $Clock
    }
}

Describe 'Open-PageConnection target selection' {
    It 'connects to the only tab whose screen identity matches' {
        $other = New-TestPage -WebSocketUrl 'ws://fake/other' -Title 'other app' -Methods (New-IdentityMethods -Matches $false)
        $target = New-TestPage -WebSocketUrl 'ws://fake/target' -Title '区画一覧' -Url 'http://localhost/plots' -Methods (New-IdentityMethods -Matches $true)
        $transport = New-FakeCdpTransport -Pages @($other, $target)
        $log = New-RecordingLog

        $connection = Open-TestConnection -Transport $transport -Log $log

        $connection.Target.Title | Should -Be '区画一覧'
        $connection.Session.WebSocketUrl | Should -Be 'ws://fake/target'
        @($transport.State.Connections) | Should -Be @('ws://fake/other', 'ws://fake/target', 'ws://fake/target')
        @($transport.State.Closed) | Should -Be @('ws://fake/other', 'ws://fake/target')
        (Get-LogMessages -Log $log -Level Info) | Should -Contain '操作対象のタブ: 区画一覧 <http://localhost/plots>'
    }

    It 'ignores tabs that cannot be business screens' {
        $target = New-TestPage -WebSocketUrl 'ws://fake/target' -Methods (New-IdentityMethods -Matches $true)
        $extras = @(
            @{ type = 'page'; title = 'Extensions'; url = 'chrome-extension://abc/popup.html'; webSocketDebuggerUrl = 'ws://fake/ext' },
            @{ type = 'page'; title = 'DevTools'; url = 'devtools://devtools/inspector.html'; webSocketDebuggerUrl = 'ws://fake/devtools' },
            @{ type = 'page'; title = 'Settings'; url = 'edge://settings'; webSocketDebuggerUrl = 'ws://fake/edge' },
            @{ type = 'service_worker'; title = 'sw'; url = 'http://localhost/sw.js'; webSocketDebuggerUrl = 'ws://fake/sw' },
            @{ type = 'page'; title = 'no socket'; url = 'http://localhost/x'; webSocketDebuggerUrl = '' }
        )
        $transport = New-FakeCdpTransport -Pages @($target) -ExtraTargets $extras

        $connection = Open-TestConnection -Transport $transport

        $connection.Session.WebSocketUrl | Should -Be 'ws://fake/target'
        @($transport.State.Connections | Where-Object { $_ -ne 'ws://fake/target' }).Count | Should -Be 0
    }

    It 'stops when no tab matches and lists every candidate with its reason' {
        $page = New-TestPage -WebSocketUrl 'ws://fake/a' -Title 'A' -Methods (New-IdentityMethods -Matches $false)
        $transport = New-FakeCdpTransport -Pages @($page)
        $log = New-RecordingLog

        { Open-TestConnection -Transport $transport -Log $log } | Should -Throw '*一致するタブが見つかりません*'
        (Get-LogMessages -Log $log -Level Warn) -join "`n" | Should -Match '\[不一致\] A <http://localhost/page>[\s\S]*identity\.title'
    }

    It 'stops when more than one tab matches (cannot decide which tab to operate)' {
        $first = New-TestPage -WebSocketUrl 'ws://fake/1' -Title 'one' -Methods (New-IdentityMethods -Matches $true)
        $second = New-TestPage -WebSocketUrl 'ws://fake/2' -Title 'two' -Methods (New-IdentityMethods -Matches $true)
        $transport = New-FakeCdpTransport -Pages @($first, $second)

        { Open-TestConnection -Transport $transport } | Should -Throw '*複数あります*1つだけ残してください*'
    }

    It 'treats a tab that refuses the connection as not matching and keeps checking others' {
        $broken = New-TestPage -WebSocketUrl 'ws://fake/broken' -Title 'broken' -Methods (New-IdentityMethods -Matches $true)
        $target = New-TestPage -WebSocketUrl 'ws://fake/target' -Methods (New-IdentityMethods -Matches $true)
        $transport = New-FakeCdpTransport -Pages @($broken, $target) -UnreachablePages @('ws://fake/broken')

        (Open-TestConnection -Transport $transport).Session.WebSocketUrl | Should -Be 'ws://fake/target'
    }

    It 'stops immediately when identification itself fails after connecting (script or catalog defect)' {
        $faulty = New-TestPage -WebSocketUrl 'ws://fake/faulty' -Methods @{ detectScreen = { param($Arguments) throw 'TypeError: x is undefined' } }
        $target = New-TestPage -WebSocketUrl 'ws://fake/target' -Methods (New-IdentityMethods -Matches $true)
        $transport = New-FakeCdpTransport -Pages @($faulty, $target)

        { Open-TestConnection -Transport $transport } | Should -Throw '*画面識別の実行中にエラー*TypeError*'
        @($transport.State.Connections) | Should -Not -Contain 'ws://fake/target'
    }

    It 'stops when the injected helper lacks a catalog method' {
        $methods = New-IdentityMethods -Matches $true
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1' -Methods $methods -HelperMethods @('detectScreen')
        $transport = New-FakeCdpTransport -Pages @($page)

        { Open-TestConnection -Transport $transport } | Should -Throw '*ClickExport=clickExport*'
    }

    It 'explains how to start the browser when the debugger endpoint is unreachable' {
        $transport = New-FakeCdpTransport -TargetListError 'connection refused'
        { Open-TestConnection -Transport $transport } | Should -Throw '*--remote-debugging-port*connection refused*'
    }
}

Describe 'Page gateway' {
    BeforeEach {
        $script:ContractQueue = New-Object System.Collections.Queue
        $queue = $script:ContractQueue
        $methods = New-IdentityMethods -Matches $true
        $methods['checkScreen'] = { param($Arguments) $queue.Dequeue() }.GetNewClosure()
        $methods['clickExport'] = { param($Arguments) [pscustomobject]@{ ok = $true; clicked = @($Arguments) } }
        $methods['readRows'] = { param($Arguments) @([pscustomobject]@{ code = 'A' }, [pscustomobject]@{ code = 'B' }) }
        $methods['isReady'] = { param($Arguments) $true }
        $script:Page = New-TestPage -WebSocketUrl 'ws://fake/target' -Methods $methods
        $script:Transport = New-FakeCdpTransport -Pages @($script:Page)
        $script:Log = New-RecordingLog
        $script:Clock = New-ManualClock
        $script:Connection = Open-TestConnection -Transport $script:Transport -Log $script:Log -Clock $script:Clock
        $script:Gateway = $script:Connection.Gateway
    }

    It 'invokes actions with arguments and returns the page value' {
        $result = & $script:Gateway.Invoke -Operation 'ClickExport' -Arguments @('GH1-A01', $true)
        $result.ok | Should -BeTrue
        @($result.clicked) | Should -Be @('GH1-A01', $true)
    }

    It 'returns query arrays that callers can wrap with @()' {
        $rows = @(& $script:Gateway.Invoke -Operation 'ReadRows')
        $rows.Count | Should -Be 2
        $rows[1].code | Should -Be 'B'
    }

    It 'waits for probes and query results' {
        & $script:Gateway.WaitUntil -Operation 'IsReady' | Should -BeTrue
        (& $script:Gateway.WaitFor -Operation 'ReadRows' -Accept { param($Value) @($Value).Count -eq 2 })[0].code | Should -Be 'A'
    }

    It 'keeps polling a contract until fatal failures disappear' {
        $script:ContractQueue.Enqueue((New-ContractResult -Scope 'sample.screen' -Failures @(@{ name = 'rows.exist'; message = '描画中' })))
        $script:ContractQueue.Enqueue((New-ContractResult -Scope 'sample.screen' -Failures @(@{ name = 'aux'; severity = 'warning'; message = '補助なし' })))

        $result = & $script:Gateway.Assert -Operation 'CheckScreen'

        $result.ok | Should -BeTrue
        @($script:Clock.State.Sleeps).Count | Should -Be 1
        (Get-LogMessages -Log $script:Log -Level Warn) -join "`n" | Should -Match '一覧画面の契約[\s\S]*補助なし'
    }

    It 'reports the last contract violation in detail when the deadline passes' {
        $violation = New-ContractResult -Scope 'sample.screen' -Failures @(@{ name = 'button.unique'; message = 'CSV出力ボタンが2件' })
        for ($i = 0; $i -lt 200; $i++) { $script:ContractQueue.Enqueue($violation) }

        { & $script:Gateway.Assert -Operation 'CheckScreen' -TimeoutSeconds 1 } | Should -Throw '*ページ契約違反: 一覧画面の契約*button.unique*CSV出力ボタンが2件*'
    }

    It 'refuses to use an operation in a way its kind does not allow' {
        { & $script:Gateway.Invoke -Operation 'CheckScreen' } | Should -Throw '*Invoke では呼び出せません*'
        { & $script:Gateway.WaitUntil -Operation 'ClickExport' } | Should -Throw '*WaitUntil では呼び出せません*'
    }

    It 'rejects misspelled parameter names instead of silently ignoring them' {
        { & $script:Gateway.Invoke -Operation 'ClickExport' -Arguemnts @('x') } | Should -Throw '*Arguemnts*'
    }

    It 'sets the download directory on the connected tab' {
        Set-PageDownloadDirectory -Connection $script:Connection -Directory '/work/downloads'
        $last = @($script:Transport.State.Sent)[-1]
        $last.Method | Should -Be 'Browser.setDownloadBehavior'
        $last.Uri | Should -Be 'ws://fake/target'
    }

    It 'closes the connection idempotently' {
        Close-PageConnection -Connection $script:Connection
        Close-PageConnection -Connection $script:Connection
        @($script:Transport.State.Closed | Where-Object { $_ -eq 'ws://fake/target' }).Count | Should -Be 2
    }
}
