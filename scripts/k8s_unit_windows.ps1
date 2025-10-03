param (
    [string]$repoName = "kubernetes", 
    [string]$repoOrg = "kubernetes",    
    [string]$pullRequestNo,
    [string]$pullBaseRef = "master",
    [string[]]$testPackages = @(),
    [switch]$SkipFailingTests = $true # When set, will skip test cases from the mapping below
)

$LogsDirPath = "c:/Logs"
$RepoPath = "c:/$repoName"
$RepoURL = "https://github.com/$repoOrg/$repoName"
$LocalPullBranch = "testBranch"
$JUNIT_FILE_NAME = "junit"
$EXTRA_PACKAGES = @("./cmd/...")
$EXCLUDED_PACKAGES = @(
    "./pkg/proxy/iptables/...",
    "./pkg/proxy/ipvs/...",
    "./pkg/proxy/nftables/...")
# Map of packages with test case names to skip.
$SkipTestsForPackage = @{
    "./cmd/..."         = @(
        "TestBytesToResetConfiguration",
        "TestBytesToJoinConfiguration",
        "TestBytesToInitConfiguration",
        "TestHollowNode/kubelet")
    "./pkg/kubelet/..." = @(
        "TestAllocatedResourcesMatchStatus",
        "TestAllocatableMemoryPressure",
        "TestComputePodActionsForPodResize",
        "TestComputePodActionsForPodResize/Nothing_when_spec.Resources_and_status.Resources_are_equivalent",
        "TestComputePodActionsForPodResize/Update_container_CPU_resources_to_equivalent_value",
        "TestCRIListPodStats",
        "TestGetTrustAnchorsBySignerNameCaching",
        "TestGRPCConnIsReused",
        "TestGRPCMethods",
        "TestKubeletServerCertificateFromFiles",
        "TestManagerWithLocalStorageCapacityIsolationOpen",
        "TestMinReclaim",
        "TestNodeReclaimFuncs",
        "TestPrepareResources",
        "TestStorageLimitEvictions",
        "TestToKubeContainerStatusWithResources/container_reporting_cpu_only",
        "TestUnprepareResources",
        "TestUpdateMemcgThreshold",
        "TestValidateKubeletConfiguration/KubeletCrashLoopBackOffMax_feature_gate_on,_no_crashLoopBackOff_config,_ok",
        "TestValidateKubeletConfiguration/Success",
        "TestValidateKubeletConfiguration/valid_MaxParallelImagePulls_and_SerializeImagePulls_combination"
    )
    "./pkg/scheduler/..." = @(
        "TestInFlightEventAsync")
    "./pkg/volume/..." = @(
        "TestPlugin",
        "TestPluginOptionalKeys"
    )
}

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
    # Do NOT use --depth (shallow clone), otherwise the relationship between tags and commits may be incomplete.
    # Because it will cause Get-VersionLdflags to fail to get correct gitVersion and gitMajor/gitMinor values.
    git clone --branch $pullBaseRef $RepoURL $RepoPath
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

function Get-VersionLdflags {
    $GitCommit = (git -C $RepoPath rev-parse "HEAD^{commit}").Trim()
    $GitStatus = (git -C $RepoPath status --porcelain)
    $GitTreeState = if ([string]::IsNullOrWhiteSpace($GitStatus)) { "clean" } else { "dirty" }
   
    $GitVersion = (git -C $RepoPath describe --tags --match='v*' --abbrev=14 "$GitCommit^{commit}").Trim()
    $DashesInVersion = ($GitVersion -replace "[^-]", "")
    if ($DashesInVersion -eq '---') {
        $GitVersion = $GitVersion -replace '-([0-9]+)-g([0-9a-f]{14})$', '.$1+$2'
    } elseif ($DashesInVersion -eq '--') {
        $GitVersion = $GitVersion -replace '-g([0-9a-f]{14})$', '+$1'
    }
    if ($GitTreeState -eq 'dirty') { $GitVersion += '-dirty' }
    
    $GitMajor = $null; $GitMinor = $null
    if ($GitVersion -match '^v([0-9]+)\.([0-9]+)(\.[0-9]+)?([-].*)?([+].*)?$') {
        $GitMajor = $Matches[1]
        $GitMinor = $Matches[2]
        if ($Matches[4]) { $GitMinor += '+' }
    }

    $BuildDate = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    
    $ldflags = @()
    $ldflags += "-X 'k8s.io/client-go/pkg/version.buildDate=$BuildDate'"
    $ldflags += "-X 'k8s.io/component-base/version.buildDate=$BuildDate'"
    if ($GitCommit) {
        $ldflags += "-X 'k8s.io/client-go/pkg/version.gitCommit=$GitCommit'"
        $ldflags += "-X 'k8s.io/component-base/version.gitCommit=$GitCommit'"
        $ldflags += "-X 'k8s.io/client-go/pkg/version.gitTreeState=$GitTreeState'"
        $ldflags += "-X 'k8s.io/component-base/version.gitTreeState=$GitTreeState'"
    }
    if ($GitVersion) {
        $ldflags += "-X 'k8s.io/client-go/pkg/version.gitVersion=$GitVersion'"
        $ldflags += "-X 'k8s.io/component-base/version.gitVersion=$GitVersion'"
    }
    if ($GitMajor -and $GitMinor) {
        $ldflags += "-X 'k8s.io/client-go/pkg/version.gitMajor=$GitMajor'"
        $ldflags += "-X 'k8s.io/component-base/version.gitMajor=$GitMajor'"
        $ldflags += "-X 'k8s.io/client-go/pkg/version.gitMinor=$GitMinor'"
        $ldflags += "-X 'k8s.io/component-base/version.gitMinor=$GitMinor'"
    }
    return $ldflags -join ' '
}

