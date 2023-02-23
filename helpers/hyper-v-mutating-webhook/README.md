# Hyper-v-mutating-webhook

A mutating admission webhook is currently required in order to run Kubernetes e2e tests against Windows nodes utilizing Hyper-V isolated containers due to (more info captured in an old [Issue #94017](https://github.com/kubernetes/kubernetes/issues/94017))

This webhook updates incoming Pod specs by setting `pod.Spec.RuntimeClassName = runhcs-wcow-hypervisor` which is a runtime class provided by containerd on Windows by default starting with v1.7.

## Installation

The following steps should be performed prior to running the e2e tests.

1. Untaint any Linux nodes in the cluster so cert-manager and admission webhook pods can run on them.

    ```bash
    kubectl taint nodes {node name} node-role.kubernetes.io/control-plane:NoSchedule-
    ```

1. Taint Windows each Windows node to insure cert-manager and the admission webhook pods land on linux nodes.

    ```bash
    kubectl taint node {node name} os=windows:NoSchedule
    ```

1. Install runtime classes.

    ```bash
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/helpers/hyper-v-mutating-webhook/hyperv-runtimeclass.yaml
    ```

1. Install cert-manager.

    ```bash
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
    ```

1. Install admission controller.

    ```bash
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/helpers/hyper-v-mutating-webhook/deployment.yaml
    ```

1. Untaint the Windows nodes

    ```bash
    kubectl taint node {node name} os=windows:NoSchedule-
    ```

1. Taint the Linux nodes

    ```bash
    kubectl taint nodes {node name} node-role.kubernetes.io/control-plane:NoSchedule
    ```

Run e2e tests.
