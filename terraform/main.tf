provider "aws" {
  region = "us-east-1"
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
  vpc_id        = "vpc-0feb480adeeba0347"  # Replace with your Master EC2 VPC ID
  peer_vpc_id   = aws_vpc.database_vpc.id
  auto_accept   = true

  tags = {
    Name = "Master-Database-VPC-Peering"
  }
}

# Route Table for Master EC2 VPC to Database VPC
resource "aws_route" "master_to_database" {
  route_table_id         = "rtb-04dd6c158fec5d70c"  # Replace with your Master EC2 VPC route table ID
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
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-Web"
  }
}

# Private Subnet for Database
resource "aws_subnet" "private_subnet_database" {
  vpc_id                  = aws_vpc.database_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
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
    cidr_blocks = ["10.0.2.0/24"]  # Bastion Host subnet
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
    Name = "MySQL-Security-Group"
  }
}

# Bastion Host Instance
resource "aws_instance" "bastion_host" {
  ami             = "ami-005fc0f236362e99f"
  instance_type   = "t2.micro"
  key_name        = "jenkins"
  subnet_id                   = aws_subnet.public_subnet_web.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]

user_data = <<-EOF
    #!/bin/bash
    # Update system and install Ansible dependencies
    sudo apt-get update -y
    sudo apt-get install -y python3 python3-pip
    sudo pip3 install boto3
  EOF

  tags = {
    Name = "Bastion-Host"
  }
}

# MySQL Instance
resource "aws_instance" "mysql_instance" {
  ami             = "ami-005fc0f236362e99f"
  instance_type   = "t2.micro"
  key_name        = "jenkins"
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
