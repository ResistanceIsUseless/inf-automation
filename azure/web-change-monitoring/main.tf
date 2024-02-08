provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "mon-resources" {
  name     = "monitoring-resources"
  location = "East US"
}

resource "azurerm_virtual_network" "internal-network" {
  name                = "internal-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.mon-resources.location
  resource_group_name = azurerm_resource_group.mon-resources.name
}

resource "azurerm_subnet" "sn-nginx-monitoring" {
  name                 = "sn-internal"
  resource_group_name  = azurerm_resource_group.mon-resources.name
  virtual_network_name = azurerm_virtual_network.internal-network.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "nic-nginx-monitoring" {
  name                = "nic-nginx-monitoring"
  location            = azurerm_resource_group.mon-resources.location
  resource_group_name = azurerm_resource_group.mon-resources.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sn-nginx-monitoring.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip-nginx-monitoring.id
  }
}

resource "azurerm_public_ip" "pip-nginx-monitoring" {
  name                = "pip-nginx-monitoring"
  location            = azurerm_resource_group.mon-resources.location
  resource_group_name = azurerm_resource_group.mon-resources.name
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "nsg-nginx-monitoring-vm" {
  name                = "nsg-nginx-monitoring-vm"
  location            = azurerm_resource_group.mon-resources.location
  resource_group_name = azurerm_resource_group.mon-resources.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_linux_virtual_machine" "nginx-monitoring-vm" {
  name                = "nginx-monitoring-vm"
  resource_group_name = azurerm_resource_group.mon-resources.name
  location            = azurerm_resource_group.mon-resources.location
  size                = "Standard_B2s"
  admin_username      = "adminuser"
  custom_data = <<-CLOUD_INIT
    # Default: false
package_update: true
#package_upgrade: true
packages:
 - nginx
 - curl
 - docker.io
 - certbot
 - python-certbot-nginx


write_files:
- content: |
    server {
      listen 443 ssl;
      listen 80;
      server_name ${var.subdomain}.${var.domain};

      ssl_certificate /etc/letsencrypt/live/${var.subdomain}.${var.domain}/fullchain.pem;
      ssl_certificate_key /etc/letsencrypt/live/${var.subdomain}.${var.domain}/privkey.pem;
      ssl_protocols TLSv1.2;

      # send request back to docker at 127.0.0.1:5000 for host ${var.subdomain}.${var.domain}
      location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        auth_basic           "restricted access";
        auth_basic_user_file /etc/nginx/.htpasswd; 


      }
    }
  path: /etc/nginx/sites-available/${var.subdomain}.${var.domain}

runcmd:
- sudo cd /etc/nginx/sites-enabled && sudo ln -s /etc/nginx/sites-available/${var.subdomain}.${var.domain} ${var.subdomain}.${var.domain}
- sudo certbot --nginx -d ${var.subdomain}.${var.domain} --email ${var.email} --non-interactive --agree-tos 
- sudo sh -c "echo -n '${var.username}:' >> /etc/nginx/.htpasswd"
- sudo sh -c "openssl passwd -apr1 ${var.password} >> /etc/nginx/.htpasswd"
- sudo nginx -t
- [ systemctl, reload, nginx ]
- sudo docker network create --driver bridge ${var.subdomain}
- sudo docker run -d --name selenium --restart unless-stopped --network ${var.subdomain} -p 4444:4444 --shm-size="2g" selenium/standalone-chrome-debug:3.141.59
- sudo docker run -d --restart always -p "5000:5000" --network ${var.subdomain} -e WEBDRIVER_URL="http://127.0.0.1:4444/wd/hub" -v datastore-volume:/datastore --name changedetection.io dgtlmoon/changedetection.io

  CLOUD_INIT
 
  network_interface_ids = [
    azurerm_network_interface.nic-nginx-${var.subdomain}.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  #  provisioner "remote-exec" {
  #  inline = [
  #    "sudo apt-get update",
  #    "sudo apt-get install -y cifs-utils",
  #    # Add commands to mount Azure Storage here
  #  ]
  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub") # Replace with your SSH public key
  }

}

resource "azurerm_storage_account" "sa-nginx-monitoring" {
  name                     = "monitoringnginxstorage"
  resource_group_name      = azurerm_resource_group.mon-resources.name
  location                 = azurerm_resource_group.mon-resources.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

}

resource "azurerm_storage_container" "content" {
  name                  = "content"
  storage_account_name  = azurerm_storage_account.sa-nginx-monitoring.name
  container_access_type = "container"
}

resource "azurerm_dns_zone" "dns_zone" {
  name                = var.domain
  resource_group_name = azurerm_resource_group.mon-resources.name
}

resource "azurerm_dns_a_record" "dns-nginx-monitoring" {
  name                = var.subdomain  // The subdomain part of your DNS record
  zone_name           = azurerm_dns_zone.dns_zone.name
  resource_group_name = azurerm_resource_group.mon-resources.name  // The resource group of your DNS zone
  ttl                 = 150
  target_resource_id  = azurerm_public_ip.pip-nginx-monitoring.id

}

output "storage_account_url" {
  value = azurerm_storage_account.sa-nginx-monitoring.primary_blob_endpoint
}

output "public_ip" {
  value = azurerm_public_ip.pip-nginx-monitoring.id
}
