#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

PROW_BUILD_ID="${BUILD_ID:-000000000000}"
AZURE_RESOURCE_GROUP="win-e2e-node-${PROW_BUILD_ID}"
AZURE_DEFAULT_IMG="MicrosoftWindowsServer:WindowsServer:2022-datacenter-core-smalldisk-g2:latest"
SSH_OPTS="-o ServerAliveInterval=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
AZURE_IMG="${WIN_VM_IMG:-$AZURE_DEFAULT_IMG}"
VM_NAME="winTestVM"
VM_LOCATION="${VM_LOCATION:-westus2}"
VM_SIZE="${VM_SIZE:-Standard_D2s_v3}"
ARTIFACTS="${ARTIFACTS:-/var/log/artifacts}"
CONTAINERD_VERSION="${CONTAINERD_VERSION:-1.7.16}"
export GINKGO_FOCUS="${GINKGO_FOCUS:-\[sig-windows\]|\[Feature:Windows\]}"

SCRIPT_PATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_ROOT=$(dirname "${SCRIPT_PATH}")
source ${SCRIPT_ROOT}/ci-k8s-common.sh

ensure_azure_cli
build_resource_group
build_test_vm
generate_ssh_key
enable_ssh_windows
test_ssh_connection
echo "Test VM created. SSH connection working"

echo "Install container features in VM"
run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} "powershell.exe -command { Install-WindowsFeature -Name 'Containers' -Restart }"
wait_for_vm_restart

copy_to ./scripts/prepare_env_windows.ps1 '/prepare_env_windows.ps1' ${VM_PUB_IP}
copy_to ./scripts/prepare_e2e_node_windows.ps1 '/prepare_e2e_node_windows.ps1' ${VM_PUB_IP}
copy_to ./scripts/k8s_e2e_node_windows.ps1 '/k8s_e2e_node_windows.ps1' ${VM_PUB_IP}

run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} "c:/prepare_env_windows.ps1"
run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} "c:/prepare_e2e_node_windows.ps1 -ContainerdVersion ${CONTAINERD_VERSION}"

if [ "${JOB_TYPE}" == "presubmit" ]; then
    if [ "${REPO_NAME}" == "kubernetes" ]; then
        echo "Running a presubmit job against kubernetes/kubernetes"
        run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} "c:/k8s_e2e_node_windows.ps1 -repoName ${REPO_NAME} -repoOrg ${REPO_OWNER} \
            -pullRequestNo ${PULL_NUMBER} -pullBaseRef ${PULL_BASE_REF} ${test_packages_arg}"
    else
        echo "Dry-Running a presubmit job against ${REPO_NAME}"
        run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} "c:/k8s_e2e_node_windows.ps1 -dryRun true"
    fi
    exit_code=$?
else
    echo "Running periodic job"
    run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} "c:/k8s_e2e_node_windows.ps1"
    exit_code=$?
fi
copy_from 'c:/Logs/*.xml' ${ARTIFACTS} ${VM_PUB_IP}
destroy_resource_group
exit $exit_code
