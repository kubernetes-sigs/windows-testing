# disable Windows Defender on Windows nodes - workaround for #75148
Set-MpPreference -DisableRealtimeMonitoring $true

[System.Environment]::SetEnvironmentVariable('DOCKER_API_VERSION', "1.39", [System.EnvironmentVariableTarget]::Machine)
