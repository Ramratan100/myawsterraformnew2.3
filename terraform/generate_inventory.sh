#!/bin/bash

# Navigate to the Terraform directory
cd "$(dirname "$0")"

# Generate inventory.json
terraform output -json | jq -r '
{
  "bastion": {
    "hosts": {
      "bastion_host": {
        "ansible_host": .bastion_host_public_ip.value,
        "ansible_user": "ubuntu"
      }
    }
  },
  "mysql": {
    "hosts": {
      "mysql_instance": {
        "ansible_host": .mysql_instance_private_ip.value,
        "ansible_user": "ubuntu"
      }
    }
  }
}' > ../ansible/inventory.json
