#Requires -Version 7.4
<#
.SYNOPSIS
    Phase 2: discovers each workload's subscription, records it in main.bicepparam, and publishes it as a GitHub Actions secret.
.DESCRIPTION
    Azure -> main.bicepparam -> GitHub secrets, in one idempotent pass.
      1. Finds the enabled subscription named *-<workload> for every workload.
      2. Replaces placeholder IDs in main.bicepparam (a real ID is overwritten only with -Force).
      3. Writes one <WORKLOAD>_SUB_ID secret per workload (corp -> CORP_SUB_ID), which
         deploy-foundation.yml substitutes into the parameter template at run time.
    Safe to re-run. -WhatIf previews the file edit and the secret names; nothing is written.
.EXAMPLE
    pwsh ./scripts/bootstrap/Sync-Subscriptions.ps1 -WhatIf
.EXAMPLE
    pwsh ./scripts/bootstrap/Sync-Subscriptions.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Environment    = 'prod',
    [string]$BicepParamPath = (Join-Path $PSScriptRoot "../../environments/$Environment/main.bicepparam"),
    [string]$GitHubOwner,
    [string]$GitHubRepository,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '../LandingZone.Bootstrap') -Force

# --- Stage 1: environment gate ---
Assert-Preflight @(
    Test-Tooling
    Test-BicepParamFile -Path $BicepParamPath
    Test-AzureSession
    Test-GitHubAccess   -Owner $GitHubOwner -Repository $GitHubRepository
) -Title 'ENVIRONMENT & ACCESS PREFLIGHT'

# --- Context (safe now) ---
$config    = Get-BicepParamConfig -Path $BicepParamPath
$repo      = Resolve-GitHubRepository -Owner $GitHubOwner -Repository $GitHubRepository
$tenantId  = Get-AzureTenantId
$workloads = @($config.Subscriptions.Keys | Sort-Object)

# --- Discover and converge main.bicepparam ---
# -WhatIf is passed explicitly: preference variables do not cross the module boundary.
$discovered    = Find-WorkloadSubscription -Workload $workloads -TenantId $tenantId
$subscriptions = Set-BicepParamSubscription -Path $BicepParamPath `
    -Current $config.Subscriptions -Desired $discovered -Force:$Force -WhatIf:$WhatIfPreference

# --- Stage 2: data gate (never publish placeholders as real secrets) ---
Assert-Preflight @(
    foreach ($w in $workloads) {
        Test-SubscriptionIdFormat -Workload $w -SubscriptionId $subscriptions[$w]
    }
) -Title 'SUBSCRIPTION ID PREFLIGHT'

# --- Plan: one row per workload; drives both the publish loop and the summary ---
$plan = @(foreach ($w in $workloads) {
    [pscustomobject]@{
        Workload       = $w
        SubscriptionId = $subscriptions[$w]
        Secret         = Get-WorkloadSecretName -Workload $w -Kind SubId
    }
})

# --- Publish ---
foreach ($row in $plan) {
    if ($PSCmdlet.ShouldProcess("$($repo.Slug) secret $($row.Secret)", 'Set')) {
        Set-GitHubSecret -Repository $repo.Slug -Name $row.Secret -Value $row.SubscriptionId
    }
}

$plan | Select-Object Workload, Secret | Format-Table -AutoSize | Out-Host

$verb = if ($WhatIfPreference) { 'previewed for' } else { 'synchronized to' }
Write-BootstrapLog "Subscription secrets $verb $($repo.Slug)." -Level Success