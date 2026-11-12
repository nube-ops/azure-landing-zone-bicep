function Find-WorkloadSubscription {
    <#
    .SYNOPSIS
        Maps workload keys to enabled subscriptions in a tenant by naming convention.
    .DESCRIPTION
        Matches subscription names ending in "-<workload>" (e.g. sub-contoso-us-corp -> corp).
        Fails if any workload matches zero or multiple subscriptions, so ambiguity never
        resolves silently.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Workload,
        [Parameter(Mandatory)][string]$TenantId
    )

    $json = az account list --all --output json `
        --query "[?tenantId=='$TenantId' && state=='Enabled'].{id:id,name:name}"
    if ($LASTEXITCODE -ne 0) { throw 'az account list failed.' }
    $subs = @($json | ConvertFrom-Json)

    $result   = [ordered]@{}
    $problems = @()
    foreach ($w in $Workload) {
        $pattern = "(^|-)$([regex]::Escape($w))$"
        $match   = @($subs | Where-Object { $_.name -match $pattern })
        if ($match.Count -eq 1) {
            $result[$w] = $match[0].id
            Write-BootstrapLog "${w}: matched subscription '$($match[0].name)'"
        }
        else { $problems += "  $w : expected one enabled subscription named '*-$w', found $($match.Count)" }
    }
    if ($problems) { throw "Subscription discovery failed:`n  $($problems -join "`n  ")" }
    $result
}