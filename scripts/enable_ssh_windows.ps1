Param(
    [parameter(Mandatory=$true)]
    [string]$SSHPublicKey
)

$ErrorActionPreference = "Stop"

# Fallback OpenSSH release used when the Windows capability cannot be
# installed (e.g. Windows Update unreachable, see
# https://github.com/kubernetes/kubernetes/issues/140900).
$OpenSSHFallbackUrl = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip"

function Set-SSHPublicKey {
    if(!$SSHPublicKey) {
        return
    }
    $authorizedKeysFile = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
    Set-Content -Path $authorizedKeysFile -Value $SSHPublicKey -Encoding ascii
    $acl = Get-Acl $authorizedKeysFile
    $acl.SetAccessRuleProtection($true, $false)
    $administratorsRule = New-Object system.security.accesscontrol.filesystemaccessrule("Administrators", "FullControl", "Allow")
    $systemRule = New-Object system.security.accesscontrol.filesystemaccessrule("SYSTEM", "FullControl", "Allow")
    $acl.SetAccessRule($administratorsRule)
    $acl.SetAccessRule($systemRule)
    $acl | Set-Acl
}

function Install-OpenSSHCapability {
    # Add-WindowsCapability downloads OpenSSH from Windows Update, which can be
    # transiently (or lastingly) unavailable. Retry with backoff before giving up.
    $attempts = 3
    for ($i = 1; $i -le $attempts; $i++) {
        try {
            Get-WindowsCapability -Online -Name OpenSSH* | Add-WindowsCapability -Online
            return $true
        } catch {
            Write-Output "Add-WindowsCapability attempt ${i}/${attempts} failed: $_"
            if ($i -lt $attempts) {
                Start-Sleep -Seconds (15 * $i)
            }
        }
    }
    return $false
}

function Install-OpenSSHFromRelease {
    # Install sshd from the Win32-OpenSSH release zip. Does not depend on
    # Windows Update, only on GitHub being reachable.
    Write-Output "Falling back to Win32-OpenSSH release install from $OpenSSHFallbackUrl"
    $zip = Join-Path $env:TEMP "OpenSSH-Win64.zip"
    $installDir = Join-Path $env:ProgramFiles "OpenSSH"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $OpenSSHFallbackUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $env:ProgramFiles -Force
    # The zip expands to OpenSSH-Win64; normalize to Program Files\OpenSSH.
    if (Test-Path (Join-Path $env:ProgramFiles "OpenSSH-Win64")) {
        if (Test-Path $installDir) {
            Remove-Item -Recurse -Force $installDir
        }
        Rename-Item -Path (Join-Path $env:ProgramFiles "OpenSSH-Win64") -NewName "OpenSSH"
    }
    & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $installDir "install-sshd.ps1")
    # The capability install creates this firewall rule; the zip install does not.
    if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    }
}

# Install OpenSSH
$(

if (-not (Install-OpenSSHCapability)) {
    Install-OpenSSHFromRelease
}
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

# Authorize SSH key
Set-SSHPublicKey

# Set PowerShell as default shell
New-ItemProperty -Force -Path "HKLM:\SOFTWARE\OpenSSH" -PropertyType String `
                 -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
) *>$1 >> c:\output.txt
