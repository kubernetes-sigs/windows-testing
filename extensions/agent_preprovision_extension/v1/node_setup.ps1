# Script file to create tmp directory in windows nodes

Write-Host "Prepulling all test images"

Start-BitsTransfer https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/Utils.ps1
Start-BitsTransfer https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/PullImages.ps1

./PullImages.ps1

[System.Environment]::SetEnvironmentVariable('DOCKER_API_VERSION', "1.39", [System.EnvironmentVariableTarget]::Machine)