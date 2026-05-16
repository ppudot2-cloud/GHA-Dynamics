# =============================================================================
# Invoke-DataverseRefresh.ps1
#
# Purpose : Iterates over a JSON config file containing Dataverse connection
#           definitions, retrieves each service account password from Azure
#           Key Vault, connects to the Dataverse org, and verifies the
#           connection is healthy.
#
# Called by : pipelines/dataverse-refresh.yml via AzurePowerShell@5 task.
#             Azure authentication is handled by the task's service connection
#             — do NOT call Connect-AzAccount here.
#
# Parameters:
#   -ConfigFile        : Full path to the connections JSON file
#   -Environment       : Label used in log output only (e.g. dev, prod)
#   -OutputPath        : Path to write the results JSON artifact
#   -MaxRetries        : Retry attempts on transient failures (default: 3)
#   -RetryDelaySeconds : Base delay between retries in seconds (default: 5)
#
# JSON object shape (see config/connections.schema.json for full schema):
#   {
#     "URL"        : "https://org.crm.dynamics.com",
#     "AKV"        : "my-keyvault-name",
#     "Username"   : "svc_d365@tenant.onmicrosoft.com",
#     "SecretName" : "d365-svc-password"
#   }
#   NOTE: SecretName is the KEY NAME in Key Vault — NOT the password value itself.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,

    [Parameter(Mandatory = $false)]
    [string]$Environment = 'unknown',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = '',

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $false)]
    [int]$RetryDelaySeconds = 5
)

# =============================================================================
# INIT
# =============================================================================

$ErrorActionPreference = 'Stop'

# FIX: Changed from "Latest" to "2.0". Version "Latest" breaks Az module
# internal code (property access on null objects inside the module itself),
# causing random failures that look unrelated to your script. Version 2.0
# still catches undefined variables and uninitialised arrays in your own code.
Set-StrictMode -Version 2.0

Write-Host "============================================================"
Write-Host " Dataverse Connection Refresh"
Write-Host " Environment  : $Environment"
Write-Host " Config file  : $ConfigFile"
Write-Host " Build ID     : $($env:BUILD_ID)"
Write-Host " Max retries  : $MaxRetries"
Write-Host " Started      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "============================================================`n"

# =============================================================================
# MODULE INSTALLATION
# =============================================================================

# FIX: Replaced "Microsoft.PowerPlatform.Cds.Client" with the current module
# name "Microsoft.PowerPlatform.Dataverse.Client". The CDS client module was
# renamed and the old package is no longer maintained. The class name inside
# the new package is "ServiceClient" (not "CdsServiceClient").
$requiredModules = @(
    'Az.Accounts',
    'Az.KeyVault',
    'Microsoft.PowerPlatform.Dataverse.Client'
)

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "[$module] Not found — installing..."
        try {
            Install-Module `
                -Name               $module `
                -Repository         PSGallery `   # FIX: Explicit repo prevents
                -Force              `              #      prompt on agents with
                -Scope              CurrentUser `  #      multiple registered feeds
                -AllowClobber       `
                -SkipPublisherCheck
            Write-Host "[$module] Installed successfully"
        }
        catch {
            throw "Failed to install module '$module': $_"
        }
    }
    else {
        Write-Host "[$module] Already available — skipping install"
    }

    Import-Module $module -Force
}

Write-Host ""

# =============================================================================
# CONFIG FILE LOADING
# =============================================================================

if (-not (Test-Path $ConfigFile)) {
    throw "Config file not found: $ConfigFile"
}

$configs = Get-Content $ConfigFile -Raw | ConvertFrom-Json

if (-not $configs -or $configs.Count -eq 0) {
    throw "Config file is empty or could not be parsed: $ConfigFile"
}

Write-Host "Loaded $($configs.Count) connection definition(s) from config`n"

# =============================================================================
# SECRET CACHE
# Keyed by "VaultName::SecretName" so entries sharing the same service account
# only hit Key Vault once rather than once per entry.
# FIX: Declared as $script:secretCache so the Get-CachedSecret function below
# can write to it unambiguously across PowerShell scope boundaries.
# =============================================================================

