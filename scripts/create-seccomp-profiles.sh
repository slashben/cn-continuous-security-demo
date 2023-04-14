#!/bin/bash
#set -x

# Create namespace for hipster shop
kubectl create namespace hipster-shop 
kubectl label ns hipster-shop  spo.x-k8s.io/enable-recording=true

# Download the yaml file for microservices demo app
curl https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml -o - | yq -s '"temp/"+.kind + "_" +.metadata.name' --no-doc

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
kubectl apply -n hipster-shop -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml

# Wait for all deployments to be ready
for deployment in "${deployments[@]}"; do
    kubectl wait --for=condition=available deployment "$deployment" -n hipster-shop --timeout=300s
done

echo "Sleeping for 10 seconds to allow the app to do stuff and generate some syscalls"
sleep 10

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


# Delete all the ProfileRecording custom resources to reconcile the SeccompProfile custom resources
for deployment in "${deployments[@]}"; do
    kubectl delete profilerecording "$deployment-recording" -n hipster-shop
done



# Loop through all deployments and patch the deployment with the SeccompProfile custom resource
for deployment in "${deployments[@]}"; do
    container_name=${deployment_to_container_name["$deployment"]}
    # Wait for the SeccompProfile custom resource to be created
    while [[ $(kubectl get sp -n hipster-shop "$deployment-recording-$container_name" -o=jsonpath='{.status.status}') != "Installed" ]]; do
        echo "Waiting for SeccompProfile for $deployment to be installed..."
        sleep 1
    done

    # Get the SeccompProfile custom resource with the path to the profile
    STATUS=`kubectl -n hipster-shop get sp "$deployment-recording-$container_name" -o=jsonpath='{.status.status}'`

    # Check if status is installed
    if [ "$STATUS" != "Installed" ]; then
        echo "SeccompProfile for $deployment is not installed"
        #exit 1
    fi

    PROFILE_PATH=`kubectl -n hipster-shop get sp "$deployment-recording-$container_name" -o=jsonpath='{.status.localhostProfile}'`

    kubectl -n hipster-shop patch deployment "$deployment" --patch '{"spec": {"template": {"spec": {"containers": [{"name": "'$container_name'", "securityContext": {"seccompProfile": {"type": "Localhost", "localhostProfile": "'$PROFILE_PATH'"}}}]}}}}'

    # Scale the deployment back up to 1 replica
    kubectl scale deployment "$deployment" -n hipster-shop --replicas=1

done


kubectl get pods -n hipster-shop -w


exit 0


kubectl label ns default  spo.x-k8s.io/enable-recording=true

cat <<EOF | kubectl apply -f -
apiVersion: security-profiles-operator.x-k8s.io/v1alpha1
kind: ProfileRecording
metadata:
  name: my-recording
spec:
  kind: SeccompProfile
  recorder: bpf
  podSelector:
    matchLabels:
      app: my-app
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  labels:
    app: my-app
spec:
  containers:
    - name: nginx
      image: quay.io/security-profiles-operator/test-nginx:1.19.1
EOF

# Wait for the pod to be ready
kubectl wait --for=condition=ready pod/my-pod --timeout=300s

echo "Sleeping for 15 seconds to allow the app to do stuff and generate some syscalls"
# Sleep but allow the script to continue to run and wait for the sleep to end
sleep 15 &
SLEEP_PID=$!

kubectl -n security-profiles-operator logs --since=2m --selector name=spod -c bpf-recorder -f &
LOG_PID=$!
:1
# Wait for the sleep to end
wait $SLEEP_PID
kill $LOG_PID

kubectl delete pod my-pod

sleep 10

kubectl get sp my-recording-nginx -o yaml




exit 0