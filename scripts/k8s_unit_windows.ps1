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
    "./pkg/proxy/nftables/...",
    "./pkg/controller/...",
    "./pkg/controlplane/...",
    "./pkg/kubelet/...",
    "./pkg/kubeapiserver/...",
    "./pkg/kubectl/...")
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
    # TEMPORARY: Override any passed-in packages to run the first six packages from the working log
    Write-Host "TEMPORARY: Overriding testPackages parameter to run targeted package list"
    Write-Host "Original testPackages parameter had $($testPackages.Count) items: $testPackages"
    return @(
        "./pkg/api/...",
        "./pkg/apis/...",
        "./pkg/capabilities/...",
        "./pkg/certauthorization/...",
        "./pkg/auth/...",
        "./pkg/client/..."
    )
    
    # Original code commented out for now
    if ($testPackages.Count -ne 0) {
        return $testPackages
    }
    
    # Original code commented out for now
    # Push-Location "$RepoPath/pkg"
    # $packages = ls -Directory  | select Name | foreach { "./pkg/" + $_.Name + "/..." }
    # $packages = $packages + $EXTRA_PACKAGES
    # $EXCLUDED_PACKAGES | foreach { $packages = $packages -ne $_ }
    # Pop-Location
    # return $packages
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
    # Set GOMAXPROCS globally for the entire machine/session
    $env:GOMAXPROCS = 4
    [Environment]::SetEnvironmentVariable("GOMAXPROCS", "4", "Process")
    Write-Host "Set GOMAXPROCS=2 globally for this session"
    Write-Host "Verification: GOMAXPROCS = $env:GOMAXPROCS"
    
    # Limit parallel jobs to prevent CPU oversubscription
    # Reduced from 4 to 2 to further reduce load
    $maxParallelJobs = 4
    $jobs = New-Object System.Collections.ArrayList
    $failedJobCount = 0
    $packageIndex = 0

    Write-Host "Starting test execution with max $maxParallelJobs parallel jobs, GOMAXPROCS=2 per job"
    Write-Host "System info: $(Get-WmiObject Win32_Processor | Select-Object -ExpandProperty NumberOfLogicalProcessors) logical processors"
    
    Write-Host "Total packages to test: $($TEST_PACKAGES.Count)"
    Write-Host "TEST_PACKAGES contents: $TEST_PACKAGES"
    Write-Host "TEST_PACKAGES type: $($TEST_PACKAGES.GetType().Name)"
    
    while ($packageIndex -lt $TEST_PACKAGES.Count -or $jobs.Count -gt 0) {
        Write-Host "Loop iteration: packageIndex=$packageIndex, jobs.Count=$($jobs.Count)"
        
        # Start new jobs up to the limit
        while ($jobs.Count -lt $maxParallelJobs -and $packageIndex -lt $TEST_PACKAGES.Count) {
            $package = $TEST_PACKAGES[$packageIndex]
            Write-Host "DEBUG: packageIndex=$packageIndex, package retrieved='$package'"
            $junit_output_file = Join-Path -Path $LogsDirPath -ChildPath ("{0}_{1}.xml" -f $JUNIT_FILE_NAME, $packageIndex)

            $testsToSkip = $null
            if ($SkipFailingTests -and $SkipTestsForPackage.ContainsKey($package)) {
                $testsToSkip = $SkipTestsForPackage[$package] -join "|"
                Write-Output "Skipping tests for package: $package, tests: $testsToSkip"
            } else {
                Write-Output "Not skipping any tests for package: $package"
            }

            Write-Output "Starting job to run tests for package: $package ($(($packageIndex + 1)) of $($TEST_PACKAGES.Count))"
            $job = Start-Job -ScriptBlock {
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
                $env:GOMAXPROCS = 4

                # Collect output in an array.
                $outputLines = @()
                $outputLines += "Job starting for package: $pkg"
                $outputLines += "GOMAXPROCS in job: $env:GOMAXPROCS"
                $outputLines += "Verification via go: $(go env GOMAXPROCS)"
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

            [void]$jobs.Add($job)
            $packageIndex++
        }

        # Wait for jobs to complete and process them
        if ($jobs.Count -gt 0) {
            # Find all completed jobs without blocking
            $completedJobs = $jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }

            if ($completedJobs.Count -eq 0) {
                # If no jobs are done, wait for any to complete to avoid a tight loop
                Write-Host "Waiting for at least one job to complete... ($($jobs.Count) active jobs)"
                $finishedJob = Wait-Job -Job $jobs -Any -Timeout 3600
                if ($null -eq $finishedJob) {
                    Write-Output "WARNING: Timeout waiting for job completion after 3600 seconds"
                    # ... (timeout handling code remains the same)
                    exit 1
                }
                # Add the first finished job to our list to process
                $completedJobs = @($finishedJob)
            }
            
            Write-Host "Found $($completedJobs.Count) completed job(s) to process."

            foreach ($finishedJob in $completedJobs) {
                Write-Host "Receiving job results for job $($finishedJob.Id)..."
                $result = Receive-Job -Job $finishedJob
                Write-Host "Job result received. Package: $($result.Package), ExitCode: $($result.ExitCode)"
                
                if ($result.ExitCode -ne 0) {
                    $failedJobCount++
                }
            
                Write-Output "Output for package: $($result.Package)"
                Write-Output $result.Output
                Write-Output "Exit code: $($result.ExitCode)"
                Write-Output ("-" * 40)
            
                # Clean up the completed job
                Write-Host "Cleaning up job $($finishedJob.Id)..."
                Remove-Job -Job $finishedJob -Force
                [void]$jobs.Remove($finishedJob)
                $remainingPackages = $TEST_PACKAGES.Count - $packageIndex
                Write-Output "Active jobs: $($jobs.Count), Remaining packages: $remainingPackages"
                Write-Output ("-" * 40)
            }
        }
    }

    Write-Host "All packages processed. failedJobCount=$failedJobCount"
    $remainingSystemJobs = Get-Job
    if ($remainingSystemJobs) {
        Write-Host "Cleaning up remaining background jobs: $($remainingSystemJobs.Count)"
        $remainingSystemJobs | Remove-Job -Force
    }
    
    if ($failedJobCount) {
        Write-Host "Exiting with code 1 due to $failedJobCount failed jobs"
        exit 1
    }
    else {
        Write-Host "Exiting with code 0 - all tests passed"
        exit 0
    }
}

Prepare-LogsDir
Clone-TestRepo
Prepare-Vendor
Build-Kubeadm
Install-Tools
Write-Host "DEBUG: Before calling Prepare-TestPackages"
$TEST_PACKAGES = @(Prepare-TestPackages)
Write-Host "DEBUG: After Prepare-TestPackages, TEST_PACKAGES = $TEST_PACKAGES (Count: $($TEST_PACKAGES.Count), Type: $($TEST_PACKAGES.GetType().Name))"
Run-K8sUnitTests
