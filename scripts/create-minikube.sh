#!/bin/bash
set -x

# Create a minikube cluster with calico as the network plugin
minikube start --cni=calico --driver=qemu2 --memory=8192 --cpus=6

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

# Deploy Kubernetes cert manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.1/cert-manager.yaml
while [[ $(kubectl get pods -n cert-manager --no-headers | wc -l) -eq 0 ]]; do
    echo "Waiting for pod in cert-manager namespace to be created..."
    sleep 10
done
kubectl --namespace cert-manager wait --for condition=ready pod -l app.kubernetes.io/instance=cert-manager --timeout=300s

# Check the return code of the cert manager deployment
if [[ $? -eq 0 ]]; then
  echo "Cert manager deployed"
else
  echo "Cert manager deployment failed"
  exit 1
fi

# Deploy the Kubernetes security operator
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/security-profiles-operator/main/deploy/operator.yaml 
# patch the operator to enable the bpf recorder
kubectl patch deployment security-profiles-operator -n security-profiles-operator --type json -p '[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "ENABLE_BPF_RECORDER", "value": "true"}}]' && sleep 10
while [[ $(kubectl get pods -n security-profiles-operator --no-headers | wc -l) -eq 0 ]]; do
    echo "Waiting for pod in security-profiles-operator namespace to be created..."
    sleep 10
done
kubectl --namespace security-profiles-operator wait --for condition=ready pod -l app=security-profiles-operator --timeout=300s

# Check the return code of the security operator deployment
if [[ $? -eq 0 ]]; then
  echo "Security operator deployed"
else
  echo "Security operator deployment failed"
  exit 1
fi

kubectl gadget deploy
# Check the return code of the gadget deployment
if [[ $? -eq 0 ]]; then
  echo "Gadget deployed"
else
  echo "Gadget deployment failed"
  exit 1
fi

exit 0



# Install the calico CNI plugin
# kubectl apply -f https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/hosted/kubeadm/1.7/calico.yaml