These scripts and templates are used with https://github.com/kubernetes-sigs/cluster-api-provider-azure and https://github.com/Azure/azure-capi-cli-extension.  

## Running the scripts
To run these scripts locally, clone https://github.com/kubernetes-sigs/cluster-api-provider-azure and set the following environment variables (use Linux, macos, or WSL2):

```
export AZURE_SUBSCRIPTION_ID=<sub-id>
export AZURE_CLIENT_ID=<client-id>
export AZURE_CLIENT_SECRET=<client-secret>
export AZURE_TENANT_ID=<tenantid>
export CAPZ_DIR="$HOME/<path-to-capz>/cluster-api-provider-azure

# optional for ability to use your own ssh key (otherwise it generates one)
export AZURE_SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_rsa.pub"
```

## Other configuration

| ENV variable  | Description  |
| ------------- | ------------ |
| `SKIP_CREATE` | Don't create a cluster.  Must set `CLUSTER_NAME` and have current a workload cluster kubeconfig file with name `./"${CLUSTER_NAME}".kubeconfig` |
| `SKIP_TEST`  | Only creates the cluster, will not run tests |
| `KUBERNETES_VERSION`  | valid values are `latest` (default) and  `latest-1.x` where x is valid kubernetes minor version such as `latest-1.24` |
