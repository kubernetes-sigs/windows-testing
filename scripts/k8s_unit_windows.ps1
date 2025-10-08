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
    "./pkg/routes/..." = @(
        "TestPreCheckLogFileNameLength"
    )
}

function Prepare-TestPackages {
    if ($testPackages.Count -ne 0) {
        return $testPackages
    }

    Push-Location "$RepoPath/pkg"
    $packages = ls -Directory | select Name | foreach { "./pkg/" + $_.Name + "/..." }
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
    # Set GOMAXPROCS globally for the entire machine/session
    $env:GOMAXPROCS = 4
    [Environment]::SetEnvironmentVariable("GOMAXPROCS", "4", "Process")
    Write-Host "Set GOMAXPROCS=4 globally for this session"
    Write-Host "Verification: GOMAXPROCS = $env:GOMAXPROCS"
    
    # Limit parallel jobs to prevent CPU oversubscription
    $maxParallelJobs = 4
    $jobs = New-Object System.Collections.ArrayList
    $failedPackages = New-Object System.Collections.ArrayList
    $packageIndex = 0

    Write-Host "Total packages to test: $($TEST_PACKAGES.Count)"
    Write-Host "TEST_PACKAGES contents: $TEST_PACKAGES"

    while ($packageIndex -lt $TEST_PACKAGES.Count -or $jobs.Count -gt 0) {
        # Start new jobs up to the limit
        while ($jobs.Count -lt $maxParallelJobs -and $packageIndex -lt $TEST_PACKAGES.Count) {
            Write-Host ">>> Starting new job: jobs.Count=$($jobs.Count), packageIndex=$packageIndex"
            [Console]::Out.Flush()
            $package = $TEST_PACKAGES[$packageIndex]
            Write-Host "INFO: packageIndex=$packageIndex, package retrieved='$package'"
            $junit_output_file = Join-Path -Path $LogsDirPath -ChildPath ("{0}_{1}.xml" -f $JUNIT_FILE_NAME, $packageIndex)

            $testsToSkip = $null
            if ($SkipFailingTests -and $SkipTestsForPackage.ContainsKey($package)) {
                $testsToSkip = $SkipTestsForPackage[$package] -join "|"
                Write-Output "Skipping tests for package: $package, tests: $testsToSkip"
            } else {
                Write-Output "Not skipping any tests for package: $package"
            }

            Write-Output "Starting job to run tests for package: $package ($($packageIndex + 1) of $($TEST_PACKAGES.Count))"
            [Console]::Out.Flush()
            
            $job = Start-Job -ScriptBlock {
                param($package, $junitIndex, $repoPath, $testsToSkip)

                Set-Location $repoPath

                $env:GOMAXPROCS = 4
                Write-Host "Job starting for package: $package from $(Get-Location)"

                # Create filesystem-safe package name
                $packageName = $package -replace '[./]', '-'
                $junitFile = "c:\Logs\junit_$($junitIndex).xml"
                $logFile = "c:\Logs\output_$($junitIndex)_$packageName.log"
                $command = "gotestsum.exe"
                
                # Build arguments array like the original
                $args = @(
                    "--junitfile=$junitFile",
                    "--packages=`"$package`""
                )
                
                # Add skip tests if specified (using the original logic)
                if ($testsToSkip) {
                    Write-Host "Adding skip arguments for tests: $testsToSkip"
                    $args += "--"
                    $args += "--skip"
                    # Escape pipe characters for cmd.exe
                    $escapedTests = $testsToSkip -replace '\|', '^|'
                    $args += "`"$escapedTests`""
                }
                
                # Convert args array to string for cmd.exe
                $arguments = $args -join " "
                
                Write-Host "Running unit tests for package: $package :: $command $arguments"
                
                # Log the command line to the output file first
                "Running unit tests for package: $package :: $command $arguments" | Out-File -FilePath $logFile -Encoding UTF8
                "=== TEST START ===" | Out-File -FilePath $logFile -Append -Encoding UTF8
                "Job started at: $(Get-Date)" | Out-File -FilePath $logFile -Append -Encoding UTF8
                
                # Use cmd.exe with file redirection to avoid PowerShell buffer issues
                # which cause a hang if output buffers fill up
                Write-Host "About to run: $command $arguments"
                "About to run: $command $arguments at $(Get-Date)" | Out-File -FilePath $logFile -Append -Encoding UTF8

                # Create temporary output file
                $tempOutputFile = "$logFile.temp"

                # Use cmd.exe to redirect output directly to file, avoiding PowerShell buffers
                $cmdLine = "cmd.exe /c $command $arguments > `"$tempOutputFile`" 2>&1"
                "Starting process at: $(Get-Date)" | Out-File -FilePath $logFile -Append -Encoding UTF8
                "Command line: $cmdLine" | Out-File -FilePath $logFile -Append -Encoding UTF8

                # Use Invoke-Expression to run the cmd command
                try {
                    Invoke-Expression $cmdLine
                    $exitCode = $LASTEXITCODE
                    if (-not $exitCode) { $exitCode = 0 }
                    
                    Write-Host "Process completed with exit code: $exitCode"
                    "Process completed with exit code: $exitCode at: $(Get-Date)" | Out-File -FilePath $logFile -Append -Encoding UTF8
                } catch {
                    Write-Host "Error running command: $_"
                    "Error running command: $_ at: $(Get-Date)" | Out-File -FilePath $logFile -Append -Encoding UTF8
                    $exitCode = 1
                }
                
                # Read the output file
                $output = ""
                if (Test-Path $tempOutputFile) {
                    try {
                        $output = Get-Content $tempOutputFile -Raw
                        # Remove the temp file
                        Remove-Item $tempOutputFile -ErrorAction SilentlyContinue
                    } catch {
                        Write-Host "Error reading output file: $_"
                        "Error reading output file: $_" | Out-File -FilePath $logFile -Append -Encoding UTF8
                        $output = "Error reading output file: $_"
                    }
                } else {
                    $output = "No output file created"
                }
                
                Write-Host "Command completed with exit code: $exitCode"
                
                # Write combined output to main log file
                if ($output) {
                    $output | Out-File -FilePath $logFile -Append -Encoding UTF8
                }
                "Exit code: $exitCode" | Out-File -FilePath $logFile -Append -Encoding UTF8
                "Job completed at: $(Get-Date)" | Out-File -FilePath $logFile -Append -Encoding UTF8

                # Prune junit XML file to remove skipped tests
                Write-Host "Pruning junit file: $junitFile"
                & prune-junit-xml.exe "$junitFile"

                # Check if log file exists and get its size
                if (Test-Path $logFile) {
                    $logSize = (Get-Item $logFile).Length
                    Write-Host "Log file size: $logSize bytes"
                } else {
                    Write-Host "ERROR: Log file not found!"
                    $logSize = 0
                }

                return [PSCustomObject]@{
                    Package    = $package
                    Output     = "See log file: $logFile (size: $logSize bytes)"
                    ExitCode   = $exitCode
                }
            } -ArgumentList $package, $packageIndex, $RepoPath, $testsToSkip

            if ($job) {
                $job.Name = "UnitTest-$package"
                [void]$jobs.Add($job)
                Write-Host ">>> Job started with ID: $($job.Id), Name: $($job.Name)"
            } else {
                Write-Host "ERROR: Failed to create job for package: $package"
                [void]$failedPackages.Add("FAILED_TO_CREATE_JOB: $package")
            }
            [Console]::Out.Flush()

            $packageIndex++
        }

        # Wait for jobs to finish
        if ($jobs.Count -gt 0) {
            Write-Host ">>> Waiting for at least one job to complete... ($($jobs.Count) active jobs)"
            [Console]::Out.Flush()
            
            $waitCounter = 0
            # Continuously check for completed jobs until at least one is found
            while (($jobs | Where-Object { $_.State -in @('Completed', 'Faulted') }).Count -eq 0 -and $jobs.Count -gt 0) {
                Start-Sleep -Seconds 1
                $waitCounter++
                if (($waitCounter % 30) -eq 0) {
                    Write-Host "INFO: Still waiting for jobs to complete after $waitCounter seconds. Current job states:"
                    $jobs | ForEach-Object { Write-Host "  - Job ID: $($_.Id), Name: $($_.Name), State: $($_.State)" }
                }
            }
        }

        $completedJobs = $jobs | Where-Object { $_.State -in @('Completed', 'Faulted') }

        if ($completedJobs.Count -gt 0) {
            Write-Host "Found $($completedJobs.Count) completed/faulted job(s) to process."
        }

        $jobsToRemove = @()
        foreach ($finishedJob in $completedJobs) {
            Write-Host "Receiving job results for job $($finishedJob.Id) (State: $($finishedJob.State))..."
            if ($finishedJob.State -eq 'Faulted') {
                Write-Host "Job $($finishedJob.Id) has faulted. Error:"
                $finishedJob.ChildJobs[0].JobStateInfo.Reason.Message | Write-Host
                [void]$failedPackages.Add("FAULTED_JOB: $($finishedJob.Name)")
            } else {
                $result = Receive-Job -Job $finishedJob
                
                # Extract package name properly, handling both array and object cases
                $packageName = $result.Package
                if ($packageName -is [array]) {
                    $packageName = $packageName[0]
                }
                # Clean up whitespace and ensure it's a string
                $packageName = [string]$packageName
                $packageName = $packageName.Trim()
                
                # Additional safety check for empty/null values
                if ([string]::IsNullOrWhiteSpace($packageName)) {
                    $packageName = "UNKNOWN_PACKAGE_$($finishedJob.Id)"
                }
                
                Write-Host "Job result received. Package: $packageName, ExitCode: $($result.ExitCode)"

                Write-Host "Output for package: $packageName"
                Write-Host $result.Output
                Write-Host "----------------------------------------"

                if ($result.ExitCode -ne 0) {
                    Write-Host "Adding failed package to results: '$packageName' (exit code: $($result.ExitCode))"
                    [void]$failedPackages.Add($packageName)
                } else {
                    Write-Host "Package '$packageName' passed (exit code: $($result.ExitCode))"
                }
            }

            Write-Host "Cleaning up job $($finishedJob.Id)..."
            Remove-Job -Job $finishedJob
            $jobsToRemove += $finishedJob

            Write-Host "Active jobs: $($jobs.Count), Remaining packages: $($TEST_PACKAGES.Count - $packageIndex)"
            Write-Host "----------------------------------------"
        }
        
        # Remove all processed jobs from the collection at once
        $jobsToRemove | ForEach-Object { [void]$jobs.Remove($_) }
    }

    Write-Host "All packages have been processed. Final job cleanup..."
    $remainingSystemJobs = Get-Job
    if ($remainingSystemJobs) {
        Write-Host "Cleaning up remaining background jobs: $($remainingSystemJobs.Count)"
        $remainingSystemJobs | Remove-Job -Force
    }
    
    if ($failedPackages.Count -gt 0) {
        Write-Host "Exiting with code 1 due to $($failedPackages.Count) failed packages: $($failedPackages -join ', ')"
        exit 1
    }
    else {
        Write-Host "Exiting with code 0 - all tests passed"
        exit 0
    }
}

# Main script execution
Prepare-LogsDir
Clone-TestRepo
Prepare-Vendor
Build-Kubeadm
Install-Tools

Write-Host "DEBUG: Before calling Prepare-TestPackages"
$TEST_PACKAGES = @(Prepare-TestPackages)
Write-Host "DEBUG: After Prepare-TestPackages, TEST_PACKAGES = $TEST_PACKAGES (Count: $($TEST_PACKAGES.Count), Type: $($TEST_PACKAGES.GetType().Name))"

Run-K8sUnitTests
