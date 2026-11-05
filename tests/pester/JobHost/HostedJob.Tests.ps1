BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/JobHost/JobHost.psm1') -Force

    $script:JobKitPath = Get-RepositoryPath 'app/modules/JobKit/JobKit.psm1'

    function New-FixtureApp {
        <#
        TestDrive 上に、最小のジョブモジュールと設定を持つ app ディレクトリを作る。
        #>
        param([Parameter(Mandatory)][string]$Name)

        $appRoot = Join-Path (Join-Path $TestDrive $Name) 'app'
        $config = Join-Path $appRoot 'config'
        $modules = Join-Path $appRoot 'modules'
        New-Item -ItemType Directory -Path $config, $modules -Force | Out-Null

        $echo = @"
Import-Module -Name '$($script:JobKitPath)' -DisableNameChecking
function Invoke-EchoJob {
    param([Parameter(Mandatory)]`$Context)
    if (`$Context.Settings.Leak) { 'leaked output' }
    if (`$Context.Settings.Fail) { throw 'echo failed on purpose' }
    & `$Context.Services.Log.Info -Message "echo: `$(`$Context.Settings.Word)"
    return New-JobResult -Job 'Echo' -Outputs @{ Word = `$Context.Settings.Word; Directory = `$Context.Settings.WorkDirectory; SettingsPath = `$Context.SettingsPath }
}
Export-ModuleMember -Function Invoke-EchoJob
"@
        $chain = @"
Import-Module -Name '$($script:JobKitPath)' -DisableNameChecking
function Invoke-ChainJob {
    param([Parameter(Mandatory)]`$Context)
    `$child = & `$Context.Services.Jobs.Run -JobName 'Echo' -Overrides @{ Word = 'from-chain'; WorkDirectory = 'runs/child' }
    `$childSettings = & `$Context.Services.Jobs.GetSettings -JobName 'Echo'
    return New-JobResult -Job 'Chain' -Outputs @{ Child = `$child; ChildDefaultWord = `$childSettings.Word }
}
Export-ModuleMember -Function Invoke-ChainJob
"@
        Set-Content -LiteralPath (Join-Path $modules 'Echo.psm1') -Value $echo -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $modules 'Chain.psm1') -Value $chain -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $config 'jobs.psd1') -Encoding UTF8 -Value @'
@{
    Jobs = @{
        Echo = @{ Module = 'modules/Echo.psm1'; Command = 'Invoke-EchoJob'; UsesBrowser = $false }
        Chain = @{ Module = 'modules/Chain.psm1'; Command = 'Invoke-ChainJob'; UsesBrowser = $false }
        Ghost = @{ Module = 'modules/Echo.psm1'; Command = 'Invoke-GhostJob'; UsesBrowser = $false }
    }
}
'@
        Set-Content -LiteralPath (Join-Path $config 'settings.psd1') -Encoding UTF8 -Value @'
@{
    Common = @{ Logging = @{ Level = 'Info'; Console = $true; File = $false } }
    Jobs = @{
        Echo = @{ Word = 'default'; WorkDirectory = 'work/echo' }
        Chain = @{}
        Ghost = @{}
    }
}
'@
        return $appRoot
    }

    function New-SilentServices {
        $lines = New-CallRecorder
        return @{
            Lines = $lines
            Overrides = @{ ConsoleWriter = { param($Level, $Line) [void]$lines.Add($Line) }.GetNewClosure() }
        }
    }
}

