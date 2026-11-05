BeforeDiscovery {
    $modulesRoot = Join-Path $PSScriptRoot '../../../app/modules'
    $script:Modules = @(Get-ChildItem -LiteralPath $modulesRoot -Directory | Sort-Object Name | ForEach-Object { $_.Name })
    $script:JobModules = @('JobChains', 'LastMonthPlantingDigest', 'PlantingRecordExport', 'PlotRosterExport', 'SoilAnalysisTargetSync')
    $script:BrowserJobModules = @('PlantingRecordExport', 'PlotRosterExport', 'SoilAnalysisTargetSync')
}

# 設計上の境界（ARCHITECTURE.md）をテストで固定する。
# 境界を越える変更をしたいときは、先に ARCHITECTURE.md と docs/decisions を更新し、このテストの規則を同時に直す。

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force

    $script:ModulesRoot = Get-RepositoryPath 'app/modules'

    # モジュール → 依存してよいモジュール（ARCHITECTURE.md「依存の向き」）
    $script:AllowedImports = @{
        JobKit = @()
        PageBridge = @('JobKit')
        JobHost = @('JobKit', 'PageBridge')
        JobChains = @('JobKit')
        LastMonthPlantingDigest = @('JobKit')
        PlantingRecordExport = @('JobKit')
        PlotRosterExport = @('JobKit')
        SoilAnalysisTargetSync = @('JobKit')
    }

    # ジョブのモジュールが直接使ってはいけないコマンド（ファイル・時刻・画面出力・プロセス・他モジュールの読み込み）。
    # これらはすべて Context.Services のポート経由で使う。
    $script:ForbiddenCommands = @(
        'Get-ChildItem', 'Get-Item', 'Get-Content', 'Set-Content', 'Add-Content', 'Out-File', 'New-Item', 'Remove-Item',
        'Copy-Item', 'Move-Item', 'Rename-Item', 'Test-Path', 'Resolve-Path', 'Import-Csv', 'Export-Csv',
        'Start-Sleep', 'Get-Date', 'Write-Host', 'Read-Host', 'Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod',
        'Import-Module', 'Invoke-HostedJob'
    )
    $script:ForbiddenTypes = @('System.IO.File', 'IO.File', 'System.IO.Directory', 'IO.Directory', 'System.IO.FileInfo', 'System.Net.WebClient', 'System.Net.Http.HttpClient', 'System.Threading.Thread')

    function Get-SourceAst {
        param([Parameter(Mandatory)][string]$Path)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw "構文エラー: $Path $($errors[0].Message)" }
        return $ast
    }

    function Get-ModuleLayout {
        <#
        モジュールの .psm1 から、依存モジュール・読み込むファイル・公開する関数を読み取る。
        #>
        param([Parameter(Mandatory)][string]$Name)

        $psm1 = Join-Path (Join-Path $script:ModulesRoot $Name) "$Name.psm1"
        $text = [System.IO.File]::ReadAllText($psm1)
        $ast = Get-SourceAst -Path $psm1

        $imports = @([regex]::Matches($text, "'(\w+)/\1\.psm1'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $loop = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)
        $files = @($loop.Condition.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
        $export = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Export-ModuleMember' }, $true)
        $exports = @($export.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -ne 'Export-ModuleMember' }, $true) | ForEach-Object { $_.Value })

        return [pscustomobject]@{ Imports = $imports; Files = $files; Exports = $exports }
    }

    function Get-ModuleSourceFiles {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $script:ModulesRoot $Name
        return @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' | Sort-Object FullName)
    }

    function Get-RelativeModulePath {
        param([string]$Name, [string]$FullName)
        return $FullName.Substring((Join-Path $script:ModulesRoot $Name).Length + 1).Replace('\', '/')
    }
}

Describe 'Module boundaries' {
    It 'gives every module in app/modules a place in the dependency rules' {
        @(Get-ChildItem -LiteralPath $script:ModulesRoot -Directory | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @($script:AllowedImports.Keys | Sort-Object)
    }

    It '<_> imports only the modules it may depend on' -TestCases $script:Modules {
        $layout = Get-ModuleLayout -Name $_
        foreach ($import in $layout.Imports) {
            $script:AllowedImports[$_] | Should -Contain $import -Because "$_ → $import は ARCHITECTURE.md の依存の向きにない"
        }
    }

    It '<_> loads every source file in its folder' -TestCases $script:Modules {
        $name = $_
        $layout = Get-ModuleLayout -Name $name
        $onDisk = @(Get-ModuleSourceFiles -Name $name | ForEach-Object { Get-RelativeModulePath -Name $name -FullName $_.FullName })
        @($layout.Files | Sort-Object) | Should -Be @($onDisk | Sort-Object) -Because '読み込まれないファイル（使われていないコード）や、存在しないファイルの読み込みを残さない'
    }

    It '<_> exports exactly the functions defined in its Public folder' -TestCases $script:Modules {
        $name = $_
        $layout = Get-ModuleLayout -Name $name
        $public = @(Get-ModuleSourceFiles -Name $name | Where-Object { (Get-RelativeModulePath -Name $name -FullName $_.FullName) -like 'Public/*' } | ForEach-Object {
                (Get-SourceAst -Path $_.FullName).FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { $_.Name }
            })
        @($layout.Exports | Sort-Object) | Should -Be @($public | Sort-Object)
    }

    It 'keeps PageBridge, JobHost and JobKit free of any job-specific knowledge' {
        $catalog = Import-PowerShellDataFile -LiteralPath (Get-RepositoryPath 'app/config/jobs.psd1')
        $names = @($catalog.Jobs.Keys) + @(Get-ChildItem -LiteralPath $script:ModulesRoot -Recurse -Filter 'PageOperations.psd1' | ForEach-Object { (Import-PowerShellDataFile -LiteralPath $_.FullName).Helper })
        foreach ($module in @('PageBridge', 'JobHost', 'JobKit')) {
            foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $script:ModulesRoot $module) -Recurse -File -Include '*.ps1', '*.psm1')) {
                $text = [System.IO.File]::ReadAllText($file.FullName)
                foreach ($name in $names) {
                    $text.Contains($name) | Should -BeFalse -Because "$module/$($file.Name) にジョブ固有の名前 $name がある"
                }
            }
        }
    }
}

