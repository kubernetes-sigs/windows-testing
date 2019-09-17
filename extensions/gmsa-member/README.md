# gMSA-Member Extension

This extension will join a worker node to the Active Directory Domain created by the gmsa-dc extension.  This should be used 
in conjunction with the gmsa-dc extension.

Add this extension to your regular Windows worker pool.

# Configuration

|Name               |Required|Acceptable Value     |
|-------------------|--------|---------------------|
|name               |yes     |gmsa-member          |
|version            |yes     |v1                   |
|rootURL            |optional|                     |

# Example

```
    ...
    "agentPoolProfiles": [
      {
        "name": "windowspool1",
        "count": 2
		...
		"extensions": [
          {
            "name": "gmsa-member",
			"singleOrAll": "all"
          }
        ]
      }
      },
	  {
        "name": "windowsgmsa",
		"count": 1
        "extensions": [
          {
            "name": "gmsa-dc"
          }
        ]
      }
    ],
    ...
    "extensionProfiles": [
      {
        "name": "gmsa-member",
        "version": "v1"
      }
    ]
    ...
```


# Supported Orchestrators

Kubernetes

# Troubleshoot

Extension execution output is logged to files found under the following directory on the target virtual machine.

```sh
C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension
```

The specified files are downloaded into the following directory on the target virtual machine.

```sh
C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension\1.*\Downloads\<n>
```
