<#
.SYNOPSIS
    Writes the deployment step summary to GITHUB_STEP_SUMMARY.

.PARAMETER EnvironmentName
    Display name of the environment (e.g. Dev, Intg, UAT).

.PARAMETER EnvironmentUrl
    Target environment URL.

.PARAMETER SolutionName
    Unique solution name.

.PARAMETER RunNumber
    GitHub run number.

.PARAMETER MockDeploy
    Whether this was a mock_deploy run.

.PARAMETER SolutionType
    'managed' or 'unmanaged'.

.PARAMETER WhoAmIOutcome
    'success', 'failure', or 'skipped'.

.PARAMETER BlockingCheckOutcome
    'success', 'failure', 'skipped', or 'disabled'.

.PARAMETER VersionCompareOutcome
    'success', 'failure', 'skipped', or 'disabled'.

.PARAMETER BackupOutcome
    'success', 'failure', 'skipped', or 'disabled'.

.PARAMETER ImportOutcome
    'success', 'failure', 'skipped', or 'mock'.
#>
param(
    [Parameter(Mandatory)][string] $EnvironmentName,
    [Parameter(Mandatory)][string] $EnvironmentUrl,
    [Parameter(Mandatory)][string] $SolutionName,
    [Parameter(Mandatory)][string] $RunNumber,
    [bool]   $MockDeploy            = $false,
    [string] $SolutionType          = 'managed',
    [string] $WhoAmIOutcome         = 'skipped',
    [string] $BlockingCheckOutcome  = 'skipped',
    [string] $VersionCompareOutcome = 'skipped',
    [string] $BackupOutcome         = 'skipped',
    [string] $ImportOutcome         = 'skipped'
)

function Get-Icon([string]$outcome) {
    switch ($outcome) {
        'success'  { return '✅' }
        'failure'  { return '❌' }
        'skipped'  { return '⏭️' }
        'disabled' { return '⏭️ Off' }
        'mock'     { return '🧪 Mock' }
        default    { return '—' }
    }
}

@"

## 📊 Deployment Summary — $EnvironmentName
| Step | Toggle | Result |
| --- | --- | --- |
| Auth (who-am-i) | Always | $(Get-Icon $WhoAmIOutcome) |
| Blocking check | $(if ($BlockingCheckOutcome -ne 'disabled') {'On'} else {'Off'}) | $(Get-Icon $BlockingCheckOutcome) |
| Version compare | $(if ($VersionCompareOutcome -ne 'disabled') {'On'} else {'Off'}) | $(Get-Icon $VersionCompareOutcome) |
| Solution Checker | ✅ Always On (enforced at build) | ✅ |
| Backup | $(if ($BackupOutcome -ne 'disabled') {'On'} else {'Off'}) | $(Get-Icon $BackupOutcome) |
| Import | $(if ($MockDeploy) {'MOCK'} else {$SolutionType}) | $(Get-Icon $ImportOutcome) |

**Environment:** ``$EnvironmentUrl``
**Solution:** ``$SolutionName``
**Run:** ``#$RunNumber``
"@ | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
