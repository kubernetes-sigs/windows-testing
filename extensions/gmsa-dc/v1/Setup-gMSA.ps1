<#
 .SYNOPSIS
 This script will automate the creation of a Group Managed Service Account,
 install the account locally, produce the JSON file with gMSA info, and convert
 it to the Yaml file needed.

 .NOTES
 This is only for automated e2e testing.  DO NOT use this for production.
 Jeremy Wood (JeremyWx)
 Version: 1.0.0.0
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# Set script variables
$GMSARoot = "C:\gmsa"

# Function to check AD services
function CheckADServices()
	{
	Sleep 4
	$svcs = "adws","dns","kdc","netlogon","ntds","lanmanserver","lanmanworkstation"
    $svcstatus = 0
        foreach ( $svc in $svcs ) {
            if ( $(Get-Service -Name $svc).Status -notlike "Running") {
                $svcstatus += 1
            }
        }

    if ($svcstatus -gt 0) {
        return $false
        } else {
        return $true
        }
    }

# Function to make sure AD is fully up
function CheckGroup()
    {
    try {
        Sleep 2
        $x = Get-AdGroupMember -Identity "Enterprise Admins"
        return $true
    } catch {
        return $false
        }
    }

# Function to import Active Directory PowerShell module without error
function ImportADPS()
    {
    try {
        Import-Module ActiveDirectory
        return $true
    } catch {
        return $false
        }
    }
	
function New-CredentialSpec {

    <#
    This function was borrowed from https://github.com/MicrosoftDocs/Virtualization-Documentation/blob/master/windows-server-container-tools/ServiceAccounts/CredentialSpec.psm1
	#>

    [CmdletBinding(DefaultParameterSetName = "DefaultPath")]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $AccountName,

        [Parameter(Mandatory = $true, ParameterSetName = "CustomPath")]
        [String]
        $Path,

        [Parameter(Mandatory = $false, ParameterSetName = "DefaultPath")]
        [Alias("Name")]
        [String]
        $FileName,

        [Parameter(Mandatory = $false)]
        [string]
        $Domain,

        [Parameter(Mandatory = $false)]
        [object[]]
        $AdditionalAccounts,

        [Parameter(Mandatory = $false)]
        [switch]
        $NoClobber = $false
    )

    # Validate domain information
    if ($Domain) {
        $ADDomain = Get-ADDomain -Server $Domain -ErrorAction Continue

        if (-not $ADDomain) {
            Write-Error "The specified Active Directory domain ($Domain) could not be found.`nCheck your network connectivity and domain trust settings to ensure the current user can authenticate to a domain controller in that domain."
            return
        }
    } else {
        # Use the logged on user's domain if an explicit domain name is not provided
        $ADDomain = Get-ADDomain -Current LocalComputer -ErrorAction Continue

        if (-not $ADDomain) {
            Write-Error "An error ocurred while loading information for the computer account's domain.`nCheck your network connectivity to ensure the computer can authenticate to a domain controller in this domain."
            return
        }

        $Domain = $ADDomain.DNSRoot
	}
    # Clean up account names and validate formatting
    $AccountName = $AccountName.TrimEnd('$')

    if ($AdditionalAccounts) {
        $AdditionalAccounts = $AdditionalAccounts | ForEach-Object {
            if ($_ -is [hashtable]) {
                # Check for AccountName and Domain keys
                if (-not $_.AccountName -or -not $_.Domain) {
                    Write-Error "Invalid additional account specified: $_`nExpected a samAccountName or a hashtable containing AccountName and Domain keys."
                    return
                }
                else {

                    @{
                        AccountName = $_.AccountName.TrimEnd('$')
                        Domain = $_.Domain
                    }
                }
            }
            elseif ($_ -is [string]) {
                @{
                    AccountName = $_.TrimEnd('$')
                    Domain = $Domain
                }
            }
            else {
                Write-Error "Invalid additional account specified: $_`nExpected a samAccountName or a hashtable containing AccountName and Domain keys."
                return
            }
        }
    }

    # Get the location to store the cred spec file either from input params or helper function
    if ($Path) {
        $CredSpecRoot = Split-Path $Path -Parent
        $FileName = Split-Path $Path -Leaf
    } else {
        $CredSpecRoot = "C:\ProgramData\docker\credentialspecs"
    }

    if (-not $FileName) {
        $FileName = "{0}_{1}" -f $ADDomain.NetBIOSName.ToLower(), $AccountName.ToLower()
    }

    $FullPath = Join-Path $CredSpecRoot "$($FileName.TrimEnd(".json")).json"
    if ((Test-Path $FullPath) -and $NoClobber) {
        Write-Error "A credential spec already exists with the name `"$FileName`".`nRemove the -NoClobber switch to overwrite this file or select a different name using the -FileName parameter."
        return
    }

    # Start hash table for output
    $output = @{}

    # Create ActiveDirectoryConfig Object
    $output.ActiveDirectoryConfig = @{}
    $output.ActiveDirectoryConfig.GroupManagedServiceAccounts = @( @{"Name" = $AccountName; "Scope" = $ADDomain.DNSRoot } )
    $output.ActiveDirectoryConfig.GroupManagedServiceAccounts += @{"Name" = $AccountName; "Scope" = $ADDomain.NetBIOSName }
    if ($AdditionalAccounts) {
        $AdditionalAccounts | ForEach-Object {
            $output.ActiveDirectoryConfig.GroupManagedServiceAccounts += @{"Name" = $_.AccountName; "Scope" = $_.Domain }
        }
    }
    
    # Create CmsPlugins Object
    $output.CmsPlugins = @("ActiveDirectory")

    # Create DomainJoinConfig Object
    $output.DomainJoinConfig = @{}
    $output.DomainJoinConfig.DnsName = $ADDomain.DNSRoot
    $output.DomainJoinConfig.Guid = $ADDomain.ObjectGUID
    $output.DomainJoinConfig.DnsTreeName = $ADDomain.Forest
    $output.DomainJoinConfig.NetBiosName = $ADDomain.NetBIOSName
    $output.DomainJoinConfig.Sid = $ADDomain.DomainSID.Value
    $output.DomainJoinConfig.MachineAccountName = $AccountName

    $output | ConvertTo-Json -Depth 5 | Out-File -FilePath $FullPath -Encoding ascii -NoClobber:$NoClobber
	
	Install-Module powershell-yaml -Force

    $CredSpecJson = Get-Item $FullPath | Select-Object @{
        Name       = 'Name'
        Expression = { $_.Name }
    },
    @{
        Name       = 'Path'
        Expression = { $_.FullName }
    }
	
	# This section of code borrowed from https://github.com/kubernetes-sigs/windows-gmsa/blob/master/scripts/GenerateCredentialSpecResource.ps1
    $dockerCredSpecPath = $CredSpecJson.Path
    Sleep 2
    $credSpecContents = Get-Content $dockerCredSpecPath | ConvertFrom-Json
    $ManifestFile = "gmsa-cred-spec-gmsa-e2e.yml"
	
	# generate the k8s resource
    $resource = [ordered]@{
        "apiVersion" = "windows.k8s.io/v1alpha1";
        "kind" = 'GMSACredentialSpec';
        "metadata" = @{
        "name" = $AccountName
        };
        "credspec" = $credSpecContents
    }

