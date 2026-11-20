function Set-ProviderRegistration {
    <# Idempotently ensures resource providers are registered in a subscription. Registers only when needed and waits for completion. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string[]]$Namespace
    )

    foreach ($ns in $Namespace) {
        $state = "$(az provider show --namespace $ns --subscription $SubscriptionId --query registrationState --output tsv)".Trim()
        if ($LASTEXITCODE -ne 0) { throw "Could not read provider '$ns' in $SubscriptionId." }

        if ($state -eq 'Registered') {
            [pscustomobject]@{ Namespace = $ns; Action = 'Exists' }
            continue
        }

        $null = Invoke-WithRetry -ErrorMessage "Could not register provider '$ns' in $SubscriptionId." -ScriptBlock {
            az provider register --namespace $ns --subscription $SubscriptionId --wait --output none
        }
        [pscustomobject]@{ Namespace = $ns; Action = 'Registered' }
    }
}