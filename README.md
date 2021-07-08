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

## Lab 7: NFS File Setup with Azure Files

> Info: Assumes the Azure File CSI Driver is installed from lab 1

Reference: https://github.com/kubernetes-sigs/azurefile-csi-driver/tree/master/deploy/example/nfs

1. Run the following to Allow NFS File Shares under your subscription:

    ```
    az feature register --name AllowNfsFileShares --namespace Microsoft.Storage

    # Run the command below to validate the feature is registered
    # This may take up to 30 minutes
    # You will see 'Microsoft.Storage/AllowNfsFileShares  Registered' once it is complete
    az feature list -o table --query "[?contains(name, 'Microsoft.Storage/AllowNfsFileShares')].{Name:name,State:properties.state}"

    az provider register --namespace Microsoft.Storage
    ```

2. Run the following to create a storage class that will dynamically provision an NFS File Share when called through a PVC:

    ```
    wget https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/deploy/example/storageclass-azurefile-nfs.yaml

    kubectl create -f storageclass-azurefile-nfs.yaml
    ```

3. Run `kubectl create ns nfs-test`

4. Run `helm install wordpress -f wordpress-values.yaml -n nfs-test bitnami/wordpress`

5. Run `kubectl logs -f $(kubectl get pod -l app.kubernetes.io/instance=wordpress -o jsonpath='{.items[0].metadata.name}' -n nfs-test) -n nfs-test` to follow the logs of the container as it starts (takes about 10 minutes on a fresh install based on my testing).

## Lab 8: NFS over Blob in Azure

Reference: https://docs.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to?tabs=azure-cli

1. Register the nfs v3 feature

    ```bash
    az login

    # regiser the nfsv3 feature in the subscription
    az feature register --namespace Microsoft.Storage --name AllowNFSV3

    # verify that the feature is registered
    az feature show --namespace Microsoft.Storage --name AllowNFSV3

    # once registered, run this command to register the resource provider
    az provider register -n Microsoft.Storage
    ```

2. Create a Storage Account Properly Configured for NFS

    > Info: Before creating the storage account, you must have registered the feature as shown above.

    Run through [step 5](https://docs.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to?tabs=azure-cli#step-5-create-and-configure-a-storage-account) of this tutorial in the Azure Portal - be sure to properly configure the Storage Account so that the NFS setting can be enabled.

    > Info: Notice the hierarchical namespace setting as well as the networking setting. You can either use a private endpoint or just select public endpoints (selected networks) and accept the VNet where AKS is deployed. This will secure the storage account to only allow connections from the AKS VNet.

3. Create a container in the storage account for the blob

    Follow [step 6](https://docs.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to?tabs=azure-cli#step-6-create-a-container) - there is no special rule for how the container is created to support the backing blob storage.

4. In your cluster, run through the following steps:

    > Info: Review the comments before running the commands to properly update the templates to work for your NFS storage account

    ```bash
    kubectl create ns nfs-blob-sample

    # Open nfs-blob-templates/nfs-blob-pv.yaml and update the path and server settings to configure the NFS Volume
    kubectl apply -f nfs-blob-templates/nfs-blob-pv.yaml -n nfs-blob-sample
    kubectl apply -f nfs-blob-templates/nfs-blob-pvc.yaml -n nfs-blob-sample
    kubectl apply -f nfs-busybox-pod.yaml -n nfs-blob-sample

    # Once the busybox pod is up and running, exec into the pod and view the "/mnt" folder
    # Create a file in the folder
    kubectl exec -it pod/busybox-sleep sh -n nfs-blob-sample
    cd /mnt
    echo "hello world" > hello-world.txt

    ###
    # Run through the same steps for another busybox pod so we can see how multiple pods can talk to the same NFS backed blob
    ###

    # Open nfs-blob-templates/nfs-blob-pv-two.yaml and update the path and server settings to configure the NFS Volume
    kubectl apply -f nfs-blob-templates/nfs-blob-pv-two.yaml -n nfs-blob-sample
    kubectl apply -f nfs-blob-templates/nfs-blob-pvc-two.yaml -n nfs-blob-sample
    kubectl apply -f nfs-busybox-pod-two.yaml -n nfs-blob-sample

    # Once the busybox pod is up and running, exec into the pod and view the "/mnt" folder
    # View the previously created file
    kubectl exec -it pod/busybox-sleep sh -n nfs-blob-sample
    cd /mnt
    cat hello-world.txt
    ```

## Lab 9: Ingress Controllers

There are a few options when it comes to [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) with AKS. We will look at the [nginx ingress controller](https://docs.microsoft.com/en-us/azure/aks/ingress-basic) and [application gateway ingress controller](https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview).

### Nginx Ingress Controller

1. Run `kubectl create namespace ingress-basic`

2. Add the helm repo for ingress-nginx: `helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx`

3. Run the following helm install to deploy the ingress controller:

    > Info: Here is the [repo](https://github.com/kubernetes/ingress-nginx/tree/master/charts/ingress-nginx) to further configure the ingress controller deployment.

    > Info: On the Azure side, you will find a Public IP is provisioned on the Load Balancer associated with your cluster. This will be the front-end IP that fronts the nginx ingress controller.

    ```
    helm install nginx-ingress ingress-nginx/ingress-nginx \
        --namespace ingress-basic \
        --set controller.replicaCount=2 \
        --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
        --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
        --set controller.admissionWebhooks.patch.nodeSelector."beta\.kubernetes\.io/os"=linux
    ```

4. To test the ingress controller, run the following:

```
# Deploy the resources
kubectl create ns test-nginx-app
kubectl apply -f aks-helloworld.yaml -n test-nginx-app

# Test the ingress
# Navigate to the address shown here
kubectl get ingress -n test-nginx-app
```

### Application Gateway Ingress Controller (AGIC)

In this lab, we will leverage the AKS add-on feature to deploy our app gateway ingress controller. Another deployment method is through [helm](https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview#difference-between-helm-deployment-and-aks-add-on).

Here are some of the [Benefits of App Gateway Ingress Controller](https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview#benefits-of-application-gateway-ingress-controller).

With AGIC you can deploy it as an add-on at cluster creation time or add it to an existing AKS cluster. Additionally, you can either have the add-on provision an App Gateway instance or use an existing App Gateway instance.

1. Run `az aks enable-addons --name <AKS-NAME> --resource-group <RESOURCE-GROUP> -a ingress-appgw --appgw-name myApplicationGateway --appgw-subnet-cidr "10.2.0.0/24"`

> Info: App Gateway requires a dedicated subnet. The command above will provision that subnet within the same default VNet used with AKS, but you may need to modify this depending on your AKS deployment. This [reference](https://docs.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure#virtual-network-and-dedicated-subnet) further describes the infrastructure/networking configuration for App Gateway.

> Validation: If you look into the `MC_` resource group that holds the infrastructure associated with the AKS cluster, you should now see an App Gateway resource provisioned.

> Validation: If you view the App Gateway resource provisioned for the cluster, you should see an 'Updating' status. The App Gateway will take some time to get configured and setup for use.

2. Run the following:

```
# Deploy the resources
# If you review the aks-helloworld-appgateway.yaml file, you'll see that changes were made on annotations to specify app gateway:
# kubernetes.io/ingress.class: azure/application-gateway
kubectl create ns test-appgateway-app
kubectl apply -f aks-helloworld-appgateway.yaml -n test-appgateway-app

# Test the ingress
# Navigate to the address shown here
kubectl get ingress -n test-appgateway-app
```