# AKS Concepts

## Prerequisites

- az cli (latest version: 2.24.x +): https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

> Info: Issues when running `az aks create` when the az cli version is not updated. If you experience an issue similar to [the following](https://github.com/Azure/azure-cli-extensions/issues/3445), try [updating the az cli](https://docs.microsoft.com/en-us/cli/azure/update-azure-cli).

- kubectl (version 1.19.x +): https://kubernetes.io/docs/tasks/tools/
- docker (version 20.10.x +): https://docs.docker.com/engine/install/

## How is AKS Architected?

Reference: https://docs.microsoft.com/en-us/azure/aks/concepts-clusters-workloads

1. Control Plane
    
    The Control Plane deployed for your Kubernetes cluster is a managed Azure resource that is abstracted away from the user. You will not configure the control plane and cannot access it directly (access is done through kubectl or the Kubernetes Dashboard). 

2. Node Pools

    Nodes of the same type and configuration are grouped together into node pools on AKS. You may have a default set of nodes and then can add a unique/specific node pool to include different VM types into your cluster for specialized workloads.

3. Taints and Tolerations

    Taints will restrict the types of pods that can be scheduled on the nodes tagged with the specified taints. Apply tolerations to a pod so that the pod can then be scheduled on nodes with that taint.

    Reference: https://docs.microsoft.com/en-us/azure/aks/operator-best-practices-advanced-scheduler#provide-dedicated-nodes-using-taints-and-tolerations

4. Cluster Autoscaler

    The cluster autoscaler can dynamically add and remove nodes from specific node pools to align to your resource utilization and scheduling demands.

    Reference: https://docs.microsoft.com/en-us/azure/aks/cluster-autoscaler#using-the-autoscaler-profile

5. Container Storage Interface (CSI)

    This is an interface or standard by which 3rd-party storage solutions can plug into Kubernetes. For AKS, this currently needs to be enabled at cluster creation time until the feature is GA.

    Reference: https://docs.microsoft.com/en-us/azure/aks/csi-storage-drivers

## Lab 1: Deploy a Cluster

1. Save the following environment variables in a `.env` file:

    ```
    # Azure resoure group settings
    RG_NAME=demo-aks-cluster                  # Resource group name
    LOCATION=eastus                           # az account list-locations --query '[].name'

    # ACR deployment settings
    ACR_NAME=demoacrinstancehs123             # ACR instance name
    ACR_SKU=basic                             # ACR sku

    # AKS deployment settings
    AKS_NAME=demo-aks                         # AKS Cluster Name, ie: 'demo-aks'
    AKS_NODE_COUNT=2                          # Initial Node Count in Cluster
    ```

2. Run the following:

    ```
    # Login to your Azure Subscription
    az login

    # Source and export the environment variables
    set -a  
    source .env    # Assumes your .env is at ./src/drupal-aks/.env
    set +a

    # Register the EnableAzureDiskFileCSIDriver preview feature before deploying AKS
    az feature register --namespace "Microsoft.ContainerService" --name "EnableAzureDiskFileCSIDriver"

    # Verify the registration status (this takes a few minutes before you should see Registered)
    az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/EnableAzureDiskFileCSIDriver')].{Name:name,State:properties.state}"

    # Refresh the registration of the Microsoft.ContainerService resource
    az provider register --namespace Microsoft.ContainerService

    # Install the aks-preview extension
    az extension add --name aks-preview

    # Update the extension to make sure you have the latest version installed
    az extension update --name aks-preview

    # Deploy the initial cluster
    ./deploy.sh

    # Get kubectl credentials
    az aks get-credentials --name $AKS_NAME --resource-group $RG_NAME --overwrite-existing
    ```

3. View the system nodepool:

    ```
    az aks nodepool list --cluster-name $AKS_NAME -g $RG_NAME
    ```

## Lab 2: Add A 'Specialized' Node Pool

1. Deploy another node pool:

    > Info: You cannot change the taint for the node pool after the pool is created.

    ```
    az aks nodepool add \
        --resource-group $RG_NAME \
        --cluster-name $AKS_NAME \
        --name cpupool \
        --node-count 1 \
        --labels hardware=highcpu \
        --node-taints sku=gpu:NoSchedule
    ```
2. Run `kubectl get nodes` to view the new node. Also run `az aks nodepool list --cluster-name $AKS_NAME --resource-group $RG_NAME -o table` to view the node pool.

    > Info: The node pools can also be seen in the Portal for the cluster

3. Run the following:

    ```
    kubectl apply -f app-workload.yaml
    kubectl get events --watch
    ```

4. View the Kubernetes Portal in Azure and see that the pods are scheduled on the new node pool given the taints and tolerations that were applied.

## Lab 3: Manually Scale the Node Pool

1. Run the following:

    ```
    az aks nodepool scale \
        --resource-group $RG_NAME \
        --cluster-name $AKS_NAME \
        --name cpupool \
        --node-count 2
    ```

2. Confirm in the portal that the node pool has been scaled up by a node.

3. Scale the node back down in the portal and confirm the action executes successfully with `kubectl get nodes`.

4. Confirm the app is still up and running.

## Lab 4: Configure Cluster Autoscaling

1. Configure cluster autoscaling for the node pool by running the following command (before running the command, confirm there is only one node in the cpupool node pool):

    ```
    az aks nodepool update \
    --resource-group $RG_NAME \
    --cluster-name $AKS_NAME \
    --name cpupool \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 5
    ```

    > Reference: https://docs.microsoft.com/en-us/azure/aks/cluster-autoscaler#use-the-cluster-autoscaler-with-multiple-node-pools-enabled

2. Run `kubectl delete deployment/azure-vote-front` and `kubectl delete deployment/azure-vote-back`.

3. Run `kubectl apply -f app-workload-replicas.yaml`. Confirm after running this that additional nodes are added to the cpupool.

4. Additionally run `kubectl scale deployments/azure-vote-front --replicas=10` and you will see additional nodes added by the cluster autoscaler.

5. Remove the deployments by running the following:

    ```
    kubectl delete deployments/azure-vote-front
    kubectl delete deployments/azure-vote-back
    ```

    > Info: In about 10 minutes, per the default cluster autoscaling profile referenced below, nodes should begin to be removed from the node pool.

    > Reference: https://docs.microsoft.com/en-us/azure/aks/cluster-autoscaler#using-the-autoscaler-profile

## Lab 5: Storage

1. When you deployed the AKS cluster, we included the CSI drivers for Azure-based storage (Azure Files and Azure Disks).

2. Run `kubectl get sc` to view the storage classes available in the cluster. We will run a test with the azurefile-csi storage class.

    > Reference: https://docs.microsoft.com/en-us/azure/aks/azure-files-csi

3. Run the following to create the PVC and an nginx pod that uses that PVC:

    ```
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/example/pvc-azurefile-csi.yaml

    kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/example/nginx-pod-azurefile.yaml
    ```

4. View the volume in the portal and notice that the volume is mounted at `/mnt/azurefile`.

5. Run `kubectl exec --stdin --tty nginx-azurefile -- /bin/bash` to open a shell in the running container. From there, navigate to `/mnt/azurefile` and create a test file with `touch testfile.txt`.

6. In the Azure portal, go to the `MC_` resource group and open up the azure file shares tab under the storage account. You should see the test file in the file share.

## Lab 6: ACR Integration

1. Run `az acr login --name $ACR_NAME` to login to the registry.

2. Run the following to pull the images to deploy locally:

    ```
    docker pull mcr.microsoft.com/oss/bitnami/redis:6.0.8
    docker pull mcr.microsoft.com/azuredocs/azure-vote-front:v1
    ```

    > Info: These are the images from the test app previously used.

3. Run the following to tag the images so they can be pushed to the ACR instance:

    ```
    # Get the registry server
    az acr list -g $RG_NAME -o table

    # Tag the images
    docker tag mcr.microsoft.com/oss/bitnami/redis:6.0.8 $ACR_NAME.azurecr.io/demo/backend
    docker tag mcr.microsoft.com/azuredocs/azure-vote-front:v1 $ACR_NAME.azurecr.io/demo/frontend
    ```

4. Push the images to ACR:

    ```
    docker push $ACR_NAME.azurecr.io/demo/backend
    docker push $ACR_NAME.azurecr.io/demo/frontend
    ```

5. Run `az acr repository list --name $ACR_NAME` to view the repositories.

6. Open the `app-workload-acr.yaml` file and update the images to reference your ACR instance.

7. Run the following to test the deployment in a new namespace:

    ```
    # Create the namespace
    kubectl create ns acr-demo

    # Deploy the service and deployments
    kubectl apply -f app-workload-acr.yaml -n acr-demo

    # Run a port-forward to view the front-end from your local machine (usefule when not deploying as a LoadBalancer service)
    kubectl port-forward svc/azure-vote-front 8000:80 -n acr-demo
    ```
