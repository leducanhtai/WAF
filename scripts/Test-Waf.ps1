#Requires -Version 5.1
<#
.SYNOPSIS
Run the localhost Juice Shop / CRS lab tests and save sanitized evidence.
#>
[CmdletBinding()]
param(
    [ValidateSet('All', 'TC01', 'TC02')]
    [string[]]$Test = @('All'),
    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 10,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../evidence/lab2/latest')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$repoRoot = Split-Path $PSScriptRoot -Parent
$runId = 'lab2-' + [guid]::NewGuid().ToString('N')
$attackJson = [ordered]@{ email = "' OR 1=1--"; password = 'lab-password' } | ConvertTo-Json -Compress
$selected = if ($Test -contains 'All') { @('TC01', 'TC02') } else { @($Test | Select-Object -Unique) }
$results = New-Object System.Collections.Generic.List[object]
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function Invoke-Compose {
    param([string[]]$Arguments)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = 'docker.exe'
    $process.StartInfo.Arguments = 'compose --project-directory "' + $repoRoot + '" ' + ($Arguments -join ' ')
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) {
            $process.Kill()
            throw 'Docker command exceeded 15 seconds.'
        }
        if ($process.ExitCode -ne 0) { throw 'Docker command failed; inspect Docker and Compose locally.' }
        [void]$stderr.GetAwaiter().GetResult()
        return $stdout.GetAwaiter().GetResult()
    } finally { $process.Dispose() }
}

function New-LabClient {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $handler.UseCookies = $false
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    # .NET Framework otherwise adds Expect: 100-continue to POST requests.
    # CRS 920450 rejects that header before SQLi/valid-login can be assessed.
    $client.DefaultRequestHeaders.ExpectContinue = $false
    return $client
}

function Invoke-LabHttp {
    param($Client, [string]$Url, [string]$Method = 'GET', [string]$Json, [string]$TokenCookie, [string]$RequestId)
    $message = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::new($Method), $Url)
    $response = $null
    try {
        if ($Json) { $message.Content = New-Object System.Net.Http.StringContent($Json, [Text.Encoding]::UTF8, 'application/json') }
        if ($TokenCookie) { $message.Headers.Add('Cookie', ('token=' + $TokenCookie)) }
        if ($RequestId) { $message.Headers.Add('X-Lab-Request-Id', $RequestId) }
        $response = $Client.SendAsync($message).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $parsed = $null
        try { $parsed = $body | ConvertFrom-Json } catch { }
        # Body and token stay in memory. Callers only serialize selected fields.
        return [pscustomobject]@{
            Status = [int]$response.StatusCode
            Json = $parsed
            HasSetCookie = $response.Headers.Contains('Set-Cookie')
        }
    } finally {
        if ($null -ne $response) { $response.Dispose() }
        $message.Dispose()
    }
}

function Get-BodyHash {
    param([string]$Json)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Json)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function New-TestRecord {
    param([string]$Id, [string]$BaseUrl, [string]$Json, [string]$Expected, [string]$RequestId)
    return [ordered]@{
        test = $Id; startedAt = [DateTimeOffset]::Now.ToString('o'); finishedAt = $null
        timezone = 'Asia/Bangkok (UTC+07:00)'; result = 'NOT RUN'; expected = $Expected
        request = [ordered]@{ url = "$BaseUrl/rest/user/login"; method = 'POST'; path = '/rest/user/login'; contentType = 'application/json; charset=utf-8'; input = ($Json | ConvertFrom-Json); bodySha256 = (Get-BodyHash $Json); requestId = $RequestId }
        response = $null; identity = $null; ruleIds = @(); actual = 'Not executed'
    }
}

function Test-AdminLogin {
    param([string]$Id, [string]$BaseUrl, [string]$Json, [string]$RequestId)
    $record = New-TestRecord $Id $BaseUrl $Json 'HTTP 200, authenticated admin@juice-sh.op, role admin verified from server' $RequestId
    $client = New-LabClient
    try {
        $login = Invoke-LabHttp -Client $client -Url $record.request.url -Method POST -Json $Json -RequestId $RequestId
        $token = [string]$login.Json.authentication.token
        $record.response = [ordered]@{ statusCode = $login.Status; hasAuthenticationToken = (-not [string]::IsNullOrWhiteSpace($token)); setCookiePresent = $login.HasSetCookie }
        $record.result = 'FAIL'
        $record.actual = 'Login did not establish the expected admin identity'
        if ($login.Status -eq 200 -and $token) {
            # This Juice Shop version reads the token cookie, not Authorization.
            # Request only identity fields; never fetch password/profile/session data.
            $who = Invoke-LabHttp -Client $client -Url "$BaseUrl/rest/user/whoami?fields=id,email,role" -TokenCookie $token
            $userId = $who.Json.user.id
            if ($who.Status -eq 200 -and $userId -and $who.Json.user.email -eq 'admin@juice-sh.op') {
                $record.identity = [ordered]@{ whoamiStatus = $who.Status; id = $userId; email = $who.Json.user.email; role = $who.Json.user.role }
                if ($record.identity.role -eq 'admin') {
                    $record.result = 'PASS'
                    $record.actual = 'Login 200; fresh token cookie verified by server whoami: admin@juice-sh.op / admin'
                }
            }
        }
    } catch {
        $record.result = 'FAIL'
        $record.actual = 'HTTP/identity verification failed: ' + $_.Exception.GetBaseException().GetType().Name
    } finally { $token = $null; $client.Dispose(); $record.finishedAt = [DateTimeOffset]::Now.ToString('o') }
    return $record
}

