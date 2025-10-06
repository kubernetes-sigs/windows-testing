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
    "./pkg/kubectl/...",
    "./pkg/apis/...")  # Temporarily excluding due to hanging issues
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
    # TEMPORARY: Override any passed-in packages to run targeted package list
    Write-Host "TEMPORARY: Overriding testPackages parameter to run targeted package list"
    Write-Host "Original testPackages parameter had $($testPackages.Count) items: $testPackages"
    return @(
        "./pkg/api/...",
        "./pkg/capabilities/...",
        "./pkg/certauthorization/...",
        "./pkg/auth/...",
        "./pkg/client/...",
        "./pkg/version/..."
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
    Write-Host "Set GOMAXPROCS=4 globally for this session"
    Write-Host "Verification: GOMAXPROCS = $env:GOMAXPROCS"
    
    # Limit parallel jobs to prevent CPU oversubscription
    $maxParallelJobs = 4
    $jobs = New-Object System.Collections.ArrayList
    $failedPackages = New-Object System.Collections.ArrayList
    $packageIndex = 0

    Write-Host "Total packages to test: $($TEST_PACKAGES.Count)"
    Write-Host "TEST_PACKAGES contents: $TEST_PACKAGES"
    Write-Host "TEST_PACKAGES type: $($TEST_PACKAGES.GetType().Name)"
    
    # Add immediate debugging with flush
    Write-Host "=== STARTING MAIN PROCESSING LOOP ===" 
    [Console]::Out.Flush()
    
    while ($packageIndex -lt $TEST_PACKAGES.Count -or $jobs.Count -gt 0) {
        Write-Host "=== Loop iteration: packageIndex=$packageIndex, jobs.Count=$($jobs.Count) ==="
        [Console]::Out.Flush()
        
        # Start new jobs up to the limit
        while ($jobs.Count -lt $maxParallelJobs -and $packageIndex -lt $TEST_PACKAGES.Count) {
            Write-Host ">>> Starting new job: jobs.Count=$($jobs.Count), packageIndex=$packageIndex"
            [Console]::Out.Flush()
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

            Write-Output "Starting job to run tests for package: $package ($($packageIndex + 1) of $($TEST_PACKAGES.Count))"
            [Console]::Out.Flush()
            
            $job = Start-Job -ScriptBlock {
                param($package, $junitIndex, $repoPath)

                Set-Location $repoPath

                $env:GOMAXPROCS = 4
                Write-Host "Job starting for package: $package from $(Get-Location)"
                Write-Host "GOMAXPROCS in job: $env:GOMAXPROCS"
                Write-Host "Verification via go: $(go env GOMAXPROCS)"
                
                Write-Host "---PROCESS LIST before test---"
                Get-Process gotestsum, go -ErrorAction SilentlyContinue
                Write-Host "------------------------------"

                $junitFile = "c:\Logs\junit_$($junitIndex).xml"
                $logFile = "c:\Logs\output_$($junitIndex).log"
                $command = "gotestsum.exe"
                $arguments = "--junitfile=$junitFile --packages=""$package"""
                Write-Host "Running unit tests for package: $package :: $command $arguments"
                
                # Log the command line to the output file first
                "Running unit tests for package: $package :: $command $arguments" | Out-File -FilePath $logFile -Encoding UTF8
                "=== TEST START ===" | Out-File -FilePath $logFile -Append -Encoding UTF8
                
                # Use System.Diagnostics.Process with async output reading to prevent buffer overflow
                Write-Host "About to run: $command $arguments"
                
                $process = New-Object System.Diagnostics.Process
                $process.StartInfo.FileName = $command
                $process.StartInfo.Arguments = $arguments
                $process.StartInfo.RedirectStandardOutput = $true
                $process.StartInfo.RedirectStandardError = $true
                $process.StartInfo.UseShellExecute = $false
                $process.StartInfo.CreateNoWindow = $true
                $process.StartInfo.WorkingDirectory = $repoPath
                
                # Set 10 minute timeout
                $timeoutMs = 20 * 60 * 1000
                
                # Create StringBuilder to collect output without blocking
                $stdout = New-Object System.Text.StringBuilder
                $stderr = New-Object System.Text.StringBuilder
                
                # Event handlers to read output asynchronously and prevent buffer overflow
                $outputAction = {
                    if ($EventArgs.Data) {
                        [void]$Event.MessageData.StringBuilder.AppendLine($EventArgs.Data)
                        # Also write directly to log file to prevent memory buildup
                        $EventArgs.Data | Out-File -FilePath "c:\Logs\output_$($Event.MessageData.Tag).log" -Append -Encoding UTF8
                    }
                }
                $errorAction = {
                    if ($EventArgs.Data) {
                        [void]$Event.MessageData.StringBuilder.AppendLine($EventArgs.Data)
                        # Also write directly to log file
                        "STDERR: $($EventArgs.Data)" | Out-File -FilePath "c:\Logs\output_$($Event.MessageData.Tag).log" -Append -Encoding UTF8
                    }
                }
                
                $outputEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $outputAction -MessageData @{StringBuilder=$stdout; Tag=$junitIndex}
                $errorEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $errorAction -MessageData @{StringBuilder=$stderr; Tag=$junitIndex}
                
                $process.Start()
                $process.BeginOutputReadLine()
                $process.BeginErrorReadLine()
                
                Write-Host "Process started with PID: $($process.Id), waiting for completion..."
                
                if (-not $process.WaitForExit($timeoutMs)) {
                    Write-Host "Process timed out after 20 minutes, killing it"
                    $process.Kill()
                    $process.WaitForExit(5000) # Wait up to 5 seconds for clean shutdown
                    $exitCode = -1
                    $output = "TIMEOUT: Process killed after 20 minutes"
                } else {
                    $exitCode = $process.ExitCode
                    $output = "Process completed normally"
                }
                
                # Clean up event handlers
                Unregister-Event -SourceIdentifier $outputEvent.Name
                Unregister-Event -SourceIdentifier $errorEvent.Name
                
                Write-Host "Command completed with exit code: $exitCode"
                
                # Final output summary (actual output is in log file)
                "=== TEST END ===" | Out-File -FilePath $logFile -Append -Encoding UTF8
                "Exit code: $exitCode" | Out-File -FilePath $logFile -Append -Encoding UTF8
                
                # Check if log file exists and get its size
                if (Test-Path $logFile) {
                    $logSize = (Get-Item $logFile).Length
                    Write-Host "Log file size: $logSize bytes"
                } else {
                    Write-Host "ERROR: Log file not found!"
                    $logSize = 0
                }
                
                Write-Host "---PROCESS LIST after test---"
                Get-Process gotestsum, go -ErrorAction SilentlyContinue
                Write-Host "-----------------------------"

                return [PSCustomObject]@{
                    Package    = $package
                    Output     = "See log file: $logFile (size: $logSize bytes)"
                    ExitCode   = $exitCode
                }
            } -ArgumentList $package, $packageIndex, $RepoPath
            
            if ($job) {
                $job.Name = "UnitTest-$package"
                [void]$jobs.Add($job)
                Write-Host ">>> Job started with ID: $($job.Id), Name: $($job.Name)"
            } else {
                Write-Host "ERROR: Failed to create job for package: $package"
                $failedPackages.Add("FAILED_TO_CREATE_JOB: $package") | Out-Null
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
                if (($waitCounter % 15) -eq 0) {
                    Write-Host "DEBUG: Still waiting for jobs to complete after $waitCounter seconds. Current job states:"
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
                $failedPackages.Add("FAULTED_JOB: $($finishedJob.Name)") | Out-Null
            } else {
                $result = Receive-Job -Job $finishedJob
                Write-Host "Job result received. Package: $($result.Package), ExitCode: $($result.ExitCode)"
                
                Write-Host "Output for package: $($result.Package)"
                Write-Host $result.Output
                Write-Host "----------------------------------------"

                if ($result.ExitCode -ne 0) {
                    $failedPackages.Add($result.Package) | Out-Null
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