function Build-Kubeadm {
    # For the cmd/kubeadm tests, we need to build the kubeadm binary and set the KUBEADM_PATH path.
    # Before building the binary, we need to inject a few fields into k8s.io/component-base/version/base.go,
    # otherwise version-related unit tests for kubeadm will fail. 
    $buildFlags = Get-VersionLdflags
    Write-Host "[Build-Kubeadm] buildFlags: $buildFlags"
    
    Push-Location "$RepoPath"
    go build -ldflags "$buildFlags" -o kubeadm.exe .\cmd\kubeadm\
    $env:KUBEADM_PATH = Join-Path "$RepoPath" "kubeadm.exe"
    Pop-Location
}

function Run-K8sUnitTests {
    # Limit parallel jobs to prevent CPU oversubscription
    $maxParallelJobs = 4
    $jobs = @()
    $failedJobCount = 0
    $packageIndex = 0

    while ($packageIndex -lt $TEST_PACKAGES.Count -or $jobs.Count -gt 0) {
        # Start new jobs up to the limit
        while ($jobs.Count -lt $maxParallelJobs -and $packageIndex -lt $TEST_PACKAGES.Count) {
            $package = $TEST_PACKAGES[$packageIndex]
            $junit_output_file = Join-Path -Path $LogsDirPath -ChildPath ("{0}_{1}.xml" -f $JUNIT_FILE_NAME, $packageIndex)

            $testsToSkip = $null
            if ($SkipFailingTests -and $SkipTestsForPackage.ContainsKey($package)) {
                $testsToSkip = $SkipTestsForPackage[$package] -join "|"
                Write-Output "Skipping tests for package: $package, tests: $testsToSkip"
            } else {
                Write-Output "Not skipping any tests for package: $package"
            }

            Write-Output "Starting job to run tests for package: $package ($(($packageIndex + 1)) of $($TEST_PACKAGES.Count))"
            $jobs += Start-Job -ScriptBlock {
                param($pkg, $outputFile, $RepoPath, $skipRegex)

                Push-Location "$RepoPath"
                $args = @(
                    "--junitfile=$outputFile",
                    "--packages=`"$pkg`""
                )
                if ($skipRegex) {
                    $args += "--"
                    $args += "--skip"
                    $args += $skipRegex
                }

                Push-Location "$RepoPath"
                # Limit GOMAXPROCS to prevent each package from using all CPUs
                $env:GOMAXPROCS = 2

                # Collect output in an array.
                $outputLines = @()
                $outputLines += "Running unit tests for package: $pkg :: gotestsum.exe " + ($args -join ' ')
                $cmdOutput = & gotestsum.exe @args 2>&1
                $outputLines += $cmdOutput
                $exitCode = $LASTEXITCODE
                $combinedOutput = $outputLines -join "`n"
                & prune-junit-xml.exe $outputFile

                [PSCustomObject]@{
                    Package  = $pkg
                    ExitCode = $exitCode
                    Output   = $combinedOutput
                }
            } -ArgumentList $package, $junit_output_file, $RepoPath, $testsToSkip
        
            $packageIndex++
        }

        # Wait for at least one job to complete before starting more
        if ($jobs.Count -gt 0) {
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
            $remainingPackages = $TEST_PACKAGES.Count - $packageIndex
            Write-Output "Active jobs: $($jobs.Count), Remaining packages: $remainingPackages"
            Write-Output ("-" * 40)
        }
    }

    if ($failedJobCount) {
        exit 1
    }
    else {
        exit 0
    }
}

Prepare-LogsDir
Clone-TestRepo
Prepare-Vendor
Build-Kubeadm
Install-Tools
$TEST_PACKAGES = Prepare-TestPackages
Run-K8sUnitTests
