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

echo "Checking for other nodes"
$IP = ""

if ($env:KUBERNETES_SERVICE_HOST) {
    $kubernetesServiceHost = $env:KUBERNETES_SERVICE_HOST
    $kubernetesServicePort = $env:KUBERNETES_SERVICE_PORT
    $podNamespace = $env:POD_NAMESPACE
    if (-not $podNamespace) {
        $podNamespace = "default"
    }

    $myHost = (Get-NetAdapter | Get-NetIPAddress -AddressFamily IPv4).IPAddress
    echo "My host: $myHost"

    $url = "https://$kubernetesServiceHost`:$kubernetesServicePort/api/v1/namespaces/$podNamespace/endpoints/rethinkdb-driver"
    echo "Endpont url: $url"

    echo "Looking for IPs..."
    $token = Get-Content /var/run/secrets/kubernetes.io/serviceaccount/token

    $json = curl.exe -s $url --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt --header "Authorization: Bearer $token" --insecure
    echo "Retrieved data: $json"

    $jsonObj = $json | ConvertFrom-Json
    $ips = jsonObj.subsets.addresses.ip
    echo "Found IPs: $ips"

    $IP = $ips | where { $_ -ne "$myHost" } | Select-Object -First 1
}

if ($IP) {
    $endpoint = "$IP`:29015"
    echo "Join to $endpoint"
    /rethinkdb/rethinkdb.exe --bind all  --join $endpoint
} else {
    echo "Start single instance"
    /rethinkdb/rethinkdb.exe --bind all
}
