param (
    [string]$repoName = "kubernetes",
    [string]$repoOrg = "kubernetes",
    [string]$pullRequestNo,
    [string]$pullBaseRef = "master",
    [string]$dryRun = "false"
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

    Write-Host "Building kube-log-runner"
    go build -o .\_output\kube-log-runner.exe .\staging\src\k8s.io\component-base\logs\kube-log-runner
    
    $outputDir = Join-Path -Path $RepoPath -ChildPath "_output"
    $env:KUBELET_PATH = $outputDir
    Pop-Location
}

function Run-K8se2enodeWindowsTests {
    Push-Location "$RepoPath"
    
    $GINKGO_FOCUS = $ginkgoFocus
    
    if ($dryRun -eq "true") {
        Write-Host "Running tests in dry run mode. Skipping test execution."
        # Create a dummy file to indicate dry ru
        New-Item -ItemType File -Path (Join-Path -Path $LogsDirPath -ChildPath "dryrun.xml") -Force
        return
    }

    Write-Host "Running e2e node tests"
    go test ./test/e2e_node `
        --bearer-token=vQIYfdCt7wIFOZtO `
        --test.v `
        --test.paniconexit0 `
        --container-runtime-endpoint "npipe://./pipe/containerd-containerd" `
        --prepull-images=false `
        --ginkgo.focus "$env:GINKGO_FOCUS" `
        --k8s-bin-dir $env:KUBELET_PATH `
        --report-dir $LogsDirPath `
        --report-complete-junit
        
    Pop-Location
}

Prepare-LogsDir
Clone-TestRepo
Build-Kubelet
Run-K8se2enodeWindowsTests
