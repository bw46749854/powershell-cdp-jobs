BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../../app/modules/JobKit/JobKit.psm1') -Force
}

Describe 'Get-PropertyValue / Test-PropertyPresent' {
    It 'reads hashtable keys and object properties the same way' {
        Get-PropertyValue -InputObject @{ Name = 'a' } -Name 'Name' | Should -Be 'a'
        Get-PropertyValue -InputObject ([pscustomobject]@{ Name = 'b' }) -Name 'Name' | Should -Be 'b'
    }

    It 'returns the default instead of failing when the key is missing' {
        Get-PropertyValue -InputObject @{} -Name 'Missing' -Default 'x' | Should -Be 'x'
        Get-PropertyValue -InputObject ([pscustomobject]@{}) -Name 'Missing' | Should -BeNullOrEmpty
        Get-PropertyValue -InputObject $null -Name 'Missing' -Default 3 | Should -Be 3
    }

    It 'distinguishes a present null value from a missing key' {
        Test-PropertyPresent -InputObject @{ Value = $null } -Name 'Value' | Should -BeTrue
        Test-PropertyPresent -InputObject @{} -Name 'Value' | Should -BeFalse
        Test-PropertyPresent -InputObject ([pscustomobject]@{ Value = $null }) -Name 'Value' | Should -BeTrue
    }
}

Describe 'Port contracts' {
    It 'returns a scriptblock member' {
        $port = [pscustomobject]@{ Run = { param($A) $A } }
        $member = Get-PortMember -Port $port -PortName 'Sample' -Member 'Run'
        & $member -A 5 | Should -Be 5
    }

    It 'names the port and member when a member is missing' {
        { Get-PortMember -Port ([pscustomobject]@{}) -PortName 'Files' -Member 'Move' } |
            Should -Throw "*'Files'*'Move'*"
    }

    It 'lists declared parameter names of a scriptblock' {
        $names = Get-ScriptBlockParameterNames -ScriptBlock { param([string]$Path, [int]$Count) }
        $names | Should -Be @('Path', 'Count')
        @(Get-ScriptBlockParameterNames -ScriptBlock { 'no params' }).Count | Should -Be 0
    }

    It 'accepts a port that declares the required members and parameters' {
        $port = [pscustomobject]@{
            Save = { param($Path, $Rows, $Extra) }
            Extra = { }
        }
        { Assert-PortShape -Port $port -PortName 'Files' -Members @{ Save = @('Path', 'Rows') } } | Should -Not -Throw
    }

    It 'reports every shape problem at once' {
        $port = [pscustomobject]@{
            Save = { param($Path) }
            Load = 'not a scriptblock'
        }
        { Assert-PortShape -Port $port -PortName 'Files' -Members @{ Save = @('Path', 'Rows'); Load = @() } } |
            Should -Throw '*Load は scriptblock ではありません*Save にパラメーター -Rows*'
    }

    It 'rejects a missing port' {
        { Assert-PortShape -Port $null -PortName 'Clock' -Members @{ Now = @() } } | Should -Throw "*'Clock'*指定されていません*"
    }
}

Describe 'Job result protocol' {
    It 'creates a successful result with outputs and summary' {
        $result = New-JobResult -Job 'Sample' -Outputs @{ Path = 'a.csv' } -Summary @{ Count = 2 }
        $result.Job | Should -Be 'Sample'
        $result.Ok | Should -BeTrue
        $result.Outputs.Path | Should -Be 'a.csv'
        $result.Summary.Count | Should -Be 2
    }

    It 'accepts exactly one result for the expected job' {
        $result = New-JobResult -Job 'Sample'
        (Assert-JobResult -Output @($result) -Job 'Sample').Job | Should -Be 'Sample'
    }

    It 'ignores null pipeline values but rejects leaked extra output' {
        $result = New-JobResult -Job 'Sample'
        (Assert-JobResult -Output @($null, $result) -Job 'Sample').Job | Should -Be 'Sample'
        { Assert-JobResult -Output @('leaked text', $result) -Job 'Sample' } | Should -Throw '*1つだけ*2 個*'
        { Assert-JobResult -Output @() -Job 'Sample' } | Should -Throw '*0 個*'
    }

    It 'rejects results of another job, objects without the protocol, and non-success results' {
        { Assert-JobResult -Output @(New-JobResult -Job 'Other') -Job 'Sample' } | Should -Throw "*'Other'*"
        { Assert-JobResult -Output @([pscustomobject]@{ Job = 'Sample' }) -Job 'Sample' } | Should -Throw '*Ok がありません*'
        $failed = New-JobResult -Job 'Sample'
        $failed.Ok = $false
        { Assert-JobResult -Output @($failed) -Job 'Sample' } | Should -Throw '*例外で通知*'
    }
}

Describe 'Read-JobSetting' {
    BeforeAll {
        $settings = @{
            Directory = 'work/tmp'
            Blank = '  '
            Timeout = 30
            Negative = -1
            Pattern = '^a.+\.csv$'
            BrokenPattern = '(['
            Headers = @('A', 'B')
            SingleText = 'A'
            EmptyList = @()
            Enabled = $true
        }
    }

    It 'returns typed values' {
        Read-JobSetting -Settings $settings -Name 'Directory' -Kind Text -Scope 'Jobs.X' | Should -Be 'work/tmp'
        Read-JobSetting -Settings $settings -Name 'Timeout' -Kind Integer -Minimum 1 -Scope 'Jobs.X' | Should -Be 30
        Read-JobSetting -Settings $settings -Name 'Pattern' -Kind Pattern -Scope 'Jobs.X' | Should -Be '^a.+\.csv$'
        @(Read-JobSetting -Settings $settings -Name 'Headers' -Kind TextList -Scope 'Jobs.X') | Should -Be @('A', 'B')
        Read-JobSetting -Settings $settings -Name 'Enabled' -Kind Flag -Scope 'Jobs.X' | Should -BeTrue
    }

    It 'reports the full setting location when a value is missing or invalid' -TestCases @(
        @{ Name = 'Missing'; Kind = 'Text'; Expected = '*Jobs.X.Missing がありません*' }
        @{ Name = 'Blank'; Kind = 'Text'; Expected = '*Jobs.X.Blank は空でない文字列*' }
        @{ Name = 'Directory'; Kind = 'Integer'; Expected = '*Jobs.X.Directory は整数*' }
        @{ Name = 'Negative'; Kind = 'Integer'; Expected = '*1 以上*' }
        @{ Name = 'BrokenPattern'; Kind = 'Pattern'; Expected = '*正規表現として解釈できません*' }
        @{ Name = 'SingleText'; Kind = 'TextList'; Expected = '*配列*' }
        @{ Name = 'EmptyList'; Kind = 'TextList'; Expected = '*空です*' }
        @{ Name = 'Directory'; Kind = 'Flag'; Expected = '*$true / $false*' }
    ) {
        param($Name, $Kind, $Expected)
        { Read-JobSetting -Settings $settings -Name $Name -Kind $Kind -Minimum 1 -Scope 'Jobs.X' } | Should -Throw $Expected
    }
}

Describe 'Invoke-LoggedStep' {
    It 'logs the step message before running the action and returns its value' {
        $events = New-Object System.Collections.ArrayList
        $log = [pscustomobject]@{ Info = { param($Message) [void]$events.Add("log:$Message") }.GetNewClosure() }

        $value = Invoke-LoggedStep -Log $log -Message 'CSVを出力します。' -Action { [void]$events.Add('action'); 42 }

        $value | Should -Be 42
        @($events) | Should -Be @('log:CSVを出力します。', 'action')
    }
}
