function Get-OidcSubject {
    <# Builds the GitHub Actions OIDC subject claim for a branch. Pure function: no side effects. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repository,
        [string]$Branch = 'main'
    )
    $json = gh api "repos/$Owner/$Repository" --jq '{repoId: .id, ownerId: .owner.id}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        throw "Could not resolve numeric IDs for '$Owner/$Repository'. Ensure 'gh' is authenticated; name-based subjects fail with AADSTS700213."
    }
    $ids = $json | ConvertFrom-Json
    'repo:{0}@{1}/{2}@{3}:ref:refs/heads/{4}' -f $Owner, $ids.ownerId, $Repository, $ids.repoId, $Branch
}