# Run capz e2e tests in a pod in aks cluster for Windows

This folder contains the scripts required to deploy kubernetes cluster and run e2e tests in a pod with CAPZ.


## When is private test needed

Sometime, a network security group blocks the traffic from internet to non Azure standard ports. In this case, the e2e tests fails to access k8s API server port 6443 when run on test client on interet.


## Overview of private test

 The k8s vnet is peered with aks vnet in the private test template to connect two vnets. The test client from internet configures workload cluster, runs k8s e2e tests via a pod on the aks worker node, and copies test results and logs from the pod via `kubectl cp` after test is completed.

## Private test template
To generate the template for private test run:

```bash
kustomize build --load-restrictor LoadRestrictionsNone . > ../templates/private-test.yaml
```

## Running private tests with capz

To run the tests, from the capz folder in this repo:

```bash
PRIVATE_TESTING=true ./run-capz-e2e.sh
```