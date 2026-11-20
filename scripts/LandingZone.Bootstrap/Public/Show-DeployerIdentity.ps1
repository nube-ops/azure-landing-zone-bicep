function Show-DeployerIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Identity)

    Write-BootstrapLog "Deployer identity: $($Identity.Name) [$($Identity.IdentityState)]"
    Write-BootstrapLog "  Resource group : $($Identity.ResourceGroup)"
    Write-BootstrapLog "  Client ID      : $($Identity.ClientId)"
    Write-BootstrapLog "  Principal ID   : $($Identity.PrincipalId)"
    Write-BootstrapLog "  Credential     : $($Identity.Credential.Name) [$($Identity.Credential.Action)]"
    Write-BootstrapLog "  Subject        : $($Identity.Credential.Subject)"
    foreach ($r in $Identity.Roles) {
        Write-BootstrapLog "  Role           : $($r.Role) @ $($r.Scope) [$($r.Action)]"
    }
}