#!/bin/bash
# set -x

# Create namespace for hipster shop
# Generate echo "Create namespace" in bold green
echo -e "\033[1;32mCreate namespace\033[0m"
kubectl create namespace hipster-shop

# Download the yaml file for microservices demo app
mkdir temp 2>/dev/null || true
curl https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml -o temp/kubernetes-manifests.yaml

deployments=()
# Loop through all yml files in temp directory
for deployment in $(yq -e -r 'select(.kind == "Deployment") | .metadata.name' temp/kubernetes-manifests.yaml); do
    deployments+=("$deployment")
done

# Install the microservices demo app
echo -e "\033[1;32mInstalling the application in the namespace\033[0m"
kubectl apply -n hipster-shop -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml

# Wait for all deployments to be ready
echo -e "\033[1;32mWaiting for all deployments to be ready\033[0m"
for deployment in "${deployments[@]}"; do
    kubectl wait --for=condition=available deployment "$deployment" -n hipster-shop --timeout=300s
done

echo -e "\033[1;32mSleeping for 180 seconds to allow the application to run all tests\033[0m"
sleep 180

# Create network policy from the event for all deployments
echo -e "\033[1;32mCreating network policies for all deployments\033[0m"

# Loop for all deployments in the namespace
for deployment in "${deployments[@]}"; do
    generatednetworkpolicy=`kubectl get generatednetworkpolicies -n hipster-shop | grep $deployment | awk '{print $1}'`
    kubectl get generatednetworkpolicies -n hipster-shop $generatednetworkpolicy -o json | yq -y '.spec' > network-policies/"$deployment".yaml
done

# apply the network policy
echo -e "\033[1;32mApplying the network policy to the namespace\033[0m"
for file in network-policies/*.yaml; do
    kubectl apply -n hipster-shop -f "$file"
done

# Restarting pods in the namespace to apply the network policy
echo -e "\033[1;32mRestarting pods in the namespace to apply the network policy\033[0m"
kubectl rollout restart deployment -n hipster-shop

# Wait for all deployments to be ready
echo -e "\033[1;32mWaiting for all deployments to be ready\033[0m"
for deployment in "${deployments[@]}"; do
    kubectl wait --for=condition=available deployment "$deployment" -n hipster-shop --timeout=300s
done

echo -e "\033[1;32mApplication state\033[0m"
kubectl get deployments -n hipster-shop


# Print the location of the network policy file
echo -e "\033[1;32mNetwork policy files are located at network-policies/*.json\033[0m"

echo -e "\033[1;32m
  _______ _     _ _______ _______ __
  |______  \_____/ |______ |______ |  |
  ______| _/    \_ |______ ______| |__| .io
\033[0m"

# Delete the namespace
kubectl delete namespace hipster-shop

