# Azure Enterprise-Scale Landing Zone (Bicep & PowerShell Automation)
A tenant-scope implementation of the Microsoft Cloud Adoption Framework (CAF) Enterprise-Scale architecture, written in Azure Bicep and supported by idempotent PowerShell automation that bootstraps secure, credential-free CI/CD.

It automates the management group hierarchy, policy governance, subscription associations and the deployer identity that GitHub Actions uses, and every step is safe to re-run.

## Engineering Highlights

* **Data-driven parameterization:** Management group names derive from `orgName` and `geoPrefix`. The hierarchy, regions and subscription mappings live in one parameter file, so `main.bicep` holds no organization-specific values. Workload identity and tags live in one registry, `workloads.json`, validated against `workloads.schema.json`.
* **Credential-free CI/CD:** GitHub Actions authenticates with short-lived OIDC federated credentials on a user-assigned managed identity. No client secrets or certificates are stored.
* **Idempotent automation:** The bootstrap scripts use get-or-create and drift-only writes. A re-run with nothing to change writes nothing, and each step reports what it did (see [Idempotency behavior](#idempotency-behavior)).
* **Fail-fast preflight gates:** Each script validates tooling, sessions, permissions and data in read-only stages before it changes anything.
* **Policy-as-Code governance:** Mandatory security benchmarks and tagging rules are enforced at the management group root.
* **DRY by construction:** One reader for `main.bicepparam` (compiled by Bicep, never regex-parsed), one place that defines resource naming (`Get-ResourceName`), one place that defines secret naming (`Get-WorkloadSecretName`), and one shared retry wrapper (`Invoke-WithRetry`).

## Architecture Topology
```text
Tenant Root Group 
├── mg-contoso-us (Organization Root)
│   ├─ mg-contoso-us-platform
│   │  ├─ mg-contoso-us-connectivity
│   │  │  └─ sub-contoso-us-connectivity (Subscription)
│   │  │     └─ rg-net-deploy-prod-cus-01   # Deployer UMI + OIDC (this subscription only)
│   │  │     └─ rg-net-hub-prod-cus-01      # Core Hub VNet, Azure Firewall, VPN Gateways
│   │  ├─ mg-contoso-us-identity
│   │  │  └─ sub-contoso-us-identity (Subscription)
│   │  │     ├─ rg-core-identity-cus-01 # Core Domain Controllers & Directory Sync
│   │  └─ mg-contoso-us-operations
│   │     └─ sub-contoso-us-operations (Subscription)
│   │        ├─ rg-ops-tenant-prod-cus-01   # Tenant-root deployer UMI (restricted access)
│   │        ├─ rg-ops-deploy-prod-cus-01   # Deployer UMI + OIDC (this subscription only)
│   │        └─ rg-ops-logs-prod-cus-01     # Central Log Analytics, Automation, & Monitor Dashboards
│   └─ mg-contoso-us-landingzones
│      ├─ mg-contoso-us-corp
│      │  └─ sub-contoso-us-corp (Subscription)
│      │     ├─ rg-corp-deploy-prod-cus-01    # Deployer UMI + OIDC (this subscription only)
│      │     ├─ rg-corp-workloads-prod-cus-01 # Internal Line-of-Business Application Workloads
│      │     └─ rg-corp-data-prod-cus-01      # Backend Databases & Persistent Storage Tiers
│      └─ mg-contoso-us-online
│         └─ sub-contoso-us-online (Subscription)
│            ├─ rg-online-deploy-prod-cus-01  # Deployer UMI + OIDC (this subscription only)
│            ├─ rg-online-web-prod-cus-01     # Public-Facing Web Apps & Microservices
│            └─ rg-online-edge-prod-cus-01    # Application Gateways, CDNs, & Front-End Routing
```
Resource names follow `<type>-<domain>-<purpose>-<env>-<region>-<nn>`, defined only in `Get-ResourceName`.

## Repository Structure
```text
azure-landing-zone-bicep/
│
├── .github/
│   └── workflows/
│       ├── deploy-foundation.yml        <-- MGs, policies & governance, subscription association
│       └── deploy-resources.yml         <-- *(planned)* Subscription-scoped VNets, NSGs and workload RGs
├── environments/
│   ├── dev/
│   └── prod/
│       ├── main.bicep                   <-- Tenant orchestration entry point
│       ├── main.bicepparam.example      <-- Committed parameter template (edit this)
│       ├── main.bicepparam              <-- LOCAL working copy with live IDs (gitignored)
│       ├── workloads.json               <-- Workload registry: domain, team, tags, bootstrapWorkload
│       ├── workloads.schema.json        <-- Schema checked by the preflight
│       ├── connectivity.bicep           <-- Subscription scope: hub & networking
│       ├── corp.bicep                   <-- Subscription scope: internal workloads
│       ├── identity.bicep               <-- Subscription scope: identity & directory services
│       ├── operations.bicep             <-- Subscription scope: logs & automation
│       └── online.bicep                 <-- Subscription scope: public web & edge routing
├── modules/
│   ├── management-groups/
│   │   ├── managementGroup.bicep
│   │   └── subscriptionAssociation.bicep
│   ├── governance/
│   ├── resource-groups/
│   ├── networking/
│   ├── key-vault/
│   └── landing-zones/
├── scripts/
│   ├── bootstrap/
│   │   ├── Sync-Subscriptions.ps1       <-- Phase 2: discover subscriptions, fill main.bicepparam, publish *_SUB_ID secrets
│   │   └── Initialize-TenantOidc.ps1    <-- Phase 3: tenant-level deployer identity and OIDC trust
│   ├── LandingZone.Bootstrap/           <-- Shared module used by both entry points
│   │   ├── LandingZone.Bootstrap.psd1
│   │   ├── LandingZone.Bootstrap.psm1
│   │   ├── prerequisites.psd1           <-- Minimum tool versions (single source)
│   │   ├── Private/                     <-- Internal helpers (not exported)
│   │   │   ├── Get-OidcSubject.ps1
│   │   │   ├── Get-TagDrift.ps1
│   │   │   ├── New-CheckResult.ps1
│   │   │   ├── Set-FederatedCredential.ps1
│   │   │   ├── Set-UserAssignedIdentity.ps1
│   │   │   └── Test-RootRbacAccess.ps1
│   │   └── Public/                      <-- Exported functions
│   │       ├── Find-WorkloadSubscription.ps1
│   │       ├── Get-AzureTenantId.ps1
│   │       ├── Get-BicepParamConfig.ps1
│   │       ├── Get-ResourceName.ps1
│   │       ├── Get-WorkloadConfig.ps1
│   │       ├── Get-WorkloadSecretName.ps1
│   │       ├── Initialize-BootstrapResourceGroup.ps1
│   │       ├── Initialize-DeployerIdentity.ps1
│   │       ├── Invoke-WithRetry.ps1
│   │       ├── Preflight.Checks.ps1
│   │       ├── Resolve-GitHubRepository.ps1
│   │       ├── Set-BicepParamSubscription.ps1
│   │       ├── Set-GitHubSecret.ps1
│   │       ├── Set-ResourceGroup.ps1
│   │       ├── Set-RoleAssignment.ps1
│   │       ├── Show-DeployerIdentity.ps1
│   │       └── Write-BootstrapLog.ps1
│   └── tools/
│       └── Update-ReadmePrerequisites.ps1
├── .gitignore
└── README.md
```

## Prerequisites

Minimum tool versions are defined in `scripts/LandingZone.Bootstrap/prerequisites.psd1`.

### Permissions

* **Tenant root scope (`/`):** User Access Administrator or Owner at `/`. The bootstrap assigns roles at this scope, and its preflight checks for the permission before writing anything. A Global Administrator must first enable *Elevate access to manage all Azure subscriptions and management groups* in Microsoft Entra ID.
* **Target subscriptions:** Visible to the signed-in account (any role, such as Reader) so discovery can find them with `az account list`.
* **GitHub repository:** Admin access, required to write Actions secrets.

### Required tools and versions

The table below is generated from `prerequisites.psd1`. Do not edit it by hand; regenerate it with:

```powershell
pwsh ./scripts/tools/Update-ReadmePrerequisites.ps1
```

<!-- prerequisites:start -->
| Tool | Minimum version | Install |
| :--- | :--- | :--- |
| PowerShell | 7.4 | `winget install --id Microsoft.PowerShell` |
| az | 2.60 | `winget install --id Microsoft.AzureCLI` |
| gh | 2.50 | `winget install --id GitHub.Cli` |
| git | 2.40 | `winget install --id Git.Git` |
<!-- prerequisites:end -->

The Bicep CLI is installed automatically by `az bicep` on first use. The scripts need it to read `main.bicepparam`.

## Security Model

* **No committed subscription IDs:** Live IDs exist only in the gitignored local `main.bicepparam` and in GitHub Actions secrets, both populated by `Sync-Subscriptions.ps1`. `Initialize-TenantOidc.ps1` publishes the client, tenant and root management group IDs.
* **Log hygiene:** `Sync-Subscriptions.ps1` logs workload and subscription *names*, not IDs. `Initialize-TenantOidc.ps1` prints the target subscription ID and the identity's client and principal IDs so the result can be audited. These are identifiers, not credentials, but review the output before pasting it into a public issue.
* **No long-lived credentials:** The deployer authenticates with GitHub OIDC federation. There are no client secrets to rotate or leak.
* **Least privilege, with a documented trade-off:** The tenant deployer holds Contributor, Resource Policy Contributor and User Access Administrator at `/`. This is highly privileged by operational necessity, because it creates management groups, policies and RBAC at tenant scope. The blast radius is limited by the OIDC trust, which is scoped to a single repository and the `main` branch. Hardening options for production:
  * replace Contributor with a custom role limited to the required actions,
  * add a condition to User Access Administrator so it can only assign approved roles,
  * split the identity into separate management-group and subscription deployers.


## Deployment Instructions

Run the phases in order.

| Phase | Purpose | Entry point |
| :--- | :--- | :--- |
| 1 | Pre-provision subscriptions and name them by convention | Manual (Azure portal or billing profile) |
| 2 | Subscription discovery, parameter sync and CI secrets | `Sync-Subscriptions.ps1` |
| 3 | Tenant deployer identity and OIDC trust | `Initialize-TenantOidc.ps1` |
| 4 | Management group hierarchy and policy-as-code deployment | `deploy-foundation.yml` (`main.bicep`) |
| 5 | Subscription-scoped connectivity hub (`connectivity.bicep`, `modules/networking/`) | `deploy-resources.yml` *(planned)* |

Both scripts accept the same context parameters, and both default to the `prod` environment.

| Parameter | Default | Used by | Purpose |
| :--- | :--- | :--- | :--- |
| `-Environment` | `prod` | both | Selects `environments/<env>/` |
| `-BicepParamPath` | `environments/<env>/main.bicepparam` | both | Parameter file to read |
| `-WorkloadsPath` | `environments/<env>/workloads.json` | Initialize | Workload registry |
| `-GitHubOwner`, `-GitHubRepository` | parsed from the `origin` remote | both | Override the target repository |
| `-GitHubBranch` | `main` | Initialize | Branch the OIDC trust is scoped to |
| `-Force` | off | Sync | Overwrite an ID that is already real |
| `-WhatIf` | off | Sync | Preview without writing |

### Phase 1: Pre-provisioning and subscription naming
Create the target subscriptions before running any script. Phase 2 discovers them by name, so the naming convention is the contract.

**Billing and creation constraints:** Pay-As-You-Go and personal accounts are typically capped at 5 active subscriptions and often throttle programmatic creation (about one per 24 hours). Create all five beforehand in the Azure portal or your enterprise agreement billing profile.

| Workload domain | Required naming keyword | Example subscription name |
| :--- | :--- | :--- |
| **Connectivity** | `connectivity` | `sub-contoso-us-connectivity` |
| **Corp landing zones** | `corp` | `sub-contoso-us-corp` |
| **Online landing zones** | `online` | `sub-contoso-us-online` |
| **Identity** | `identity` | `sub-contoso-us-identity` |
| **Operations** | `operations` | `sub-contoso-us-operations` |

* **Naming rule:** Each subscription name must end in `-<keyword>` (for example `-corp`), and exactly one *enabled* subscription per keyword may exist in the signed-in tenant.
* **Parameter file rule:** Edit your topology and metadata in the committed `environments/prod/main.bicepparam.example`. Create your local working copy with `copy main.bicepparam.example main.bicepparam`. Phase 2 fills in the live subscription IDs, so never type them by hand. The local file contains production IDs, is gitignored, and must never be committed.
* **Placeholders must be distinct per workload** (for example `11111111-…` for one workload and `22222222-…` for the next). Phase 2 replaces IDs by text, so two workloads sharing one placeholder would overwrite each other.

### Phase 2: Subscription discovery, parameter sync and CI secrets
**Prerequisites:** `az login` and `gh auth login` against the target tenant and repository, a local `main.bicepparam` (Phase 1), and subscriptions named per the Phase 1 convention.

Preview, then apply, from the repository root:

```powershell
pwsh ./scripts/bootstrap/Sync-Subscriptions.ps1 -WhatIf   # preview: planned ID changes and secret names; writes nothing
pwsh ./scripts/bootstrap/Sync-Subscriptions.ps1
```

What `Sync-Subscriptions.ps1` does (Azure → `main.bicepparam` → GitHub secrets):

* **Preflight gate:** Verifies tooling versions, the parameter file, a live Azure session, GitHub authentication, the git remote and repository admin access before touching anything.
* **Discovers by convention:** For each workload in `main.bicepparam`, finds the one enabled subscription in your tenant whose name ends in `-<workload>`. Zero or multiple matches abort with one message listing every offending workload. Nothing is guessed.
* **Replaces placeholders only:** Swaps placeholder IDs for discovered IDs everywhere they appear in the file, including where an ID is reused (policy exemptions). An ID that is already real is kept unless you pass `-Force`.
* **Converges idempotently:** When nothing needs to change, it writes nothing and reports `[IDEMPOTENT]`.
* **Validates before publishing:** Every ID must be a real GUID and not a placeholder before any secret is written.
* **Publishes CI secrets:** Upserts one `<WORKLOAD>_SUB_ID` secret per workload (for example `CORP_SUB_ID`) and prints a workload-to-secret summary. `deploy-foundation.yml` substitutes these into the parameter template at run time.

Full behavior and parameters: `Get-Help ./scripts/bootstrap/Sync-Subscriptions.ps1 -Full`

**Troubleshooting:**

* `expected one enabled subscription named '*-corp', found 0`: the name does not end in `-corp`, the subscription is disabled, or it is in a different tenant than your session (`az login --tenant <id>`).
* `found 2` or more: duplicates exist. Rename or disable the extras.

### Phase 3: OIDC bootstrap and identity trust

**Prerequisites:** Phase 2 has completed, so `main.bicepparam` holds real subscription IDs. The bootstrap refuses to run against placeholders. Your repository must use the immutable OIDC subject format (see [OIDC subject format](#oidc-subject-format)).

Mark your primary deployment region with `isPrimary: true` in the `regionalConfig` of your parameter file. Pair the secondary region with its Azure-paired region for high availability and disaster recovery readiness.

Run from the repository root:

```powershell
pwsh ./scripts/bootstrap/Initialize-TenantOidc.ps1
```

What `Initialize-TenantOidc.ps1` does:

* **Reads configuration once, through the Bicep compiler:** `Get-BicepParamConfig` compiles `main.bicepparam` with `az bicep build-params` and reads the resulting JSON, so there is no regex parsing. It derives the primary location, region code and subscription map. The bootstrap workload and its tags come from `workloads.json`.
* **Gates in stages:** Environment and access first (tooling, parameter file, `workloads.json` against its schema, Azure and GitHub sessions, repository admin). Then configuration (the bootstrap subscription ID is a real GUID). Then the Azure target (subscription enabled and in your tenant, `Microsoft.Resources` and `Microsoft.ManagedIdentity` registered, User Access Administrator at `/`).
* **Resolves context:** Tenant ID from your Azure session. Owner and repository from the flags, or from the `origin` remote if omitted.
* **Provisions idempotently** (get-or-create, no duplicates on re-run):
  1. Resource group `rg-<domain>-tenant-<env>-<region>-01` in the bootstrap subscription, with tags from `workloads.json`.
  2. User-assigned managed identity `id-<domain>-tenant-<env>-<region>-01`.
  3. Federated credential for `api://AzureADTokenExchange`, using the immutable subject for your repository and branch.
  4. Contributor, Resource Policy Contributor and User Access Administrator at `/`.
* **Rides out transient errors:** `Invoke-WithRetry` wraps resource group creation, tag merges and role assignment. Role assignment retries longer because a new identity can take time to replicate.
* **Publishes CI secrets:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `TENANT_ROOT_MANAGEMENT_GROUP_ID`.
* **Prints a verification summary:** The identity, resource group, client and principal IDs, credential subject, and each role with its state (`Created` or `Exists`).

**Troubleshooting:**

* `AADSTS700213` in a workflow: the token subject does not match the credential. Check the repository's OIDC subject setting against the `Subject` line the script printed, and see [OIDC subject format](#oidc-subject-format).
* `Resource group '...' exists in '<region>', expected '<region>'`: a resource group's location cannot be changed in place. The script warns and does not attempt a fix.

### Phase 4: Management group topology and deployment

> **Sequencing:** Complete Phase 3 first. Once `main.bicep` deploys the `Root-Tagging-Initiative` policy set at the management group root, later resource provisioning must comply with the enterprise tagging guardrails.

* **Customizing the topology:** Edit the management group hierarchy and subscription associations in the committed `environments/prod/main.bicepparam.example`, and mirror the change in your local `main.bicepparam` so the bootstrap scripts see the same topology.
* **Default deployment:** With no changes, the pipeline deploys the topology documented above.
* **Execution:** The parameter template feeds `main.bicep`, which drives data-driven creation of management groups, governance policies and subscription associations. The `*_SUB_ID` secrets from Phase 2 supply the live IDs at run time.
* **Trigger, watch and dump failures:**

```powershell
gh workflow run deploy-foundation.yml; gh run watch --exit-status; gh run view $(gh run list --limit 1 --json databaseId --jq '.[0].databaseId') --log-failed
```

## Idempotency behavior

Every bootstrap step reports what it did, so a second run is easy to audit.

| Step | Outcomes | Write behavior |
| :--- | :--- | :--- |
| `main.bicepparam` IDs | `[IDEMPOTENT]` or ID updated | Writes only when an ID changes; a real ID is kept without `-Force` |
| Resource group | `Created`, `TagsConverged`, `Unchanged` | Merges only missing or different tags; never removes tags added by others |
| Managed identity, credential | Reported per object | Created only if absent |
| Role assignments | `Created`, `Exists` | Existence check by principal ID, so no Graph lookup is needed |
| GitHub secrets | `Set` | Always upserted (`gh secret set` overwrites), so a re-run is safe but reports `Set` rather than `Unchanged` |

## Post-Deployment Verification

To verify that management groups, policy assignments and subscription associations have converged:

* **Management group hierarchy:**

```powershell
az account management-group list --query "[].{Name:name, DisplayName:displayName, ID:id}" --output table
```

* **Tenant subscription inventory:**

```powershell
az account list --all --output table
```

* **Inherited policy assignments at the organization root:**

```powershell
az policy assignment list --scope "/providers/Microsoft.Management/managementGroups/mg-contoso-us" --query "[].{Name:name, DisplayName:displayName, Enforcement:enforcementMode}" --output table
```

* **Scoped policy exemption:**

```powershell
$connectivitySub = az account list --query "[?ends_with(name, '-connectivity')].id | [0]" --output tsv
az policy exemption show --name "exemption-allow-hub-public-ips" --scope "/subscriptions/$connectivitySub" --output table
```

## Core Infrastructure and Connectivity

* **Phase 5:** Subscription-scoped connectivity hub deployment (`connectivity.bicep` and `modules/networking/`).
