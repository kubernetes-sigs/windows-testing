#!/bin/bash

# Wait for all pods in kube-system namespace to be running before applying taints

sleep 60
OUT=$(kubectl get pods -n kube-system -o custom-columns=STATUS:status.phase | grep -v "STATUS\|Running")
while [[ ! -z $OUT ]]; do
sleep 2
OUT=$(kubectl get pods -n kube-system -o custom-columns=STATUS:status.phase | grep -v "STATUS\|Running")
echo "Waited 2 seconds." >> /tmp/master_extension.log
echo $(kubectl get pods --all-namespaces) >> /tmp/master_extension.log
done

master_node=$(kubectl get nodes | grep master | awk '{print $1}')

kubectl taint nodes $master_node node-role.kubernetes.io/master=:NoSchedule
kubectl label nodes $master_node node-role.kubernetes.io/master=NoSchedule

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
