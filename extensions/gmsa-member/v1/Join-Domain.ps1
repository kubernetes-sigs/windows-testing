<#
 .SYNOPSIS
 This script will join the local computer to the domain for gmsa testing

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

Start-Transcript -Path "$GMSARoot\join.txt"

# Create a working directory and change to it
if (( Test-Path -Path "$GMSARoot") -eq $false ) {
    mkdir $GMSARoot
    Set-Location -Path $GMSARoot
} 

# Function to find the Domain Controller
function FindDC() {
    Try {
        $DCIP = C:\k\kubectl.exe get node --kubeconfig=C:\k\config --selector="DomainRole=DC" -o jsonpath="{.items[*].status.addresses[?(@.type=='InternalIP')].address}"
        if ($null -eq $DCIP) {
            return 11
        } else {
            Write-Host "DC IP Address is $DCIP"
            return $DCIP
        }        
    } catch {
        Start-Sleep 10
        return 11
    }
}

function ChangeDNS($DCIP) {
    Try {
        if ($null -eq $DCIP) {
            $DCIP = FindDC
        }
        Write-Host "Changing DNS to $DCIP"
        $Adapter = Get-NetAdapter | Where-Object {$_.Name -like "vEthernet (Ether*"}
        Set-DnsClientServerAddress -InterfaceIndex ($Adapter).ifIndex -ServerAddresses $DCIP
        return $true
    } catch {
        return $false
    }
}

function JoinDomain($GMSARoot) {
    Write-Host "Join to domain"
    $adminpass = Get-Content -Path "$GMSARoot\admin.txt"
    $joinCred = New-Object pscredential -ArgumentList ([pscustomobject]@{
        UserName = "k8sgmsa\gmsa-admin"
        Password = (ConvertTo-SecureString -String ($adminpass -replace "`n|`r") -AsPlainText -Force)[0]
    })
    Try {
        Add-Computer -Domain "k8sgmsa.lan" -Credential $joinCred
        return $true
    } catch {
        Start-Sleep 10
        return $false
    }

}

function CopyFiles($DCIP) {
    Write-Host "Copy Files from $DCIP"
    Try {
        Invoke-WebRequest -UseBasicParsing http://$DCIP/admin.txt -OutFile "$GMSARoot\admin.txt"
        Invoke-WebRequest -UseBasicParsing http://$DCIP/gmsa-cred-spec-gmsa-e2e.txt -OutFile "$GMSARoot\gmsa-cred-spec-gmsa-e2e.yml"
        return $true
    } catch {
        Start-Sleep 5
        return $false
    }
}

# Find the DC and get its IP
Do { $DCIP = FindDC } while ( $DCIP -eq 11 -or $null -eq $DCIP)
$DCIP = FindDC

# Set NIC to look at DC for DNS
Do { $DNSResult = ChangeDNS } while ( $DNSResult -eq $false )

# Obtain the password to join the domain
Do { $CopyResult = CopyFiles($DCIP)} while ( $CopyResult -eq $false )

# Join the domain
Do { $JDResult = JoinDomain($GMSARoot) } while ( $JDResult -eq $false )

# Reboot to finish the join
Restart-Computer -Force
