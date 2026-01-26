# Quick Reference: CAPZ Mutating Webhook Helm Chart

## Chart Name
`capz-mutating-webhook`

## Purpose
Generic Helm chart that can deploy **both** HPC and Hyper-V mutating webhooks using different values files.

## Configuration

Edit `REGISTRY` and `VERSION` in the Makefile, or override on command line:

```bash
# Edit Makefile defaults
REGISTRY ?= ghcr.io/kubernetes-sigs/windows-testing
VERSION ?= 1.0

# Or override on command line
make docker-build-all REGISTRY=myregistry.io VERSION=2.0
```

## Quick Commands

```bash
# Show current config
make config

# Build and push
make docker-build-all
make docker-push-all

# Deploy
make helm-install-hyperv
make helm-install-hpc

# Upgrade
make helm-upgrade-hyperv
make helm-upgrade-hpc

# Preview templates (dry-run)
make helm-template-hyperv
make helm-template-hpc
```

### Full Workflow

```bash
# 1. Verify config
make config

# 2. Build and push
make docker-build-all
make docker-push-all

# 3. Install cert-manager (required once per cluster)
make helm-install-cert-manager

# 4. Deploy webhook
make helm-install-hyperv
```

## Testing

### Dry Run
```bash
# Test Hyper-V
helm install test-hyperv ./helm \
  -f values-hyperv.yaml \
  --dry-run --debug

# Test HPC
helm install test-hpc ./helm \
  -f values-hpc.yaml \
  --dry-run --debug
```

## Key Differences Between Webhook Types

| Feature | Hyper-V | HPC |
|---------|---------|-----|
| Image | `ghcr.io/kubernetes-sigs/windows-testing/hyperv-webhook:latest` | `ghcr.io/kubernetes-sigs/windows-testing/hpc-webhook:latest` |
| Namespace | `hyperv-webhook` | `hpc-webhook` |
| RuntimeClass | Yes (`runhcs-wcow-hypervisor`) | No |
| Object Selector | `hyperv-isolation: "true"` (opt-in) | None (applies to all pods) |

## Directory Structure
```
helpers/
├── Makefile                      # Build and deploy targets (REGISTRY/VERSION defined here)
└── helm/
    ├── Chart.yaml                # Chart metadata
    ├── values.yaml               # Default values
    ├── values-hyperv.yaml        # Hyper-V specific values
    ├── values-hpc.yaml           # HPC specific values
    ├── README.md                 # This documentation
    ├── .helmignore               # Files to exclude
    └── templates/
        ├── _helpers.tpl          # Template helpers with dynamic naming
        ├── namespace.yaml        # Namespace resource
        ├── serviceaccount.yaml   # ServiceAccount
        ├── rbac.yaml             # ClusterRole & ClusterRoleBinding
        ├── deployment.yaml       # Webhook deployment
        ├── service.yaml          # Webhook service
        ├── poddisruptionbudget.yaml  # PodDisruptionBudget
        ├── certificate.yaml      # Certificate/Issuer (cert-manager)
        ├── mutatingwebhookconfiguration.yaml  # Webhook configuration
        └── runtimeclass.yaml     # RuntimeClass (Hyper-V only)
```

## Configuration

The chart is configured via the `webhookType` value which determines:
- Image repository (defaults to `ghcr.io/kubernetes-sigs/windows-testing/{webhookType}-webhook`)
- Namespace name (defaults to `{webhookType}-webhook`)
- Certificate issuer name (defaults to `{webhookType}-webhook-selfsigned-issuer`)
- Webhook behavior and configuration

### Key Configuration Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `webhookType` | Type of webhook: `hyperv` or `hpc` | `""` (required) |
| `namespace.name` | Namespace to deploy into | `{webhookType}-webhook` |
| `namespace.create` | Create the namespace | `true` |
| `deployment.replicaCount` | Number of webhook replicas | `1` |
| `deployment.image.registry` | Image registry | `ghcr.io/kubernetes-sigs/windows-testing` |
| `deployment.image.repository` | Full image repository (overrides registry) | `""` (auto-generated) |
| `deployment.image.tag` | Image tag | `"1.0"` (Chart appVersion) |
| `deployment.image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `deployment.service.port` | Service port | `443` |
| `deployment.service.targetPort` | Container target port | `8443` |
| `deployment.nodeSelector` | Node selector for webhook pod | `kubernetes.io/os: linux` |
| `certificate.useCertManager` | Use cert-manager for certificates | `true` |
| `webhookConfiguration.timeoutSeconds` | Webhook call timeout | `10` |
| `webhookConfiguration.failurePolicy` | Failure policy | `Fail` |
| `webhookConfiguration.objectSelector` | Label selector for pods to mutate | `{}` |
| `runtimeClass.enabled` | Create RuntimeClass (Hyper-V only) | `true` |

## Upgrading

### Hyper-V Webhook
```bash
helm upgrade hyperv-webhook ./helm \
  -f values-hyperv.yaml
```

### HPC Webhook
```bash
helm upgrade hpc-webhook ./helm \
  -f values-hpc.yaml
```

## Uninstalling

```bash
# Remove Hyper-V webhook
helm uninstall hyperv-webhook -n hyperv-webhook

# Remove HPC webhook
helm uninstall hpc-webhook -n hpc-webhook
```
