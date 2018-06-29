# there are some issues with DNS name resolution, so we're going to bypass them.
# Redis will try to contact redis-master, so we'll insert that entry into the
# hosts file, if we can.
if (Test-Path C:\var\run\secrets\kubernetes.io\serviceaccount\namespace) {
    # we're running inside a kubernetes pod, and we have the namespace.
    Write-Host "We're running inside a kubernetes pod."

    $namespace = Get-Content C:\var\run\secrets\kubernetes.io\serviceaccount\namespace

    $redisMasterIps = Resolve-DnsName redis-master.$namespace`.svc.cluster.local
    $ip = $redisMasterIps[0].IPAddress
    Add-Content -Value "$ip redis-master" -Path C:\Windows\System32\drivers\etc\hosts
}

if (-not (Test-Path env:GET_HOSTS_FROM)) { $env:GET_HOSTS_FROM = 'dns' }

if ((Get-Childitem Env:GET_HOSTS_FROM) -eq "env") {
  if (Test-Path env:REDIS_MASTER_SERVICE_HOST) {
    C:\redis\redis-server.exe C:\redis\redis.windows.conf --slaveof $(Get-Childitem Env:REDIS_MASTER_SERVICE_HOST) 6379
  }
}
else{
    C:\redis\redis-server.exe C:\redis\redis.windows.conf --slaveof redis-master 6379
 }
