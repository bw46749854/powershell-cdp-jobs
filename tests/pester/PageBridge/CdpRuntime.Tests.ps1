BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/PageBridge/PageBridge.psm1') -Force
}

Describe 'Invoke-CdpEvaluate' {
    It 'evaluates with awaitPromise and returnByValue and returns the value' {
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1'
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand {
            param($Request, $Page)
            return @(@{ id = $Request.id; result = @{ result = @{ type = 'number'; value = 42 } } })
        }

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock) } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            Invoke-CdpEvaluate -Session $session -Expression '6 * 7' | Should -Be 42

            $params = $Transport.State.Sent[0].Request.params
            $params.awaitPromise | Should -BeTrue
            $params.returnByValue | Should -BeTrue
            $params.expression | Should -Be '6 * 7'
        }
    }

    It 'classifies page errors with the helper-missing marker as fatal and others as javascript errors' -TestCases @(
        @{ Description = 'Error: [pagekit:helper-missing] gone'; Category = 'helper-missing' }
        @{ Description = 'Error: [pagekit:method-missing] x.y'; Category = 'helper-missing' }
        @{ Description = 'Error: ボタンが一意に決まりません'; Category = 'javascript' }
    ) {
        param($Description, $Category)
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1'
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand {
            param($Request, $Page)
            return @(@{ id = $Request.id; result = @{ result = @{ type = 'object' }; exceptionDetails = @{ text = 'Uncaught'; exception = @{ description = $Description } } } })
        }.GetNewClosure()

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock); Category = $Category } {
            param($Transport, $Clock, $Category)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            $failure = $null
            try { Invoke-CdpEvaluate -Session $session -Expression 'x' } catch { $failure = $_ }
            Get-BridgeErrorCategory -ErrorObject $failure | Should -Be $Category
            $failure.Exception.Message | Should -Match 'ページ内スクリプトでエラー'
        }
    }
}

Describe 'Wait-CdpEvaluation' {
    It 'polls until the value is accepted, tolerating transient page errors' {
        $script:responses = New-Object System.Collections.Queue
        $script:responses.Enqueue(@{ exceptionDetails = @{ text = 'Uncaught'; exception = @{ description = 'TypeError: rendering' } } })
        $script:responses.Enqueue(@{ result = @{ type = 'boolean'; value = $false } })
        $script:responses.Enqueue(@{ result = @{ type = 'boolean'; value = $true } })
        $queue = $script:responses
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1'
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand {
            param($Request, $Page)
            return @(@{ id = $Request.id; result = $queue.Dequeue() })
        }.GetNewClosure()
        $clock = New-ManualClock

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = $clock } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            Wait-CdpEvaluation -Session $session -Expression 'ready()' -Accept { param($Value) $Value -eq $true } -TimeoutSeconds 5 -Description 'ready' |
                Should -BeTrue
            @($Clock.State.Sleeps) | Should -Be @(250, 250)
        }
    }

    It 'fails fast on a fatal error instead of waiting until the deadline' {
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1'
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand { param($Request, $Page) return @('#close') }
        $clock = New-ManualClock

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = $clock } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            $failure = $null
            try { Wait-CdpEvaluation -Session $session -Expression 'x' -Accept { $true } -TimeoutSeconds 30 -Description 'x' } catch { $failure = $_ }
            Get-BridgeErrorCategory -ErrorObject $failure | Should -Be 'session-lost'
            @($Clock.State.Sleeps).Count | Should -Be 0
        }
    }

    It 'reports the last value when the deadline passes as a non-fatal wait-timeout' {
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1'
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand {
            param($Request, $Page)
            return @(@{ id = $Request.id; result = @{ result = @{ type = 'object'; value = @{ state = 'loading' } } } })
        }

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock) } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            $failure = $null
            try { Wait-CdpEvaluation -Session $session -Expression 'x' -Accept { param($Value) $Value.state -eq 'done' } -TimeoutSeconds 1 -Description '詳細パネル表示' } catch { $failure = $_ }

            Get-BridgeErrorCategory -ErrorObject $failure | Should -Be 'wait-timeout'
            Test-BridgeFatalCategory -Category 'wait-timeout' | Should -BeFalse
            $failure.Exception.Message | Should -Match '詳細パネル表示.*"state":"loading"'
        }
    }

    It 'propagates an exception thrown by Accept immediately' {
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1'
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand {
            param($Request, $Page)
            return @(@{ id = $Request.id; result = @{ result = @{ type = 'number'; value = 1 } } })
        }

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock) } {
            param($Transport, $Clock)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            { Wait-CdpEvaluation -Session $session -Expression 'x' -Accept { throw 'shape mismatch' } -TimeoutSeconds 10 -Description 'x' } |
                Should -Throw '*shape mismatch*'
            @($Clock.State.Sleeps).Count | Should -Be 0
        }
    }
}

Describe 'Set-CdpDownloadBehavior' {
    It 'uses Browser.setDownloadBehavior when accepted' {
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1'
        $transport = New-FakeCdpTransport -Pages @($page)

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock); Log = (New-RecordingLog) } {
            param($Transport, $Clock, $Log)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            Set-CdpDownloadBehavior -Session $session -Directory '/work/tmp' -Log $Log | Should -Be 'Browser.setDownloadBehavior'
            $request = $Transport.State.Sent[0].Request
            $request.params.behavior | Should -Be 'allow'
            $request.params.downloadPath | Should -Be '/work/tmp'
        }
    }

    It 'falls back to Page.setDownloadBehavior and records why' {
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1'
        $transport = New-FakeCdpTransport -Pages @($page) -OnCommand {
            param($Request, $Page)
            if ($Request.method -eq 'Browser.setDownloadBehavior') {
                return @(@{ id = $Request.id; error = @{ message = 'not allowed for page target' } })
            }
            return @(@{ id = $Request.id; result = @{} })
        }
        $log = New-RecordingLog

        InModuleScope PageBridge -Parameters @{ Transport = $transport; Clock = (New-ManualClock); Log = $log } {
            param($Transport, $Clock, $Log)
            $session = Open-CdpSession -Transport $Transport -WebSocketUrl 'ws://fake/1' -ConnectTimeoutSeconds 1 -CommandTimeoutSeconds 5 -Clock $Clock

            Set-CdpDownloadBehavior -Session $session -Directory '/work/tmp' -Log $Log | Should -Be 'Page.setDownloadBehavior'
            @($Transport.State.Sent | ForEach-Object { $_.Method }) | Should -Be @('Browser.setDownloadBehavior', 'Page.setDownloadBehavior')
        }

        (Get-LogMessages -Log $log -Level Warn) | Should -Match 'not allowed for page target'
    }
}
