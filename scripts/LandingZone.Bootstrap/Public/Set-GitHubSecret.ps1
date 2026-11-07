# AFTER – Public\Set-GitHubSecret.ps1
function Set-GitHubSecret {
    <# Upserts a repo (or environment) secret. 'gh secret set' overwrites, so reruns are safe.
       The value goes through stdin and is never printed. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repository,      # owner/repo
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Value,
        [string]$Environment
    )
    $ghArgs = @('secret', 'set', $Name, '--repo', $Repository)
    if ($Environment) { $ghArgs += @('--env', $Environment) }

    $out = $Value | gh @ghArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set secret '$Name' on '$Repository': $out" }
    Write-BootstrapLog "Secret '$Name': Set" -Level Success
}