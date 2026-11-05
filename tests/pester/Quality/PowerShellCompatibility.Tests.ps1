BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $script:PowerShellFiles = @(
        foreach ($folder in @('app', 'mock', 'tests', 'tools')) {
            Get-ChildItem -LiteralPath (Join-Path $root $folder) -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' |
                Where-Object { $_.FullName -notmatch '[\\/]tools[\\/]vendor[\\/]' } |
                ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Length + 1).Replace('\', '/') } }
        }
    )
}

# 本番は Windows PowerShell 5.1 で動く。開発・テストは PowerShell 7 でも行うため、
# 7 でしか動かない書き方が紛れ込まないよう、構文と既知の API を機械的に確かめる（docs/guides/powershell-compatibility.md）。

BeforeAll {
    # PowerShell 7 で追加された演算子（5.1 では構文エラーになる）
    $script:ModernTokenKinds = @('QuestionDot', 'QuestionLBracket', 'QuestionQuestion', 'QuestionQuestionEquals', 'AndAnd', 'OrOr')
    $script:ModernAstTypes = @('TernaryExpressionAst', 'PipelineChainAst')

    # 5.1 に無いパラメーター（コマンド名 → パラメーター名）
    $script:ModernParameters = @{
        'ForEach-Object' = @('Parallel', 'ThrottleLimit', 'AsJob')
        'ConvertFrom-Json' = @('AsHashtable', 'Depth', 'NoEnumerate')
        'ConvertTo-Json' = @('AsArray', 'EnumsAsStrings', 'EscapeHandling')
        'Get-Content' = @('AsByteStream')
        'Set-Content' = @('AsByteStream')
        'Add-Content' = @('AsByteStream')
        'Export-Csv' = @('UseQuotes', 'QuoteFields')
        'Join-Path' = @('AdditionalChildPath')
        'Import-PowerShellDataFile' = @('SkipLimitCheck')
        'Select-String' = @('Raw', 'NoEmphasis')
        'Test-Connection' = @('TargetName')
    }
    $script:ModernCommands = @('Test-Json', 'Get-Error', 'Remove-Alias', 'Get-Uptime', 'Join-String', 'ConvertFrom-Markdown')

    # .NET Framework（5.1）に無い API
    $script:ModernApiPattern = '\[(System\.)?IO\.Path\]::(GetRelativePath|Join|TrimEndingDirectorySeparator|EndsInDirectorySeparator)|' +
        '\[(System\.)?Text\.Encoding\]::Latin1|\[(System\.)?DateTime\]::UnixEpoch|::ToHexString\(|\.ReplaceLineEndings\(|' +
        '\[(System\.)?HashCode\]|\[(System\.)?(Range|Index)\]|PriorityQueue|ReadAllTextAsync|WriteAllTextAsync|' +
        '-Encoding\s+(utf8NoBOM|utf8BOM)|\$Is(Windows|Linux|MacOS)\b|\$PSStyle\b'
}

Describe 'PowerShell source <Name>' -ForEach $script:PowerShellFiles {
    BeforeAll {
        $tokens = $null
        $errors = $null
        $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $script:Tokens = $tokens
        $script:Errors = $errors
        $script:Text = [System.IO.File]::ReadAllText($Path)
    }

    It 'parses without errors' {
        @($script:Errors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) | Should -BeNullOrEmpty
    }

    It 'uses only syntax that Windows PowerShell 5.1 understands' {
        @($script:Tokens | Where-Object { $script:ModernTokenKinds -contains $_.Kind.ToString() } | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Text)" }) | Should -BeNullOrEmpty
        @($script:Ast.FindAll({ param($node) $script:ModernAstTypes -contains $node.GetType().Name }, $true) | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Extent.Text)" }) | Should -BeNullOrEmpty
    }

    It 'uses only commands and parameters that Windows PowerShell 5.1 has' {
        $problems = foreach ($command in @($script:Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))) {
            $name = $command.GetCommandName()
            if ($script:ModernCommands -contains $name) { "$($command.Extent.StartLineNumber): $name" }
            if ($name -and $script:ModernParameters.ContainsKey($name)) {
                foreach ($parameter in @($command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] })) {
                    if ($script:ModernParameters[$name] -contains $parameter.ParameterName) { "$($command.Extent.StartLineNumber): $name -$($parameter.ParameterName)" }
                }
            }
            if ($name -eq 'Join-Path') {
                $positional = @($command.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] })
                if ($positional.Count -gt 2) { "$($command.Extent.StartLineNumber): Join-Path に3つ以上のパス（5.1 は2つまで）" }
            }
        }
        @($problems) | Should -BeNullOrEmpty
    }

    It 'uses only .NET APIs that .NET Framework has' {
        if ($Name -eq 'tests/pester/Quality/PowerShellCompatibility.Tests.ps1') { return }   # 検出パターンを定義しているこのファイル自身は除く
        $lines = $script:Text -split "`r?`n"
        @(for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -match $script:ModernApiPattern -and $lines[$index] -notmatch '^\s*#') { "$($index + 1): $($lines[$index].Trim())" }
            }) | Should -BeNullOrEmpty
    }
}
