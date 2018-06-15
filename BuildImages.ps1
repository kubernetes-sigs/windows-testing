Param(
    [string]$BaseImage = "microsoft/windowsservercore:1803",
    [string]$Repository = "e2eteam",
    [bool]$Recreate = $true,
    [bool]$PushToDocker = $false
 )

$VerbosePreference = "continue"

function BuildGoFiles($folders) {
    Get-Command -ErrorAction Ignore -Name go | Out-Null
    if (!$?) {
        Write-Verbose ("Go is not installed or not found. Skipping building " +
                       "go files. This might result in some docker images " +
                       "failing to build.")
        return
    }

    Write-Verbose "Building Go items..."
    foreach ($folder in $folders) {
        $items = Get-ChildItem -Recurse -Filter "*.go" $folder | ? Name -NotMatch "util"
        foreach ($item in $items) {
            $exePath = Join-Path $item.DirectoryName ($item.BaseName + ".exe")
            if (Test-Path $exePath) {
                Write-Verbose "$exePath already exists. Skipping go build for it."
                continue
            }

            $sourceFilePath = Join-Path $item.DirectoryName $item.Name
            Write-Verbose "Building $sourceFilePath to $exePath"
            pushd $item.DirectoryName
            go build -o $exePath .
            popd
        }
    }
}

function BuildDockerImages($images, $repository, $recreate) {
    Write-Verbose "Building Docker images..."
    $failedImages = New-Object System.Collections.ArrayList
    $allDockerImages = docker images

    foreach ($image in $images) {
        $imgName = $image.Name
        foreach ($version in $image.Versions) {
            $fullImageName = "$repository/$imgName`:$version"

            if (!$recreate) {
                $imageFound = $allDockerImages | findstr "$repository/$imgName" | findstr $version
                if ($imageFound) {
                    Write-Verbose "Image ""$fullImageName"" already exists. Skipping."
                    continue
                }
            }

            # check if the image is based on another already built image,
            # like busybox. If it's not found, use the base image name as is.
            $imgBase = $image.ImageBase
            $imgBaseObj = $images | ? Name -eq $image.ImageBase
            if ($imgBaseObj) {
                $imgBaseObjVersion = $imgBaseObj[0].Versions[0]
                $imgBase = "$repository/$imgBase`:$imgBaseObjVersion"
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


function PushDockerImages($images) {
    Write-Verbose "Pushing Docker images..."
    $failedImages = $myArray = New-Object System.Collections.ArrayList

    foreach ($image in $images) {
        $imgName = $image.Name
        foreach ($version in $image.Versions) {
            $fullImageName = "$repository/$imgName`:$version"
            docker push "$fullImageName" | Write-Verbose

            if (!$?) {
                $failedImages.Add($fullImageName)
            }
        }
    }

    return $failedImages
}


function DockerImage
{
    param
    (
        $Name,
        $Versions = "1.0",
        $ImageBase = $BaseImage
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


$images = @(
    # base images used to build other images.
    DockerImage -Name "busybox" -Versions "1.24"
    DockerImage -Name "curl" -Versions "1803"
    DockerImage -Name "java" -Versions "openjdk-8-jre" -ImageBase "busybox"
    DockerImage -Name "test-webserver"

    DockerImage -Name "cassandra" -Versions "v13" -ImageBase "java"
    DockerImage -Name "dnsutils" -ImageBase "busybox"
    DockerImage -Name "echoserver" -Versions "1.10"
    DockerImage -Name "entrypoint-tester"
    DockerImage -Name "fakegitserver"
    DockerImage -Name "gb-frontend" -Versions "v5"
    DockerImage -Name "gb-redisslave" -Versions "v2"
    DockerImage -Name "hazelcast-kubernetes" -Versions "3.8_1" -ImageBase "java"
    DockerImage -Name "hostexec" -Versions "1.1" -ImageBase "busybox"
    DockerImage -Name "jessie-dnsutils" -ImageBase "busybox"
    DockerImage -Name "k8s-sample-admission-webhook" -Versions "1.10v2"
    DockerImage -Name "kitten" -ImageBase "test-webserver"
    DockerImage -Name "liveness"
    DockerImage -Name "logs-generator"
    DockerImage -Name "mounttest"
    DockerImage -Name "nautilus" -ImageBase "test-webserver"
    DockerImage -Name "net" -ImageBase "busybox"
    DockerImage -Name "netexec" -ImageBase "busybox"
    DockerImage -Name "nginx-slim" -Versions @("0.20","0.21") -ImageBase "busybox"
    DockerImage -Name "no-snat-test"
    DockerImage -Name "pause" -Versions "3.1"
    DockerImage -Name "port-forward-tester"
    DockerImage -Name "porter"
    DockerImage -Name "redis"
    DockerImage -Name "resource-consumer" -Versions "1.3"
    DockerImage -Name "resource-consumer/controller"
    DockerImage -Name "serve-hostname"
    DockerImage -Name "spark" -Versions "1.5.2_v1" -ImageBase "java"
    DockerImage -Name "storm-nimbus" -Versions "latest" -ImageBase "java"
    DockerImage -Name "storm-worker" -Versions "latest" -ImageBase "java"
    DockerImage -Name "zookeeper" -Versions "latest" -ImageBase "java"
)


BuildGoFiles $images.Name
$failedBuildImages = BuildDockerImages $images $Repository $Recreate
if ($PushToDocker) {
    $failedPushImages = PushDockerImages $images
}

if ($failedBuildImages) {
    Write-Host "Docker images that failed to build: $failedBuildImages"
}

if ($failedPushImages) {
    Write-Host "Docker images that failed to push: $failedPushImages"
}
