#/bin/bash

# Deploy kubescape
helm repo add kubescape https://kubescape.github.io/helm-charts/
helm repo update
# Note: all the needed capabilities are already set to true in the default values.yaml file, so no need to set them here (networkPolicyService, seccompProfileService, runtimeObservability)
helm upgrade --install kubescape kubescape/kubescape-operator -n kubescape --create-namespace --set clusterName=`kubectl config current-context`

# Check the return code of the kubescape deployment
if [[ $? -eq 0 ]]; then
  echo "Kubescape deployed"
else
  echo "Kubescape deployment failed"
  exit 1
fi

# Wait for the pods in kubescape namespace to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=kubescape -n kubescape --timeout=600s
