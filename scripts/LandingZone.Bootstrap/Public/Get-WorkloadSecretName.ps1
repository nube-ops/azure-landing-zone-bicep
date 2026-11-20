function Get-WorkloadSecretName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Workload,
        [Parameter(Mandatory)][ValidateSet('SubId', 'ClientId')][string]$Kind
    )
    $suffix = @{ SubId = 'SUB_ID'; ClientId = 'CLIENT_ID' }[$Kind]
    # Secret names can't contain '-', and workload names may (^[a-z0-9-]+$ in the schema).
    '{0}_{1}' -f $Workload.ToUpperInvariant().Replace('-', '_'), $suffix
}