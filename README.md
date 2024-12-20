# MySQL Server Installation and Configuration via Ansible

This repository provides an Ansible playbook to install and configure MySQL Server on a remote host. It also sets up a test PHP script to verify the MySQL connection.

## Features
- Installs MySQL Server.
- Configures MySQL to allow connections from all IPs.
- Creates a MySQL user (`nat_user`) for a specific IP range.
- Installs Apache and PHP on a bastion host.
- Deploys test PHP scripts for MySQL connection and server info.

## Prerequisites

1. **Ansible Installed:** Ensure you have Ansible installed on the control node.
   ```bash
   sudo apt update && sudo apt install -y ansible
   ```
2. **Python and pip Installed:** Ensure Python 3 and pip are installed on the control node.
   ```bash
   sudo apt install -y python3 python3-pip
   ```
3. **Network Configuration:** Ensure the target servers have proper network access for package installation and Ansible communication.

## Playbook Overview

### MySQL Server Configuration
The `mysql_instance` playbook performs the following tasks:
1. Installs and starts the MySQL Server.
2. Configures MySQL to accept connections from any IP address (`bind-address = 0.0.0.0`).
3. Creates a MySQL user `nat_user` for the `10.0.2.%` IP range.
4. Restarts the MySQL service to apply changes.

### Apache and PHP Setup
The `bastion` playbook:
1. Installs Apache, PHP, and MySQL PHP modules.
2. Deploys test PHP scripts:
   - `index.php` to display server information.
   - `test.php` to verify MySQL connectivity.
3. Enables and starts the Apache service.

## Usage

### Step 1: Clone Repository
Clone this repository to your Ansible control node:
```bash
git clone <repository_url>
cd <repository_folder>
```

### Step 2: Update Inventory File
Edit the `inventory` file to include the target hosts:
```ini
[mysql_instance]
mysql.example.com ansible_user=ubuntu ansible_ssh_private_key_file=/path/to/key.pem

[bastion]
bastion.example.com ansible_user=ubuntu ansible_ssh_private_key_file=/path/to/key.pem
```

### Step 3: Run the Playbook
Execute the playbook:
```bash
ansible-playbook -i inventory playbook.yml
```

### Step 4: Verify Setup
- Access the `index.php` file via the bastion server's public IP:
  ```
  http://<bastion_ip>/index.php
  ```
- Verify MySQL connection via `test.php`:
  ```
  http://<bastion_ip>/test.php
  ```

## Customization

### MySQL User and Password
Update the `vars` section in the playbook to specify the desired user credentials:
```yaml
vars:
  nat_user_password: "your_password"
```

### PHP Test Script
Modify the `test.php` script content in the playbook if needed:
```php
$conn = new mysqli('10.0.1.X', 'web_user', 'password', 'mysql');
```
Replace `10.0.1.X`, `web_user`, and `password` with appropriate values.

## Troubleshooting

1. **Failed to Install `python3-pip`:**
   Ensure the server has internet connectivity and the correct repository is enabled.
   ```bash
   sudo apt update && sudo apt install -y python3-pip
   ```

2. **Network Unreachable Error:**
   Check DNS settings and network connectivity on the target server:
   ```bash
   ping 8.8.8.8
   ```

3. **MySQL Access Denied:**
   Ensure the root password is correctly set and included in the playbook where necessary.

## License
This project is licensed under the MIT License. See the `LICENSE` file for details.

## Author
Ram Ratan Yadav  
Location: Gurgaon, India
