#Requires -Version 7.4
<#
.SYNOPSIS
    Publishes each workload's subscription ID from main.bicepparam as a GitHub Actions secret.
.DESCRIPTION
    main.bicepparam is the single source of truth. This script reads it through
    Get-BicepParamConfig and writes one <WORKLOAD>_SUB_ID secret per workload
    (for example corp -> CORP_SUB_ID), which deploy-foundation.yml substitutes into the
    parameter template at run time. Safe to re-run; use -WhatIf to preview secret names.
.EXAMPLE
    pwsh ./scripts/bootstrap/Sync-SubscriptionSecrets.ps1 -WhatIf
.EXAMPLE
    pwsh ./scripts/bootstrap/Sync-SubscriptionSecrets.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Environment    = 'prod',
    [string]$BicepParamPath = (Join-Path $PSScriptRoot "../../environments/$Environment/main.bicepparam"),
    [string]$GitHubOwner,
    [string]$GitHubRepository
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '../LandingZone.Bootstrap') -Force

Assert-Preflight @(
    Test-Tooling
    Test-BicepParamFile  -Path $BicepParamPath
    Test-GitHubSession
    Test-GitHubRemote    -Owner $GitHubOwner -Repository $GitHubRepository
    Test-GitHubRepoAdmin -Owner $GitHubOwner -Repository $GitHubRepository
) -Title 'ENVIRONMENT & ACCESS PREFLIGHT'

$config = Get-BicepParamConfig -Path $BicepParamPath
$repo   = Resolve-GitHubRepository -Owner $GitHubOwner -Repository $GitHubRepository
$slug   = "$($repo.Owner)/$($repo.Repository)"

foreach ($workload in $config.Subscriptions.Keys | Sort-Object) {
    $secretName = '{0}_SUB_ID' -f $workload.ToUpperInvariant()
    if ($PSCmdlet.ShouldProcess("$slug secret $secretName", 'Set')) {
        Set-GitHubSecret -Repository $slug -Name $secretName -Value $config.Subscriptions[$workload]
    }
}

Write-BootstrapLog "Subscription secrets synchronized to $slug." -Level Success