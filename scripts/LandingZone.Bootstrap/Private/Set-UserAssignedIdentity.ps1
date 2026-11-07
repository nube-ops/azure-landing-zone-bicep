function Set-UserAssignedIdentity {
    <# Idempotently ensures a user-assigned managed identity exists with the given tags. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$Location,
        [System.Collections.IDictionary]$Tags = @{}
    )

    $tagArgs = if ($Tags.Count) { @('--tags') + @($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) } else { @() }
    $common  = @('--name', $Name, '--resource-group', $ResourceGroupName, '--subscription', $SubscriptionId)

    $null   = az identity show @common --output none 2>$null
    $action = if ($LASTEXITCODE -eq 0) { 'Exists' } else { 'Created' }

    $json = Invoke-WithRetry -MaxRetries 3 -DelaySeconds 5 -ErrorMessage "Failed to ensure identity '$Name'." -ScriptBlock {
        az identity create @common --location $Location @tagArgs --output json
    }
    $umi = $json | ConvertFrom-Json

    [pscustomobject]@{
        Name        = $umi.name
        Id          = $umi.id
        ClientId    = $umi.clientId
        PrincipalId = $umi.principalId
        Action      = $action
    }
}