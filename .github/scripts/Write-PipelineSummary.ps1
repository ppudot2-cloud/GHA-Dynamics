<#
.SYNOPSIS
    Writes the final pipeline summary table to GITHUB_STEP_SUMMARY.

.PARAMETER SolutionList
    Comma-separated list of solutions that were processed.

.PARAMETER SolutionCount
    Number of solutions.

.PARAMETER RunNumber
    GitHub run number.

.PARAMETER RefName
    Git ref name (branch or tag).

.PARAMETER CommitSha
    Full commit SHA.

.PARAMETER SetupResult / BuildResult
    GitHub job outcomes for setup and build.

.PARAMETER GateDevResult / DeployDevResult
    GitHub job outcomes for the Dev gate and deploy.

.PARAMETER GateIntgResult / DeployIntgResult / etc.
    GitHub job outcomes for each gate and deploy stage.
#>
param(
    [string] $SolutionList      = '',
    [string] $SolutionCount     = '0',
    [string] $RunNumber         = '',
    [string] $RefName           = '',
    [string] $CommitSha         = '',
    [string] $SetupResult       = 'skipped',
    [string] $BuildResult       = 'skipped',
    [string] $GateDevResult     = 'skipped',
    [string] $DeployDevResult   = 'skipped',
    [string] $GateIntgResult    = 'skipped',
    [string] $DeployIntgResult  = 'skipped',
    [string] $GateUatResult     = 'skipped',
    [string] $DeployUatResult   = 'skipped',
    [string] $GatePerfResult    = 'skipped',
    [string] $DeployPerfResult  = 'skipped',
    [string] $GateProdResult    = 'skipped',
    [string] $DeployProdResult  = 'skipped'
)

function Get-Icon([string]$outcome) {
    switch ($outcome) {
        'success'   { return '✅' }
        'skipped'   { return '⏭️' }
        'cancelled' { return '🚫' }
        default     { return '❌' }
    }
}

@"
# 🏭 Release Pipeline Summary

**Solutions:** ``$SolutionList``
**Run:** ``#$RunNumber`` | **Ref:** ``$RefName`` | **Commit:** ``$CommitSha``

| Stage | Environment | Result |
| --- | --- | --- |
| 🔍 Resolve | — | $(Get-Icon $SetupResult) |
| 🏗️ Build + JFrog Upload (×$SolutionCount) | — | $(Get-Icon $BuildResult) |
| 🔐 Gate | Dev | $(Get-Icon $GateDevResult) |
| 🚀 Deploy | Dev | $(Get-Icon $DeployDevResult) |
| 🔐 Gate | Intg | $(Get-Icon $GateIntgResult) |
| 🚀 Deploy | Intg | $(Get-Icon $DeployIntgResult) |
| 🔐 Gate | UAT | $(Get-Icon $GateUatResult) |
| 🚀 Deploy | UAT | $(Get-Icon $DeployUatResult) |
| 🔐 Gate | Perf | $(Get-Icon $GatePerfResult) |
| 🚀 Deploy | Perf | $(Get-Icon $DeployPerfResult) |
| 🔐 Gate | Prod | $(Get-Icon $GateProdResult) |
| 🚀 Deploy | Prod | $(Get-Icon $DeployProdResult) |
"@ | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
