#!/bin/bash

# Wait for coredns pod to be ready
while true; do
	COREDNS_READY=$(kubectl get pods -l k8s-app=kube-dns -n kube-system -o custom-columns=STATUS:status.containerStatuses[0].ready --no-headers)
	if [ "${COREDNS_READY}" = "true" ]; then
		echo "$(date -R) - coredns is ready" >> /tmp/master_extension.log
		kubectl get pods --all-namespaces >> /tmp/master_extension.log
		break
	fi
	sleep 2
done

# Wait for all pods in kube-system namespace to be ready before applying taints
while true; do
	NOTREADY_PODS=$(kubectl get pods -n kube-system -o custom-columns=STATUS:status.containerStatuses[0].ready --no-headers | grep -v "true")
	if [ -z "${NOTREADY_PODS}" ]; then
		echo "$(date -R) - All kube-system pods are ready" >> /tmp/master_extension.log
		kubectl get pods --all-namespaces >> /tmp/master_extension.log
		break
	fi
	sleep 2
done

master_node=$(kubectl get nodes | grep master | awk '{print $1}')

kubectl taint nodes "$master_node" node-role.kubernetes.io/master=:NoSchedule
kubectl label nodes "$master_node" node-role.kubernetes.io/master=NoSchedule

# Prepull images
kubectl create -f https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/gce/prepull.yaml
# Wait 15 minutes for the test images to be pulled onto the nodes.
sleep 15m
# Check the status of the pods.
kubectl get pods -o wide >> /tmp/master_extension.log
# Delete the pods anyway since pre-pulling is best-effort
kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/gce/prepull.yaml
# Wait a few more minutes for the pod to be cleaned up.
sleep 3m