ConvertTo-Yaml $resource | Set-Content $ManifestFile

Write-Output "K8S manifest rendered at $ManifestFile"
}

# Change to working directory
Set-Location -Path $GMSARoot

# Script Logging - Feel free to comment out if you like.
Start-Transcript -Path "$GMSARoot\Setup-gmsa.txt" -Append
# Making sure the AD services are up and running
do {$ADresult = CheckADServices} while ($ADresult -eq $false)

# Import Active Directory PowerShell module
do {$ADPSresult = ImportADPS} while ($ADPSresult -eq $false)

# Make sure AD server instance is listening on port
do {$CGresult = CheckGroup} while ($CGresult -eq $false)


if (Get-AdGroupMember -Identity "Enterprise Admins" | Select-String -Pattern "gmsa-admin" -Quiet) {
    
    # Add the KDS Root Key
    $KdsRootKey = Get-KdsRootKey
    if ($KdsRootKey -eq $null) {
        # This command creates the KDS Root Key with a time 10 hours in the past.
        # Active Directory will not permit use of this key until at least 10 hours has
        # passed to allow distribution to all Domain Controllers in the domain.
        # https://docs.microsoft.com/en-us/windows-server/security/group-managed-service-accounts/create-the-key-distribution-services-kds-root-key
        Add-KdsRootKey –EffectiveTime ((get-date).addhours(-10))
        # Make sure we are PAST the 10 hour mark
        Start-Sleep -Seconds 15
    }
    
    # Directory for credspecs if not already created
    mkdir -Path C:\ProgramData\docker\credentialspecs -ErrorAction SilentlyContinue

    # Import AD Module and Setup gMSA
    New-ADServiceAccount -Name gmsa-e2e -DNSHostName gmsa-e2e.k8sgmsa.lan -PrincipalsAllowedToRetrieveManagedPassword "Domain Computers" -ServicePrincipalnames http/gmsa-e2e.k8sgmsa.lan

    # Run New-CredntialSpec to provide the Yaml CredSpec
    New-CredentialSpec -Name gmsa-e2e -AccountName gmsa-e2e
	
    # Copy files to make them available for download
	Copy-Item -Path "C:\gmsa\admin.txt" -Destination "C:\inetpub\wwwroot\"
    Copy-Item -Path "C:\gmsa\gmsa-cred-spec-gmsa-e2e.yml" -Destination "C:\inetpub\wwwroot\gmsa-cred-spec-gmsa-e2e.txt"
	
	# Label the DC
	$hostname = hostname
	C:\k\kubectl.exe --kubeconfig C:\k\config label nodes $hostname DomainRole=DC

} else {
    # Add new admin account to needed groups
    Add-ADGroupMember -Identity "Enterprise Admins" -Members gmsa-admin
    Add-ADGroupMember -Identity "Domain Admins" -Members gmsa-admin
    $RunOnce = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    Set-ItemProperty $RunOnce "gmsa" -Value "C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe -command $GMSARoot\Setup-gMSA.ps1" -Type String
    Restart-Computer -Force
}

