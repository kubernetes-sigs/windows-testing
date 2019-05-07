#!/bin/bash

# Wait for all pods in kube-system namespace to be running before applying taints

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

