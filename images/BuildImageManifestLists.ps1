# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Param(
    [string]$Repository = "e2eteam",
    [bool]$Recreate = $true,
    [bool]$PushToDocker = $false
 )

$VerbosePreference = "continue"

. "$PSScriptRoot\Utils.ps1"

BuildGoFiles $Images.Name $Recreate

$failedBuildImages = New-Object System.Collections.ArrayList
$failedPushImages = New-Object System.Collections.ArrayList
$failedBuildManifests = New-Object System.Collections.ArrayList
$failedPushManifests = New-Object System.Collections.ArrayList

foreach ($baseImage in $BaseImages) {
    $failedBuildImages += Build-DockerImages $Images $baseImage.ImageName $Repository $Recreate $baseImage.Suffix
    if ($PushToDocker) {
        $failedPushImages += Push-DockerImages $Images $Repository $baseImage.Suffix
    }
}

$failedBuildManifests = Build-DockerManifestLists $Images $BaseImages $Repository
if ($PushToDocker) {
    $failedPushManifests = Push-DockerManifestLists $Images $Repository
}

if ($failedBuildImages) {
    Write-Host "Docker images that failed to build: $failedBuildImages"
}

if ($failedPushImages) {
    Write-Host "Docker images that failed to push: $failedPushImages"
}

if ($failedBuildManifests) {
    Write-Host "Docker manifest lists that failed to build: $failedBuildManifests"
}

if ($failedPushManifests) {
    Write-Host "Docker manifest lists that failed to push: $failedPushManifests"
}
