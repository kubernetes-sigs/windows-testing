param (
    [string]$goVersion = "1.23.6"
)

$PACKAGES= @{ git = ""; golang = $goVersion; make = "" }

Write-Host "Downloading chocolatey package"
curl.exe -L "https://packages.chocolatey.org/chocolatey.0.10.15.nupkg" -o 'c:\choco.zip'
Expand-Archive "c:\choco.zip" -DestinationPath "c:\choco"

Write-Host "Installing choco"
& "c:\choco\tools\chocolateyInstall.ps1"

Write-Host "Set choco.exe path."
$env:PATH+=";C:\ProgramData\chocolatey\bin"

Write-Host "Install necessary packages"

foreach ($package in $PACKAGES.Keys) {
    $command = "choco.exe install $package --yes --no-progress"
    $version = $PACKAGES[$package]
    if (-Not [string]::IsNullOrEmpty($version)) {
        $command += " --version $version"
    }
    Invoke-Expression $command
    if ( !$? ){
        echo "Failed installing package $package"
        exit
    }
}

Write-Host "Configuring Windows Defender exclusions to improve test performance"
try {
    # Disable multiple Defender features for test execution
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
    Set-MpPreference -DisableBehaviorMonitoring $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue
    Write-Host "Defender monitoring features disabled"
    
    # Add path exclusions for directories used during testing
    Add-MpPreference -ExclusionPath "C:\kubernetes" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionPath "C:\Logs" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionPath "C:\Users\azureuser\go" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionPath "C:\Users\azureuser\AppData\Local\go-build" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionPath "C:\Program Files\Go" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionPath "C:\choco" -ErrorAction SilentlyContinue
    Write-Host "Path exclusions added for test directories"
    
    # Add process exclusions for Go toolchain and build tools
    Add-MpPreference -ExclusionProcess "go.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "git.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "gotestsum.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "compile.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "link.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "make.exe" -ErrorAction SilentlyContinue
    Write-Host "Process exclusions added for build tools"
    
    # Verify settings were applied
    $prefs = Get-MpPreference
    Write-Host "Real-time monitoring: $($prefs.DisableRealtimeMonitoring)"
    Write-Host "Behavior monitoring: $($prefs.DisableBehaviorMonitoring)"
} catch {
    Write-Host "Warning: Could not configure Windows Defender exclusions: $_"
    Write-Host "Continuing anyway..."
}

Write-Host "Set up environment."

if (${Env:HOME} -ne $null) {
    $userGoBin = "${Env:HOME}\go\bin"
} else {
    $userGoBin = "${Env:HOMEPATH}\go\bin"
}

$path = ";c:\Program Files\Git\bin;c:\Program Files\Go\bin;${userGoBin};"
$env:PATH+=$path

Write-Host $env:PATH

[Environment]::SetEnvironmentVariable("PATH", $env:PATH, 'User')

# Log go env for future reference:
go env

