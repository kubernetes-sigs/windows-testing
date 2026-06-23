param (
    [string]$repoName = "kubernetes",
    [string]$repoOrg = "kubernetes",
    [string]$pullRequestNo,
    [string]$pullBaseRef = "master",
    [string]$dryRun = "false",
    [string]$ginkgoFocus = ""
)

$LogsDirPath = "c:/Logs"
$RepoPath = "c:/$repoName"
$RepoURL = "https://github.com/$repoOrg/$repoName"
$LocalPullBranch = "testBranch"

$ErrorActionPreference = "Stop"

function Prepare-LogsDir {
    if (Test-Path $LogsDirPath) {
        Write-Host "Logs directory already exists. Deleting it."
        Remove-Item -Recurse -Force $LogsDirPath
    }
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

function Build-Kubelet {
    Write-Host "Building kubelet"

    Push-Location "$RepoPath"
    go build -o .\_output\kubelet.exe .\cmd\kubelet\
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        throw "Failed to build kubelet (exit code $LASTEXITCODE)"
    }

    Write-Host "Building kube-log-runner"
    go build -o .\_output\kube-log-runner.exe .\staging\src\k8s.io\component-base\logs\kube-log-runner
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        throw "Failed to build kube-log-runner (exit code $LASTEXITCODE)"
    }

    $outputDir = Join-Path -Path $RepoPath -ChildPath "_output"
    $env:KUBELET_PATH = $outputDir
    Pop-Location
}

function Run-K8se2enodeWindowsTests {
    Push-Location "$RepoPath"

    Write-Host "Running e2e node tests"

    # Use --flag=value form so no flag can accidentally consume the following
    # token as its value, and only pass --ginkgo.focus when it is non-empty
    # (Windows PowerShell 5.1 drops empty-string arguments to native commands,
    # which would otherwise make --ginkgo.focus swallow the next flag).
    $testArgs = @(
        "test"
        "./test/e2e_node_windows"
        "--bearer-token=vQIYfdCt7wIFOZtO"
        "--test.v"
        "--test.paniconexit0"
        "--container-runtime-endpoint=npipe://./pipe/containerd-containerd"
        "--prepull-images=false"
        "--k8s-bin-dir=$env:KUBELET_PATH"
        "--report-dir=$LogsDirPath"
        "--report-complete-junit"
    )

    if (-not [string]::IsNullOrEmpty($ginkgoFocus)) {
        $testArgs += "--ginkgo.focus=$ginkgoFocus"
    }

    Write-Host "Test command: go $($testArgs -join ' ')"

    & go @testArgs
    # Capture the test exit code so the caller can propagate it. A failing
    # native command does not stop the script under PowerShell 5.1, so without
    # this the script would exit 0 even when the tests fail.
    $script:testExitCode = $LASTEXITCODE

    Pop-Location
}

Prepare-LogsDir
Clone-TestRepo
Build-Kubelet
Run-K8se2enodeWindowsTests

Write-Host "e2e node tests exited with code $script:testExitCode"
exit $script:testExitCode
