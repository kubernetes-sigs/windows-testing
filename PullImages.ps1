Param(
    [string]$Repository = "e2eteam"
 )

$VerbosePreference = "continue"

. "$PSScriptRoot\Utils.ps1"

$failedPullImages = PullDockerImages $Images $Repository

if ($failedPullImages) {
    Write-Host "Docker images that failed to pull: $failedPullImages"
}
