function Set-RoleAssignment {
    <# Idempotently ensures a role assignment exists. Existence check uses principalId, so no Graph lookup is needed on a brand-new identity. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Scope,
        [string]$PrincipalType = 'ServicePrincipal'
    )

    $count = az role assignment list --scope $Scope --role $Role `
        --query "[?principalId=='$PrincipalId' && scope=='$Scope'] | length(@)" --output tsv
    if ($LASTEXITCODE -ne 0) { throw "Failed to list role assignments for '$Role' at '$Scope'." }
    if ([int]$count -gt 0) {
        return [pscustomobject]@{ Role = $Role; Scope = $Scope; Action = 'Exists' }
    }

    # Longer retry: a just-created UMI can take a while to replicate (PrincipalNotFound).
    $null = Invoke-WithRetry -MaxRetries 5 -DelaySeconds 10 -ErrorMessage "Failed to assign '$Role' at '$Scope'." -ScriptBlock {
        az role assignment create --assignee-object-id $PrincipalId --assignee-principal-type $PrincipalType `
            --role $Role --scope $Scope --output none
    }
    [pscustomobject]@{ Role = $Role; Scope = $Scope; Action = 'Created' }
}