#!/bin/bash

# Get the IP of the DC as soon as it is available
while [$DCIP = $null]
do
    DCIP=$(kubectl get node --selector="agentpool=windowsgmsa" -o jsonpath="{.items[*].status.addresses[?(@.type=='InternalIP')].address}") > /dev/null 2>&1
    sleep 5
done

cat << EOF >> coredns-custom.sed
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  Corefile: |
    k8sgmsa.lan:53 {
      errors
      cache 30
      log
      forward . DCIP
    }
EOF

# Place the IP for the DC into the config file
sed "s/DCIP/${DCIP}/g" coredns-custom.sed > coredns-custom.yml

# Apply the config file
kubectl apply -f coredns-custom.yml

# Restart the CoreDNS pods to pick up the changes
kubectl -n kube-system rollout restart deployment coredns
