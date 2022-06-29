#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

LOCAL_DIR=${BASH_SOURCE[0]}
SSH_OPTS="-o ServerAliveInterval=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
PROW_BUILD_ID="${BUILD_ID:-000000000000}"
AZURE_RESOURCE_GROUP="win-unit-test-${PROW_BUILD_ID}"
AZURE_DEFAULT_IMG="MicrosoftWindowsServer:WindowsServer:2022-datacenter-smalldisk-g2:20348.524.220201"
AZURE_IMG="${WIN_VM_IMG:-$AZURE_DEFAULT_IMG}"
VM_NAME="winTestVM"
VM_LOCATION="${VM_LOCATION:-westus2}"
VM_SIZE="${VM_SIZE:-Standard_D2s_v3}"
ARTIFACTS="${ARTIFACTS:-/var/log/artifacts}"


function onError(){
    az group list | jq ' .[] | .name' | grep ${AZURE_RESOURCE_GROUP}
    if [ $? -ne 0 ]; then
        az group delete -n ${AZURE_RESOURCE_GROUP} --yes --no-wait
    fi
}

trap onError ERR 

parse_cred() {
    grep -E -o "\b$1[[:blank:]]*=[[:blank:]]*\"[^[:space:]\"]+\"" | cut -d '"' -f 2
}

ensure_azure_envs() {

# for Prow we use the provided AZURE_CREDENTIALS file.
# the file is expected to be in toml format.
    if [[ -n "${AZURE_CREDENTIALS:-}" ]]; then
        AZURE_SUBSCRIPTION_ID="$(parse_cred SubscriptionID < "${AZURE_CREDENTIALS}")"
        AZURE_TENANT_ID="$(parse_cred TenantID < "${AZURE_CREDENTIALS}")"
        AZURE_CLIENT_ID="$(parse_cred ClientID < "${AZURE_CREDENTIALS}")"
        AZURE_CLIENT_SECRET="$(parse_cred ClientSecret < "${AZURE_CREDENTIALS}")"
        AZURE_MULTI_TENANCY_ID="$(parse_cred MultiTenancyClientID < "${AZURE_CREDENTIALS}")"
        AZURE_MULTI_TENANCY_SECRET="$(parse_cred MultiTenancyClientSecret < "${AZURE_CREDENTIALS}")"
        AZURE_STORAGE_ACCOUNT="$(parse_cred StorageAccountName < "${AZURE_CREDENTIALS}")"
        AZURE_STORAGE_KEY="$(parse_cred StorageAccountKey < "${AZURE_CREDENTIALS}")"
    fi
} 

ensure_azure_cli() {
    if [[ -z "$(command -v az)" ]]; then
  	echo "installing Azure CLI"
  	apt-get update && apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
  	curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
  	AZ_REPO=$(lsb_release -cs)
  	echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${AZ_REPO} main" | tee /etc/apt/sources.list.d/azure-cli.list
  	apt-get update && apt-get install -y azure-cli
  	az login --service-principal -u "${AZURE_CLIENT_ID}" -p "${AZURE_CLIENT_SECRET}" --tenant "${AZURE_TENANT_ID}" > /dev/null
    fi
}


build_resource_group() {
	az group create -n ${AZURE_RESOURCE_GROUP} -l ${VM_LOCATION} --tags creationTimestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ') 
}

destroy_resource_group() {
	echo "Destroying resource group ${AZURE_RESOURCE_GROUP}"
	az group delete -n ${AZURE_RESOURCE_GROUP} --yes
}

build_test_vm() {

    echo "Building test vm"
	DETAILS=$(az vm create -n ${VM_NAME} -g ${AZURE_RESOURCE_GROUP} --admin-username=azureuser --admin-password=Passw0rdAdmin --image=${AZURE_IMG} --nsg-rule SSH --size ${VM_SIZE} --public-ip-sku Standard -o json)
        PUB_IP=$(echo $DETAILS | jq -r .publicIpAddress)
        if [ "$PUB_IP" == "null" ]
        then
           RETRY=0
           while [ "$PUB_IP" == "null" ] || [ $RETRY -le 5 ]
           do
              sleep 5
              PUB_IP=$(az vm show -d -g ${AZURE_RESOURCE_GROUP} -n ${VM_NAME} -o json --query publicIps | jq -r)
              RETRY=$(( $RETRY + 1 ))
           done
        fi

        if [ "$PUB_IP" == "null" ]
        then
            echo "failed to fetch public IP"
            exit 1
        fi
        VM_PUB_IP=$PUB_IP
}

