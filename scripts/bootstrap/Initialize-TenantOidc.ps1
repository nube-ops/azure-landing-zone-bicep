#Requires -Version 7.4
<#
.SYNOPSIS
    Bootstraps the tenant-level deployer identity in its own resource group.
.DESCRIPTION
    Registers the required resource providers in the bootstrap subscription (only if needed),
    then: resource group (get-or-create + tags) -> UMI -> GitHub OIDC credential -> roles at '/'
    -> Actions secrets. Idempotent.
.EXAMPLE
    pwsh ./scripts/bootstrap/Initialize-TenantOidc.ps1
#>
[CmdletBinding()]
param(
    [string]$Environment    = 'prod',
    [string]$BicepParamPath = (Join-Path $PSScriptRoot "../../environments/$Environment/main.bicepparam"),
    [string]$WorkloadsPath  = (Join-Path $PSScriptRoot "../../environments/$Environment/workloads.json"),
    [string]$GitHubOwner,
    [string]$GitHubRepository,
    [string]$GitHubBranch = 'main'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '../LandingZone.Bootstrap') -Force

# --- Stage 1: environment gate ---
Assert-Preflight @(
    Test-Tooling
    Test-BicepParamFile  -Path $BicepParamPath
    Test-JsonFile        -Path $WorkloadsPath
    Test-AzureSession
    Test-GitHubAccess    -Owner $GitHubOwner -Repository $GitHubRepository
) -Title 'ENVIRONMENT & ACCESS PREFLIGHT'

# --- Context (safe now) ---
$config            = Get-BicepParamConfig -Path $BicepParamPath
$repo              = Resolve-GitHubRepository -Owner $GitHubOwner -Repository $GitHubRepository
$tenantId          = Get-AzureTenantId
$bootstrapWorkload = (Get-Content -LiteralPath $WorkloadsPath -Raw | ConvertFrom-Json).bootstrapWorkload
$wl             = Get-WorkloadConfig -Path $WorkloadsPath -Workload $bootstrapWorkload -Environment $Environment
$subscriptionId = $config.Subscriptions[$bootstrapWorkload]
Assert-Preflight @(
    Test-SubscriptionIdFormat -Workload $bootstrapWorkload -SubscriptionId $subscriptionId
) -Title 'CONFIGURATION PREFLIGHT'

$requiredProviders = @('Microsoft.Resources', 'Microsoft.ManagedIdentity')
$name     = @{ Domain = $wl.Domain; Purpose = 'tenant'; Environment = $Environment; RegionCode = $config.PrimaryRegionCode }
$rgName   = Get-ResourceName -Type rg @name
$identity = Get-ResourceName -Type id @name
$tags     = $wl.Tags
$rootMgId = "/providers/Microsoft.Management/managementGroups/$tenantId"

# --- Stage 2: target gate ---
Assert-Preflight @(
    Test-TargetSubscription      -SubscriptionId $subscriptionId -TenantId $tenantId
    Test-CanWriteRoleAssignment -Scope '/'
) -Title 'AZURE TARGET & RBAC PREFLIGHT'

# --- Provision: providers -> RG (get-or-create) -> UMI -> federated credential -> roles ---
foreach ($r in Set-ProviderRegistration -SubscriptionId $subscriptionId -Namespace $requiredProviders) {
    Write-BootstrapLog "Provider $($r.Namespace): $($r.Action)" -Level Success
}

$rg = Initialize-BootstrapResourceGroup -Config $config -Workload $bootstrapWorkload `
        -ResourceGroupName $rgName -Tags $tags

$deployer = Initialize-DeployerIdentity `
    -Name              $identity `
    -ResourceGroupName $rg.Name `
    -SubscriptionId    $rg.SubscriptionId `
    -Location          $rg.Location `
    -Tags              $tags `
    -Repository        $repo `
    -Branch            $GitHubBranch `
    -RoleAssignment    @(
        @{ Role = 'Contributor';                 Scope = '/' }
        @{ Role = 'Resource Policy Contributor'; Scope = '/' }
        @{ Role = 'User Access Administrator';   Scope = '/' }
    )

# --- Secrets differ per entry point, so they stay here ---
Set-GitHubSecret -Repository $repo.Slug -Name 'AZURE_CLIENT_ID'                 -Value $deployer.ClientId
Set-GitHubSecret -Repository $repo.Slug -Name 'AZURE_TENANT_ID'                 -Value $tenantId
Set-GitHubSecret -Repository $repo.Slug -Name 'TENANT_ROOT_MANAGEMENT_GROUP_ID' -Value $rootMgId

Show-DeployerIdentity -Identity $deployer
Write-BootstrapLog 'Tenant deployer bootstrap complete.' -Level Success