Describe 'Invoke-HostedJob' {
    It 'runs the job command with a context and returns its result' {
        $appRoot = New-FixtureApp -Name 'basic'
        $silent = New-SilentServices

        $result = Invoke-HostedJob -AppRoot $appRoot -JobName 'Echo' -ServiceOverrides $silent.Overrides

        $result.Job | Should -Be 'Echo'
        $result.Outputs.Word | Should -Be 'default'
        $result.Outputs.Directory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $appRoot) 'work/echo')))
        ($silent.Lines -join "`n") | Should -Match 'Echo 開始[\s\S]*echo: default[\s\S]*Echo 正常終了'
    }

    It 'applies settings overrides for this run only' {
        $appRoot = New-FixtureApp -Name 'override'
        $silent = New-SilentServices

        (Invoke-HostedJob -AppRoot $appRoot -JobName 'Echo' -SettingsOverrides @{ Word = 'override' } -ServiceOverrides $silent.Overrides).Outputs.Word | Should -Be 'override'
        (Invoke-HostedJob -AppRoot $appRoot -JobName 'Echo' -ServiceOverrides $silent.Overrides).Outputs.Word | Should -Be 'default'
    }

    It 'logs the failure and rethrows it' {
        $appRoot = New-FixtureApp -Name 'failure'
        $silent = New-SilentServices

        { Invoke-HostedJob -AppRoot $appRoot -JobName 'Echo' -SettingsOverrides @{ Fail = $true } -ServiceOverrides $silent.Overrides } | Should -Throw '*echo failed on purpose*'
        ($silent.Lines -join "`n") | Should -Match '\[ERROR  \].*Echo は異常終了しました: echo failed on purpose'
    }

    It 'detects output leaked into the pipeline as a protocol violation' {
        $appRoot = New-FixtureApp -Name 'leak'
        $silent = New-SilentServices

        { Invoke-HostedJob -AppRoot $appRoot -JobName 'Echo' -SettingsOverrides @{ Leak = $true } -ServiceOverrides $silent.Overrides } | Should -Throw '*1つだけ*2 個*'
    }

    It 'fails before running when the job name or command is unknown' {
        $appRoot = New-FixtureApp -Name 'unknown'
        $silent = New-SilentServices

        { Invoke-HostedJob -AppRoot $appRoot -JobName 'Nope' -ServiceOverrides $silent.Overrides } | Should -Throw '*ジョブ定義にないジョブ名です: Nope*'
        { Invoke-HostedJob -AppRoot $appRoot -JobName 'Ghost' -ServiceOverrides $silent.Overrides } | Should -Throw '*Command が見つかりません*Invoke-GhostJob*'
    }

    It 'runs child jobs with the parent settings file and passes overrides to the child only' {
        $appRoot = New-FixtureApp -Name 'chain'
        $customSettings = Join-Path (Split-Path -Parent $appRoot) 'custom-settings.psd1'
        Copy-Item -LiteralPath (Join-Path $appRoot 'config/settings.psd1') -Destination $customSettings
        (Get-Content -LiteralPath $customSettings -Raw).Replace("Word = 'default'", "Word = 'custom'") | Set-Content -LiteralPath $customSettings -Encoding UTF8
        $silent = New-SilentServices

        $result = Invoke-HostedJob -AppRoot $appRoot -JobName 'Chain' -SettingsPath $customSettings -ServiceOverrides $silent.Overrides

        $result.Outputs.Child.Outputs.Word | Should -Be 'from-chain'
        $result.Outputs.Child.Outputs.SettingsPath | Should -Be ([System.IO.Path]::GetFullPath($customSettings))
        $result.Outputs.Child.Outputs.Directory | Should -Be ([System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $appRoot) 'runs/child')))
        $result.Outputs.ChildDefaultWord | Should -Be 'custom'
        @($silent.Lines | Where-Object { $_ -like '*echo: from-chain*' }).Count | Should -Be 1
    }
}

Describe 'Browser service' {
    BeforeAll {
        $operations = Join-Path $TestDrive 'ops.psd1'
        Set-Content -LiteralPath $operations -Encoding UTF8 -Value @'
@{
    Helper = 'sampleHelper'
    Operations = @{
        DetectScreen = @{ Method = 'detectScreen'; Kind = 'Identity'; Scope = 'sample.identity' }
        ReadCount = @{ Method = 'readCount'; Kind = 'Query' }
    }
}
'@
        $scriptPath = Join-Path $TestDrive 'kernel.js'
        Set-Content -LiteralPath $scriptPath -Value '/* simulated */' -Encoding UTF8
        $script:Entry = [pscustomobject]@{ Name = 'Sample'; UsesBrowser = $true; Operations = $operations; Scripts = @($scriptPath) }
        $script:Common = @{ Browser = @{ DebuggerUrl = 'http://localhost:9222/json'; ConnectTimeoutSeconds = 1; CommandTimeoutSeconds = 5 } }
    }

    It 'connects through the job catalog and forwards page operations' {
        $page = New-SimulatedPage -WebSocketUrl 'ws://fake/1' -Title '区画一覧' -Methods @{
            detectScreen = { param($Arguments) New-ContractResult -Scope 'sample.identity' }
            readCount = { param($Arguments) 40 }
        }
        $transport = New-FakeCdpTransport -Pages @($page)
        $log = New-RecordingLog

        $browser = InModuleScope JobHost -Parameters @{ Common = $script:Common; Entry = $script:Entry; Log = $log; Transport = $transport } {
            param($Common, $Entry, $Log, $Transport)
            New-HostBrowserService -Common $Common -Entry $Entry -Log $Log -Clock (New-ManualClock) -Transport $Transport
        }

        { & $browser.Invoke -Operation 'ReadCount' } | Should -Throw '*先に Connect*'

        (& $browser.Connect).Title | Should -Be '区画一覧'
        & $browser.Invoke -Operation 'ReadCount' | Should -Be 40
        & $browser.IsFatal -ErrorObject (New-CategorizedTestException -Category 'session-lost' -Message 'x') | Should -BeTrue

        & $browser.Close
        & $browser.Close
        { & $browser.Invoke -Operation 'ReadCount' } | Should -Throw '*先に Connect*'
    }

    It 'validates Common.Browser settings before connecting' {
        InModuleScope JobHost -Parameters @{ Entry = $script:Entry } {
            param($Entry)
            { New-HostBrowserService -Common @{} -Entry $Entry -Log (New-RecordingLog) -Clock (New-HostClock) } | Should -Throw '*Common.Browser*'
            $bad = @{ Browser = @{ DebuggerUrl = 'http://x'; ConnectTimeoutSeconds = 0; CommandTimeoutSeconds = 5 } }
            { New-HostBrowserService -Common $bad -Entry $Entry -Log (New-RecordingLog) -Clock (New-HostClock) } | Should -Throw '*Common.Browser.ConnectTimeoutSeconds は 1 以上*'
        }
    }
}
