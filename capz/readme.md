# Upstream kubernetes e2e testing with CAPZ for Windows

These scripts and templates are used with [cluster-api-provider-azure](https://github.com/kubernetes-sigs/cluster-api-provider-azure) and [azure cli extension](https://github.com/Azure/azure-capi-cli-extension).  

## Running the scripts

To run these scripts locally, clone [CAPZ](https://github.com/kubernetes-sigs/cluster-api-provider-azure) and set the following environment variables (use Linux, macos, or WSL2):

```bash
export AZURE_SUBSCRIPTION_ID=<sub-id>
export AZURE_CLIENT_ID=<client-id>
export AZURE_CLIENT_SECRET=<client-secret>
export AZURE_TENANT_ID=<tenantid>
export CAPZ_DIR="$HOME/<path-to-capz>/cluster-api-provider-azure

# optional for ability to use your own ssh key (otherwise it generates one)
# NOTE: Azure does not support ed25519 encrypted SSH keys!
export AZURE_SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_rsa.pub"
```

## Other configuration

| ENV variable  | Description  |
| ------------- | ------------ |
| `SKIP_CREATE` | Don't create a cluster.  Must set `CLUSTER_NAME` and have current a workload cluster kubeconfig file with name `./"${CLUSTER_NAME}".kubeconfig` |
| `SKIP_TEST`  | Only creates the cluster, will not run tests |
| `SKIP_CLEANUP` | Don't delete the cluster / resource group deletion |
| `RUN_SERIAL_TESTS` | If set to `true` then serial slow tests will be run with default ginkgo settings |
| `KUBERNETES_VERSION`  | Valid values are `latest` (default) and  `latest-1.x` where x is valid kubernetes minor version such as `latest-1.24` |
| `AZURE_LOCATION` | The azure region to deploy resources into |
| `WINDOWS_KPNG` | If specified, will create a cluster using an out-of-tree kube-proxy implementation from [k-sigs/windows-service-proxy](https://github.com/kubernetes-sigs/windows-service-proxy) |

## GMSA support

Set the environment variable `GMSA=true`.

This requires additional set up in the Azure Subscriptions. See the readme in [gmsa folder](gmsa/readme.md).

## Hyper-V isolated containers support

Requires containerd v1.7+ deployed to the Windows nodes.

Set the environment variable `HYPERV=true`.

See [the HyperV testing README](../helpers/hyper-v-mutating-webhook/README.md) for more information.

