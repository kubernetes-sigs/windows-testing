# Hyper-v-mutating-webhook

A mutating admission webhook is currently required in order to run Kubernetes e2e tests against Windows nodes utalizing Hyper-V isolated containers due to (more info captured in [Issue #94017](https://github.com/kubernetes/kubernetes/issues/94017))

This webhook does updates incoming Pod specs where `nodeSelector` is set to `"kubernetes.io/os" : windows` by

- setting `pod.Spec.RuntimeClassName = 'windows-2004'
- appending `-windows-amd64-2004` to `pod.Spec.Conainers[].Image` fields


## Installation

The following steps should be performed prior to running the e2e tests.

These steps assume the Windows nodes in the cluster have been provisioned to use containerd and containerd's config defines a runtime class handler named `runhcs-wcow-hypervisor-19041`. More information on runtime classes and how to configure them can be found at (https://kubernetes.io/docs/concepts/containers/runtime-class/).

1. Taint Windows each Windows node to insure cert-manager and the admission webhook pods land on linux nodes.

    ```bash
    kubectl taint node {node name} os=windows:NoSchedule
    ```

1. Install runtime classes.

    ```bash
    kubectl apply -f <link>
    ```

1. Install cert-manager.

    ```bash
    kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.15.2/cert-manager.yaml
    ```

1. Install admission controller.

    ```bash
    kubectl apply -f <link>
    ```

Run e2e tests.
