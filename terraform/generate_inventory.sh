#!/bin/bash

# Navigate to the Terraform directory
cd "$(dirname "$0")"

# Fetch Terraform outputs and generate YAML format directly
output_bastion_host=$(terraform output -raw bastion_host_public_ip)
output_mysql_ip=$(terraform output -raw mysql_instance_private_ip)

# Write YAML to a file
echo "bastion:" > ../ansible/inventory.yml
echo "  hosts:" >> ../ansible/inventory.yml
echo "    bastion_host:" >> ../ansible/inventory.yml
echo "      ansible_host: $output_bastion_host" >> ../ansible/inventory.yml
echo "      ansible_user: ubuntu" >> ../ansible/inventory.yml
echo "mysql:" >> ../ansible/inventory.yml
echo "  hosts:" >> ../ansible/inventory.yml
echo "    mysql_instance:" >> ../ansible/inventory.yml
echo "      ansible_host: $output_mysql_ip" >> ../ansible/inventory.yml
echo "      ansible_user: ubuntu" >> ../ansible/inventory.yml

echo "Terraform outputs written to inventory.yml"
