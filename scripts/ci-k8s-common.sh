#!/bin/bash

SSH_OPTS="-o ServerAliveInterval=20 -o ServerAliveCountMax=3 -o ConnectTimeout=30 -o ConnectionAttempts=3 -o TCPKeepAlive=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_OPTS_LONG="-o ServerAliveInterval=10 -o ServerAliveCountMax=12 -o ConnectTimeout=30 -o TCPKeepAlive=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

function onError(){
    az group list | jq ' .[] | .name' | grep ${AZURE_RESOURCE_GROUP}
    if [ $? -eq 0 ]; then
        az group delete -n ${AZURE_RESOURCE_GROUP} --yes --no-wait
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
  	
        if [[ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]]; then
            echo "Logging in with federated token"
            # AZURE_CLIENT_ID has been overloaded with Azure Workload ID in the preset-azure-cred-wi.
            # This is done to avoid exporting Azure Workload ID as AZURE_CLIENT_ID in the test scenarios.
            az login --service-principal -u "${AZURE_CLIENT_ID}" -t "${AZURE_TENANT_ID}" --federated-token "$(cat "${AZURE_FEDERATED_TOKEN_FILE}")" > /dev/null

            # Use --auth-mode "login" in az storage commands to use RBAC permissions of login identity. This is a well known ENV variable the Azure cli
            export AZURE_STORAGE_AUTH_MODE="login"
        else
            echo "AZURE_FEDERATED_TOKEN_FILE environment variable must be set to path location of token file"
            exit 1
        fi
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

wait_for_vm_restart() {
    echo "Waiting for VM restart"
    # Waiting 30 seconds. SSH might respond while server is shutting down.
    sleep 30
    while [ ! $( ssh -i ${SSH_KEY_FILE} ${SSH_OPTS} azureuser@${VM_PUB_IP}  "hostname") ];
    do
        echo "Unable to connect to azurevm"
        sleep 5
    done
    echo "Connection reestablished. VM restarted succesfully."
}
