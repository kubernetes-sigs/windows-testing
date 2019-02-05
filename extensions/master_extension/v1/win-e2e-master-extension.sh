#!/bin/bash

master_node=$(kubectl get nodes | grep master | awk '{print $1}')

kubectl taint nodes $master_node key=value:NoSchedule
kubectl label nodes $master_node node-role.kubernetes.io/master=NoSchedule

