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

function BuildDockerImages($images, $baseImage, $repository, $recreate) {
    Write-Verbose "Building Docker images..."
    $failedImages = $myArray = New-Object System.Collections.ArrayList
    $allDockerImages = docker images

    foreach ($image in $images.Keys) {
        $version = $images["$image"]
        $imageName = "$repository/$image`:$version"

        if (!$recreate) {
            $imageFound = $allDockerImages | findstr "$repository/$image" | findstr $version
            if ($imageFound) {
                Write-Verbose "Image ""$imageName"" already exists. Skipping."
                continue
            }
        }

        pushd $image
        docker build -t "$imageName" --build-arg BASE_IMAGE="$baseImage" . | Write-Verbose
        $result = $?
        popd

        if (!$result) {
            $failedImages.Add($imageName)
        }
    }

    return $failedImages
}

function PushDockerImages($images) {
    Write-Verbose "Pushing Docker images..."
    $failedImages = $myArray = New-Object System.Collections.ArrayList

    foreach ($image in $images.Keys) {
        $version = $images["$image"]
        $imageName = "$repository/$image`:$version"
        docker push "$imageName" | Write-Verbose

        if (!$?) {
            $failedImages.Add($imageName)
        }
    }

    return $failedImages
}

$images = [ordered]@{}
# base images used to build other images.
$images.Add("busybox", "1.24")
$images.Add("curl", "1803")
$images.Add("java-base", "1.8.0")
$images.Add("test-webserver", "1.0")

$images.Add("cassandra", "v13")
$images.Add("dnsutils", "1.0")
$images.Add("echoserver", "1.10")
$images.Add("entrypoint-tester", "1.0")
$images.Add("fakegitserver", "1.0")
$images.Add("gb-frontend", "v5")
$images.Add("gb-redisslave", "v2")
$images.Add("hazelcast-kubernetes", "3.8_1")
$images.Add("hostexec", "1.1")
$images.Add("jessie-dnsutils", "1.0")
$images.Add("kitten", "1.0")
$images.Add("liveness", "1.0")
$images.Add("logs-generator", "1.0")
$images.Add("mounttest", "1.0")
$images.Add("nautilus", "1.0")
$images.Add("net", "1.0")
$images.Add("netexec", "1.0")
$images.Add("nginx-slim", "0.20")
$images.Add("no-snat-test", "1.0")
$images.Add("pause", "3.1")
$images.Add("port-forward-tester", "1.0")
$images.Add("porter", "1.0")
$images.Add("redis", "1.0")
$images.Add("resource-consumer", "1.3")
$images.Add("serve-hostname", "1.0")
$images.Add("spark", "1.5.2_v1")
$images.Add("storm-nimbus", "latest")
$images.Add("storm-worker", "latest")
$images.Add("zookeeper", "latest")


BuildGoFiles $images.Keys
$failedBuildImages = BuildDockerImages $images $BaseImage $Repository $Recreate
if ($PushToDocker) {
    $failedPushImages = PushDockerImages $images
}

if ($failedBuildImages) {
    Write-Host "Docker images that failed to build: $failedBuildImages"
}

if ($failedPushImages) {
    Write-Host "Docker images that failed to push: $failedPushImages"
}
