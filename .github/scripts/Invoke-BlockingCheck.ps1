<#
.SYNOPSIS
    Checks for in-progress async operations on a Power Platform environment.

.DESCRIPTION
    Queries the Dataverse Web API for async operations that are in-progress,
    waiting, or pausing (statuscode 10/20/30/0) and are of import/publish/upgrade
    type. Fails if any blocking operations are found.

.PARAMETER EnvironmentUrl
    Target environment URL (e.g. https://myorg-dev.crm.dynamics.com).

.PARAMETER AppId
    Service principal application/client ID.

.PARAMETER ClientSecret
    Service principal client secret.

.PARAMETER TenantId
    Azure AD tenant ID.

.PARAMETER EnvironmentName
    Display name for logging (e.g. Dev, Intg).
#>
param(
    [Parameter(Mandatory)][string] $EnvironmentUrl,
    [Parameter(Mandatory)][string] $AppId,
    [Parameter(Mandatory)][string] $ClientSecret,
    [Parameter(Mandatory)][string] $TenantId,
    [string] $EnvironmentName = 'Target'
)

$ErrorActionPreference = 'Stop'

Write-Host "🔍 Checking for in-progress async operations on $EnvironmentUrl ..."

# Acquire OAuth token
$tokenBody = @{
    client_id     = $AppId
    client_secret = $ClientSecret
    grant_type    = 'client_credentials'
    scope         = "$EnvironmentUrl/.default"
}
$tokenResponse = Invoke-RestMethod `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
    -Method POST `
    -Body $tokenBody
$token = $tokenResponse.access_token

if (-not $token) {
    Write-Error "::error::Failed to acquire OAuth token. Verify service principal credentials."
    exit 1
}

# Query in-progress solution-related async operations
# statuscode: 10=Waiting, 20=InProgress, 0=WaitingForResources
# operationtype: 1=import, 6=publishall, 25=solutionimport, 55=upgrade, 71=uninstall
$filter  = "statuscode in (10,20,0) and operationtype in (1,6,7,9,25,55,71,72)"
$select  = "name,statuscodename,operationtypename,createdon"
$apiUrl  = "$EnvironmentUrl/api/data/v9.2/asyncoperations?`$filter=$filter&`$select=$select"

$headers = @{
    'Authorization'  = "Bearer $token"
    'Accept'         = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'  = '4.0'
}
$response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method GET
$ops = $response.value

"blocking-count=$($ops.Count)" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append

if ($ops.Count -gt 0) {
    Write-Host "::warning::Found $($ops.Count) in-progress operation(s) on $EnvironmentName."

    @"

### ⚠️ In-Progress Async Operations on $EnvironmentName
| Name | Status | Type | Created |
| --- | --- | --- | --- |
"@ | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append

    foreach ($op in $ops) {
        "| $($op.name) | $($op.statuscodename) | $($op.operationtypename) | $($op.createdon) |" |
            Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
    }

    Write-Error "::error::Deployment blocked: $($ops.Count) in-progress operation(s) detected. Resolve them before deploying."
    exit 1
} else {
    Write-Host "✅ No blocking operations found on $EnvironmentName."
    "✅ No blocking operations found on **$EnvironmentName**." |
        Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
}
