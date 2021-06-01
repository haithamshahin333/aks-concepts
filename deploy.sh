# Create a resource group for the Drupal workload
echo "Creating resource group '$RG_NAME' in region '$LOCATION'."
az group create --name $RG_NAME --location $LOCATION

# Create an Azure Container Registry instance
echo "Creating ACR '$ACR_NAME' in resource group '$RG_NAME'."
az acr create \
    --resource-group $RG_NAME \
    --name $ACR_NAME \
    --sku $ACR_SKU

# Create an AKS cluster 
echo "Creating AKS cluster '$AKS_NAME' in resource group '$RG_NAME'."
az aks create \
    --name $AKS_NAME \
    --resource-group $RG_NAME \
    --node-count $AKS_NODE_COUNT \
    --enable-addons monitoring \
    --enable-managed-identity \
    --attach-acr $ACR_NAME \
    --no-ssh-key \
    --aks-custom-headers EnableAzureDiskFileCSIDriver=true