<#
.SYNOPSIS
    Writes the final build step summary table to GITHUB_STEP_SUMMARY.

.PARAMETER SolutionName
    Unique solution name.

.PARAMETER SolutionVersion
    Stamped version string (e.g. 1.0.42.0).

.PARAMETER ArtifactName
    GitHub Actions artifact name.

.PARAMETER RunNumber
    GitHub run number.

.PARAMETER MockDeploy
    Whether this was a mock_deploy run.

.PARAMETER CheckerGeo
    Solution Checker geography used.

.PARAMETER DataSchemaFile
    Path to data schema file (empty string = not used).

.PARAMETER EnableJFrogUpload
    Whether JFrog upload was enabled.

.PARAMETER JFrogUrl
    JFrog base URL (for real upload display).

.PARAMETER JFrogRepo
    JFrog repository name.

.PARAMETER EnableSolutionChecker
    Whether Solution Checker was enabled.
#>
param(
    [Parameter(Mandatory)][string] $SolutionName,
    [Parameter(Mandatory)][string] $SolutionVersion,
    [Parameter(Mandatory)][string] $ArtifactName,
    [Parameter(Mandatory)][string] $RunNumber,
    [bool]   $MockDeploy            = $false,
    [string] $CheckerGeo            = 'UnitedStates',
    [string] $DataSchemaFile        = '',
    [bool]   $EnableJFrogUpload     = $false,
    [string] $JFrogUrl              = '',
    [string] $JFrogRepo             = '',
    [bool]   $EnableSolutionChecker = $true
)

$mode = if ($MockDeploy) { 'mock_deploy' } else { 'live' }

$checkerRow = if (-not $EnableSolutionChecker) {
    "| Solution Checker | — | ⏭️ Disabled |"
} elseif ($MockDeploy) {
    "| Solution Checker | mock_deploy | 🧪 Simulated (ZIP + XML validation) |"
} else {
    "| Solution Checker | live | ✅ Real (geo: ``$CheckerGeo``) |"
}

$dataRow = if (-not $DataSchemaFile) {
    "| Export config data | — | ⏭️ No schema file provided |"
} elseif ($MockDeploy) {
    "| Export config data | mock_deploy | 🧪 Simulated (schema parse + placeholder ZIP) |"
} else {
    "| Export config data | live | ✅ Real (schema: ``$DataSchemaFile``) |"
}

$jfrogRow = if (-not $EnableJFrogUpload) {
    "| JFrog upload | — | ⏭️ Disabled |"
} elseif ($MockDeploy) {
    "| JFrog upload | mock_deploy | 🧪 Simulated (no network call) |"
} else {
    "| JFrog upload | live | ✅ Real → ``$JFrogUrl/$JFrogRepo`` |"
}

@"

## 🏗️ Build Results — $SolutionName
| Step | Mode | Status |
| --- | --- | --- |
| Version stamp | Always | ``$SolutionVersion`` |
| Pack Unmanaged | Always | ✅ $(if ($MockDeploy) { 'Mock (no PAC CLI)' } else { 'Real (PAC CLI)' }) |
| Pack Managed | Always | ✅ $(if ($MockDeploy) { 'Mock (no PAC CLI)' } else { 'Real (PAC CLI)' }) |
$checkerRow
$dataRow
$jfrogRow

| Artifact | ``$ArtifactName`` |
| Run # | $RunNumber |
"@ | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
