function Get-AzureTenantId {
    <#
    .SYNOPSIS
        Returns the tenant ID of the active Azure CLI session.
    .DESCRIPTION
        Throws a clear error instead of a null-reference on .Trim() when there is no session.
        Run Test-AzureSession in the environment gate first for a live-token check.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $tenantId = az account show --query tenantId --output tsv
    if ($LASTEXITCODE -ne 0 -or -not $tenantId) {
        throw "Get-AzureTenantId: no active Azure CLI session. Run 'az login'."
    }
    "$tenantId".Trim()
}