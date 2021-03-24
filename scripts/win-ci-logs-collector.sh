#!/bin/bash
# Copyright 2020 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


if [ "$#" -ne 3 ]; then
    echo "Unexpected number of parameters $#."
    echo "Usage: win-ci-logs-collector.sh masterIp sshPrivateKeyPath aksEngineOutputPath"
    exit 1
fi

MASTER_IP=${1}
TEMP_AKS_PATH=${2}
SSH_KEY=${3}
USER="azureuser"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Check for ssh key in path
if [ -z "$SSH_KEY" ]
then
    echo "ssh key not found. Defaulting to .ssh/id_rsa."
    SSH_KEY="${HOME}/.ssh/id_rsa"
fi

if [ ! -f "$SSH_KEY" ]
then
    echo "ssh key file ${SSH_KEY} does not exist. Exiting."
    exit
fi

function redact_sensitive_content {

    # Some of the log files gathered may contain sensitive information in the form of UUIDs.
    # Since logging is public, we redact all sensitive info.
    # If for some reason redacting fails, we exclude that log file from collection process.
    file=$1
    regex="[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

    if ! $(sed -i -E "s/${regex}/REDACTED/gI" $file); then
        echo "Redacting failed. Log file %s will be excluded from log."
        rm $file
    fi
}

# Collect master provisioning logs
master_logs_output="${ARTIFACTS}/master_provisioning"
readonly master_provisioning_logs=(
    "/tmp/master_extension.log"
    "/var/log/azure/win-e2e-master-extension.log"
    "/var/log/azure/update-coredns.log"
    "/var/log/azure/cluster-provision.log"
    "/var/log/azure/configure-hyperv-webhook.log"
    "/var/log/azure/custom-script/handler.log"
)

mkdir -p "${master_logs_output}"

for log_file in "${master_provisioning_logs[@]}"; do
    destination="${master_logs_output}/$(basename -- ${log_file})"
    scp ${SSH_OPTS} -i ${SSH_KEY} ${USER}@${MASTER_IP}:${log_file} ${destination}
    if [ ! $? -eq 0 ]
    then
         echo "Unable to collect log file ${log_file} from master. Skipping."
         continue
    fi
    redact_sensitive_content ${destination}
done

echo "Finished collecting master provisioning logs."

echo "Get Windows nodes."
# We cannot rely on kubernetes to give us the hostnames of the Windows nodes in the deployment
# as the provisioning scripts for the Windows nodes may have failed to set up kubelet.
# It is safer to get the Windows nodes hostnames by searching the azuredeploy.json template

azuredeploy_path="${TEMP_AKS_PATH}/azuredeploy.json"

vmname_prefixes=$(grep "windows.*VMNamePrefix\":" ${azuredeploy_path} | awk '{ print $2 }' | tr -d ",\"")
SAVEIFS=$IFS
IFS=$'\n'
vmname_prefixes=($vmname_prefixes)
IFS=$SAVEIFS

readonly provisioning_logs=(
    "c:/AzureData/CustomDataSetupScript.log"
)


function collect_windows_vm_logs {
    win_hostname=${1}
    win_logs_location="${ARTIFACTS}/${win_hostname}"
    win_logs_collector_script_path="c:\\k\\Debug\\collect-windows-logs.ps1"
    win_logs_collector_script_url="https://raw.githubusercontent.com/Azure/aks-engine/master/scripts/collect-windows-logs.ps1"

    echo "Testing connection to host ${win_hostname}."
    if ! $(ssh ${SSH_OPTS} -J ${USER}@${MASTER_IP} ${USER}@${win_hostname} "exit"); then
        return
    fi

    mkdir -p ${win_logs_location}

    #Collecting provisioning logs
    for log_file in "${provisioning_logs[@]}"; do
        scp -T ${SSH_OPTS} -o "ProxyJump ${USER}@${MASTER_IP}" ${USER}@${win_hostname}:"c:\\${log_file}" "${win_logs_location}/$(basename -- ${log_file})"
        if [ ! $? -eq 0 ]
        then
            echo "Unable to collect log file ${log_file} from Windows Node ${win_hostname}. Skipping."
        fi
    done

    #Collecting k8s logs
    echo "Checking if logs collector script is already present on Windows machine."
    if $(ssh ${SSH_OPTS} -J ${USER}@${MASTER_IP} ${USER}@${win_hostname} "powershell.exe -c Test-Path ${win_logs_collector_script_path}" | grep -q "False")
    then
        echo "Downloading log collector script to Windows machine ${win_hostname}."
        if $(ssh ${SSH_OPTS} -J ${USER}@${MASTER_IP} ${USER}@${win_hostname} "powershell.exe -c \"curl.exe --retry 5 --retry-delay 0 -L ${win_logs_collector_script_url} -o ${win_logs_collector_script_path} \""); then
            echo "Unable to download logs_collector_script to machine ${win_hostname}"
            return 1
        fi
    fi

    echo "Invoke logs_collector_script on Windows node ${win_hostname}"
    $(ssh ${SSH_OPTS} -J ${USER}@${MASTER_IP} ${USER}@${win_hostname} "powershell.exe -c \"${win_logs_collector_script_path}\"")

    echo "Copying logs from Windows node ${win_hostname}"
    scp -T ${SSH_OPTS} -o "ProxyJump ${USER}@${MASTER_IP}" ${USER}@${win_hostname}:"c:\\Users\\${USER}\\*.zip" "${win_logs_location}/debug.zip"
    if [ ! $? -eq 0 ]
    then
        echo "Unable to collect log files from Windows Node ${win_hostname}. Skipping."
    fi

}

function collect_agentpool_logs() {
    agentpool_prefix=${1}
    # TODO (adelina-t): We should actually call this script with the exact number of vms per agent pool.
    # Until we fix this, we can safely assume a maximum of 3 vms per agent pool.
    for i in $(seq 0 2)
    do
        echo "Collecting logs for vm ${agentpool_prefix}${i}"
        collect_windows_vm_logs "${agentpool_prefix}${i}"
    done
}

# In order to ProxyJump from master to Windows nodes we need to forward authentication.
# ssh-agent must be running on the environment running this script and the propper
# ssh keys must be added.


if [ ! -x $(command -v ssh-agent) ] ; then
    echo "In order to ProxyJump for collecting Windows logs, ssh-agent is requred. Cannot find ssh-agent. Exiting."
fi

if [ -z ${SSH_AUTH_SOCK} ]; then
    eval `ssh-agent -s`
fi

if ! $(ssh-add $SSH_KEY); then
    echo "Unable to add SSH_KEY to ssh-agent. Exiting."
    exit
fi

echo "Prepare ssh config for proxyjump."

echo "Host ${MASTER_IP}" > /root/.ssh/config
echo "  StrictHostKeyChecking=no" >> /root/.ssh/config
echo "  UserKnownHostsFile=/dev/null" >> /root/.ssh/config



for agentpool in "${vmname_prefixes[@]}"
do
    collect_agentpool_logs ${agentpool}
done
