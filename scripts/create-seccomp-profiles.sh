#!/bin/bash
set -xe

# Create namespace for hipster shop
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

echo -e "\033[1;32mDownscaling deployments\033[0m"
# Downscale all deployments to 0 replicas
for deployment in "${deployments[@]}"; do
    kubectl scale deployment "$deployment" -n hipster-shop --replicas=0
done

# Loop over all deployment and wait for them to be have 0 pods
for deployment in "${deployments[@]}"; do
    while [[ $(kubectl get deployments.apps -n hipster-shop $deployment -o=jsonpath='{.status.availableReplicas}') -ne "0" ]]; do
        echo "Waiting for $deployment in hipster-shop namespace to be scaled down..."
        sleep 1
    done
done

for deployment in "${deployments[@]}"; do
    # Getting the application
    applicationprofile=`kubectl get applicationprofile -n hipster-shop | grep $deployment | awk '{print $1}'`
    kubectl get applicationprofile -n hipster-shop $applicationprofile -o yaml > temp/applicationprofile-$deployment.yaml
    python scripts/convert-approfile-to-seccomp.py temp/applicationprofile-$deployment.yaml > seccomp-profiles/$deployment.yaml
    kubectl apply -n hipster-shop -f seccomp-profiles/$deployment.yaml
done

echo -e "\033[1;32mPatching deployments with the SeccompProfile custom resources and restarting the application\033[0m"

# Loop through all deployments and patch the deployment with the SeccompProfile custom resource
for deployment in "${deployments[@]}"; do
    for container_name in $(kubectl get deployments.apps -n hipster-shop $deployment -o jsonpath='{.spec.template.spec.containers[*].name}'); do
        kubectl patch deployment "$deployment" -n hipster-shop --patch '{"spec": {"template": {"spec": {"containers": [{"name": "'$container_name'", "securityContext": {"seccompProfile": {"type": "Localhost", "localhostProfile": "'hipster-shop/Deployment-$deployment-$container_name.json'"}}}]}}}}'
    done

    # Scale the deployment back up to 1 replica
    kubectl scale deployment "$deployment" -n hipster-shop --replicas=1
done


# Wait for all deployments to be ready
echo -e "\033[1;32mWaiting for all deployments to be ready\033[0m"
for deployment in "${deployments[@]}"; do
    kubectl wait --for=condition=available deployment "$deployment" -n hipster-shop --timeout=300s
done

echo -e "\033[1;32mApplication state\033[0m"
kubectl get deployments -n hipster-shop

echo -e "\033[1;32m
  _______ _     _ _______ _______ __
  |______  \_____/ |______ |______ |  |
  ______| _/    \_ |______ ______| |__| .io
\033[0m"

# Delete the namespace
kubectl delete namespace hipster-shop

