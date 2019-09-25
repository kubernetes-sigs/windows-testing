# gMSA-coredns Extension

This extension will modify the local coredns config to allow resources to locate the Active Directory domain and members created by 
the gmsa-dc and gmsa-member extensions.

This extension will need to be run against the master.

# Configuration

|Name               |Required|Acceptable Value     |
|-------------------|--------|---------------------|
|name               |yes     |gmsa-coredns         |
|version            |yes     |v1                   |
|rootURL            |optional|                     |

# Example

```
    ...
    "masterProfile": {
      "count": 1,
      "dnsPrefix": "",
      "vmSize": "Standard_D2_v3",
      "distro": "ubuntu",
      "extensions": [
          {
              "name": "master_extension"
          },
          {
              "name": "gmsa-coredns"
          }
      ]
    },
    ...
    "extensionProfiles": [
        {
          "name":                "gmsa-coredns",
          "version":             "v1",
          "extensionParameters": "parameters",
          "rootURL":             "https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/",
          "script":              "update-coredns.sh"
        }
    ]
    ...
```


# Supported Orchestrators

Kubernetes

# Troubleshoot

Extension execution output is logged to files found under the following directory on the target virtual machine.

```
/var/log/azure/update-coredns.log
```
