#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

SSH_OPTS="-o ServerAliveInterval=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
PROW_BUILD_ID="${BUILD_ID:-000000000000}"
AZURE_RESOURCE_GROUP="win-unit-test-${PROW_BUILD_ID}"
AZURE_DEFAULT_IMG="MicrosoftWindowsServer:WindowsServer:2022-datacenter-smalldisk-g2:latest"
AZURE_IMG="${WIN_VM_IMG:-$AZURE_DEFAULT_IMG}"
VM_NAME="winTestVM"
VM_LOCATION="${VM_LOCATION:-westus2}"
VM_SIZE="${VM_SIZE:-Standard_D2s_v3}"
ARTIFACTS="${ARTIFACTS:-/var/log/artifacts}"
SKIP_FAILING_TESTS="${SKIP_FAILING_TESTS:-true}"

# Depending on the job, we may have run only a subset of unit tests.
# If not given, we'll run all of them.
TEST_PACKAGES="${TEST_PACKAGES:-}"

SCRIPT_PATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_ROOT=$(dirname "${SCRIPT_PATH}")
source ${SCRIPT_ROOT}/ci-k8s-common.sh

trap onError ERR 

ensure_azure_cli
build_resource_group
build_test_vm
generate_ssh_key
enable_ssh_windows
test_ssh_connection
echo "Test VM created. SSH connection working"
copy_to ./scripts/prepare_env_windows.ps1 '/prepare_env_windows.ps1' ${VM_PUB_IP}
copy_to ./scripts/k8s_unit_windows.ps1 '/k8s_unit_windows.ps1' ${VM_PUB_IP}
run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} 'c:/prepare_env_windows.ps1'

echo "Install container features in VM"
run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} "powershell.exe -command { Install-WindowsFeature -Name 'Containers' -Restart }"
wait_for_vm_restart

# Skip failing tests by default
# Note it must be set to False (not false) for powershell to honor it
skip_arg="-SkipFailingTests"
if [ "${SKIP_FAILING_TESTS,,}" = "false" ]; then
    skip_arg="-SkipFailingTests:False"
fi

set +e  # Temporarily disable errexit
trap - ERR   # Temporarily disable the ERR trap
# if repo name is windows-testing, the intention is to test updates to the scripts
# as if they were running as a periodic job against kubernetes/kubernete.
if [ "${JOB_TYPE}" == "presubmit" ] && [ "${REPO_NAME}" != "windows-testing" ]
then
    echo "Running a presubmit job"
    # Include the -testPackages argument only if we have $TEST_PACKAGES to test.
    test_packages_arg=""
    if [[ -n "${TEST_PACKAGES}" ]]; then
        test_packages_arg="-testPackages ${TEST_PACKAGES}"
    fi

    run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} "c:/k8s_unit_windows.ps1 ${skip_arg} -repoName ${REPO_NAME} -repoOrg ${REPO_OWNER} -pullRequestNo ${PULL_NUMBER} -pullBaseRef ${PULL_BASE_REF} ${test_packages_arg}"
    exit_code=$?
else
    echo "Running periodic job"
    run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} "c:/k8s_unit_windows.ps1 ${skip_arg}"
    exit_code=$?
fi
set -e  # Re-enable errexit
trap onError ERR  # Re-enable the ERR trap

copy_from 'c:/Logs/*.xml' ${ARTIFACTS} ${VM_PUB_IP}
destroy_resource_group

exit $exit_code