$script:secretCache = @{}

function Get-CachedSecret {
    param(
        [string]$VaultName,
        [string]$SecretName
    )

    $cacheKey = "$VaultName::$SecretName"

    if ($script:secretCache.ContainsKey($cacheKey)) {
        Write-Host "  (using cached secret for '$SecretName')"
        return $script:secretCache[$cacheKey]
    }

    Write-Host "  Fetching secret '$SecretName' from vault '$VaultName'..."
    $secretObj = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName

    if (-not $secretObj) {
        throw "Secret '$SecretName' not found in vault '$VaultName'"
    }

    $script:secretCache[$cacheKey] = $secretObj.SecretValue
    return $secretObj.SecretValue
}

# =============================================================================
# RETRY HELPER
# Wraps a scriptblock with retry and exponential backoff.
# FIX: Added permanent-error short-circuit. Known permanent errors (wrong vault,
# secret not found, auth failure) are rethrown immediately without wasting
# retries — these will not resolve on their own and retrying burns KV quota.
# =============================================================================

$permanentErrorPatterns = @(
    'SecretNotFound',
    'VaultNotFound',
    'Forbidden',
    'AuthenticationFailed',
    'does not exist',
    'was not found'
)

function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName,
        [int]$Retries,
        [int]$BaseDelay
    )

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            $result = & $ScriptBlock
            return $result
        }
        catch {
            $errMsg = "$_"

            # FIX: Check for permanent errors and fail immediately without retry
            $isPermanent = $script:permanentErrorPatterns | Where-Object { $errMsg -match $_ }
            if ($isPermanent) {
                throw "[$OperationName] Permanent error (not retrying): $errMsg"
            }

            if ($attempt -ge $Retries) {
                throw "[$OperationName] Failed after $Retries attempt(s): $errMsg"
            }

            # Exponential backoff: 5s → 10s → 20s
            $delay = [int]($BaseDelay * [Math]::Pow(2, $attempt - 1))
            Write-Warning "  [$OperationName] Attempt $attempt failed — retrying in ${delay}s: $errMsg"
            Start-Sleep -Seconds $delay
        }
    }
}

# =============================================================================
# CONNECTION TRACKING
# =============================================================================

$results   = [System.Collections.Generic.List[hashtable]]::new()
$failures  = [System.Collections.Generic.List[string]]::new()
$successes = [System.Collections.Generic.List[string]]::new()

# =============================================================================
# MAIN LOOP
# =============================================================================

