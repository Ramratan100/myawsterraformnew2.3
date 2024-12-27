provider "aws" {
  region = "ap-northeast-1"
}

# VPC for Database
resource "aws_vpc" "database_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Database-VPC"
  }
}

# VPC Peering Connection
resource "aws_vpc_peering_connection" "vpc_peering" {
  vpc_id        = "vpc-00ec09536f7ae310f"  # Replace with your Master EC2 VPC ID
  peer_vpc_id   = aws_vpc.database_vpc.id
  auto_accept   = true

  tags = {
    Name = "Master-Database-VPC-Peering"
  }
}

# Route Table for Master EC2 VPC to Database VPC
resource "aws_route" "master_to_database" {
  route_table_id         = "rtb-0c82564b54a7fa492"  # Replace with your Master EC2 VPC route table ID
  destination_cidr_block = aws_vpc.database_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
}

# Route Table for Database VPC to Master EC2 VPC
resource "aws_route" "database_to_master" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "172.31.0.0/16"  # Master EC2 VPC CIDR
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
}

# Internet Gateway
resource "aws_internet_gateway" "database_igw" {
  vpc_id = aws_vpc.database_vpc.id

  tags = {
    Name = "Database-IGW"
  }
}

# Public Subnet for Web
resource "aws_subnet" "public_subnet_web" {
  vpc_id                  = aws_vpc.database_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-Web"
  }
}

# Private Subnet for Database
resource "aws_subnet" "private_subnet_database" {
  vpc_id                  = aws_vpc.database_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "Private-Subnet-Database"
  }
}

# NAT Gateway for Private Subnet
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "NAT-Gateway-EIP"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_web.id

  tags = {
    Name = "NAT-Gateway"
  }
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.database_vpc.id

  tags = {
    Name = "Private-Route-Table-Database"
  }
}

resource "aws_route" "private_to_internet" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}

resource "aws_route_table_association" "private_route_table_association" {
  subnet_id      = aws_subnet.private_subnet_database.id
  route_table_id = aws_route_table.private_route_table.id
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.database_vpc.id

  tags = {
    Name = "Public-Route-Table"
  }
}

resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.database_igw.id
}

resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet_web.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.database_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Bastion-Security-Group"
  }
}

resource "aws_security_group" "mysql_sg" {
  vpc_id = aws_vpc.database_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Bastion Host subnet
  }

ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
  from_port   = -1
  to_port     = -1
  protocol    = "icmp"
  cidr_blocks = ["10.0.2.0/24"]  # Replace with the CIDR block of the Bastion host
}

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "MySQL-Security-Group"
  }
}

# Bastion Host Instance
resource "aws_instance" "bastion_host" {
  ami             = "ami-0ac6b9b2908f3e20d"
  instance_type   = "t2.micro"
  key_name        = "tokyojenkins"
  subnet_id                   = aws_subnet.public_subnet_web.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]

