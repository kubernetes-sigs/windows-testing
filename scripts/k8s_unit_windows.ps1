param (
    [string]$repoName = "kubernetes", 
    [string]$repoOrg = "kubernetes",    
    [string]$pullRequestNo,
    [string]$pullBaseRef = "master",
    [string[]]$testPackages = @()
)

$LogsDirPath = "c:/Logs"
$RepoPath = "c:/$repoName"
$RepoURL = "https://github.com/$repoOrg/$repoName"
$LocalPullBranch = "testBranch"
$JUNIT_FILE_NAME="junit"
$EXTRA_PACKAGES = @("./cmd/...")
$EXCLUDED_PACKAGES = @("./pkg/proxy/iptables/...", "./pkg/proxy/ipvs/...", "./pkg/proxy/nftables/...")


function Prepare-TestPackages {
    if ($testPackages.Count -ne 0) {
        return $testPackages
    }

    Push-Location "$RepoPath/pkg"
    $packages = ls -Directory  | select Name | foreach { "./pkg/" + $_.Name + "/..." }
    $packages = $packages + $EXTRA_PACKAGES
    $EXCLUDED_PACKAGES | foreach { $packages = $packages -ne $_ }
    Pop-Location
    return $packages

}

function Prepare-LogsDir {
    
    mkdir $LogsDirPath

}

function Clone-TestRepo {
    Write-Host "Cloning $repoName repo"
    git clone --branch $pullBaseRef $RepoURL $RepoPath --depth=1
    if (($pullRequestNo -ne $null) -and ($pullRequestNo -ne "")) {
        Write-Host "Pulling PR $pullRequestNo changes"
        cd $RepoPath
        git fetch origin refs/pull/$pullRequestNo/head:$LocalPullBranch
        git checkout $LocalPullBranch
        if (! $?) {
            Write-Host "Failed to pull PR $pullRequestNo changes. Exiting"
            exit
        }
    }
}

function Install-Tools {

    Write-Host "Install testing tools"
    Push-Location "$RepoPath/hack/tools"
    go install gotest.tools/gotestsum
    Pop-Location

    Push-Location "$RepoPath/cmd/prune-junit-xml"
    go install .
    Pop-Location

}

function Prepare-Vendor {
    
    Write-Host "Downloading vendor files"
    Push-Location "$RepoPath"
    go mod vendor
    Pop-Location

}

function Build-Kubeadm {
    # For the cmd/kubeadm tests, we need to build the kubeadm binary and set the KUBEADM_PATH path.
    # Before building the binary, we need to inject a few fields into k8s.io/component-base/version/base.go,
    # otherwise version-related unit tests for kubeadm will fail. 
    $buildFlags = @(
        "-X 'k8s.io/component-base/version.gitTreeState=clean'",
        "-X 'k8s.io/component-base/version.gitMajor=1'",
        "-X 'k8s.io/component-base/version.gitMinor=30'",
        "-X 'k8s.io/component-base/version.gitVersion=v1.30.0'",
        "-X 'k8s.io/component-base/version.gitCommit=a06568062c41b4f0f903dcb78aa6ea348bbdecfc'"
    )

    Push-Location "$RepoPath"
    go build -ldflags "$buildFlags" -o kubeadm.exe .\cmd\kubeadm\
    $env:KUBEADM_PATH = Join-Path "$RepoPath" "kubeadm.exe"
    Pop-Location
}

function Run-K8sUnitTests {

    $jobs = @()

    for ($index = 0; $index -lt $TEST_PACKAGES.Count; $index++) {
        $package = $TEST_PACKAGES[$index]
        $junit_output_file = Join-Path -Path $LogsDirPath -ChildPath ("{0}_{1}.xml" -f $JUNIT_FILE_NAME, $index)
        
        Write-Output "Starting job to run tests for package: $package"
        $jobs += Start-Job -ScriptBlock {
            param($pkg, $outputFile, $RepoPath)

            Push-Location "$RepoPath"
            Write-Output "Running unit tests for package: $pkg"
                    # Collect output in an array.
            $outputLines = @()
            $outputLines += "Running unit tests for package: $pkg"
            $cmdOutput = & gotestsum.exe --junitfile $outputFile --packages $pkg 2>&1
            $outputLines += $cmdOutput
            $exitCode = $LASTEXITCODE
            $combinedOutput = $outputLines -join "`n"

            [PSCustomObject]@{
                Package = $pkg
                ExitCode = $exitCode
                Output = $combinedOutput
            }
        } -ArgumentList $package, $junit_output_file, $RepoPath
    }

    $failedJobCount = 0 
    while ($jobs.Count -gt 0) {
        $finishedJob = Wait-Job -Job $jobs -Any
        $result = Receive-Job -Job $finishedJob
        
        if ($result.ExitCode -ne 0) {
            $failedJobCount++
        }
    
        Write-Output "Output for package: $($result.Package)"
        Write-Output $result.Output
        Write-Output "Exit code: $($result.ExitCode)"
        Write-Output ("-" * 40)
    
        $jobs = $jobs | Where-Object { $_.Id -ne $finishedJob.Id }
        Write-Output "Waiting for $($jobs.Count) more jobs to complete"
        Write-Output ("-" * 40)
    }

    if ($failedJobCount) {
        exit 1
    } else {
        exit 0
    }
}

Prepare-LogsDir
Clone-TestRepo
Prepare-Vendor
Build-Kubeadm
Install-Tools
$TEST_PACKAGES=Prepare-TestPackages
Run-K8sUnitTests