function Test-BlockedLogin {
    param([string]$RequestId)
    $record = New-TestRecord 'TC02' 'http://localhost:8080' $attackJson 'HTTP 403; no authentication token or session cookie' $RequestId
    $record.logSinceUtc = [DateTimeOffset]::UtcNow.AddSeconds(-2).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $client = New-LabClient
    try {
        $login = Invoke-LabHttp -Client $client -Url $record.request.url -Method POST -Json $attackJson -RequestId $RequestId
        $hasToken = -not [string]::IsNullOrWhiteSpace([string]$login.Json.authentication.token) -or
            -not [string]::IsNullOrWhiteSpace([string]$login.Json.token) -or
            -not [string]::IsNullOrWhiteSpace([string]$login.Json.data.tmpToken)
        $record.response = [ordered]@{ statusCode = $login.Status; hasAuthenticationToken = $hasToken; setCookiePresent = $login.HasSetCookie }
        $record.result = 'FAIL'
        $record.actual = 'Blocked-login response did not meet HTTP 403 / no-token criteria'
        if ($login.Status -eq 403 -and -not $hasToken -and -not $login.HasSetCookie) {
            $record.result = 'PASS'
            $record.actual = 'HTTP 403; no authentication token or Set-Cookie returned'
        }
    } catch {
        $record.result = 'FAIL'
        $record.actual = 'HTTP request failed: ' + $_.Exception.GetBaseException().GetType().Name
    } finally { $client.Dispose(); $record.finishedAt = [DateTimeOffset]::Now.ToString('o') }
    return $record
}

$context = [ordered]@{ runId = $runId; startedAt = [DateTimeOffset]::Now.ToString('o'); endpointSource = 'main.js, build/server.js, build/routes/login.js and build/routes/currentUser.js inspected; whoami requires a token cookie'; preflight = 'NOT RUN' }
try {
    $configuration = Invoke-Compose @('config', '--format', 'json') | ConvertFrom-Json
    $environmentValues = (Invoke-Compose @('exec', '-T', 'waf', 'printenv', 'MODSEC_RULE_ENGINE', 'BLOCKING_PARANOIA')).Trim() -split '\r?\n'
    $activeModsec = Invoke-Compose @('exec', '-T', 'waf', 'cat', '/etc/modsecurity.d/modsecurity.conf')
    $activeCrs = Invoke-Compose @('exec', '-T', 'waf', 'cat', '/opt/owasp-crs/crs-setup.conf')
    if ($environmentValues[0] -ne 'On' -or $environmentValues[1] -ne '1' -or $activeModsec -notmatch '(?m)^SecRuleEngine On\s*$' -or $activeCrs -notmatch 'setvar:tx.blocking_paranoia_level=1"') { throw 'WAF must be On at paranoia 1.' }
    & powershell.exe -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'Wait-LabReady.ps1') -TimeoutSeconds 30
    if ($LASTEXITCODE -ne 0) { throw 'Lab readiness failed.' }
    $context.preflight = 'PASS'
    $context.engine = $environmentValues[0]; $context.blockingParanoia = $environmentValues[1]
    $context.images = [ordered]@{ web = $configuration.services.web.image; waf = $configuration.services.waf.image }
    foreach ($id in $selected) {
        if ($id -eq 'TC01') { $results.Add((Test-AdminLogin 'TC01' 'http://localhost:3000' $attackJson $runId)) }
        if ($id -eq 'TC02') { $results.Add((Test-BlockedLogin $runId)) }
    }
} catch {
    $context.preflight = 'FAIL'
    foreach ($id in $selected) {
        $baseUrl = if ($id -eq 'TC01') { 'http://localhost:3000' } else { 'http://localhost:8080' }
        $record = New-TestRecord $id $baseUrl $attackJson 'Preflight must pass before executing test' $runId
        $record.actual = 'NOT RUN: Docker/readiness/configuration preflight failed: ' + $_.Exception.GetBaseException().GetType().Name
        $record.finishedAt = [DateTimeOffset]::Now.ToString('o')
        $results.Add($record)
    }
}

foreach ($record in $results) {
    $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory ($record.test + '.json')) -Encoding UTF8
    Write-Host ("{0}: {1} - {2}" -f $record.test, $record.result, $record.actual)
}
$context.finishedAt = [DateTimeOffset]::Now.ToString('o')
$context.results = @($results.ToArray())
$context | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'run.json') -Encoding UTF8
if ($results.Count -ne $selected.Count -or @($results | Where-Object { $_.result -ne 'PASS' }).Count -gt 0) { exit 1 }
exit 0
