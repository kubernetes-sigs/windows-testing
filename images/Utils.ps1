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

function BuildGoFiles($folders, $recreate) {
    Get-Command -ErrorAction Ignore -Name go | Out-Null
    if (!$?) {
        Write-Verbose ("Go is not installed or not found. Skipping building " +
                       "go files. This might result in some docker images " +
                       "failing to build.")
        return
    }

    Write-Verbose "Building Go items..."
    foreach ($folder in $folders) {
        $items = Get-ChildItem -Recurse $folder | ? Name -Match ".*.go(lnk)?$" | ? Name -NotMatch "util"
        foreach ($item in $items) {
            $exePath = Join-Path $item.DirectoryName ($item.BaseName + ".exe")
            if (!$recreate -and (Test-Path $exePath)) {
                Write-Verbose "$exePath already exists. Skipping go build for it."
                continue
            }

            $sourceFilePath = Join-Path $item.DirectoryName $item.Name
            Write-Verbose "Building $sourceFilePath to $exePath"
            pushd $item.DirectoryName
            $source = "."
            if ($item.Extension -eq ".golnk") {
                $source = (cat $item).Trim()
            }
            go build -o $exePath $source
            popd
        }
    }
}

Function Build-DockerImages {
    Param (
      [Parameter(Mandatory=$true)]  [PSObject[]]$Images,
      [Parameter(Mandatory=$true)]  [String]$BaseImage,
      [Parameter(Mandatory=$true)]  [String]$Repository,
      [Parameter(Mandatory=$true)]  [bool]$Recreate,
      [Parameter(mandatory=$false)] [String]$VersionSuffix = ""
    )

    Write-Verbose "Building Docker images..."
    $failedImages = New-Object System.Collections.ArrayList
    $allDockerImages = docker images

    foreach ($image in $Images) {
        $imgName = $image.Name
        foreach ($version in $image.Versions) {
            $version = "$version$VersionSuffix"
            $fullImageName = "$Repository/$imgName`:$version"

            if (!$Recreate) {
                $imageFound = $allDockerImages | Select-String -Pattern "$Repository/$imgName" | Select-String -Pattern "\s$version\s"
                if ($imageFound) {
                    Write-Verbose "Image ""$fullImageName"" already exists. Skipping."
                    continue
                }
            }

            # if the image has no ImageBase, use $BaseImage instead.
            # if it has, check if the image is based on another already built
            # image, like busybox.
            if ($image.ImageBase -eq "") {
                $imgBase = $BaseImage
            } else {
                $imgBase = $image.ImageBase
                $imgBaseObj = $Images | ? Name -eq $image.ImageBase
                if ($imgBaseObj) {
                    $imgBaseObjVersion = $imgBaseObj[0].Versions[0]
                    $imgBase = "$Repository/$imgBase`:$imgBaseObjVersion$VersionSuffix"
                }
            }

            pushd $imgName
            Write-Verbose "Building $fullImageName, using as base image: $imgBase."
            docker build -t "$fullImageName" --build-arg BASE_IMAGE="$imgBase" . | Write-Verbose
            $result = $?
            popd

            if (!$result) {
                $failedImages.Add($fullImageName)
            }
        }
    }

    return $failedImages
}


Function Push-DockerImages {
    Param (
      [Parameter(Mandatory=$true)]  [PSObject]$Images,
      [Parameter(Mandatory=$true)]  [String]$Repository,
      [Parameter(mandatory=$false)] [String]$VersionSuffix = ""
    )

    Write-Verbose "Pushing Docker images..."
    $failedImages = $myArray = New-Object System.Collections.ArrayList

    foreach ($image in $images) {
        $imgName = $image.Name
        foreach ($version in $image.Versions) {
            $version = "$version$VersionSuffix"
            $fullImageName = "$Repository/$imgName`:$version"
            docker push "$fullImageName" | Write-Verbose

            if (!$?) {
                $failedImages.Add($fullImageName)
            }
        }
    }

    return $failedImages
}


Function Build-DockerManifestLists {
    Param (
      [Parameter(Mandatory=$true)]  [PSObject]$Images,
      [Parameter(Mandatory=$true)]  [PSObject]$BaseImages,
      [Parameter(Mandatory=$true)]  [String]$Repository
    )

    Write-Verbose "Creating Docker manifest lists..."
    $failedManifests = $myArray = New-Object System.Collections.ArrayList

    foreach ($image in $images) {
        $manifestName = $image.Name
        foreach ($version in $image.Versions) {
            $fullManifestName = "$Repository/$manifestName`:$version"
            $manifestImages = $BaseImages.Suffix | % {$fullManifestName + $_}
            docker manifest create --amend "$fullManifestName" $manifestImages | Write-Verbose

            if (!$?) {
                $failedManifests.Add($fullManifestName)
            }
        }
    }

    return $failedManifests
}


