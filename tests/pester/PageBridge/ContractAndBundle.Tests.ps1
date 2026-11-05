BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/PageBridge/PageBridge.psm1') -Force
}

Describe 'Page contract results' {
    It 'formats only failed checks with severity and details' {
        InModuleScope PageBridge {
            $result = [pscustomobject]@{
                scope = 'sample.screen'; ok = $false; fatalCount = 1; warningCount = 1
                checks = @(
                    [pscustomobject]@{ name = 'a.ok'; ok = $true; severity = 'fatal'; message = 'fine'; details = $null },
                    [pscustomobject]@{ name = 'b.unique'; ok = $false; severity = 'fatal'; message = '一意であること'; details = [pscustomobject]@{ count = 2 } },
                    [pscustomobject]@{ name = 'c.hint'; ok = $false; severity = 'warning'; message = '補助'; details = $null }
                )
            }

            $text = Format-PageContractResult -Result $result
            $text | Should -Match 'scope=sample\.screen ok=False fatal=1 warning=1'
            $text | Should -Match '\[fatal\] b\.unique: 一意であること details=\{"count":2\}'
            $text | Should -Match '\[warning\] c\.hint: 補助'
            $text | Should -Not -Match 'a\.ok'
        }
    }

    It 'logs warnings but passes when there is no fatal failure' {
        $log = New-RecordingLog
        $result = New-ContractResult -Scope 'sample.screen' -Failures @(@{ name = 'hint'; severity = 'warning'; message = '補助スコープなし' })

        InModuleScope PageBridge -Parameters @{ Result = $result; Log = $log } {
            param($Result, $Log)
            $operation = [pscustomobject]@{ Name = 'Check'; Scope = 'sample.screen' }
            { Assert-PageContractPassed -Result $Result -Operation $operation -Description '画面' -Log $Log } | Should -Not -Throw
        }

        (Get-LogMessages -Log $log -Level Warn) | Should -Match '補助スコープなし'
    }

    It 'throws a contract error when a fatal check fails' {
        $result = New-ContractResult -Scope 'sample.screen' -Failures @(@{ name = 'button.unique'; message = 'ボタンが2件' })

        InModuleScope PageBridge -Parameters @{ Result = $result; Log = (New-RecordingLog) } {
            param($Result, $Log)
            $operation = [pscustomobject]@{ Name = 'Check'; Scope = 'sample.screen' }
            $failure = $null
            try { Assert-PageContractPassed -Result $Result -Operation $operation -Description '画面' -Log $Log } catch { $failure = $_ }
            $failure.Exception.Message | Should -Match 'ページ契約違反: 画面'
            Get-BridgeErrorCategory -ErrorObject $failure | Should -Be 'contract'
        }
    }

    It 'treats a scope mismatch or a malformed result as a configuration error' {
        InModuleScope PageBridge {
            $operation = [pscustomobject]@{ Name = 'Check'; Scope = 'sample.screen' }
            $other = [pscustomobject]@{ scope = 'other'; ok = $true; fatalCount = 0; warningCount = 0; checks = @() }
            { Assert-PageContractScope -Result $other -Operation $operation } | Should -Throw '*scope が一致しません*'
            { Assert-PageContractScope -Result $true -Operation $operation } | Should -Throw '*契約結果の形ではありません*'
        }
    }
}

Describe 'Page script bundle' {
    It 'concatenates scripts in order, strips BOMs, and ends with the kernel acknowledgement' {
        $first = Join-Path $TestDrive 'kernel.js'
        $second = Join-Path $TestDrive 'feature.js'
        [System.IO.File]::WriteAllText($first, 'var a = 1;', (New-Object System.Text.UTF8Encoding -ArgumentList $true))
        [System.IO.File]::WriteAllText($second, 'var b = "区画";', (New-Object System.Text.UTF8Encoding -ArgumentList $false))

        InModuleScope PageBridge -Parameters @{ Paths = @($first, $second) } {
            param($Paths)
            $text = Read-PageScriptText -Paths $Paths
            $text.IndexOf([char]0xFEFF) | Should -Be -1
            $text.IndexOf('var a = 1;') | Should -BeLessThan $text.IndexOf('var b = "区画";')

            $expression = New-PageBundleExpression -ScriptText $text -Helper 'sampleHelper' -JobName 'Sample Job'
            $expression | Should -Match 'window\.__pagekit\.ack\("sampleHelper"\)'
            $expression | Should -Match '//# sourceURL=pagekit/Sample_Job\.bundle\.js'
        }
    }

    It 'reports a missing script file as a configuration error' {
        InModuleScope PageBridge {
            { Read-PageScriptText -Paths @('/no/such/file.js') } | Should -Throw '*ページスクリプトが見つかりません*'
        }
    }

    It 'verifies that the injected helper implements every catalog method' {
        InModuleScope PageBridge {
            $catalog = [pscustomobject]@{
                Helper = 'sampleHelper'
                Operations = @{
                    Detect = [pscustomobject]@{ Name = 'Detect'; Method = 'detect' }
                    Click = [pscustomobject]@{ Name = 'Click'; Method = 'click' }
                }
            }

            { Assert-PageBundleAck -Ack ([pscustomobject]@{ ok = $true; helper = 'sampleHelper'; methods = @('detect', 'click', 'extra') }) -Catalog $catalog } | Should -Not -Throw
            { Assert-PageBundleAck -Ack ([pscustomobject]@{ ok = $true; helper = 'sampleHelper'; methods = @('detect') }) -Catalog $catalog } | Should -Throw '*Click=click*'
            { Assert-PageBundleAck -Ack ([pscustomobject]@{ ok = $true; helper = 'otherHelper'; methods = @() }) -Catalog $catalog } | Should -Throw '*一致しません*'
            { Assert-PageBundleAck -Ack ([pscustomobject]@{ ok = $false; reason = 'kernel_missing' }) -Catalog $catalog } | Should -Throw '*kernel*'
            { Assert-PageBundleAck -Ack $null -Catalog $catalog } | Should -Throw '*注入に失敗*'
        }
    }
}
