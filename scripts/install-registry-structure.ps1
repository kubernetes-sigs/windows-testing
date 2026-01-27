<#
.SYNOPSIS
    Creates the OCI registry directory structure for the agnhost fake-registry-server on Windows.

.DESCRIPTION
    This script uses containerd (ctr) to pull a container image and extract its contents to create
    a Docker/OCI registry directory structure. This structure is required for running the agnhost
    fake-registry-server on Windows.

.PARAMETER ImageRef
    The full image reference to pull (e.g., "registry.k8s.io/pause:3.10")
    Default: registry.k8s.io/pause:3.10

.PARAMETER RegistryDir
    The target directory where the registry structure will be created.
    Default: C:\var\registry

.PARAMETER Tag
    The tag name to use in the registry structure (e.g., "testing", "latest").
    This is the tag that clients will use to pull the image from the fake registry.
    Default: testing

.EXAMPLE
    .\Install-RegistryStructure.ps1
    Creates the registry structure for the default pause image at C:\var\registry

.EXAMPLE
    .\Install-RegistryStructure.ps1 -ImageRef "registry.k8s.io/pause:3.9"
    Creates the structure for pause:3.9

.NOTES
    Author: Kubernetes Contributors
    Requires: PowerShell 5.1+ or PowerShell Core 7+
    Requires: containerd with ctr.exe in PATH
    Note: This script always overwrites the existing registry directory
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Full image reference to pull")]
    [string]$ImageRef = "registry.k8s.io/pause:3.10.1",

    [Parameter(HelpMessage="Target directory for registry structure")]
    [string]$RegistryDir = "C:\var\registry",

    [Parameter(HelpMessage="Tag name to use in the registry")]
    [string]$Tag = "testing"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Constants
$CONTAINERD_NAMESPACE = "k8s.io"

#region Helper Functions

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Get-DigestPath {
    <#
    .SYNOPSIS
        Converts a digest to a nested directory path following Docker registry layout.
        Example: sha256:abc123... -> sha256\ab\abc123...\data
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseDir,
        [Parameter(Mandatory=$true)]
        [string]$Digest
    )

    $parts = $Digest -split ':', 2
    if ($parts.Count -ne 2 -or $parts[1].Length -lt 2) {
        return Join-Path -Path $BaseDir -ChildPath $Digest
    }

    $algo = $parts[0]
    $hash = $parts[1]
    $prefix = $hash.Substring(0, 2)

    return Join-Path -Path $BaseDir -ChildPath $algo |
           Join-Path -ChildPath $prefix |
           Join-Path -ChildPath $hash |
           Join-Path -ChildPath "data"
}

function Save-ContentToPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $fileDir = Split-Path -Parent $FilePath
    if (-not (Test-Path -Path $fileDir)) {
        New-Item -Path $fileDir -ItemType Directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($FilePath, $Content)
    Write-Host "Saved: $FilePath"
}

function Copy-FileToPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath
    )

    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
    Write-Host "Copied: $DestinationPath"
}

function Get-ExtractedBlobPath {
    <#
    .SYNOPSIS
        Finds the blob path in the extracted tar, trying both flat layout and OCI layout.
        Flat layout: blobs/sha256-{hash}
        OCI layout: blobs/sha256/{hash}
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ExtractDir,
        [Parameter(Mandatory=$true)]
        [string]$Digest
    )

    $digestParts = $Digest -split ':', 2
    $algo = $digestParts[0]
    $hash = $digestParts[1]

    # Try flat layout first: blobs/sha256-{hash}
    $flatPath = Join-Path -Path $ExtractDir -ChildPath "blobs" |
                Join-Path -ChildPath "$algo-$hash"
    if (Test-Path -Path $flatPath) {
        return $flatPath
    }

    # Try OCI layout: blobs/sha256/{hash}
    $ociPath = Join-Path -Path $ExtractDir -ChildPath "blobs" |
               Join-Path -ChildPath $algo |
               Join-Path -ChildPath $hash
    if (Test-Path -Path $ociPath) {
        return $ociPath
    }

    # Return flat path (will fail with proper error message)
    return $flatPath
}

#endregion

#region Main Execution

