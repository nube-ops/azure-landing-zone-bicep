function Test-RootRbacAccess {
    <#
    .SYNOPSIS
        Verifies the signed-in user holds a role at '/' that can write role assignments.
    .DESCRIPTION
        The permissions API has no tenant-root form, so we read the caller's active
        assignments instead. Azure still enforces authorization at assignment time.
    #>
    [CmdletBinding()]
    param()

    $writerRoles = @('Owner', 'User Access Administrator', 'Role Based Access Control Administrator')

    $oid   = az ad signed-in-user show --query id --output tsv 2>$null
    $roles = if ($LASTEXITCODE -eq 0 -and $oid) {
        az role assignment list --scope '/' --assignee $oid --include-inherited --include-groups `
            --query '[].roleDefinitionName' --output tsv 2>$null
    }
    $held = @($roles) | Where-Object { $_ -in $writerRoles } | Select-Object -Unique

    $ok      = [bool]$held
    $message = if ($ok) { "RBAC: $($held -join ', ') at '/'" }
               else     { "RBAC: no role at '/' that can write role assignments" }
    $fix     = if ($ok) { $null } else { "Global Administrator: enable Elevate access (Entra ID > Properties > Access management for Azure resources), then az logout / az login." }

    New-CheckResult -Name 'RbacAccess' -Ok $ok -Message $message -Remediation $fix
}