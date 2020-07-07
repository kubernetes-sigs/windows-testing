#!/bin/bash

echo "start master extension" >> /tmp/master_extension.log

KUBECONFIG="$(find /home/*/.kube/config)"
KUBECTL="kubectl --kubeconfig=${KUBECONFIG}"

wait_for_kube_system_pods() {
    while true; do
    	NOTREADY_PODS=$(${KUBECTL} get pods -n kube-system -o custom-columns=STATUS:status.containerStatuses[0].ready --no-headers | grep -v "true")
    	if [ -z "${NOTREADY_PODS}" ]; then
    		echo "$(date -R) - All kube-system pods are ready" >> /tmp/master_extension.log
    		${KUBECTL} get pods --all-namespaces >> /tmp/master_extension.log
    		break
    	fi
    	sleep 2
    done
}

export -f wait_for_kube_system_pods
timeout 300 bash -c wait_for_kube_system_pods || exit 1

master_node=$(${KUBECTL} get nodes | grep master | awk '{print $1}')

${KUBECTL} taint nodes "$master_node" node-role.kubernetes.io/master=:NoSchedule
${KUBECTL} label nodes "$master_node" node-role.kubernetes.io/master=NoSchedule

echo "finish master extension" >> /tmp/master_extension.log
