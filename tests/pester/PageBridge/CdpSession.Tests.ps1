BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/PageBridge/PageBridge.psm1') -Force
}

Describe 'Bridge error categories' {
    It 'reads the category through PowerShell exception wrapping' {
        InModuleScope PageBridge {
            $inner = New-BridgeException -Category 'session-lost' -Message 'gone'
            $wrapped = New-Object System.Management.Automation.RuntimeException -ArgumentList 'outer', $inner
            Get-BridgeErrorCategory -ErrorObject $wrapped | Should -Be 'session-lost'
        }
    }

    It 'infers session-lost and timeout from .NET exception types' {
        InModuleScope PageBridge {
            Get-BridgeErrorCategory -ErrorObject (New-Object System.ObjectDisposedException -ArgumentList 'socket') | Should -Be 'session-lost'
            Get-BridgeErrorCategory -ErrorObject (New-Object System.TimeoutException -ArgumentList 'slow') | Should -Be 'timeout'
            Get-BridgeErrorCategory -ErrorObject (New-Object System.ArgumentException -ArgumentList 'other') | Should -Be ''
        }
    }

    It 'treats only communication-breaking categories as fatal' {
        Test-PageBridgeFatalError -ErrorObject (New-CategorizedTestException -Category 'helper-missing' -Message 'x') | Should -BeTrue
        Test-PageBridgeFatalError -ErrorObject (New-CategorizedTestException -Category 'timeout' -Message 'x') | Should -BeTrue
        Test-PageBridgeFatalError -ErrorObject (New-CategorizedTestException -Category 'wait-timeout' -Message 'x') | Should -BeFalse
        Test-PageBridgeFatalError -ErrorObject (New-CategorizedTestException -Category 'javascript' -Message 'x') | Should -BeFalse
        Test-PageBridgeFatalError -ErrorObject (New-CategorizedTestException -Category 'contract' -Message 'x') | Should -BeFalse
    }
}

Describe 'Send-CdpCommand' {
    BeforeEach {
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1'
    }

    It 'matches the response by id and skips events and other responses' {
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand {
            param($Request, $Page)
            return @(
                @{ method = 'Page.frameNavigated'; params = @{} },
                @{ id = 999; result = @{ value = 'other' } },
                @{ id = $Request.id; result = @{ value = 'mine' } }
            )
        }

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock) } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            (Send-CdpCommand -Session $session -Method 'Test.echo').value | Should -Be 'mine'
            (Send-CdpCommand -Session $session -Method 'Test.echo').value | Should -Be 'mine'
            $session.NextId | Should -Be 2
        }
    }

    It 'turns a CDP error response into a command error without closing the session' {
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand {
            param($Request, $Page)
            return @(@{ id = $Request.id; error = @{ code = -32601; message = 'method not found' } })
        }

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock) } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            $failure = $null
            try { Send-CdpCommand -Session $session -Method 'Nope.call' } catch { $failure = $_ }

            $failure.Exception.Message | Should -Match 'method=Nope\.call.*method not found'
            Get-BridgeErrorCategory -ErrorObject $failure | Should -Be 'command'
            $session.Closed | Should -BeFalse
        }
    }

    It 'aborts the session when the browser closes the socket' {
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand { param($Request, $Page) return @('#close') }

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock) } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            $failure = $null
            try { Send-CdpCommand -Session $session -Method 'Runtime.evaluate' } catch { $failure = $_ }

            Get-BridgeErrorCategory -ErrorObject $failure | Should -Be 'session-lost'
            $session.Closed | Should -BeTrue
            @($Transport.State.Aborted) | Should -Be @('ws://fake/1')

            { Send-CdpCommand -Session $session -Method 'Runtime.evaluate' } | Should -Throw '*既に閉じています*'
        }
    }

    It 'times out against the command deadline and stops the session' {
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand {
            param($Request, $Page)
            return @(@{ method = 'Network.event'; params = @{} }, @{ method = 'Network.event'; params = @{} })
        }

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock -StepMilliseconds 2000) } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 3 -Clock $Clock

            $failure = $null
            try { Send-CdpCommand -Session $session -Method 'Slow.call' } catch { $failure = $_ }

            Get-BridgeErrorCategory -ErrorObject $failure | Should -Be 'timeout'
            $failure.Exception.Message | Should -Match 'method=Slow\.call'
            $session.Closed | Should -BeTrue
        }
    }

    It 'reports an unreadable response as a protocol error' {
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand { param($Request, $Page) return @('{not json') }

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock) } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            $failure = $null
            try { Send-CdpCommand -Session $session -Method 'Runtime.evaluate' } catch { $failure = $_ }
            Get-BridgeErrorCategory -ErrorObject $failure | Should -Be 'protocol'
        }
    }

    It 'rejects a transport that does not have the expected shape' {
        InModuleScope PageBridge -Parameters @{ Clock = (New-ManualClock) } {
            param($Clock)
            { Open-CdpSession -Transport ([pscustomobject]@{ Connect = { param($Uri) } }) -WebSocketUrl 'ws://x' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 1 -Clock $Clock } |
                Should -Throw "*'CdpTransport'*"
        }
    }
}
