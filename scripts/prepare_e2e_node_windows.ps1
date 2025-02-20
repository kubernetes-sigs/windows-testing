param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerdVersion
)

$ErrorActionPreference = "Stop"

# Install containerd, based on: https://github.com/containerd/containerd/blob/main/docs/getting-started.md#installing-containerd-on-windows
# If containerd previously installed run:
Stop-Service containerd -ErrorAction Continue
sc.exe delete containerd -ErrorAction Continue

# Download and extract desired containerd Windows binaries
curl.exe -LO https://github.com/containerd/containerd/releases/download/v$ContainerdVersion/containerd-$ContainerdVersion-windows-amd64.tar.gz
tar.exe xvf .\containerd-$ContainerdVersion-windows-amd64.tar.gz

# Copy
Copy-Item -Path .\bin -Destination $Env:ProgramFiles\containerd -Recurse -Force

# add the binaries (containerd.exe, ctr.exe) in $env:Path
$Path = [Environment]::GetEnvironmentVariable("PATH", "Machine") + [IO.Path]::PathSeparator + "$Env:ProgramFiles\containerd"
[Environment]::SetEnvironmentVariable( "Path", $Path, "Machine")
# reload path, so you don't have to open a new PS terminal later if needed
$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# configure
containerd.exe config default | Out-File $Env:ProgramFiles\containerd\config.toml -Encoding ascii
# Review the configuration. Depending on setup you may want to adjust:
# - the sandbox_image (Kubernetes pause image)
# - cni bin_dir and conf_dir locations
Get-Content $Env:ProgramFiles\containerd\config.toml

Add-MpPreference -ExclusionProcess "$Env:ProgramFiles\containerd\containerd.exe"

# Register and start service
#containerd.exe --register-service
# Start-Service containerd
# Use nssm to register and start containerd as a service, which can get a better logging
curl.exe -LO https://upstreamartifacts.azureedge.net/nssm/nssm.exe
Add-MpPreference -ExclusionProcess ".\nssm.exe"
./nssm.exe install containerd "$Env:ProgramFiles\containerd.\containerd.exe"
./nssm.exe set containerd AppStdout "$Env:ProgramFiles\containerd\containerd.log"
./nssm.exe set containerd AppStderr "$Env:ProgramFiles\containerd\containerd.err.log"
./nssm.exe start containerd

# Setting up network https://www.jamessturtevant.com/posts/Windows-Containers-on-Windows-10-without-Docker-using-Containerd/
# Create the folder for cni binaries and configuration
mkdir -force "$Env:ProgramFiles\containerd\cni\bin"
mkdir -force "$Env:ProgramFiles\containerd\cni\conf"

# Download and extract the CNI plugins
curl.exe -LO https://github.com/microsoft/windows-container-networking/releases/download/v0.3.1/windows-container-networking-cni-amd64-v0.3.1.zip
Expand-Archive windows-container-networking-cni-amd64-v0.3.1.zip -DestinationPath "$Env:ProgramFiles\containerd\cni\bin" -Force

# Create a nat network
curl.exe -LO https://raw.githubusercontent.com/microsoft/SDN/master/Kubernetes/windows/hns.psm1
Import-Module ./hns.psm1

$subnet="10.0.0.0/16" 
$gateway="10.0.0.1"
New-HNSNetwork -Type Nat -AddressPrefix $subnet -Gateway $gateway -Name "nat"

#Set up the containerd network config using the same gateway and subnet.
@"
{
    "cniVersion": "0.2.0",
    "name": "nat",
    "type": "nat",
    "master": "Ethernet",
    "ipam": {
        "subnet": "$subnet",
        "routes": [
            {
                "gateway": "$gateway"
            }
        ]
    },
    "capabilities": {
        "portMappings": true,
        "dns": true
    }
}
"@ | Set-Content "$Env:ProgramFiles\containerd\cni\conf\0-containerd-nat.conf" -Force
