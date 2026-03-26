<#
.SYNOPSIS
  Push the entire force-app/main/default tree to ucsf-prod (invoice PDF, student email, triggers, flows, etc.).

.DESCRIPTION
  Wrapper around Push_UCSF_Prod.ps1 with -QuickTests enabled by default so production validates
  ProgramEnrollmentStudentEmail_Tests, ProgramEnrollmentInvoiceController_Tests, and
  ProgramEnrollmentNotify_Tests (same gate used for recent successful deploys).

  For a full-org test run instead, use: .\Push_UCSF_Prod.ps1  (omit -QuickTests)

.EXAMPLE
  .\Push_All_To_UCSF_Prod.ps1

.EXAMPLE
  .\Push_All_To_UCSF_Prod.ps1 -ValidateOnly

.EXAMPLE
  .\Push_All_To_UCSF_Prod.ps1 -NoPause
#>

[CmdletBinding()]
param(
    [switch] $ValidateOnly,
    [switch] $NoPause
)

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$inner = Join-Path $scriptDir "Push_UCSF_Prod.ps1"
if (-not (Test-Path $inner)) {
    Write-Error "Missing Push_UCSF_Prod.ps1 next to this script: $inner"
}

& $inner -OrgAlias "ucsf-prod" -QuickTests -ValidateOnly:$ValidateOnly -NoPause:$NoPause