try {
    Write-Info "Starting registry structure creation"
    Write-Info "Image: $ImageRef"
    Write-Info "Target: $RegistryDir"

    # Check for containerd/ctr
    try {
        $null = & ctr.exe --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "ctr.exe not functional"
        }
    }
    catch {
        Write-ErrorMessage "ctr.exe (containerd CLI) not found in PATH"
        Write-Host "Please ensure containerd is installed and ctr.exe is in your PATH" -ForegroundColor Yellow
        exit 1
    }

    # Parse image reference to get image name
    # Example: registry.k8s.io/pause:3.10 -> pause
    $imageWithoutRegistry = $ImageRef -replace '^[^/]+/', ''
    $imageName = ($imageWithoutRegistry -split ':')[0]
    Write-Host "Image name: $imageName"

    # Clean up existing registry directory
    if (Test-Path -Path $RegistryDir) {
        Write-Info "Removing existing registry directory"
        Remove-Item -Path $RegistryDir -Recurse -Force -ErrorAction Stop
    }

    # Create directory structure
    $imageDir = Join-Path -Path $RegistryDir -ChildPath $imageName
    $manifestsDir = Join-Path -Path $imageDir -ChildPath "manifests"
    $blobsDir = Join-Path -Path $imageDir -ChildPath "blobs"

    New-Item -Path $manifestsDir -ItemType Directory -Force | Out-Null
    New-Item -Path $blobsDir -ItemType Directory -Force | Out-Null

    # Pull the image
    Write-Info "Pulling image from registry..."
    & ctr.exe -n $CONTAINERD_NAMESPACE images pull --platform windows/amd64 $ImageRef 2>&1 | ForEach-Object {
        Write-Host $_
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to pull image: $ImageRef"
    }

    # Export the image
    Write-Info "Exporting image..."
    $exportPath = Join-Path -Path $env:TEMP -ChildPath "image-export-$(Get-Random).tar"
    & ctr.exe -n $CONTAINERD_NAMESPACE images export $exportPath $ImageRef 2>&1 | ForEach-Object {
        Write-Host $_
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to export image: $ImageRef"
    }

    try {
        # Extract the tar file
        Write-Info "Extracting image contents..."
        $extractDir = Join-Path -Path $env:TEMP -ChildPath "image-extract-$(Get-Random)"
        New-Item -Path $extractDir -ItemType Directory -Force | Out-Null

        Push-Location $extractDir
        try {
            & tar.exe -xf $exportPath 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to extract image tar"
            }
        }
        finally {
            Pop-Location
        }

        # Read the index.json
        $indexPath = Join-Path -Path $extractDir -ChildPath "index.json"
        if (-not (Test-Path -Path $indexPath)) {
            throw "index.json not found in exported image"
        }

        $index = Get-Content -Path $indexPath -Raw | ConvertFrom-Json
        Write-Host "Found $($index.manifests.Count) manifest(s) in index"

        # Process the manifest list (we assume it's always a manifest list)
        $manifestDesc = $index.manifests[0]
        $manifestDigest = $manifestDesc.digest
        Write-Info "Processing manifest list (digest: $manifestDigest, mediaType: $($manifestDesc.mediaType), size: $($manifestDesc.size))"

        # Read manifest list from blobs
        $manifestBlobPath = Get-ExtractedBlobPath -ExtractDir $extractDir -Digest $manifestDigest

        if (-not (Test-Path -Path $manifestBlobPath)) {
            throw "Manifest blob not found: $manifestBlobPath"
        }

        $manifestContent = Get-Content -Path $manifestBlobPath -Raw
        $manifest = $manifestContent | ConvertFrom-Json

        # Filter for Windows manifests only
        Write-Info "Filtering Windows manifests..."
        $windowsManifests = $manifest.manifests | Where-Object {
            $_.platform.os -eq "windows"
        }

        if (-not $windowsManifests -or $windowsManifests.Count -eq 0) {
            throw "No Windows manifests found in image"
        }

        Write-Host "Found $($windowsManifests.Count) Windows manifest(s)"

        # Create filtered manifest list with only Windows images
        $filteredManifest = @{
            schemaVersion = $manifest.schemaVersion
            mediaType = $manifest.mediaType
            manifests = $windowsManifests
        }
        $filteredContent = $filteredManifest | ConvertTo-Json -Depth 10 -Compress

        # Calculate digest for the filtered manifest
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($filteredContent)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($bytes)
        $hashString = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
        $newDigest = "sha256:$hashString"

        # Save filtered manifest list
        $manifestPath = Get-DigestPath -BaseDir $manifestsDir -Digest $newDigest
        Save-ContentToPath -FilePath $manifestPath -Content $filteredContent

        # Create tag file
        $tagFilePath = Join-Path -Path $manifestsDir -ChildPath $Tag
        Save-ContentToPath -FilePath $tagFilePath -Content $newDigest

        # Process each Windows manifest and copy blobs
        Write-Info "Copying manifests and blobs..."
        foreach ($winManifest in $windowsManifests) {
            $winDigest = $winManifest.digest
            Write-Host "Processing Windows manifest: $winDigest"

            $winManifestBlobPath = Get-ExtractedBlobPath -ExtractDir $extractDir -Digest $winDigest

            if (-not (Test-Path -Path $winManifestBlobPath)) {
                Write-Warning "Windows manifest blob not found: $winManifestBlobPath"
                continue
            }

            $winManifestContent = Get-Content -Path $winManifestBlobPath -Raw
            $winManifestPath = Get-DigestPath -BaseDir $manifestsDir -Digest $winDigest
            Save-ContentToPath -FilePath $winManifestPath -Content $winManifestContent

            # Parse manifest to get config and layers
            $winManifestObj = $winManifestContent | ConvertFrom-Json

            # Copy config blob
            if ($winManifestObj.config) {
                $configDigest = $winManifestObj.config.digest
                $configBlobPath = Get-ExtractedBlobPath -ExtractDir $extractDir -Digest $configDigest
                if (Test-Path -Path $configBlobPath) {
                    $configDestPath = Get-DigestPath -BaseDir $blobsDir -Digest $configDigest
                    Copy-FileToPath -SourcePath $configBlobPath -DestinationPath $configDestPath
                }
            }

            # Copy layer blobs
            if ($winManifestObj.layers) {
                foreach ($layer in $winManifestObj.layers) {
                    $layerDigest = $layer.digest
                    $layerBlobPath = Get-ExtractedBlobPath -ExtractDir $extractDir -Digest $layerDigest
                    if (Test-Path -Path $layerBlobPath) {
                        $layerDestPath = Get-DigestPath -BaseDir $blobsDir -Digest $layerDigest
                        Copy-FileToPath -SourcePath $layerBlobPath -DestinationPath $layerDestPath
                    }
                }
            }
        }

        Write-Success "Successfully created registry structure at: $RegistryDir"
    }
    finally {
        # Cleanup temporary files
        Write-Host "Cleaning up temporary files..."
        if (Test-Path -Path $exportPath) {
            Remove-Item -Path $exportPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -Path $extractDir) {
            Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    exit 0
}
catch {
    Write-ErrorMessage "Failed to create registry structure: $_"
    Write-Host $_.ScriptStackTrace
    exit 1
}

#endregion
