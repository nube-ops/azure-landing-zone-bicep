function Resolve-GitHubRepository {
    [CmdletBinding()]
    param([string]$Owner, [string]$Repository)

    # Explicit values win; the git remote is only parsed to fill what is missing.
    $resolvedOwner = $Owner
    $resolvedRepo  = $Repository

    if (-not ($Owner -and $Repository)) {
        $remoteUrl = "$(git config --get remote.origin.url 2>$null)".Trim()
        if (-not ($remoteUrl -match 'github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$')) {
            throw "Git remote 'origin' is missing or not a GitHub URL (found: '$remoteUrl')."
        }
        if (-not $resolvedOwner) { $resolvedOwner = $Matches[1] }
        if (-not $resolvedRepo)  { $resolvedRepo  = $Matches[2] }
    }

    [pscustomobject]@{
        Owner      = $resolvedOwner
        Repository = $resolvedRepo
        Slug       = "$resolvedOwner/$resolvedRepo"
    }
}