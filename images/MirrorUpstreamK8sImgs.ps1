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

$VerbosePreference = "continue"


function MirrorK8sUpstreamImages {

    param (
        $Lists
    )

    Write-Verbose "Pulling Upstream Docker k8s images..."
    $failedImages = $myArray = New-Object System.Collections.ArrayList

    foreach ($manifest in $Lists) {

            echo $manifest

            $upstreamImageName = $manifest.ImageUpstreamName
            foreach ($version in $manifest.Versions) {
                $upstreamImageFullName = "${upstreamImageName}:${version}"
                docker pull $upstreamImageFullName | Write-Verbose

                if ( $manifest.Mirror ) {
                    Write-Verbose "Mirroring upstream image ${upstreamImageFullName} "
                    $mirrorImageFullName = "$($manifest.LinuxImage):${version}"
                    Write-Verbose "Tagging as ${mirrorImageFullName}"
                    docker tag "${upstreamImageFullName}" "${mirrorImageFullName}" | Write-Verbose
                    Write-Verbose "Pushing image to mirror repo"
                    docker push "${mirrorImageFullName}" | Write-Verbose
                }
                if ( -Not $? ) {
                    $failedImages.Add($UpstreamImageName)
                }
            }
    }

    return $failedImages
}

function ImageFullName
{
    param (
        $Repo,
        $Name,
        $Version,
        $ImageNameSuffix = $null
    )

    $UpstreamImage = "${Repo}/${Name}${ImageNameSuffix}"
    $UpstreamImage
}
function ManifestList
{
    param
    (
        $Name,
        $Versions = "1.0",
        $LinuxImageUpstreamK8sRepo = "k8s.gcr.io/e2e-test-images",
        $LinuxImageSuffix = "-amd64",
        $Mirror = $true
    )

    if ($Versions -is [string]) {
        $Versions = @($Versions)
    }

    $image = New-Object -TypeName PSObject
    $image | Add-Member -MemberType NoteProperty -Name Name -Value $Name
    $image | Add-Member -MemberType NoteProperty -Name Versions -Value $Versions
    $image | Add-Member -MemberType NoteProperty -Name Mirror -Value $Mirror

    $imageUpstreamName = ImageFullName -Repo $LinuxImageUpstreamK8sRepo -Name $image.Name -ImageNameSuffix $LinuxImageSuffix
    $image | Add-Member -MemberType NoteProperty -Name ImageUpstreamName -Value $imageUpstreamName

    if ( $Mirror ) {
        $linuxImage = ImageFullName -Repo "e2ek8simgs" -Name $image.Name -ImageNameSuffix $LinuxImageSuffix
    }
    else {
        $linuxImage = $imageUpstreamName
    }

    $image | Add-Member -MemberType NoteProperty -Name LinuxImage -Value $linuxImage

    $windowsImage = ImageFullName -Repo "k8sprow.azurecr.io/kubernetes-e2e-test-images" -Name $image.Name
    $image | Add-Member -MemberType NoteProperty -Name WindowsImage -Value $windowsImage


    # Calling "image" below outputs it, acting as a "return" value
    $image
}

function GetVersionedImage($imageName, $version) {

    return "${imageName}:${version}"
}

function CreateManifestLists {

    Param (
        $Lists,
        $Push = $false
    )

    Write-Verbose "Creating Manifest lists for images"

    foreach ($manifest in $Lists) {

        $fullManifestListName = ImageFullName -Repo "e2ek8simgs" -Name $manifest.Name
        Write-Host "Creating Manifest List $fullManifestListName"
        foreach ( $version in $manifest.Versions ) {
            docker manifest create $(GetVersionedImage $fullManifestListName $version) $(GetVersionedImage $manifest.LinuxImage $version ) $(GetVersionedImage $manifest.WindowsImage $version) | Write-Host
            docker manifest inspect $(GetVersionedImage $fullManifestListName $version) | Write-Host

            if ( $Push ) {
                docker manifest push -p $(GetVersionedImage $fullManifestListName $version)
            }
        }

    }


}

$ManifestLists = @(
    # base images used to build other images.
    ManifestList -Name "busybox" -Versions "1.29" -LinuxImageUpstreamK8sRepo "amd64" -Mirror $false -LinuxImageSuffix $null
    ManifestList -Name "test-webserver"

    ManifestList -Name "dnsutils" -ImageBase "busybox" -Versions "1.1"
    ManifestList -Name "echoserver" -ImageBase "busybox" -Versions "2.1"
    ManifestList -Name "entrypoint-tester"
    ManifestList -Name "fakegitserver"
    ManifestList -Name "gb-frontend" -Versions "v6" -LinuxImageUpstreamK8sRepo "gcr.io/google-samples"
    ManifestList -Name "gb-redisslave" -Versions "v3" -LinuxImageUpstreamK8sRepo "gcr.io/google-samples"
    ManifestList -Name "hostexec" -Versions "1.1" -ImageBase "busybox"
    ManifestList -Name "jessie-dnsutils" -ImageBase "busybox"
    ManifestList -Name "kitten" -ImageBase "test-webserver"
    ManifestList -Name "liveness"
    ManifestList -Name "logs-generator"
    ManifestList -Name "mounttest"
    ManifestList -Name "nautilus" -ImageBase "test-webserver"
    ManifestList -Name "net" -ImageBase "busybox"
    ManifestList -Name "netexec" -ImageBase "busybox" -Versions "1.1"
    ManifestList -Name "nettest"
    ManifestList -Name "nginx" -Versions @("1.14-alpine","1.15-alpine") -ImageBase "busybox" -LinuxImageUpstreamK8sRepo "amd64" -Mirror $false -LinuxImageSuffix $null
    ManifestList -Name "no-snat-test"
#   ManifestList -Name "pause" -Versions "3.1"
    ManifestList -Name "port-forward-tester"
    ManifestList -Name "porter"
    ManifestList -Name "redis"
    ManifestList -Name "serve-hostname" -Versions "1.1"
    ManifestList -Name "webhook" -Versions "1.12v2"
)


MirrorK8sUpstreamImages -Lists $ManifestLists
CreateManifestLists -Lists $ManifestLists -Push $true
