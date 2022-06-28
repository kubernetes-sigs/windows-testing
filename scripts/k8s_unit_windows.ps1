$LogsDirPath = "c:/Logs"
$K8sPath = "c:/Kubernetes"
$K8sRepo = "https://github.com/kubernetes/kubernetes"


function Prepare-LogsDir {
    
    mkdir $LogsDirPath

}

function Clone-K8s {
    Write-Host "Cloning Kubernetes repo"
    git clone $K8sRepo $K8sPath --depth=1
}

function Install-Tools {

    Write-Host "Install testing tools"
    Push-Location "$K8sPath/hack/tools"
    go install gotest.tools/gotestsum
    Pop-Location

    Push-Location "$K8sPath/cmd/prune-junit-xml"
    go install .
    Pop-Location

}

function Prepare-Vendor {
    
    Write-Host "Downloading vendor files"
    Push-Location "$K8sPath"
    go mod vendor
    Pop-Location

}

$JUNIT_FILE_NAME="junit"
$TEST_PACKAGES = @("./pkg/...", "./cmd/...")

function Run-K8sUnitTests {

    Push-Location "$K8spath"
    for ( $index = 0; $index -lt $TEST_PACKAGES.count; $index++ ) {
        
        echo "Running unit tests for packages" $TEST_PACKAGES[$index]
        $junit_output_file=Join-Path -Path $LogsDirPath -ChildPath "${JUNIT_FILE_NAME}_${index}.xml"
        
        gotestsum.exe --junitfile $junit_output_file --packages $TEST_PACKAGES[$index]
    }
    Pop-Location

}

Prepare-LogsDir
Clone-K8s
Prepare-Vendor
Install-Tools
Run-K8sUnitTests
