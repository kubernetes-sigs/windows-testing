# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Function Get-DnsName {
    Param (
      [Parameter(Mandatory=$true)] [String]$DnsName
    )

    # NOTE(claudiub): if there are some initial network connectivity issues,
    # we'll retry to get resolve the DNS name.
    for ($i = 0; $i -le 100; $i++) {
        $dnsEntries = Resolve-DnsName $DnsName
        if ($?) {
            return $dnsEntries
        }

        # sleep between retries.
        Start-Sleep -Milliseconds 500
    }
    return $null
}

# there are some issues with DNS name resolution, so we're going to bypass them.
# Redis will try to contact redis-master, so we'll insert that entry into the
# hosts file, if we can.
if (Test-Path C:\var\run\secrets\kubernetes.io\serviceaccount\namespace) {
    # we're running inside a kubernetes pod, and we have the namespace.
    Write-Host "We're running inside a kubernetes pod."

    $namespace = Get-Content C:\var\run\secrets\kubernetes.io\serviceaccount\namespace

    $redisMasterIps = Get-DnsName redis-master.$namespace`.svc.cluster.local
    if (!$redisMasterIps) {
        echo "Could not resolve the redis-master DNS name."
        exit 1
    }

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
