#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

log() {
	local msg=$1
	echo "$(date -R): $msg"
}

wait_for_agent_nodes() {
	# upstream test requires at least two agent nodes
	log "wait for agent nodes"
	while [[ $(${KUBECTL} get nodes --selector=node-role.kubernetes.io/agent -ojson | jq '.items | length') -lt "2" ]]; do
		sleep 10
	done
}

wait_for_coredns_pods() {
	log "wait for core dns"
	while true; do
		# must wait for a pod specifically, if use other mechinisms there is a race condition
		# where no system pods are deployed then the taints are applied to the node
		# creating a situation where the nodes never become ready for the tests.
		# This will loop even if core-dns is created yet.
		COREDNS_READY=$(${KUBECTL} get pods -l k8s-app=kube-dns -n kube-system -o custom-columns=STATUS:status.containerStatuses[0].ready --no-headers)
		if [ "${COREDNS_READY}" = "true" ]; then
			log "coredns is ready"
			break
		fi
		sleep 2
	done
	${KUBECTL} get pods --all-namespaces
}

wait_for_kube_system_pods() {
	# now that the pods are there we can wait for all system pods
	log "wait for system pods"
	${KUBECTL} wait --for=condition=ready pod --all -n kube-system
	log "All kube-system pods are ready"
	${KUBECTL} get pods --all-namespaces
}

# require exports for timeout which spawns new sub shell
export KUBECONFIG="$(find /home/*/.kube/config)"
export KUBECTL="kubectl --kubeconfig=${KUBECONFIG}"
export -f wait_for_agent_nodes
export -f wait_for_coredns_pods
export -f wait_for_kube_system_pods
export -f log

log "start master extension"
# 10m is a long time to wait but other system pods should be online shortly after
# track the time so we can have visibility into timing and possibly lower eventually
time timeout 1800 bash -c wait_for_agent_nodes

# due to bug in provisioning in aks-engine that has become more frequent recently
# we add some debugging as well as restart the kube-addon manager so that it doesn't 
# get stuck in a bad loop looking for "/etc/kubernetes/addons/init"
# A restart when it is running sucessfully doesn't trigger any changes to 
# already running pods managed by the addon manager
#
# See https://github.com/Azure/aks-engine/issues/4753 for more details
${KUBECTL} get pods -A
${KUBECTL} delete pod -n kube-system -l app=kube-addon-manager

time timeout 500 bash -c wait_for_coredns_pods
time timeout 500 bash -c wait_for_kube_system_pods

master_node=$(${KUBECTL} get nodes | grep master | awk '{print $1}')

${KUBECTL} taint nodes "$master_node" node-role.kubernetes.io/master=:NoSchedule || true
${KUBECTL} label nodes "$master_node" node-role.kubernetes.io/master=NoSchedule || true

# For k8s versions 1.17 1.18 pre-pull because tests images with windowsservercore as base image have a pull time in range of 10+ mins
# For 1.19+ the images are nanoserver and have much smaller pull times
# View image by version: https://github.com/kubernetes/kubernetes/blob/master/test/utils/image/manifest.go#L203
currentMinorVersion=$(kubectl version -o json | jq -r .serverVersion.minor)
currentMinorVersion=$(echo  ${currentMinorVersion//+}) #drop the + if there on builds from branches
prepullVersions=("17 18")
log "current server minor version: $currentMinorVersion"
log "prepullVersions: ${prepullVersions}"
if [[ " ${prepullVersions[@]} " =~ " ${currentMinorVersion} " ]]; then
	log "running pre-pull"
	prepullFile="https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/gce/prepull-1.${currentMinorVersion}.yaml"
	log "prepull file: $prepullFile"
	${KUBECTL} create -f "$prepullFile" || true

	log "wait 15m time period to let large images be pulled onto nodes"
	sleep 15m
	${KUBECTL} get pods -A -o wide
	${KUBECTL} get ds -A -o wide
	${KUBECTL} describe ds
	${KUBECTL} delete -f "$prepullFile"

	log "wait 3m period for pods to be removed"
	sleep 3m
fi

# Check the status of all the pods.
${KUBECTL} get pods -A -o wide
${KUBECTL} describe nodes
log "finish master extension"
