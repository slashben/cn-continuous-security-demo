#!/bin/bash
#set -x

# Create namespace for hipster shop
# Generate echo "Create namespace" in bold green
echo -e "\033[1;32mCreate namespace\033[0m"
kubectl create namespace hipster-shop 

# Download the yaml file for microservices demo app
mkdir temp 2>/dev/null || true
curl https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml -o - | yq -s '"temp/"+.kind + "_" +.metadata.name' --no-doc


echo -e "\033[1;32mEnabling recording for all deployments\033[0m"

deployments=()
declare -A deployment_to_container_name
# Loop through all yml files in temp directory
for file in temp/Deployment*.yml; do
    name=$(yq ".metadata.name" "$file" )
    deployments+=("$name")
done

# Start recording network events
echo -e "\033[1;32mStarting network event recording for the namespace\033[0m"
kubectl gadget advise network-policy monitor -n hipster-shop --output temp/networktrace.log > /dev/null &
# Store the PID of the process to kill it later
GADGET_PID=$!

# Check if the return code is ok
if [ $? -ne 0 ]; then
    echo "Error: Failed to start network event recording"
    exit 1
fi

# Install the microservices demo app
echo -e "\033[1;32mInstalling the application in the namespace\033[0m"
kubectl apply -n hipster-shop -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml

# Wait for all deployments to be ready
echo -e "\033[1;32mWaiting for all deployments to be ready\033[0m"
for deployment in "${deployments[@]}"; do
    kubectl wait --for=condition=available deployment "$deployment" -n hipster-shop --timeout=300s
done

echo -e "\033[1;32mSleeping for 60 seconds to allow the application to run all tests\033[0m"
sleep 60

# Stop the network event recording
echo -e "\033[1;32mStopping network event recording\033[0m"
kill -SIGINT $GADGET_PID

# Create network policy from the event for all deployments
echo -e "\033[1;32mCreating network policies for all deployments\033[0m"
kubectl gadget advise network-policy report --input temp/networktrace.log --output network-policies/all-namespace.yml

# apply the network policy
echo -e "\033[1;32mApplying the network policy to the namespace\033[0m"
kubectl apply -f network-policies/all-namespace.yml -n hipster-shop

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
echo -e "\033[1;32mNetwork policy file is located at network-policies/all-namespace.yml\033[0m"

echo -e "\033[1;32m
  _______ _     _ _______ _______ __
  |______  \_____/ |______ |______ |  |
  ______| _/    \_ |______ ______| |__| .io
\033[0m"

# Delete the namespace
kubectl delete namespace hipster-shop

