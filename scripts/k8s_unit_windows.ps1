param (
    [string]$repoName = "kubernetes", 
    [string]$repoOrg = "kubernetes",    
    [string]$pullRequestNo,
    [string]$pullBaseRef = "master"
)

$LogsDirPath = "c:/Logs"
$RepoPath = "c:/$repoName"
$RepoURL = "https://github.com/$repoOrg/$repoName"
$LocalPullBranch = "testBranch"
$JUNIT_FILE_NAME="junit"
$EXTRA_PACKAGES = @("./cmd/...")
$EXCLUDED_PACKAGES = @("./pkg/proxy/...", "./cmd/kubeadm/test/...")


function Prepare-TestPackages {
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

function Run-K8sUnitTests {

    Push-Location "$RepoPath"
    for ( $index = 0; $index -lt $TEST_PACKAGES.count; $index++ ) {
        
        echo "Running unit tests for packages" $TEST_PACKAGES[$index]
        $junit_output_file=Join-Path -Path $LogsDirPath -ChildPath "${JUNIT_FILE_NAME}_${index}.xml"
        
        gotestsum.exe --junitfile $junit_output_file --packages $TEST_PACKAGES[$index]
    }
    Pop-Location

}

Prepare-LogsDir
Clone-TestRepo
Prepare-Vendor
Install-Tools
$TEST_PACKAGES=Prepare-TestPackages
Run-K8sUnitTests