Describe 'Job modules' {
    It '<_> reaches files, time, the console and other jobs only through its ports' -TestCases ($script:JobModules + @('JobKit')) {
        $name = $_
        foreach ($file in @(Get-ModuleSourceFiles -Name $name)) {
            $ast = Get-SourceAst -Path $file.FullName
            $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
            foreach ($command in $commands) {
                $script:ForbiddenCommands | Should -Not -Contain $command -Because "$name/$($file.Name) は $command を直接使わず、ポートを使う"
            }

            $types = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.TypeExpressionAst] }, $true) | ForEach-Object { $_.TypeName.FullName })
            foreach ($type in $types) {
                $script:ForbiddenTypes | Should -Not -Contain $type -Because "$name/$($file.Name) は [$type] を直接使わず、ポートを使う"
            }

            $clockReads = @($ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.MemberExpressionAst] -and
                        $node.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                        @('datetime', 'System.DateTime', 'DateTime') -contains $node.Expression.TypeName.FullName -and
                        @('Now', 'UtcNow', 'Today') -contains $node.Member.Value
                    }, $true))
            $clockReads.Count | Should -Be 0 -Because "$name/$($file.Name) は現在時刻を Clock ポートから得る"
        }
    }

    It '<_> touches the Context only in its composition root and job command' -TestCases $script:JobModules {
        $name = $_
        foreach ($file in @(Get-ModuleSourceFiles -Name $name)) {
            $relative = Get-RelativeModulePath -Name $name -FullName $file.FullName
            if ($relative -like 'Public/*' -or $relative -eq 'Private/Ports.ps1') { continue }
            $uses = @((Get-SourceAst -Path $file.FullName).FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.UserPath -eq 'Context' }, $true))
            $uses.Count | Should -Be 0 -Because "$name/$relative は Context ではなくポートと設定値を受け取る"
        }
    }

    It '<_> exports only the job commands that the job catalog points to' -TestCases $script:JobModules {
        $name = $_
        $catalog = Import-PowerShellDataFile -LiteralPath (Get-RepositoryPath 'app/config/jobs.psd1')
        $commands = @($catalog.Jobs.Values | Where-Object { $_.Module -eq "modules/$name/$name.psm1" } | ForEach-Object { $_.Command })
        @((Get-ModuleLayout -Name $name).Exports | Sort-Object) | Should -Be @($commands | Sort-Object)
    }

    It '<_> keeps selectors and DOM access out of PowerShell' -TestCases $script:BrowserJobModules {
        $name = $_
        foreach ($file in @(Get-ModuleSourceFiles -Name $name)) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            $text | Should -Not -Match '\b(document|window)\.\w|querySelector|getElementById' -Because "$name/$($file.Name): 画面の探し方は app/browser のページスクリプトにだけ書く"
        }
    }
}

