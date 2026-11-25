# Azure Enterprise-Scale Landing Zone (Bicep & PowerShell Automation)
[![Foundation deploy](https://github.com/nube-ops/azure-landing-zone-bicep/actions/workflows/deploy-foundation.yml/badge.svg?branch=main)](https://github.com/nube-ops/azure-landing-zone-bicep/actions/workflows/deploy-foundation.yml)

A tenant-scope Azure landing zone built from code and deployed with **no stored credentials**. Bicep creates the management group hierarchy, policy guardrails and subscription associations. Idempotent PowerShell builds the GitHub OIDC trust that the pipeline deploys through. Aligned to the Microsoft Cloud Adoption Framework (CAF) Enterprise-Scale reference architecture.

**Status:** Phases 1–5 implemented and run end to end against a live tenant. Phase 6 is in progress: the resource pipeline is in place and deploys the hub and logs resource groups. Hub networking is planned.

## At a glance

| | |
| :--- | :--- |
| **Scope** | Tenant root: 8 management groups, 5 subscriptions, 6 deployer identities |
| **Governance** | 4 custom policy definitions and initiatives (tagging, allowed locations, storage hardening, tag audit), the Microsoft cloud security benchmark, and 1 scoped exemption |
| **Identity** | GitHub OIDC federated credentials on user-assigned managed identities. Zero client secrets |
| **Automation** | 3 PowerShell entry points on one shared module: preflight gates, idempotent writes, retry |
| **CI/CD** | GitHub Actions: Bicep build and lint gate on every pull request, what-if or deploy on manual dispatch only. Tenant-scope runs are serialized, and subscription-scope runs use one per-subscription deployer identity each |

## What this demonstrates

| Skill | Where to look |
| :--- | :--- |
| Bicep at tenant scope (modules, loops, exported functions, `.bicepparam`) | [`environments/prod/main.bicep`](environments/prod/main.bicep), [`modules/`](modules) |
| Azure Policy as code (initiatives, assignments, exemptions) | [`modules/governance/`](modules/governance) |
| Workload identity federation and RBAC | [`Initialize-TenantOidc.ps1`](scripts/bootstrap/Initialize-TenantOidc.ps1), [`Initialize-SubscriptionOidc.ps1`](scripts/bootstrap/Initialize-SubscriptionOidc.ps1) |
| Production-style PowerShell (preflight, `-WhatIf`, retry, drift-only writes) | [`scripts/LandingZone.Bootstrap/`](scripts/LandingZone.Bootstrap) |
| CI/CD with what-if preview, a lint gate and a per-subscription identity matrix | [`deploy-foundation.yml`](.github/workflows/deploy-foundation.yml), [`deploy-resources.yml`](.github/workflows/deploy-resources.yml) |
| Naming and tagging standards that feed cost allocation | [`workloads.json`](environments/prod/workloads.json), [`naming.bicep`](modules/resource-groups/naming.bicep) |

## Architecture Topology
```text
Tenant Root Group 
├── mg-contoso-us (Organization Root)
│   ├─ mg-contoso-us-platform
│   │  ├─ mg-contoso-us-connectivity
│   │  │  └─ sub-contoso-us-connectivity (Subscription)
│   │  │     ├─ rg-net-deploy-prod-cus-01   # Deployer UMI + OIDC (this subscription only)
│   │  │     └─ rg-net-hub-prod-cus-01      # Hub VNet, Azure Firewall, VPN gateways
│   │  ├─ mg-contoso-us-identity
│   │  │  └─ sub-contoso-us-identity (Subscription)
│   │  │     ├─ rg-id-deploy-prod-cus-01    # Deployer UMI + OIDC (this subscription only)
│   │  │     └─ rg-id-core-prod-cus-01      # (planned) Domain controllers, directory sync
│   │  └─ mg-contoso-us-operations
│   │     └─ sub-contoso-us-operations (Subscription)
│   │        ├─ rg-ops-tenant-prod-cus-01   # Tenant-root deployer UMI (restricted access)
│   │        ├─ rg-ops-deploy-prod-cus-01   # Deployer UMI + OIDC (this subscription only)
│   │        └─ rg-ops-logs-prod-cus-01     # Log Analytics, automation, dashboards
│   └─ mg-contoso-us-landingzones
│      ├─ mg-contoso-us-corp
│      │  └─ sub-contoso-us-corp (Subscription)
│      │     ├─ rg-corp-deploy-prod-cus-01    # Deployer UMI + OIDC (this subscription only)
│      │     ├─ rg-corp-workloads-prod-cus-01 # (planned) Line-of-business workloads
│      │     └─ rg-corp-data-prod-cus-01      # (planned) Databases and persistent storage
│      └─ mg-contoso-us-online
│         └─ sub-contoso-us-online (Subscription)
│            ├─ rg-online-deploy-prod-cus-01  # Deployer UMI + OIDC (this subscription only)
│            ├─ rg-online-web-prod-cus-01     # (planned) Public web apps and microservices
│            └─ rg-online-edge-prod-cus-01    # (planned) Application gateways, CDN, front-end routing
```
Resource names follow `<type>-<domain>-<purpose>-<env>-<region>-<nn>`, defined once per language: `Get-ResourceName` for the scripts and `naming.bicep` for Bicep. `contoso` is a placeholder organization name.


## Design decisions

* **Data-driven:** `main.bicep` holds no organization-specific values. Hierarchy, regions and subscription mappings live in one parameter file. Workload identity and tags live in a schema-validated registry (`workloads.json`).
* **The compiler is the parser:** `main.bicepparam` is read by compiling it with `az bicep build-params`, never with regular expressions.
* **Check everything, then write:** each script runs read-only preflight stages (tooling, sessions, permissions, data) and aborts with remediation steps before it changes anything.
* **Idempotent by design:** get-or-create and drift-only writes. A re-run with nothing to change writes nothing. Tags are merged, so tags added by others are never removed.
* **Audit before enforce:** the Microsoft cloud security benchmark is assigned as `DoNotEnforce` and is one parameter away from enforcement.
* **Defensive details:** the OIDC subject uses the repository's immutable numeric IDs, policy assignment names are length-safe by construction, and role assignment retries absorb managed identity replication delay.

## Security model

* **No stored credentials:** GitHub Actions and the bootstrap identities authenticate with short-lived OIDC tokens. There are no client secrets or certificates to rotate or leak.
* **No committed identifiers:** the committed parameter file uses placeholder subscription IDs. Live IDs exist only in a gitignored local file and in GitHub Actions secrets, and the workflow substitutes them at run time. History was scanned for live identifiers before publishing.
* **Log hygiene:** `Sync-Subscriptions.ps1` logs workload and subscription names, not IDs. The two `Initialize-*Oidc.ps1` scripts print the target subscription, client and principal IDs so the result can be audited, so redact their output before sharing it.
* **Least privilege, with documented trade-offs:**
  * The tenant deployer holds Contributor, Resource Policy Contributor and User Access Administrator at `/`, because it creates management groups, policy and RBAC at tenant scope.
  * Each subscription deployer holds Contributor on its own subscription only.
  * Trust is scoped to one repository and the `main` branch, and the deploy job runs only on manual dispatch.
* **Known limits and next hardening steps:**
  * Replace Contributor at `/` with a custom role limited to the required actions.
  * Add a condition to User Access Administrator so it can assign only approved roles.
  * Secrets are repository-level and the credential subject is branch-based, so any workflow on `main` can use any deployer. Environment-scoped credentials would narrow this.

## Quick start

Requires PowerShell 7.4+, `az`, `gh` and `git`. Create five subscriptions named `*-connectivity`, `*-identity`, `*-operations`, `*-corp` and `*-online` first. The full runbook is [below](#runbook).

```powershell
Copy-Item environments/prod/main.bicepparam.example environments/prod/main.bicepparam
pwsh ./scripts/bootstrap/Sync-Subscriptions.ps1 -WhatIf   # preview, writes nothing
pwsh ./scripts/bootstrap/Sync-Subscriptions.ps1           # Phase 2: discover subscriptions, publish secrets
pwsh ./scripts/bootstrap/Initialize-TenantOidc.ps1        # Phase 3: tenant deployer identity + OIDC
gh workflow run deploy-foundation.yml -f mode=what-if     # Phase 4: preview
gh workflow run deploy-foundation.yml -f mode=deploy      # Phase 4: apply
pwsh ./scripts/bootstrap/Initialize-SubscriptionOidc.ps1  # Phase 5: per-subscription deployer identities
```

## Deployment phases

| Phase | Purpose | Entry point | Status |
| :--- | :--- | :--- | :--- |
| 1 | Pre-provision subscriptions named by convention | Manual | Done |
| 2 | Subscription discovery, parameter sync, CI secrets | `Sync-Subscriptions.ps1` | Done |
| 3 | Tenant deployer identity and OIDC trust | `Initialize-TenantOidc.ps1` | Done |
| 4 | Management groups, subscription associations, policy as code | `deploy-foundation.yml` | Done |
| 5 | Per-subscription deployer identities and OIDC trust | `Initialize-SubscriptionOidc.ps1` | Done |
| 6 | Hub and logs resource groups, then hub networking and workload resource groups | `deploy-resources.yml` | In progress |

## Prerequisites

Minimum versions are defined in `scripts/LandingZone.Bootstrap/prerequisites.psd1`. Required permissions are listed in the [runbook](#permissions).

<!-- prerequisites:start -->
| Tool | Minimum version | Install |
| :--- | :--- | :--- |
| PowerShell | 7.4 | `winget install --id Microsoft.PowerShell` |
| az | 2.60 | `winget install --id Microsoft.AzureCLI` |
| gh | 2.50 | `winget install --id GitHub.Cli` |
| git | 2.40 | `winget install --id Git.Git` |
<!-- prerequisites:end -->

The table is generated: run `pwsh ./scripts/tools/Update-ReadmePrerequisites.ps1` instead of editing it by hand. The Bicep CLI is installed by `az bicep` on first use.

## Repository Structure
```text
azure-landing-zone-bicep/
│
├── .github/
│   ├── actions/setup-bicep/             <-- Composite action: Bicep install with retry
│   ├── dependabot.yml                   <-- Weekly GitHub Actions version updates
│   └── workflows/
│       ├── deploy-foundation.yml        <-- MGs, policies & governance, subscription association
│       └── deploy-resources.yml         <-- Subscription-scoped VNets, NSGs and workload RGs
├── environments/
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
│   ├── governance/
│   ├── resource-groups/
│   ├── networking/                     <-- (planned)
│   └── key-vault/                      <-- (planned)
├── scripts/
│   ├── bootstrap/
│   │   ├── Sync-Subscriptions.ps1       <-- Phase 2: discover subscriptions, fill main.bicepparam, publish *_SUB_ID secrets
│   │   ├── Initialize-TenantOidc.ps1    <-- Phase 3: tenant-level deployer identity and OIDC trust
│   │   └── Initialize-SubscriptionOidc.ps1   <-- Phase 5: per-subscription deployer identities and OIDC trust
│   ├── LandingZone.Bootstrap/           <-- Shared module used by all entry points
│   │   ├── LandingZone.Bootstrap.psd1/.psm1  <-- Module manifest and loader
│   │   ├── prerequisites.psd1           <-- Minimum tool versions (single source)
│   │   ├── Private/                     <-- Internal helpers (not exported)
│   │   └── Public/                      <-- Preflight checks, naming, identity, RBAC, GitHub secrets
│   └── tools/Update-ReadmePrerequisites.ps1
├── .gitignore
└── README.md
```

## Runbook

Operator reference for each phase. Run every command from the repository root.

### Permissions

| Phase | Needs |
| :--- | :--- |
| 2 | Reader on the target subscriptions (so `az account list` can find them) |
| 3 | User Access Administrator or Owner at tenant root `/`, plus Contributor or Owner on the bootstrap (operations) subscription |
| 4 | Write access to the GitHub repository to dispatch the workflow. The deployer identity from Phase 3 does the Azure work |
| 5 | Owner on each target subscription (or Contributor plus User Access Administrator). Tenant-root rights are not needed |
| All | Admin on the GitHub repository, to write Actions secrets |
| 6 | Write access to the GitHub repository to dispatch the workflow, from `main`. The Phase 5 deployer identities do the Azure work |

To get rights at `/`, a Global Administrator must first enable *Elevate access to manage all Azure subscriptions and management groups* in Microsoft Entra ID, then you run `az logout` and `az login`.

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
* **Parameter file rule:** Edit your topology and metadata in the committed `environments/prod/main.bicepparam.example`. Create your local working copy with `Copy-Item environments/prod/main.bicepparam.example environments/prod/main.bicepparam`. Phase 2 fills in the live subscription IDs, so never type them by hand. The local file contains production IDs, is gitignored, and must never be committed.
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
* **Log hygiene:** logs workload and subscription *names*, not IDs.

Full behavior and parameters: `Get-Help ./scripts/bootstrap/Sync-Subscriptions.ps1 -Full`

**Troubleshooting:**

* `expected one enabled subscription named '*-corp', found 0`: the name does not end in `-corp`, the subscription is disabled, or it is in a different tenant than your session (`az login --tenant <id>`).
* `found 2` or more: duplicates exist. Rename or disable the extras.

### Phase 3: OIDC bootstrap and identity trust

**Prerequisites:** Phase 2 has completed, so `main.bicepparam` holds real subscription IDs. The bootstrap refuses to run against placeholders, and the OIDC subject must match your repository and branch (see `Get-OidcSubject` in `scripts/LandingZone.Bootstrap/Private/Get-OidcSubject.ps1`).

Mark your primary region with `isPrimary: true` in `regionalConfig`, and pair the secondary region with its Azure-paired region.

Run from the repository root:
```powershell
pwsh ./scripts/bootstrap/Initialize-TenantOidc.ps1
```

What `Initialize-TenantOidc.ps1` does:

* **Reads configuration once, through the Bicep compiler:** `Get-BicepParamConfig` compiles `main.bicepparam` with `az bicep build-params` and reads the resulting JSON, so there is no regex parsing. It derives the primary location, region code and subscription map. The bootstrap workload and its tags come from `workloads.json`.
* **Gates in stages:** Environment and access first (tooling, parameter file, `workloads.json` against its schema, Azure and GitHub sessions, repository admin). Then configuration (the bootstrap subscription ID is a real GUID). Then the Azure target (subscription enabled and in your tenant, a role at `/` that can write role assignments).
* **Registers providers:** `Microsoft.Resources` and `Microsoft.ManagedIdentity` are registered in the bootstrap subscription only if needed.
* **Provisions idempotently** (get-or-create, no duplicates on re-run):
  1. Resource group `rg-<domain>-tenant-<env>-<region>-01` in the bootstrap subscription, with tags from `workloads.json`.
  2. User-assigned managed identity `id-<domain>-tenant-<env>-<region>-01`.
  3. Federated credential for `api://AzureADTokenExchange`, using the immutable subject for your repository and branch.
  4. Contributor, Resource Policy Contributor and User Access Administrator at `/`.
* **Rides out transient errors:** `Invoke-WithRetry` wraps resource group creation, tag merges and role assignment. Role assignment retries longer because a new identity can take time to replicate.
* **Publishes CI secrets:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `TENANT_ROOT_MANAGEMENT_GROUP_ID`.
* **Prints a verification summary:** The identity, resource group, client and principal IDs, credential subject, and each role with its state (`Created` or `Exists`).

**Troubleshooting:**

* `AADSTS700213` in a workflow: the token subject does not match the credential. Compare the `Subject` line printed by the bootstrap script against your federated credential and repository settings.
* `Resource group '...' exists in '<region>', expected '<region>'`: a resource group's location cannot be changed in place. The script warns and does not attempt a fix.

### Phase 4: Management group topology and deployment

> **Sequencing:** Complete Phases 2 and 3 first. Once `main.bicep` deploys the policy sets at the management group root, everything provisioned afterwards must comply with the tagging and allowed-location guardrails. Phase 5 is the first step that runs under them.

* **Customizing the topology:** Edit the management group hierarchy and subscription associations in the committed `environments/prod/main.bicepparam.example`, and mirror the change in your local `main.bicepparam` so the bootstrap scripts see the same topology.
* **Default deployment:** With no changes, the pipeline deploys the topology documented above.
* **Execution:** the workflow copies the template, substitutes the `*_SUB_ID` secrets from Phase 2, resolves the deployment location from the primary region, authenticates with OIDC, and runs a tenant-scope deployment of `main.bicep`.
* **Pull requests** run only the Bicep build and lint gate. The deploy job is skipped, because the OIDC credential trusts `main` only.
* **Trigger, watch and dump failures:**

The workflow defaults to `what-if` and changes nothing until dispatched with `mode=deploy`.

```powershell
gh workflow run deploy-foundation.yml -f mode=what-if    # preview
gh workflow run deploy-foundation.yml -f mode=deploy     # apply

Start-Sleep -Seconds 5                                    # let the new run register
$id = gh run list --workflow deploy-foundation.yml --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $id --exit-status
gh run view $id --log-failed                              # only if it failed
```

Run logs on a public repository are public. Secret values are masked, but other identifiers in command output are not, so the deploy step prints only the provisioning state.

**Post-Deployment Verification:** 
```powershell
# Management group hierarchy
az account management-group list --query "[].{Name:name, DisplayName:displayName, ID:id}" --output table

# Subscription inventory
az account list --all --output table

# Policy assignments at the organization root
az policy assignment list --scope "/providers/Microsoft.Management/managementGroups/mg-contoso-us" --query "[].{Name:name, DisplayName:displayName, Enforcement:enforcementMode}" --output table

# Scoped policy exemption
$connectivitySub = az account list --query "[?ends_with(name, '-connectivity')].id | [0]" --output tsv
az policy exemption show --name "exemption-allow-hub-public-ips" --scope "/subscriptions/$connectivitySub" --output table
```

### Phase 5: Subscription deployer identities

**Prerequisites:** Phase 2 has completed (real subscription IDs; placeholders are refused) and Phase 4 was applied with `mode=deploy`, so the management groups, subscription associations and policy assignments exist. The resource groups created here are then evaluated by the root policies (allowed locations and required tags). The tags come from `workloads.json`, so they satisfy the tagging guardrails.

```powershell
pwsh ./scripts/bootstrap/Initialize-SubscriptionOidc.ps1
pwsh ./scripts/bootstrap/Initialize-SubscriptionOidc.ps1 -Workload corp,online   # optional subset
```

Per workload, idempotently:
* **Gates first:** tooling, parameter file, `workloads.json` against its schema, Azure and GitHub sessions, then per subscription: enabled, in your tenant, and able to write role assignments.
* **Registers providers:** `Microsoft.Resources` and `Microsoft.ManagedIdentity` are registered only if needed, because a subscription never used with Azure Resource Manager has them unregistered.
* **Provisions:** resource group `rg-<domain>-deploy-<env>-<region>-01` with tags from `workloads.json`, user-assigned managed identity `id-<domain>-deploy-<env>-<region>-01`, and the GitHub OIDC credential.
* **Assigns least privilege:** Contributor on that subscription only, not at `/`.
* **Publishes CI secrets:** one `<WORKLOAD>_CLIENT_ID` secret per workload (for example `CORP_CLIENT_ID`).

The operations subscription ends up with two identities: the tenant deployer from Phase 3 (`rg-ops-tenant-...`) and its own subscription deployer (`rg-ops-deploy-...`).

This phase deploys no workload resources. The `*_CLIENT_ID` secrets are consumed by `deploy-resources.yml` (Phase 6).

### Phase 6: Subscription resources (in progress)

**Prerequisites:** Phases 4 and 5 are done, so the policies exist and each subscription has its deployer identity and `<WORKLOAD>_CLIENT_ID` / `<WORKLOAD>_SUB_ID` secrets. The workflow must be dispatched from `main`, because the OIDC credential trusts that branch only.

```powershell
gh workflow run deploy-resources.yml -f mode=what-if    # preview
gh workflow run deploy-resources.yml -f mode=deploy     # apply
```

* **One job per workload:** a matrix signs in with that workload's own deployer identity (Contributor on its subscription only) and deploys `environments/<env>/<workload>.bicep` at subscription scope. Runs for different subscriptions can run in parallel, and runs for the same subscription never overlap.
* **Current scope:** `connectivity` and `operations` (the hub and logs resource groups). `corp`, `identity` and `online` are placeholders with no resources yet. Add each to the matrix when it gets some.
* **Parameters:** primary location and region code are read from `main.bicepparam.example` with the Bicep compiler. The environment comes from the matrix.
* **Verify:**
  ```powershell
  foreach ($sub in (az account list --query "[].id" -o tsv)) { az group list --subscription $sub --query "[?contains(name,'-hub-') || contains(name,'-logs-')].name" -o tsv }
  ```
* **Planned:** `modules/networking/` (hub VNet and subnets) comes next. Firewall, gateways and spoke peering are deferred until a spoke needs them.

Built by Osvaldo Ceballos.
