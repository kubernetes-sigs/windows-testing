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
