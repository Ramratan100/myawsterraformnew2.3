provider "aws" {
  region = "us-east-1"
}

# VPC Configuration
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

# Subnets
resource "aws_subnet" "public_subnets" {
  count             = 2
  vpc_id            = aws_vpc.database_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.database_vpc.cidr_block, 8, count.index)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 2
  vpc_id            = aws_vpc.database_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.database_vpc.cidr_block, 8, count.index + 2)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "Private-Subnet-${count.index + 1}"
  }
}

# Route Tables
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

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# NAT Gateway for Private Subnets
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name = "NAT-Gateway"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.database_vpc.id

  tags = {
    Name = "Private-Route-Table"
  }
}

resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
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
    Name = "Bastion-SG"
  }
}

resource "aws_security_group" "mysql_sg" {
  vpc_id = aws_vpc.database_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Private subnet CIDR block
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
    Name = "MySQL-SG"
  }
}

# Bastion Host Instance
resource "aws_instance" "bastion_host" {
  ami             = "ami-005fc0f236362e99f"
  instance_type   = "t2.micro"
  key_name        = "jenkins"
  subnet_id       = aws_subnet.public_subnets[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "Bastion-Host"
  }
}

# MySQL Instance (Primary)
resource "aws_instance" "mysql_instance" {
  ami             = "ami-005fc0f236362e99f"
  instance_type   = "t2.micro"
  key_name        = "jenkins"
  subnet_id       = aws_subnet.private_subnets[0].id
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]

  tags = {
    Name = "MySQL-Instance"
  }
}

# MySQL Instance (Secondary)
resource "aws_instance" "mysql_instance_2" {
  ami             = aws_ami.mysql_ami.id
  instance_type   = "t2.micro"
  key_name        = "jenkins"
  subnet_id       = aws_subnet.private_subnets[1].id
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]

  tags = {
    Name = "Secondary-MySQL-Instance"
  }
}

# MySQL Load Balancer
resource "aws_lb" "mysql_lb" {
  name               = "mysql-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.mysql_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "MySQL-LB"
  }
}

resource "aws_lb_target_group" "mysql_tg" {
  name        = "mysql-target-group"
  port        = 3306
  protocol    = "TCP"
  vpc_id      = aws_vpc.database_vpc.id
}

resource "aws_lb_listener" "mysql_listener" {
  load_balancer_arn = aws_lb.mysql_lb.arn
  port              = 3306
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mysql_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "mysql_instance_1" {
  target_group_arn = aws_lb_target_group.mysql_tg.arn
  target_id        = aws_instance.mysql_instance.id
  port             = 3306
}

resource "aws_lb_target_group_attachment" "mysql_instance_2" {
  target_group_arn = aws_lb_target_group.mysql_tg.arn
  target_id        = aws_instance.mysql_instance_2.id
  port             = 3306
}

# Outputs
output "mysql_load_balancer_dns" {
  description = "DNS of the MySQL load balancer"
  value       = aws_lb.mysql_lb.dns_name
}

output "bastion_host_ip" {
  description = "Public IP of Bastion Host"
  value       = aws_instance.bastion_host.public_ip
}