$index = 0
foreach ($c in $configs) {
    $index++
    $conn        = $null
    $elapsedMs   = $null
    $errorDetail = $null

    Write-Host "------------------------------------------------------------"
    Write-Host "[$index / $($configs.Count)] $($c.URL)"

    try {

        # ── Field validation ────────────────────────────────────────────────
        foreach ($field in @('URL', 'AKV', 'Username', 'SecretName')) {
            if (-not $c.$field) {
                throw "Missing required field '$field' in config entry #$index"
            }
        }

        # ── URL format validation ───────────────────────────────────────────
        $uri = $null
        if (-not [Uri]::TryCreate($c.URL, [UriKind]::Absolute, [ref]$uri)) {
            throw "Invalid URL format '$($c.URL)' in config entry #$index"
        }

        # ── Retrieve secret (cached, with retry) ────────────────────────────
        $securePassword = Invoke-WithRetry `
            -ScriptBlock    { Get-CachedSecret -VaultName $c.AKV -SecretName $c.SecretName } `
            -OperationName  "KeyVault:$($c.AKV)/$($c.SecretName)" `
            -Retries        $MaxRetries `
            -BaseDelay      $RetryDelaySeconds

        # ── Connect to Dataverse (with retry and timing) ────────────────────
        Write-Host "  Connecting as '$($c.Username)'..."

        $conn = Invoke-WithRetry -Retries $MaxRetries -BaseDelay $RetryDelaySeconds `
            -OperationName "DataverseConnect:$($c.URL)" `
            -ScriptBlock {

                # FIX: Replaced the NetworkCredential constructor (undocumented
                # overload that may not resolve at runtime) with the connection
                # string constructor which is the officially supported path for
                # username/password authentication.
                #
                # The password must be briefly decrypted to build the connection
                # string. It is zeroed from memory immediately after the string
                # is built. Do NOT log $plainPassword anywhere.
                $bstr        = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
                $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)   # Zero memory immediately

                $connString = "AuthType=Office365;" +
                              "Username=$($c.Username);" +
                              "Password=$plainPassword;" +
                              "Url=$($c.URL)"

                # Clear plaintext reference as soon as it's been consumed
                $plainPassword = $null

                # FIX: Updated class name from CdsServiceClient to ServiceClient
                # to match the renamed Microsoft.PowerPlatform.Dataverse.Client module.
                # FIX: Stopwatch started here (inside the scriptblock) so elapsed
                # time reflects only the actual connection attempt, not retry delays.
                $sw     = [System.Diagnostics.Stopwatch]::StartNew()
                $client = New-Object Microsoft.PowerPlatform.Dataverse.Client.ServiceClient($connString)
                $sw.Stop()

                if (-not $client.IsReady) {
                    $errMsg = if ($client.LastError) {
                        $client.LastError.Message
                    } else {
                        "ServiceClient.IsReady returned false with no error detail"
                    }
                    throw $errMsg
                }

                # Return both the client and elapsed time as a tuple-like hashtable
                return @{ Client = $client; ElapsedMs = $sw.ElapsedMilliseconds }
            }

        # Unpack the result
        $elapsedMs = [long]$conn.ElapsedMs    # FIX: Explicit long cast for clean JSON serialisation
        $connClient = $conn.Client

        Write-Host "  ✅ Connected successfully ($($elapsedMs)ms)"
        $successes.Add($c.URL)

    }
    catch {
        $errorDetail = "$_"
        Write-Warning "  ❌ FAILED: $errorDetail"
        $failures.Add("$($c.URL) — $errorDetail")
    }
    finally {
        # Dispose connection client to release network resources
        if ($null -ne $connClient -and $connClient -is [System.IDisposable]) {
            $connClient.Dispose()
        }

        # Accumulate structured result — wrapped in its own try so a serialisation
        # error here does not suppress the original connection error
        try {
            $results.Add(@{
                url        = $c.URL
                username   = $c.Username
                akv        = $c.AKV
                secretName = $c.SecretName
                success    = ($null -eq $errorDetail)
                elapsedMs  = $elapsedMs
                error      = $errorDetail
                timestamp  = (Get-Date -Format 'o')
            })
        }
        catch {
            Write-Warning "Failed to record result for $($c.URL): $_"
        }
    }
}

# =============================================================================
# RESULTS ARTIFACT
# =============================================================================

if ($OutputPath) {
    $outputDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $artifactData = @{
        buildId     = $env:BUILD_ID
        environment = $Environment
        runAt       = (Get-Date -Format 'o')
        total       = $configs.Count
        passed      = $successes.Count
        failed      = $failures.Count
        results     = $results
    }

    $artifactData | ConvertTo-Json -Depth 5 | Set-Content $OutputPath -Encoding UTF8
    Write-Host "`nResults written to: $OutputPath"
}

# =============================================================================
# SUMMARY
# =============================================================================

Write-Host "`n============================================================"
Write-Host " Summary"
Write-Host "============================================================"
Write-Host " Total    : $($configs.Count)"
Write-Host " Passed   : $($successes.Count)"
Write-Host " Failed   : $($failures.Count)"
Write-Host " Finished : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

if ($failures.Count -gt 0) {
    Write-Host "`n Failed connections:"
    $failures | ForEach-Object { Write-Host "   ❌ $_" }
    throw "$($failures.Count) of $($configs.Count) connection(s) failed. See log above for details."
}

Write-Host "`n All $($configs.Count) connection(s) refreshed successfully."
