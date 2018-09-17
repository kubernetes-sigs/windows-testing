Param(
    [string]$BaseImage = "microsoft/windowsservercore:1803",
    [string]$Repository = "e2eteam",
    [bool]$Recreate = $true,
    [bool]$PushToDocker = $false
 )

$VerbosePreference = "continue"

. "$PSScriptRoot\Utils.ps1"

BuildGoFiles $Images.Name
$failedBuildImages = BuildDockerImages $Images $Repository $Recreate
if ($PushToDocker) {
    $failedPushImages = PushDockerImages $Images
}

if ($failedBuildImages) {
    Write-Host "Docker images that failed to build: $failedBuildImages"
}

if ($failedPushImages) {
    Write-Host "Docker images that failed to push: $failedPushImages"
}
