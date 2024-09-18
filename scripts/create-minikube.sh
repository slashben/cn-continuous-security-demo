#!/bin/bash
set -x

# Create a minikube cluster with calico as the network plugin
minikube start --cni=calico #--driver=qemu2 --memory=8192 --cpus=6

# Check return code of minikube start
if [[ $? -eq 0 ]]; then
  echo "Minikube cluster created"
else
  echo "Minikube cluster creation failed"
  exit 1
fi

# Check that the cluster is running if not, exit
if [[ $(minikube status | grep 'apiserver: Running') ]]; then
  echo "Minikube is running"
else
  echo "Minikube is not running"
  exit 1
fi
