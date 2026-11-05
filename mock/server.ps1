<#
.SYNOPSIS
モック画面（mock/site）を http://localhost:<Port>/ で配信する、確認用の小さな静的 Web サーバー。

.DESCRIPTION
- localhost からの接続だけを受ける（他の PC からは見えない）。管理者権限は不要。
- GET / HEAD だけを受け付け、site フォルダーの外のファイルは返さない（../ や絶対パスによる指定を拒否する）。
- Ctrl+C で停止する。

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File mock\server.ps1
.EXAMPLE
pwsh -File mock/server.ps1 -Port 8181

.NOTES
Windows PowerShell 5.1 で動くこと。テスト（E2E）からも別プロセスとして起動して使う。
#>
param(
    [ValidateRange(1024, 65535)][int]$Port = 8080,
    [string]$Root = ''
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path $PSScriptRoot 'site' }
$siteRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
if (-not (Test-Path -LiteralPath $siteRoot -PathType Container)) { throw "配信するフォルダーが見つかりません: $siteRoot" }

$contentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.js' = 'text/javascript; charset=utf-8'
    '.css' = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.svg' = 'image/svg+xml'
    '.png' = 'image/png'
    '.ico' = 'image/x-icon'
}

function Resolve-SiteFile {
    <#
    .SYNOPSIS
    URL のパスを site フォルダー内のファイルに対応付ける。外を指す・見つからない場合は $null。
    #>
    param([Parameter(Mandatory)][string]$UrlPath)

    $relative = [System.Uri]::UnescapeDataString($UrlPath).TrimStart('/')
    $segments = @($relative -split '[\\/]' | Where-Object { $_ -ne '' })
    foreach ($segment in $segments) {
        if ($segment -eq '.' -or $segment -eq '..' -or $segment.Contains(':')) { return $null }
    }

    $candidate = $siteRoot
    foreach ($segment in $segments) { $candidate = Join-Path $candidate $segment }
    $candidate = [System.IO.Path]::GetFullPath($candidate)

    $prefix = $siteRoot + [System.IO.Path]::DirectorySeparatorChar
    if ($candidate -ne $siteRoot -and -not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }

    if (Test-Path -LiteralPath $candidate -PathType Container) {
        return [pscustomobject]@{ Path = (Join-Path $candidate 'index.html'); IsDirectory = $true }
    }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return [pscustomobject]@{ Path = $candidate; IsDirectory = $false }
    }
    return $null
}

function Send-Response {
    param(
        [Parameter(Mandatory)][System.Net.HttpListenerContext]$Context,
        [Parameter(Mandatory)][int]$Status,
        [string]$ContentType = 'text/plain; charset=utf-8',
        [byte[]]$Body = @(),
        [hashtable]$Headers = @{}
    )

    $response = $Context.Response
    $response.StatusCode = $Status
    $response.ContentType = $ContentType
    $response.Headers['Cache-Control'] = 'no-store'
    $response.Headers['X-Content-Type-Options'] = 'nosniff'
    foreach ($name in $Headers.Keys) { $response.Headers[$name] = $Headers[$name] }
    $response.ContentLength64 = $Body.Length
    if ($Context.Request.HttpMethod -ne 'HEAD' -and $Body.Length -gt 0) {
        $response.OutputStream.Write($Body, 0, $Body.Length)
    }
    $response.OutputStream.Close()
}

function Invoke-Request {
    param([Parameter(Mandatory)][System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $text = { param($Value) [System.Text.Encoding]::UTF8.GetBytes($Value) }

    if ($request.HttpMethod -ne 'GET' -and $request.HttpMethod -ne 'HEAD') {
        Send-Response -Context $Context -Status 405 -Body (& $text 'Method Not Allowed') -Headers @{ Allow = 'GET, HEAD' }
        return 405
    }

    $urlPath = $request.Url.AbsolutePath
    $file = Resolve-SiteFile -UrlPath $urlPath
    if ($null -eq $file -or -not (Test-Path -LiteralPath $file.Path -PathType Leaf)) {
        Send-Response -Context $Context -Status 404 -Body (& $text 'Not Found')
        return 404
    }

    if ($file.IsDirectory -and -not $urlPath.EndsWith('/')) {
        Send-Response -Context $Context -Status 301 -Headers @{ Location = $urlPath + '/' }
        return 301
    }

    $extension = [System.IO.Path]::GetExtension($file.Path).ToLowerInvariant()
    $contentType = 'application/octet-stream'
    if ($contentTypes.ContainsKey($extension)) { $contentType = $contentTypes[$extension] }
    Send-Response -Context $Context -Status 200 -ContentType $contentType -Body ([System.IO.File]::ReadAllBytes($file.Path))
    return 200
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "モック画面を配信しています: http://localhost:$Port/  （停止は Ctrl+C）"
Write-Host "配信フォルダー: $siteRoot"

try {
    while ($listener.IsListening) {
        $pending = $listener.GetContextAsync()
        # 短い間隔で待ち直し、Ctrl+C で止められるようにする
        while (-not $pending.Wait(500)) { }
        $context = $pending.Result
        try {
            $status = Invoke-Request -Context $context
            Write-Host ('{0:HH:mm:ss} {1} {2} {3}' -f (Get-Date), $context.Request.HttpMethod, $context.Request.Url.AbsolutePath, $status)
        }
        catch {
            Write-Host "要求の処理に失敗しました: $($_.Exception.Message)"
            try { $context.Response.Abort() } catch { }
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
