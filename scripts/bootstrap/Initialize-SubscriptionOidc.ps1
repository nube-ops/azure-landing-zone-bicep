#Requires -Version 7.4
<#
.SYNOPSIS
    Bootstraps one deployer identity per workload subscription.
.DESCRIPTION
    Per workload: resource group (get-or-create + tags) -> UMI -> GitHub OIDC credential
    -> Contributor on the subscription -> <WORKLOAD>_CLIENT_ID secret.
    Idempotent. Workloads come from main.bicepparam; domain and tags from workloads.json.
.EXAMPLE
    pwsh ./scripts/bootstrap/Initialize-SubscriptionOidc.ps1
.EXAMPLE
    pwsh ./scripts/bootstrap/Initialize-SubscriptionOidc.ps1 -Workload corp,online
#>
[CmdletBinding()]
param(
    [string]$Environment    = 'prod',
    [string[]]$Workload,    # optional subset; default = all workloads in main.bicepparam
    [string]$BicepParamPath = (Join-Path $PSScriptRoot "../../environments/$Environment/main.bicepparam"),
    [string]$WorkloadsPath  = (Join-Path $PSScriptRoot "../../environments/$Environment/workloads.json"),
    [string]$GitHubOwner,
    [string]$GitHubRepository,
    [string]$GitHubBranch = 'main'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '../LandingZone.Bootstrap') -Force

# Single place that defines what a subscription deployer may do (scope: its own subscription).
$deployerRoles = @('Contributor')

# --- Stage 1: environment gate ---
Assert-Preflight @(
    Test-Tooling
    Test-BicepParamFile -Path $BicepParamPath
    Test-JsonFile       -Path $WorkloadsPath
    Test-AzureSession
    Test-GitHubAccess   -Owner $GitHubOwner -Repository $GitHubRepository
) -Title 'ENVIRONMENT & ACCESS PREFLIGHT'

# --- Context (safe now) ---
$config   = Get-BicepParamConfig -Path $BicepParamPath
$repo     = Resolve-GitHubRepository -Owner $GitHubOwner -Repository $GitHubRepository
$tenantId = Get-AzureTenantId

$targets = if ($Workload) { @($Workload | Select-Object -Unique) } else { @($config.Subscriptions.Keys | Sort-Object) }
$unknown = @($targets | Where-Object { -not $config.Subscriptions.ContainsKey($_) })
if ($unknown) {
    throw "Unknown workload(s): $($unknown -join ', '). Available: $($config.Subscriptions.Keys -join ', ')."
}

# Plan: one row per workload; resolved before any write so bad config fails early.
$plan = @(foreach ($w in $targets) {
    $wl   = Get-WorkloadConfig -Path $WorkloadsPath -Workload $w -Environment $Environment
    $name = @{ Domain = $wl.Domain; Purpose = 'deploy'; Environment = $Environment; RegionCode = $config.PrimaryRegionCode }
    $id   = $config.Subscriptions[$w]
    [pscustomobject]@{
        Workload          = $w
        SubscriptionId    = $id
        Scope             = "/subscriptions/$id"
        Tags              = $wl.Tags
        ResourceGroupName = Get-ResourceName -Type rg @name
        IdentityName      = Get-ResourceName -Type id @name
    }
})

Assert-Preflight @(
    foreach ($p in $plan) { Test-SubscriptionIdFormat -Workload $p.Workload -SubscriptionId $p.SubscriptionId }
) -Title 'CONFIGURATION PREFLIGHT'

# --- Stage 2: target gate ---
Assert-Preflight @(
    foreach ($p in $plan) {
        @(
            Test-TargetSubscription     -SubscriptionId $p.SubscriptionId -TenantId $tenantId
            Test-ProviderRegistered     -SubscriptionId $p.SubscriptionId -Namespace 'Microsoft.Resources'
            Test-ProviderRegistered     -SubscriptionId $p.SubscriptionId -Namespace 'Microsoft.ManagedIdentity'
            Test-CanWriteRoleAssignment -Scope $p.Scope
        ) | ForEach-Object { $_.Group = "$($p.Workload) ($($p.SubscriptionId))"; $_ }
    }
) -Title 'AZURE TARGET & RBAC PREFLIGHT'

# --- Provision per workload: RG -> UMI -> federated credential -> roles -> secret ---
foreach ($p in $plan) {
    Write-BootstrapLog "Workload: $($p.Workload)"

    $rg = Initialize-BootstrapResourceGroup -Config $config -Workload $p.Workload `
            -ResourceGroupName $p.ResourceGroupName -Tags $p.Tags

    $deployer = Initialize-DeployerIdentity `
        -Name              $p.IdentityName `
        -ResourceGroupName $rg.Name `
        -SubscriptionId    $rg.SubscriptionId `
        -Location          $rg.Location `
        -Tags              $p.Tags `
        -Repository        $repo `
        -Branch            $GitHubBranch `
        -RoleAssignment    @($deployerRoles | ForEach-Object { @{ Role = $_; Scope = $p.Scope } })

    Set-GitHubSecret -Repository $repo.Slug -Name (Get-WorkloadSecretName -Workload $p.Workload -Kind ClientId) -Value $deployer.ClientId

    Show-DeployerIdentity -Identity $deployer
}

Write-BootstrapLog "Subscription deployer bootstrap complete for: $($targets -join ', ')." -Level Success