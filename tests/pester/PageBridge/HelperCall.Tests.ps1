BeforeDiscovery {
    $nodeAvailable = $null -ne (Get-Command node -ErrorAction SilentlyContinue)
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/PageBridge/PageBridge.psm1') -Force

    function New-TestOperation {
        param([string]$Name, [string]$Method, [string]$Kind, [string]$Scope = '')
        return [pscustomobject]@{ Name = $Name; Method = $Method; Kind = $Kind; Scope = $Scope; TimeoutSeconds = 0; Label = $Name }
    }

    function Invoke-ExpressionsInNode {
        param([Parameter(Mandatory)][object[]]$Cases)
        $script = Get-RepositoryPath 'tests/support/evaluate-expressions.js'
        $json = ConvertTo-Json -InputObject @($Cases) -Depth 10
        $output = $json | & node $script
        $results = @{}
        foreach ($result in @(ConvertFrom-Json -InputObject ($output -join ''))) { $results[$result.name] = $result }
        return $results
    }

}

Describe 'New-HelperCallExpression' {
    It 'passes every argument as a JSON literal in order' {
        InModuleScope PageBridge {
            $operation = [pscustomobject]@{ Name = 'Sync'; Method = 'syncSelection'; Kind = 'Action'; Scope = '' }
            $expression = New-HelperCallExpression -Helper 'sampleHelper' -Operation $operation -Arguments @('GH1-A01', $true, $null, 3)

            $expression | Should -Match 'kit\.helpers\["sampleHelper"\]'
            $expression | Should -Match 'helper\["syncSelection"\]'
            $expression | Should -Match 'method\.apply\(helper, \["GH1-A01", true, null, 3\]\)'
            $expression | Should -Match '^\(async \(\) => \{'
        }
    }

    It 'refuses names that would allow script injection' {
        InModuleScope PageBridge {
            $operation = [pscustomobject]@{ Name = 'X'; Method = 'x"]; alert(1); //'; Kind = 'Action'; Scope = '' }
            { New-HelperCallExpression -Helper 'sampleHelper' -Operation $operation } | Should -Throw '*Method 名が JavaScript の識別子ではありません*'
        }
    }
}

Describe 'Helper absence policy (evaluated in Node.js)' -Skip:(-not $nodeAvailable) {
    BeforeAll {
        $operations = @(
            (New-TestOperation -Name 'Detect' -Method 'detect' -Kind 'Identity' -Scope 'sample.identity'),
            (New-TestOperation -Name 'Check' -Method 'check' -Kind 'Contract' -Scope 'sample.screen'),
            (New-TestOperation -Name 'Click' -Method 'click' -Kind 'Action'),
            (New-TestOperation -Name 'Rows' -Method 'rows' -Kind 'Query'),
            (New-TestOperation -Name 'Ready' -Method 'ready' -Kind 'Probe'),
            (New-TestOperation -Name 'Close' -Method 'close' -Kind 'Cleanup')
        )

        $cases = @()
        $expressions = InModuleScope PageBridge -Parameters @{ Operations = $operations } {
            param($Operations)
            $map = @{}
            foreach ($operation in $Operations) {
                $map[$operation.Kind] = New-HelperCallExpression -Helper 'sampleHelper' -Operation $operation -Arguments @('a', 1)
            }
            return $map
        }

        foreach ($kind in @($expressions.Keys)) {
            $cases += @{ name = "absent-$kind"; helper = 'sampleHelper'; helpers = $null; expression = $expressions[$kind] }
        }
        $cases += @{ name = 'present-Action'; helper = 'sampleHelper'; helpers = @{ click = 'clicked' }; expression = $expressions['Action'] }
        $cases += @{ name = 'missing-method'; helper = 'sampleHelper'; helpers = @{ other = 1 }; expression = $expressions['Action'] }
        $cases += @{ name = 'page-error'; helper = 'sampleHelper'; helpers = @{ click = @{ throws = '候補が2件あります' } }; expression = $expressions['Action'] }

        $script:Results = Invoke-ExpressionsInNode -Cases $cases
    }

    It 'returns a fatal contract failure for identity and contract operations' {
        foreach ($name in @('absent-Identity', 'absent-Contract')) {
            $result = $script:Results[$name]
            $result.ok | Should -BeTrue
            $result.value.ok | Should -BeFalse
            $result.value.fatalCount | Should -Be 1
            $result.value.checks[0].name | Should -Be 'helper.registered'
        }
        $script:Results['absent-Identity'].value.scope | Should -Be 'sample.identity'
        $script:Results['absent-Contract'].value.scope | Should -Be 'sample.screen'
    }

    It 'throws a helper-missing marker for actions and queries (never an empty result)' {
        foreach ($name in @('absent-Action', 'absent-Query')) {
            $script:Results[$name].ok | Should -BeFalse
            $script:Results[$name].error | Should -Match '\[pagekit:helper-missing\]'
        }
    }

    It 'returns false for probes and a warning object for cleanup' {
        $script:Results['absent-Probe'].value | Should -BeFalse
        $script:Results['absent-Cleanup'].value.severity | Should -Be 'warning'
        $script:Results['absent-Cleanup'].value.ok | Should -BeFalse
    }

    It 'calls the helper method with the helper as this and the given arguments' {
        $value = $script:Results['present-Action'].value
        $value.returned | Should -Be 'clicked'
        $value.args | Should -Be @('a', 1)
        $value.self | Should -BeTrue
    }

    It 'distinguishes a missing method and a page error' {
        $script:Results['missing-method'].error | Should -Match '\[pagekit:method-missing\]'
        $script:Results['page-error'].error | Should -Be '候補が2件あります'
    }
}
