#Requires -Version 5.1
<#
.SYNOPSIS
Wait for Juice Shop HTML on both the direct and WAF routes.
.DESCRIPTION
Uses one overall deadline, bounded HTTP requests, no proxy, and no redirects.
Exit 0 means both routes returned HTTP 200 with the Juice Shop SPA shell.
Exit 1 means a route failed, timed out, or returned an unexpected page.
This does not test browser rendering, authentication, or attack blocking.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 120,

    [ValidateRange(1, 30)]
    [int]$PollIntervalSeconds = 2,

    [uri]$WebUrl = 'http://localhost:3000/',
    [uri]$WafUrl = 'http://localhost:8080/'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.UseProxy = $false
$handler.AllowAutoRedirect = $false
$client = New-Object System.Net.Http.HttpClient($handler)
$client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$routes = @(
    [pscustomobject]@{ Name = 'web'; Url = $WebUrl; Ready = $false; Detail = 'Not checked' },
    [pscustomobject]@{ Name = 'waf'; Url = $WafUrl; Ready = $false; Detail = 'Not checked' }
)

try {
    Write-Host "Waiting for Juice Shop on both routes (timeout ${TimeoutSeconds}s)."
    do {
        foreach ($route in $routes) {
            $remainingMs = ($TimeoutSeconds * 1000) - $clock.Elapsed.TotalMilliseconds
            if ($remainingMs -le 0) { break }

            $budgetMs = [int][Math]::Max(1, [Math]::Min(5000, $remainingMs))
            $cancel = New-Object System.Threading.CancellationTokenSource
            $cancel.CancelAfter($budgetMs)
            $response = $null
            $previous = $route.Detail
            $route.Ready = $false
            try {
                # Default completion buffers the body within the cancellation budget.
                $response = $client.GetAsync($route.Url, $cancel.Token).GetAwaiter().GetResult()
                $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $status = [int]$response.StatusCode
                $isHtml = $null -ne $response.Content.Headers.ContentType -and
                    $response.Content.Headers.ContentType.MediaType -eq 'text/html'
                $isJuiceShop = $body -match '<title>\s*OWASP Juice Shop\s*</title>' -and
                    $body -match '<app-root(?:\s|>)'

                if ($status -eq 200 -and $isHtml -and $isJuiceShop) {
                    $route.Ready = $true
                    $route.Detail = 'HTTP 200; Juice Shop title and app-root found'
                } else {
                    $route.Detail = "HTTP $status; expected Juice Shop HTML (html=$isHtml, app=$isJuiceShop)"
                }
            } catch {
                $route.Detail = $_.Exception.GetBaseException().Message
            } finally {
                if ($null -ne $response) { $response.Dispose() }
                $cancel.Dispose()
            }

            if ($route.Detail -ne $previous) {
                Write-Host ("[{0}] {1} - {2}" -f $route.Name, $route.Url, $route.Detail)
            }
        }

        if (@($routes | Where-Object { -not $_.Ready }).Count -eq 0) {
            Write-Host ("READY: both routes passed in {0:N2}s." -f $clock.Elapsed.TotalSeconds)
            exit 0
        }

        $remainingMs = ($TimeoutSeconds * 1000) - $clock.Elapsed.TotalMilliseconds
        if ($remainingMs -gt 0) {
            $sleepMs = [int][Math]::Max(1, [Math]::Min($PollIntervalSeconds * 1000, $remainingMs))
            Start-Sleep -Milliseconds $sleepMs
        }
    } while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)

    [Console]::Error.WriteLine("NOT READY after ${TimeoutSeconds}s. Check 'docker compose ps' and 'docker compose logs --tail 50 web waf'.")
    foreach ($route in $routes) {
        [Console]::Error.WriteLine(("[{0}] {1} - {2}" -f $route.Name, $route.Url, $route.Detail))
    }
    exit 1
} finally {
    $clock.Stop()
    $client.Dispose()
    $handler.Dispose()
}
