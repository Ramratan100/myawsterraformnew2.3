provider "aws" {
  region = "us-east-1"  # Update as per your desired region
}

resource "aws_vpc_peering_connection" "vpc_peering" {
  peer_region = null  # Remove or set to null if auto_accept is true
  auto_accept = true
  ...
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  ...
}

# VPC Peering Connection
resource "aws_vpc_peering_connection" "vpc_peering" {
  vpc_id        = "vpc-0feb480adeeba0347" # Replace with your Master EC2 VPC ID (172.31.0.0/16)
  peer_vpc_id   = aws_vpc.database_vpc.id
  auto_accept   = true
  peer_region   = "us-east-1"

  tags = {
    Name = "Master-Database-VPC-Peering"
  }
}

# Route Table for Master EC2 VPC to route traffic to Database VPC
resource "aws_route" "master_to_database" {
  route_table_id         = "rtb-04dd6c158fec5d70c" # Replace with your Master EC2 VPC route table ID
  destination_cidr_block = "10.0.0.0/16"  # CIDR of Database VPC
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
}

# Route Table for Database VPC to route traffic to Master EC2 VPC
resource "aws_route" "database_to_master" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "172.31.0.0/16"  # CIDR of Master EC2 VPC
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering.id
}


# Create VPC for Database
resource "aws_vpc" "database_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Database-VPC"
  }
}

# Create a private subnet for MySQL in Database VPC
resource "aws_subnet" "private_subnet_database" {
  vpc_id            = aws_vpc.database_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "Private-Subnet-Database"
  }
}

# Create a public subnet for the Bastion Host in WebApp VPC
resource "aws_subnet" "public_subnet_web" {
  vpc_id            = aws_vpc.database_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-Web"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "database_igw" {
  vpc_id = aws_vpc.database_vpc.id

  tags = {
    Name = "Database-IGW"
  }
}

# Create a NAT Gateway for the private subnet internet access
resource "aws_eip" "nat_eip" {
  vpc = true

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

# Route table for the private subnet (using NAT Gateway for internet access)
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

# Associate Private Route Table with Private Subnet
resource "aws_route_table_association" "private_route_table_association" {
  subnet_id      = aws_subnet.private_subnet_database.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create a route table for the public subnet to the internet
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

# Associate Public Route Table with Public Subnet
resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet_web.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security group for Bastion Host
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-security-group"
  description = "Allow HTTP, HTTPS, and SSH access"
  vpc_id      = aws_vpc.database_vpc.id

ingress {
    from_port   = 80
    to_port     = 80
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
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH access from anywhere (or use your IP range)
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

# Security group for MySQL instance (Allow access from Bastion Host)
resource "aws_security_group" "mysql_sg" {
  name        = "mysql-security-group"
  description = "Allow access from Bastion Host"
  vpc_id      = aws_vpc.database_vpc.id

  # Allow ICMP (ping) from the Bastion Host subnet
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.2.0/24"]  # Allow ping from Bastion subnet
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]  # Allow MySQL access from Bastion Host
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]  # Allow SSH access from Bastion Host subnet
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

# Create Bastion Host in Public Subnet
resource "aws_instance" "bastion_host" {
  ami             = "ami-005fc0f236362e99f"  # Replace with your chosen AMI for Bastion Host
  instance_type   = "t2.micro"
  key_name        = "jenkins"
  subnet_id       = aws_subnet.public_subnet_web.id
  associate_public_ip_address = true  # Ensure this instance gets a public IP
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "Bastion-Host"
  }
  # User data script to install MySQL, PHP, and Apache
  user_data = <<-EOF
    #!/bin/bash
    # Update the system
    sudo apt update -y

    # Install Apache and PHP
    sudo apt install apache2 php libapache2-mod-php php-mysql -y

    # Restart Apache to apply PHP configuration
    sudo systemctl restart apache2

    # Create a PHP test file to verify installation
    echo "<?php phpinfo(); ?>" > /var/www/html/info.php

    # Create a simple PHP script to fetch data from MySQL and display it
    echo "<?php
    \$servername = '10.0.1.X';
    \$username = 'web_user';
    \$password = 'password';
    \$dbname = 'testdb';

    \$conn = new mysqli(\$servername, \$username, \$password, \$dbname);
    if (\$conn->connect_error) {
        die('Connection failed: ' . \$conn->connect_error);
    }

    \$sql = 'SELECT * FROM users';
    \$result = \$conn->query(\$sql);
    if (\$result->num_rows > 0) {
        while(\$row = \$result->fetch_assoc()) {
            echo 'id: ' . \$row['id'] . ' - Name: ' . \$row['name'] . '<br>';
        }
    } else {
        echo '0 results';
    }

    \$conn->close();
    ?>" > /var/www/html/db_test.php
  EOF
}

# Create MySQL EC2 instance in Private Subnet
resource "aws_instance" "mysql_instance" {
  ami             = "ami-005fc0f236362e99f"  # Replace with your AMI ID for MySQL
  instance_type   = "t2.micro"
  key_name        = "jenkins"
  subnet_id       = aws_subnet.private_subnet_database.id
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]

  tags = {
    Name = "MySQL-Instance"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y mysql-server
              systemctl start mysql
              systemctl enable mysql

              # Allow access to MySQL from anywhere (for user 'web_user')
              mysql -e "CREATE USER 'web_user'@'%' IDENTIFIED BY 'password';"
              mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'web_user'@'%';"
              mysql -e "FLUSH PRIVILEGES;"

              # Create a database and a sample table for testing
              mysql -e "CREATE DATABASE testdb;"
              mysql -e "USE testdb; CREATE TABLE users (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100));"
              mysql -e "USE testdb; INSERT INTO users (name) VALUES ('Test User');" 
              # Restart MySQL service to apply changes
              systemctl restart mysql
            EOF
}
