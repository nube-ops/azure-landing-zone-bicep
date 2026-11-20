function Set-BicepParamSubscription {
    <#
    .SYNOPSIS
        Converges the subscription IDs in a main.bicepparam file to the desired values.
    .DESCRIPTION
        Replaces every occurrence of a workload's current ID, including where it is reused
        (policy exemptions). A current ID that already passes Test-SubscriptionIdFormat is
        treated as deliberate and kept unless -Force. Writes nothing when already converged.
        Takes Current from Get-BicepParamConfig so the file is compiled once, not twice.
    .OUTPUTS
        [hashtable] the effective workload -> ID map (the planned one under -WhatIf)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Current,   # Get-BicepParamConfig .Subscriptions
        [Parameter(Mandatory)][System.Collections.IDictionary]$Desired,   # Find-WorkloadSubscription
        [switch]$Force
    )

    $text      = Get-Content -LiteralPath $Path -Raw
    $effective = @{}
    $replaced  = 0

    $dupes = $Current.GetEnumerator() | Group-Object Value | Where-Object Count -gt 1
    if ($dupes -and -not $Force) {
        throw "Workloads share the same subscription ID value; cannot safely replace by text: $($dupes.Name -join ', ')"
    }

    foreach ($workload in ($Current.Keys | Sort-Object)) {
        $old = $Current[$workload]
        $new = $Desired[$workload]
        $effective[$workload] = $old
        if (-not $new -or $old -eq $new) { continue }

        if (-not $Force -and (Test-SubscriptionIdFormat -Workload $workload -SubscriptionId $old).Ok) {
            Write-BootstrapLog "${workload} keeps its current ID; discovery found a different subscription. Use -Force to overwrite." -Level Warning
            continue
        }
        $text = $text.Replace($old, $new)
        $effective[$workload] = $new
        $replaced++
        Write-BootstrapLog "${workload}: subscription ID updated"
    }

    if ($replaced -eq 0) {
        Write-BootstrapLog 'main.bicepparam subscription IDs already converged.' -Level Idempotent
        return $effective
    }
    if ($PSCmdlet.ShouldProcess($Path, "Replace $replaced subscription ID(s)")) {
        Set-Content -LiteralPath $Path -Value $text -NoNewline
    }
    $effective
}