Describe 'Operation catalogs and page scripts' {
    It 'maps every operation of <_> to a method that its page scripts define' -TestCases $script:BrowserJobModules {
        $name = $_
        $catalog = Import-PowerShellDataFile -LiteralPath (Get-RepositoryPath 'app/config/jobs.psd1')
        $entry = @($catalog.Jobs.Values | Where-Object { $_.Module -eq "modules/$name/$name.psm1" })[0]
        $operations = Import-PowerShellDataFile -LiteralPath (Get-RepositoryPath ('app/' + $entry.Browser.Operations))
        $scriptText = (@($entry.Browser.Scripts) | ForEach-Object { [System.IO.File]::ReadAllText((Get-RepositoryPath ('app/' + $_))) }) -join "`n"

        [regex]::IsMatch($scriptText, "kit\.define\('$($operations.Helper)'") | Should -BeTrue -Because "ヘルパー $($operations.Helper) を kit.define で登録する"
        foreach ($operation in @($operations.Operations.Keys)) {
            $method = $operations.Operations[$operation].Method
            [regex]::IsMatch($scriptText, "(?m)^\s*(async\s+)?$method\s*\(") | Should -BeTrue -Because "$name の操作 $operation → $method"
        }
    }

    It 'documents the contract (meaning) and the absorbed structure at the top of every screen and feature script' {
        foreach ($file in @(Get-ChildItem -LiteralPath (Get-RepositoryPath 'app/browser') -Recurse -Filter '*.js' | Where-Object { $_.Directory.Name -ne 'kernel' })) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            $header = [regex]::Match($text, '(?s)^/\*.*?\*/').Value
            if ($file.Name -match '^[a-z-]+\.js$' -and $text -match "kit\.define\(" -and $text -notmatch "kit\.part\(") { continue }
            $header | Should -Match '部品名' -Because $file.Name
            $header | Should -Match '契約（意味）' -Because $file.Name
            $header | Should -Match '吸収する構造の違い' -Because $file.Name
        }
    }

    It 'never sends data out of the page or stores it' {
        foreach ($file in @(Get-ChildItem -LiteralPath (Get-RepositoryPath 'app/browser') -Recurse -Filter '*.js')) {
            [System.IO.File]::ReadAllText($file.FullName) | Should -Not -Match '\bfetch\s*\(|XMLHttpRequest|new\s+WebSocket|sendBeacon|localStorage|sessionStorage|\beval\s*\(|new\s+Function\s*\(' -Because $file.Name
        }
    }
}
