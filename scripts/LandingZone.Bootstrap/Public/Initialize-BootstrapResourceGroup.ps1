function Initialize-BootstrapResourceGroup {
    <#
    .SYNOPSIS
        Ensures a resource group exists in a workload's subscription with that workload's tags.
    .DESCRIPTION
        Single owner of subscription/location resolution and logging. Callers own the
        name (from Get-BicepParamConfig) and the tags (from Get-WorkloadConfig).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,                                  # from Get-BicepParamConfig
        [Parameter(Mandatory)][string]$Workload,                        # home workload: selects the subscription
        [Parameter(Mandatory)][string]$ResourceGroupName,               # from Get-BicepParamConfig
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tags     # from Get-WorkloadConfig
    )

    $subscriptionId = $Config.Subscriptions[$Workload]
    if (-not $subscriptionId) { throw "No subscription mapped for workload '$Workload'." }

    Write-BootstrapLog "Target: $ResourceGroupName in $($Config.PrimaryLocation) (sub $subscriptionId)"
    $rg = Set-ResourceGroup -Name $ResourceGroupName -SubscriptionId $subscriptionId `
        -Location $Config.PrimaryLocation -Tags $Tags

    $detail = if ($rg.ChangedTags.Count) { " (tags: $($rg.ChangedTags -join ', '))" } else { '' }
    Write-BootstrapLog "Resource group '$($rg.Name)': $($rg.Action)$detail" -Level Success

    [pscustomobject]@{
        Name           = $rg.Name
        SubscriptionId = $subscriptionId
        Location       = $Config.PrimaryLocation
        Action         = $rg.Action
    }
}