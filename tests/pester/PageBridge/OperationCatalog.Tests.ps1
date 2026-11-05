BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/PageBridge/PageBridge.psm1') -Force

    function Write-CatalogFile {
        param([Parameter(Mandatory)][string]$Body)
        $path = Join-Path $TestDrive ("catalog_{0}.psd1" -f [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $path -Value $Body -Encoding UTF8
        return $path
    }

    $script:ValidCatalog = @'
@{
    Helper = 'sampleHelper'
    Operations = @{
        DetectScreen = @{ Method = 'detectScreen'; Kind = 'Identity'; Scope = 'sample.identity'; TimeoutSeconds = 2 }
        CheckScreen  = @{ Method = 'checkScreen'; Kind = 'Contract'; Scope = 'sample.screen'; Label = '画面契約' }
        ClickExport  = @{ Method = 'clickExport'; Kind = 'Action' }
        ReadRows     = @{ Method = 'readRows'; Kind = 'Query' }
        IsReady      = @{ Method = 'isReady'; Kind = 'Probe' }
        ClosePanel   = @{ Method = 'closePanel'; Kind = 'Cleanup' }
    }
}
'@
}

Describe 'Import-PageOperationCatalog' {
    It 'loads operations with their kind, scope, timeout, and label' {
        $catalog = Import-PageOperationCatalog -Path (Write-CatalogFile -Body $script:ValidCatalog)

        $catalog.Helper | Should -Be 'sampleHelper'
        $catalog.IdentityOperation | Should -Be 'DetectScreen'
        $catalog.Operations.DetectScreen.TimeoutSeconds | Should -Be 2
        $catalog.Operations.CheckScreen.Label | Should -Be '画面契約'
        $catalog.Operations.ClickExport.Label | Should -Be 'ClickExport'
        $catalog.Operations.ReadRows.Scope | Should -Be ''
    }

    It 'rejects catalogs that break the operation rules' -TestCases @(
        @{ Case = 'unknown key (typo)'; Body = "@{ Helper = 'h'; Operations = @{ D = @{ Method = 'd'; Kind = 'Identity'; Scope = 's' }; A = @{ Method = 'a'; Kind = 'Action'; Await = `$true } } }"; Expected = "*未知のキー 'Await'*" }
        @{ Case = 'unknown kind'; Body = "@{ Helper = 'h'; Operations = @{ D = @{ Method = 'd'; Kind = 'Identity'; Scope = 's' }; A = @{ Method = 'a'; Kind = 'Click' } } }"; Expected = '*Kind は*' }
        @{ Case = 'contract without scope'; Body = "@{ Helper = 'h'; Operations = @{ D = @{ Method = 'd'; Kind = 'Identity'; Scope = 's' }; C = @{ Method = 'c'; Kind = 'Contract' } } }"; Expected = '*Scope*必要*' }
        @{ Case = 'scope on an action'; Body = "@{ Helper = 'h'; Operations = @{ D = @{ Method = 'd'; Kind = 'Identity'; Scope = 's' }; A = @{ Method = 'a'; Kind = 'Action'; Scope = 'x' } } }"; Expected = '*Identity / Contract の操作にだけ*' }
        @{ Case = 'method is not an identifier'; Body = "@{ Helper = 'h'; Operations = @{ D = @{ Method = 'd(); alert(1)'; Kind = 'Identity'; Scope = 's' } } }"; Expected = '*Method は JavaScript の識別子*' }
        @{ Case = 'helper is not an identifier'; Body = "@{ Helper = 'a-b'; Operations = @{ D = @{ Method = 'd'; Kind = 'Identity'; Scope = 's' } } }"; Expected = '*Helper*識別子*' }
        @{ Case = 'no identity operation'; Body = "@{ Helper = 'h'; Operations = @{ A = @{ Method = 'a'; Kind = 'Action' } } }"; Expected = '*Kind=Identity の操作がちょうど1つ*0 個*' }
        @{ Case = 'two identity operations'; Body = "@{ Helper = 'h'; Operations = @{ D = @{ Method = 'd'; Kind = 'Identity'; Scope = 's' }; E = @{ Method = 'e'; Kind = 'Identity'; Scope = 't' } } }"; Expected = '*2 個*' }
        @{ Case = 'invalid timeout'; Body = "@{ Helper = 'h'; Operations = @{ D = @{ Method = 'd'; Kind = 'Identity'; Scope = 's'; TimeoutSeconds = 0 } } }"; Expected = '*TimeoutSeconds*' }
        @{ Case = 'empty operations'; Body = "@{ Helper = 'h'; Operations = @{} }"; Expected = '*Operations が空*' }
    ) {
        param($Case, $Body, $Expected)
        { Import-PageOperationCatalog -Path (Write-CatalogFile -Body $Body) } | Should -Throw $Expected
    }

    It 'reports a missing catalog file' {
        { Import-PageOperationCatalog -Path (Join-Path $TestDrive 'missing.psd1') } | Should -Throw '*操作カタログが見つかりません*'
    }
}

Describe 'Get-PageOperation use rules' {
    It 'allows each kind only through its intended call style' -TestCases @(
        @{ Name = 'DetectScreen'; Use = 'Invoke'; Allowed = $true }
        @{ Name = 'CheckScreen'; Use = 'Assert'; Allowed = $true }
        @{ Name = 'CheckScreen'; Use = 'Invoke'; Allowed = $false }
        @{ Name = 'ClickExport'; Use = 'Invoke'; Allowed = $true }
        @{ Name = 'ClickExport'; Use = 'WaitUntil'; Allowed = $false }
        @{ Name = 'ReadRows'; Use = 'WaitFor'; Allowed = $true }
        @{ Name = 'IsReady'; Use = 'WaitUntil'; Allowed = $true }
        @{ Name = 'IsReady'; Use = 'Invoke'; Allowed = $false }
        @{ Name = 'ClosePanel'; Use = 'Invoke'; Allowed = $true }
        @{ Name = 'ClosePanel'; Use = 'Assert'; Allowed = $false }
    ) {
        param($Name, $Use, $Allowed)
        $catalog = Import-PageOperationCatalog -Path (Write-CatalogFile -Body $script:ValidCatalog)

        InModuleScope PageBridge -Parameters @{ Catalog = $catalog; Name = $Name; Use = $Use; Allowed = $Allowed } {
            param($Catalog, $Name, $Use, $Allowed)
            if ($Allowed) {
                (Get-PageOperation -Catalog $Catalog -Name $Name -Use $Use).Name | Should -Be $Name
            }
            else {
                { Get-PageOperation -Catalog $Catalog -Name $Name -Use $Use } | Should -Throw "*では呼び出せません*"
            }
        }
    }

    It 'rejects operations that are not in the catalog' {
        $catalog = Import-PageOperationCatalog -Path (Write-CatalogFile -Body $script:ValidCatalog)
        InModuleScope PageBridge -Parameters @{ Catalog = $catalog } {
            param($Catalog)
            { Get-PageOperation -Catalog $Catalog -Name 'Unknown' -Use 'Invoke' } | Should -Throw '*未定義の操作です: Unknown*'
        }
    }
}
