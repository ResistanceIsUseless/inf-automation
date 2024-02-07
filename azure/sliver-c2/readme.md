# Using Terraform to build a vm running nginx and sliver in Azure
To run use the following commands:

```
az login
cd azure-silver
terraform init
export PUBLIC_IP=$(curl -s ifconfig.me)
terraform plan -var="my_ip=$PUBLIC_IP"
terraform apply -var="my_ip=$PUBLIC_IP"
```

Then get the public IP of the VM and login:
```
az vm show --resource-group <YourResourceGroupName> --name <YourVMName> --query 'networkProfile.networkInterfaces[].id' -o tsv
az network nic show --ids <NetworkInterfaceId> --query 'ipConfigurations[].publicIpAddress.id' -o tsv

ssh azureadmin@x.x.x.x
```
To configure the nginx CDN path you will need to get the storage account path:
- *I highly reccomend using [Azure SE](https://azure.microsoft.com/en-us/products/storage/storage-explorer) to manage files on the storage account.*
```
az storage container show --name <container-name> --account-name <storage-account-name> --account-key <your-account-key> --query "url" --output tsv
```


To delete everything:
`terraform destroy`


# TODO:
1. get the certs added from lets encrypt on build
2. make sliver so it runs as a service on a loopback as part of cloud-init (edit docker file or add command args?)
3. mount storage account to vm
