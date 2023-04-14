#!/bin/bash
#set -x

# Create namespace for hipster shop
# Generate echo "Create namespace" in bold green
echo -e "\033[1;32mCreate namespace\033[0m"
kubectl create namespace hipster-shop 
kubectl label ns hipster-shop  spo.x-k8s.io/enable-recording=true

# Download the yaml file for microservices demo app
mkdir temp 2>/dev/null || true
curl https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml -o - | yq -s '"temp/"+.kind + "_" +.metadata.name' --no-doc


echo -e "\033[1;32mEnabling recording for all deployments\033[0m"

deployments=()
declare -A deployment_to_container_name
# Loop through all yml files in temp directory
for file in temp/Deployment*.yml; do
    name=$(yq ".metadata.name" "$file" )
    container_name=$(yq ".spec.template.spec.containers[0].name" "$file" )
    deployment_to_container_name["$name"]="$container_name"
    deployments+=("$name")

    # Create profile recording for each deployment
    cat <<EOF | kubectl apply -n hipster-shop -f -
apiVersion: security-profiles-operator.x-k8s.io/v1alpha1
kind: ProfileRecording
metadata:
  name: $name-recording
spec:
    kind: SeccompProfile
    recorder: bpf
    mergeStrategy: containers
    podSelector:
        matchLabels:
            app: $name
EOF
done

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

echo -e "\033[1;32mDownscaling deployments\033[0m"
# Downscale all deployments to 0 replicas
for deployment in "${deployments[@]}"; do
    kubectl scale deployment "$deployment" -n hipster-shop --replicas=0
done

# Loop over all deployment and wait for them to be have 0 pods
for deployment in "${deployments[@]}"; do
    while [[ $(kubectl get deployments.apps -n hipster-shop paymentservice -o=jsonpath='{.status.availableReplicas}') -ne "0" ]]; do
        echo "Waiting for $deployment in hipster-shop namespace to be scaled down..."
        sleep 1
    done
done

echo -e "\033[1;32mLetting the operator create the SeccompProfile custom resources\033[0m"
sleep 30

echo "Current profile recordings:"
kubectl get profilerecording -n hipster-shop
echo "Current SeccompProfiles:"
kubectl get sp -n hipster-shop

echo -e "\033[1;32mDeleting recordings to trigger reconciliation\033[0m"
# Delete all the ProfileRecording custom resources to reconcile the SeccompProfile custom resources
for deployment in "${deployments[@]}"; do
    kubectl delete profilerecording "$deployment-recording" -n hipster-shop
done


echo -e "\033[1;32mPatching deployments with the SeccompProfile custom resources and restarting the application\033[0m"

# Loop through all deployments and patch the deployment with the SeccompProfile custom resource
for deployment in "${deployments[@]}"; do
    container_name=${deployment_to_container_name["$deployment"]}
    # Wait for the SeccompProfile custom resource to be created
    echo "Waiting for SeccompProfile for $deployment-$container_name to be installed..."
    counter=0
    while ! kubectl get sp -n hipster-shop "$deployment-recording-$container_name" &>/dev/null ; do

        sleep 1
        counter=$((counter+1))
        if [ $counter -gt 60 ]; then
            echo "SeccompProfile for $deployment is not installed"
            exit 1
        fi
    done

    # Get the SeccompProfile custom resource with the path to the profile
    STATUS=`kubectl -n hipster-shop get sp "$deployment-recording-$container_name" -o=jsonpath='{.status.status}'`

    # Check if status is installed
    if [ "$STATUS" != "Installed" ]; then
        echo "SeccompProfile for $deployment is not installed"
        exit 1
    fi

    PROFILE_PATH=`kubectl -n hipster-shop get sp "$deployment-recording-$container_name" -o=jsonpath='{.status.localhostProfile}'`

    kubectl -n hipster-shop patch deployment "$deployment" --patch '{"spec": {"template": {"spec": {"containers": [{"name": "'$container_name'", "securityContext": {"seccompProfile": {"type": "Localhost", "localhostProfile": "'$PROFILE_PATH'"}}}]}}}}'

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

# Saving the SeccompProfile custom resources for each deployment to a file
echo -e "\033[1;32mSaving the SeccompProfile custom resources to a file\033[0m"
for deployment in "${deployments[@]}"; do
    container_name=${deployment_to_container_name["$deployment"]}
    kubectl get sp "$deployment-recording-$container_name" -n hipster-shop -o yaml > "seccomp-profiles/$deployment-recording-$container_name".yml
    echo "Stored SeccompProfile for $deployment in seccomp-profiles/$deployment-recording-$container_name.yml"
done

echo -e "\033[1;32m
  _______ _     _ _______ _______ __
  |______  \_____/ |______ |______ |  |
  ______| _/    \_ |______ ______| |__| .io
\033[0m"

# Delete the namespace
kubectl delete namespace hipster-shop

