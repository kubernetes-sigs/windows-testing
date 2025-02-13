$PACKAGES= @{ git = ""; golang = "1.23.6"; make = "" }

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