Function Push-DockerManifestLists {
    Param (
      [Parameter(Mandatory=$true)]  [PSObject]$Images,
      [Parameter(Mandatory=$true)]  [String]$Repository
    )

    Write-Verbose "Pushing Docker manifest lists..."
    $failedManifests = $myArray = New-Object System.Collections.ArrayList

    foreach ($image in $images) {
        $imgName = $image.Name
        foreach ($version in $image.Versions) {
            $version = "$version$VersionSuffix"
            $fullManifestName = "$Repository/$imgName`:$version"
            docker manifest push --purge "$fullManifestName" | Write-Verbose

            if (!$?) {
                $failedManifests.Add($fullManifestName)
            }
        }
    }

    return $failedManifests
}


function PullDockerImages($images) {
    Write-Verbose "Pulling Docker images..."
    $failedImages = $myArray = New-Object System.Collections.ArrayList

    foreach ($image in $images) {
        $imgName = $image.Name
        foreach ($version in $image.Versions) {
            $fullImageName = "$repository/$imgName`:$version"
            docker pull "$fullImageName" | Write-Verbose

            if (!$?) {
                $failedImages.Add($fullImageName)
            }
        }
    }

    return $failedImages
}


function BaseImage
{
    param
    (
        $ImageName,
        $Suffix
    )

    $psObj = New-Object -TypeName PSObject
    $psObj | Add-Member -MemberType NoteProperty -Name ImageName -Value $ImageName
    $psObj | Add-Member -MemberType NoteProperty -Name Suffix -Value "-$Suffix"

    # Calling "psObj" below outputs it, acting as a "return" value
    $psObj
}


$BaseImages = @(
    BaseImage -ImageName "microsoft/windowsservercore:1803" -Suffix "1803"
    BaseImage -ImageName "mcr.microsoft.com/windows/servercore:ltsc2019" -Suffix "1809"
)


function DockerImage
{
    param
    (
        $Name,
        $Versions = "1.0",
        $ImageBase = ""
    )

    if ($Versions -is [string]) {
        $Versions = @($Versions)
    }

    $image = New-Object -TypeName PSObject
    $image | Add-Member -MemberType NoteProperty -Name Name -Value $Name
    $image | Add-Member -MemberType NoteProperty -Name Versions -Value $Versions
    $image | Add-Member -MemberType NoteProperty -Name ImageBase -Value $ImageBase

    # Calling "image" below outputs it, acting as a "return" value
    $image
}


$Images = @(
    # base images used to build other images.
    DockerImage -Name "busybox" -Versions "1.29"
    DockerImage -Name "curl" -Versions "1803"
    DockerImage -Name "java" -Versions "openjdk-8-jre" -ImageBase "busybox"
    DockerImage -Name "test-webserver"

    DockerImage -Name "cassandra" -Versions "v13" -ImageBase "java"
    DockerImage -Name "dnsutils" -ImageBase "busybox" -Versions "1.2"
    DockerImage -Name "echoserver" -ImageBase "busybox" -Versions "2.2"
    DockerImage -Name "entrypoint-tester"
    DockerImage -Name "etcd" -Versions "v3.3.10", "3.3.10"
    DockerImage -Name "fakegitserver"
    DockerImage -Name "gb-frontend" -Versions "v6"
    DockerImage -Name "gb-redisslave" -Versions "v3"
    DockerImage -Name "hazelcast-kubernetes" -Versions "3.8_1" -ImageBase "java"
    DockerImage -Name "hostexec" -Versions "1.1" -ImageBase "busybox"
    DockerImage -Name "iperf" -ImageBase "busybox"
    DockerImage -Name "jessie-dnsutils" -ImageBase "busybox"  -Versions "1.1"
    DockerImage -Name "kitten" -ImageBase "test-webserver"
    DockerImage -Name "liveness" -Versions "1.1"
    DockerImage -Name "logs-generator"
    DockerImage -Name "mounttest"
    DockerImage -Name "nautilus" -ImageBase "test-webserver"
    DockerImage -Name "net" -ImageBase "busybox"
    DockerImage -Name "netexec" -ImageBase "busybox" -Versions "1.1"
    DockerImage -Name "nettest"
    DockerImage -Name "nginx" -Versions @("1.14-alpine","1.15-alpine") -ImageBase "busybox"
    DockerImage -Name "no-snat-test"
    DockerImage -Name "pause" -Versions "3.1"
    DockerImage -Name "port-forward-tester"
    DockerImage -Name "porter"
    DockerImage -Name "redis" -ImageBase "busybox"
    DockerImage -Name "resource-consumer" -Versions "1.5"
    DockerImage -Name "resource-consumer-controller"
    DockerImage -Name "rethinkdb" -Version "1.16.0_1" -ImageBase "busybox"
    DockerImage -Name "sample-apiserver" -Versions "1.10"
    DockerImage -Name "serve-hostname" -Versions "1.1"
    DockerImage -Name "webhook" -Versions "1.15v1"
)
