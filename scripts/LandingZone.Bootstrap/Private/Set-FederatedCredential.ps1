function Set-FederatedCredential {
    <# Idempotently ensures a GitHub OIDC federated credential exists on a UMI. Name is derived from the subject, so reruns converge. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IdentityName,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$Subject,
        [string]$Name = 'github-main',
        [string]$Issuer   = 'https://token.actions.githubusercontent.com',
        [string]$Audience = 'api://AzureADTokenExchange'
    )

    $credName = $Name
    if ($credName.Length -gt 120) { $credName = $credName.Substring(0, 120) }

    $common = @('--name', $credName, '--identity-name', $IdentityName,
                '--resource-group', $ResourceGroupName, '--subscription', $SubscriptionId)

    $existingJson = az identity federated-credential show @common --output json 2>$null
    $verb = 'create'; $action = 'Created'
    if ($LASTEXITCODE -eq 0) {
        $cur = $existingJson | ConvertFrom-Json
        if ($cur.subject -eq $Subject -and $cur.issuer -eq $Issuer -and $cur.audiences -contains $Audience) {
            return [pscustomobject]@{ Name = $credName; Subject = $Subject; Action = 'Unchanged' }
        }
        $verb = 'update'; $action = 'Updated'
    }

    $null = Invoke-WithRetry -MaxRetries 3 -DelaySeconds 5 -ErrorMessage "Failed to $verb federated credential '$credName'." -ScriptBlock {
        az identity federated-credential $verb @common --issuer $Issuer --subject $Subject --audiences $Audience --output none
    }
    [pscustomobject]@{ Name = $credName; Subject = $Subject; Action = $action }
}