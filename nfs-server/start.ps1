Write-Host "Starting nfs-server"
Start-Process .\winnfsd.exe "C:\exports" 
sleep 3600