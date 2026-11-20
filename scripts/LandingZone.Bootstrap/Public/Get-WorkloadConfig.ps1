function Get-WorkloadConfig {
    <#
    .SYNOPSIS
        Returns what the RG and tag steps need for one workload: Domain and Tags.
    .DESCRIPTION
        workloads.json is the registry. This function exposes only the part the
        bootstrap scripts use. When security groups arrive, add a Team property here.
        Owner comes from team.name and Environment from the caller, so neither is duplicated in the file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Workload,
        [Parameter(Mandatory)][string]$Environment
    )

    $registry = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $entry    = $registry.workloads[$Workload]   # hashtable index: null instead of a StrictMode error
    if (-not $entry) { throw "Get-WorkloadConfig: workload '$Workload' is not defined in '$Path'." }

    $tags = [ordered]@{ Owner = $entry.team.name; Environment = $Environment }
    foreach ($key in $entry.tags.Keys) { $tags[$key] = $entry.tags[$key] }

    [pscustomobject]@{ Workload = $Workload; Domain = $entry.domain; Tags = $tags }
}