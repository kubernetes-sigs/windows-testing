# there are some issues with DNS name resolution, so we're going to bypass them.
# guestbook will try to contact redis-master and redis-slave, so we'll insert
# those entries into the hosts file, if we can.
if (Test-Path C:\var\run\secrets\kubernetes.io\serviceaccount\namespace) {
    # we're running inside a kubernetes pod, and we have the namespace.
    Write-Host "We're running inside a kubernetes pod."

    $namespace = Get-Content C:\var\run\secrets\kubernetes.io\serviceaccount\namespace

    $redisMasterIps = Resolve-DnsName redis-master.$namespace`.svc.cluster.local
    $ip = $redisMasterIps[0].IPAddress
    Add-Content -Value "$ip redis-master" -Path C:\Windows\System32\drivers\etc\hosts

    $redisSlaveIps = Resolve-DnsName redis-slave.$namespace`.svc.cluster.local
    $ip = $redisSlaveIps[0].IPAddress
    Add-Content -Value "$ip redis-slave" -Path C:\Windows\System32\drivers\etc\hosts
}

Stop-Process -Name httpd -Force
c:/Users/ContainerAdministrator/AppData/Roaming/Apache24/bin/httpd.exe