generate_ssh_key() {
    echo "Generate ssh keys"
    # Generate SSH key.
    AZURE_SSH_PUBLIC_KEY_FILE=${AZURE_SSH_PUBLIC_KEY_FILE:-""}
    if [ -z "${AZURE_SSH_PUBLIC_KEY_FILE}" ]; then
        echo "generating sshkey for unittests"
        SSH_KEY_FILE=.sshkey
        rm -f "${SSH_KEY_FILE}" 2>/dev/null
        ssh-keygen -t rsa -b 2048 -f "${SSH_KEY_FILE}" -N '' 1>/dev/null
        AZURE_SSH_PUBLIC_KEY_FILE="${SSH_KEY_FILE}.pub"
    fi
    AZURE_SSH_PUBLIC_KEY_B64=$(base64 "${AZURE_SSH_PUBLIC_KEY_FILE}" | tr -d '\r\n')
    export AZURE_SSH_PUBLIC_KEY_B64
    AZURE_SSH_PUBLIC_KEY=$(tr -d '\r\n' < "${AZURE_SSH_PUBLIC_KEY_FILE}")
}

copy_from() {
    
    if [ -z $1 ]
    then
        echo "must set remtoe path for scp"
        return 1
    fi
    local REMOTE_PATH=$1
    if [ -z $2 ]
    then
        echo "must set local path for scp"
        return 1
    fi
    local LOCAL_PATH=$2
    if [ -z $3 ]
    then
        echo "must set remote vm ip for scp"
        return 1
    fi
    local SSH_HOST=$3

    echo "Copying $REMOTE_PATH from $SSH_HOST:$REMOTE_PATH to ${LOCAL_PATH}"
    scp -i ${SSH_KEY_FILE} ${SSH_OPTS} azureuser@${SSH_HOST}:${REMOTE_PATH} ${LOCAL_PATH}
}

copy_to() {
    
    if [ -z $1 ]
    then
        echo "must set local path for scp"
        return 1
    fi
    local LOCAL_PATH=$1
    if [ -z $2 ]
    then
        echo "must set remtoe path for scp"
        return 1
    fi
    local REMOTE_PATH=$2
    if [ -z $3 ]
    then
        echo "must set remote vm ip for scp"
        return 1
    fi
    local SSH_HOST=$3

    echo "Copying $LOCAL_PATH to $SSH_HOST:$REMOTE_PATH"
    scp -i ${SSH_KEY_FILE} ${SSH_OPTS} ${LOCAL_PATH} azureuser@${SSH_HOST}:${REMOTE_PATH}

}

run_remote_cmd() {
    local SSH_HOST=$1
    local SSH_KEY=$2
    local CMD=$3

    ssh -i ${SSH_KEY_FILE} ${SSH_OPTS} azureuser@${SSH_HOST} "${CMD}"

}

enable_ssh_windows() {
    echo "Enabling SSH for Windows VM"
    az vm run-command invoke  --command-id RunPowerShellScript -n ${VM_NAME} -g ${AZURE_RESOURCE_GROUP} --scripts "@$(pwd)/scripts/enable_ssh_windows.ps1" --parameters "SSHPublicKey=${AZURE_SSH_PUBLIC_KEY}"
}

test_ssh_connection() {
	echo "Testing ssh connection to Windows VM"
    SSH_KEY_FILE=.sshkey
	if ! ssh -i ${SSH_KEY_FILE} ${SSH_OPTS} azureuser@${VM_PUB_IP}  "hostname";
    then
        exit 1
    fi
    echo "Windows VM SSH connection OK"
}

ensure_azure_envs
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
run_remote_cmd ${VM_PUB_IP} ${SSH_KEY_FILE} 'c:/k8s_unit_windows.ps1'
copy_from 'c:/Logs/*.xml' ${ARTIFACTS} ${VM_PUB_IP}
destroy_resource_group
