# Copyright 2018 The Kubernetes Authors.
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
    [string]$BaseImage = "microsoft/windowsservercore:1803",
    [string]$Repository = "e2eteam",
    [bool]$Recreate = $true,
    [bool]$PushToDocker = $false
 )

$VerbosePreference = "continue"

. "$PSScriptRoot\Utils.ps1"

BuildGoFiles $Images.Name $Recreate
CopyPythonFiles $Images.Name

# we are trying to use an external image for the Python-based images, so we
# have to retag the "python:3.7.2-windowsservercore" based on the given
# $BaseImage.
foreach ($base in $BaseImages) {
    if ($BaseImage -eq $base.Name) {
        $basePython = "python:3.7.2-windowsservercore"
        $suffix = $base.Suffix
        $actualImageName = "$basePython$suffix"
        Write-Verbose "Retagging $actualImageName as $basePython"
        docker tag $actualImageName $basePython
    }
}

$failedBuildImages = Build-DockerImages $Images $BaseImage $Repository $Recreate
if ($PushToDocker) {
    $failedPushImages = Push-DockerImages $Images $Repository
}

if ($failedBuildImages) {
    Write-Host "Docker images that failed to build: $failedBuildImages"
}

if ($failedPushImages) {
    Write-Host "Docker images that failed to push: $failedPushImages"
}
