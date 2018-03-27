if (-not (Test-Path env:GET_HOSTS_FROM)) { $env:GET_HOSTS_FROM = 'dns' }
if (Get-Childitem Env:GET_HOSTS_FROM) -eq "env") {
  if (Test-Path env:REDIS_MASTER_SERVICE_HOST) {
  & "C:\redis\redis-server.exe" --slaveof $(Get-Childitem Env:REDIS_MASTER_SERVICE_HOST) 6379
  }
}
else{
 & "C:\redis\redis-server.exe" --slaveof redis-master 6379
 }
