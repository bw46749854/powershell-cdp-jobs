<#
.SYNOPSIS
テストをまとめて実行する（Pester と Node.js のブラウザスクリプトテスト）。

.DESCRIPTION
既定では次を実行する。
  - Pester : tests/pester 配下（単体・設計境界・ドキュメント品質）
  - Node   : tests/js 配下（app/browser のスクリプトを jsdom 上で検証）
E2E（実ブラウザ + モック画面でジョブを通し実行）は時間がかかるため -IncludeE2E 指定時だけ実行する。

Pester は tools/vendor/Pester を優先して読み込み、無ければインストール済みの 5.5 以上を使う。

.EXAMPLE
pwsh -File tools/Invoke-Tests.ps1
.EXAMPLE
powershell -File tools\Invoke-Tests.ps1 -Suite Pester -Coverage
.EXAMPLE
pwsh -File tools/Invoke-Tests.ps1 -Suite Pester -IncludeE2E
#>
param(
    [ValidateSet('All', 'Pester', 'Js')]
    [string]$Suite = 'All',

    [string[]]$Path = @(),

    [switch]$IncludeE2E,

    [switch]$Coverage,

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Normal'
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$exitCode = 0

function Import-TestPester {
    $vendored = Join-Path $repositoryRoot 'tools/vendor/Pester/5.7.1/Pester.psd1'
    Remove-Module Pester -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $vendored) {
        Import-Module $vendored -Force
        return
    }

    $installed = Get-Module -ListAvailable Pester |
        Where-Object { $_.Version -ge [version]'5.5.0' } |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $installed) {
        throw 'Pester 5.5 以上が見つかりません。tools/vendor/Pester を配置するか、Pester 5 をインストールしてください。'
    }

    Import-Module $installed.Path -Force
}

if ($Suite -in @('All', 'Pester')) {
    Import-TestPester

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = if ($Path.Count -gt 0) { $Path } else { @(Join-Path $repositoryRoot 'tests') }
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = $Verbosity
    if (-not $IncludeE2E) {
        $configuration.Filter.ExcludeTag = @('E2E')
    }

    if ($Coverage) {
        $outDirectory = Join-Path $repositoryRoot 'tests/out'
        if (-not (Test-Path -LiteralPath $outDirectory)) {
            New-Item -ItemType Directory -Path $outDirectory -Force | Out-Null
        }

        $configuration.CodeCoverage.Enabled = $true
        $configuration.CodeCoverage.Path = @(Join-Path $repositoryRoot 'app/modules')
        $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
        $configuration.CodeCoverage.OutputPath = Join-Path $outDirectory 'coverage.xml'
    }

    $result = Invoke-Pester -Configuration $configuration
    if ($result.FailedCount -gt 0 -or $result.FailedBlocksCount -gt 0 -or $result.FailedContainersCount -gt 0) {
        $exitCode = 1
    }
}

if ($Suite -in @('All', 'Js')) {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Warning 'node が見つからないため、ブラウザスクリプトのテスト（tests/js）を実行しませんでした。'
        if ($Suite -eq 'Js') { $exitCode = 1 }
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot 'node_modules/jsdom'))) {
        Write-Warning 'jsdom が未インストールです。リポジトリ直下で npm install を実行してください。'
        $exitCode = 1
    }
    else {
        Push-Location $repositoryRoot
        try {
            & $node.Source --test (Join-Path 'tests' 'js')
            if ($LASTEXITCODE -ne 0) { $exitCode = 1 }
        }
        finally {
            Pop-Location
        }
    }
}

exit $exitCode