user_data = <<-EOF
    #!/bin/bash

    # Update system and install required packages
    sudo apt-get update -y
    sudo apt-get install -y python3 python3-pip awscli apache2
    sudo apt install php-mysqli -y
    sudo apt install mysql-client-core-8.0

    # Install Python packages
    sudo pip3 install boto3

    # Create /home/ubuntu directory if it does not exist
    sudo mkdir -p /home/ubuntu

    # Download the private key (jenkins.pem) from the presigned URL
    wget "https://ramratan-bucket-2510.s3.amazonaws.com/jenkins.pem?AWSAccessKeyId=AKIAZ3MGMYHMT6M3VUVM&Signature=eApwyOpugPZnjl1LgQy%2FUHMAdBg%3D&Expires=1734595756" -O /home/ubuntu/jenkins.pem

    # Set the appropriate permissions for the private key
    sudo chmod 400 /home/ubuntu/jenkins.pem

    # Change the ownership of jenkins.pem to ubuntu
    sudo chown ubuntu:ubuntu /home/ubuntu/jenkins.pem

    # Fetch the private IP of the MySQL instance dynamically
    MYSQL_IP=$(aws ec2 describe-instances \
        --instance-ids ${aws_instance.mysql_instance.id} \
        --query "Reservations[].Instances[].PrivateIpAddress" \
        --output text)

    # Create a PHP test page to verify MySQL connectivity
    echo "<?php phpinfo(); ?>" | sudo tee /var/www/html/index.php
    echo "<?php
    // Enable error reporting for debugging
    ini_set('display_errors', 1);
    ini_set('display_startup_errors', 1);
    error_reporting(E_ALL);

    // Start the session
    session_start();

    // Check if the user is logged in
    if (!isset(\$_SESSION['logged_in']) || \$_SESSION['logged_in'] !== true) {
        header('Location: login.php'); // Redirect to login page if not logged in
        exit();
    }

    // Database connection parameters
    \$servername = \"$MYSQL_IP\";
    \$username = \"web_user\";
    \$password = \"password\";
    \$database = \"employees\";

    // Create connection
    \$conn = new mysqli(\$servername, \$username, \$password, \$database);

    // Check connection
    if (\$conn->connect_error) {
        die(\"Connection failed: \" . \$conn->connect_error);
    }

    // Handle form submission to add employee
    if (\$_SERVER[\"REQUEST_METHOD\"] == \"POST\" && isset(\$_POST['add_employee'])) {
        // Sanitize and validate input data
        \$name = mysqli_real_escape_string(\$conn, \$_POST['name']);
        \$email = mysqli_real_escape_string(\$conn, \$_POST['email']);
        \$department = mysqli_real_escape_string(\$conn, \$_POST['department']);
        \$salary = mysqli_real_escape_string(\$conn, \$_POST['salary']);
        \$hire_date = mysqli_real_escape_string(\$conn, \$_POST['hire_date']);
        \$position = mysqli_real_escape_string(\$conn, \$_POST['position']);

        // Ensure all fields are provided
        if (empty(\$name) || empty(\$email) || empty(\$department) || empty(\$salary) || empty(\$hire_date) || empty(\$position)) {
            \$message = \"All fields are required!\";
        } else {
            // Prepare and bind
            \$sql = \"INSERT INTO employee_data (name, email, department, salary, hire_date, position) 
                    VALUES ('\$name', '\$email', '\$department', '\$salary', '\$hire_date', '\$position')\";

            if (\$conn->query(\$sql) === TRUE) {
                \$message = \"New employee added successfully.\";
            } else {
                \$message = \"Error: \" . \$conn->error;
            }
        }
    }

    // Handle employee deletion
    if (isset(\$_GET['delete_id'])) {
        \$delete_id = \$_GET['delete_id'];
        
        // Delete the employee record
        \$sql = \"DELETE FROM employee_data WHERE id = \$delete_id\";
        if (\$conn->query(\$sql) === TRUE) {
            \$message = \"Employee deleted successfully.\";
        } else {
            \$message = \"Error: \" . \$conn->error;
        }
    }

    // Fetch employee data from MySQL
    \$sql = \"SELECT id, name, email, department, salary, hire_date, position FROM employee_data\";
    \$result = \$conn->query(\$sql);
    ?>

    <!DOCTYPE html>
    <html lang=\"en\">
    <head>
        <meta charset=\"UTF-8\">
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
        <title>Add Employee</title>
    </head>
    <body>
        <h2>Welcome to Employee Management</h2>

        <!-- Add Employee Form -->
        <h3>Add Employee Details</h3>
        <?php if (isset(\$message)) { echo \"<p style='color: green;'>\$message</p>\"; } ?>
        <form method=\"POST\" action=\"\">
            <label for=\"name\">Name:</label><br>
            <input type=\"text\" id=\"name\" name=\"name\" required><br><br>
            <label for=\"email\">Email:</label><br>
            <input type=\"email\" id=\"email\" name=\"email\" required><br><br>
            <label for=\"department\">Department:</label><br>
            <input type=\"text\" id=\"department\" name=\"department\" required><br><br>
            <label for=\"salary\">Salary:</label><br>
            <input type=\"text\" id=\"salary\" name=\"salary\" required><br><br>
            <label for=\"hire_date\">Hire Date:</label><br>
            <input type=\"date\" id=\"hire_date\" name=\"hire_date\" required><br><br>
            <label for=\"position\">Position:</label><br>
            <input type=\"text\" id=\"position\" name=\"position\" required><br><br>
            <input type=\"submit\" name=\"add_employee\" value=\"Add Employee\">
        </form>

        <!-- Display Employees -->
        <h3>Employee List</h3>
        <table border=\"1\">
            <tr>
                <th>ID</th>
                <th>Name</th>
                <th>Email</th>
                <th>Department</th>
                <th>Salary</th>
                <th>Hire Date</th>
                <th>Position</th>
                <th>Actions</th>
            </tr>
            <?php
            if (\$result->num_rows > 0) {
                while(\$row = \$result->fetch_assoc()) {
                    echo \"<tr>\";
                    echo \"<td>\" . \$row['id'] . \"</td>\";
                    echo \"<td>\" . \$row['name'] . \"</td>\";
                    echo \"<td>\" . \$row['email'] . \"</td>\";
                    echo \"<td>\" . \$row['department'] . \"</td>\";
                    echo \"<td>\" . \$row['salary'] . \"</td>\";
                    echo \"<td>\" . \$row['hire_date'] . \"</td>\";
                    echo \"<td>\" . \$row['position'] . \"</td>\";
                    echo \"<td><a href='?delete_id=\" . \$row['id'] . \"'>Delete</a></td>\";
                    echo \"</tr>\";
                }
            } else {
                echo \"<tr><td colspan='8'>No employees found</td></tr>\";
            }
            ?>
        </table>
    </body>
    </html>
  EOF

  tags = {
    Name = "Bastion-Host"
  }
}
# MySQL Instance
resource "aws_instance" "mysql_instance" {
  ami             = "ami-0ac6b9b2908f3e20d"
  instance_type   = "t2.micro"
  key_name        = "tokyojenkins"
  subnet_id              = aws_subnet.private_subnet_database.id
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]

user_data = <<-EOF
    #!/bin/bash
    # Update system and install Ansible dependencies
    sudo apt-get update -y
    sudo apt-get install -y python3 python3-pip
    sudo pip3 install boto3
  EOF

  tags = {
    Name = "MySQL-Instance"
  }
}
