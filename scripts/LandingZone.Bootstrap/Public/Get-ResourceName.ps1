function Get-ResourceName {
    <#
    .SYNOPSIS
        Builds a CAF-style resource name: <type>-<domain>-<purpose>-<env>-<region>-<nn>.
    .DESCRIPTION
        The only place the naming convention is defined. Pure and offline: no Azure calls,
        no config reads. Add a Type to the ValidateSet only when a script needs one.
    .EXAMPLE
        $name = @{ Domain = 'ops'; Purpose = 'tenant'; Environment = 'prod'; RegionCode = 'cus' }
        Get-ResourceName -Type rg @name   # rg-ops-tenant-prod-cus-01
        Get-ResourceName -Type id @name   # id-ops-tenant-prod-cus-01
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateSet('rg', 'id')][string]$Type,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+$')][string]$Domain,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+$')][string]$Purpose,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+$')][string]$Environment,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+$')][string]$RegionCode,
        [ValidateRange(1, 99)][int]$Instance = 1
    )

    '{0}-{1}-{2}-{3}-{4}-{5:d2}' -f $Type, $Domain, $Purpose, $Environment, $RegionCode, $Instance
}