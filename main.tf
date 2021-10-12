#terraform {
#  required_providers {
#    aws = {
#      source  = "hashicorp/aws"
#      version = "~> 3.0"
#    }
#  }
#}

#create variable
#the value is automatically gets from terraform.tfvars file
variable "subnet_prefix" {
  description = "cidr block for the subnet"
  #default = ""
  type = string
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  access_key = "acess_key"
  secret_key = "secret_key"
}

#1. Create vpc
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
}

#2. Create internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

#3. Create route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    "Name" = "prod"
  }
}

#4. Create subnet
resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod-vpc.id
  cidr_block = var.subnet_prefix
  availability_zone = "us-east-1a"


  tags = {
    "Name" = "prod-subnet"
  }
}

#5. Associate subnet with routetable
resource "aws_route_table_association" "association" {
  subnet_id = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

#6. Create security groups (allow port 22, 80, 443)
resource "aws_security_group" "allow_web" {
  name = "allow_web_trafic"
  description = "Allow web trafic"
  vpc_id = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTPS"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  tags = {
    Name = "Allow web"
  }
}

#7. Create networking interface with an ip in subnet created (step 4)
resource "aws_network_interface" "web-server-nic" {
  subnet_id = aws_subnet.subnet-1.id
  private_ips = ["10.0.1.50"]
  security_groups = [ aws_security_group.allow_web.id ]
}


#8. Assing an elastic IP to the networking interface created (step 7)
resource "aws_eip" "ip" {
  vpc = true
  network_interface = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

#print something
output "server_public_ip" {
  value = aws_eip.ip.public_ip
}

#9. Create ubuntu server and install/enable apache2
resource "aws_instance" "web-server-instance" {
  ami = "ami-09e67e426f25ce0d7"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "myec2"
  
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c 'echo your very first web server > /var/www/html/index.html'
              EOF

  tags = {
    "Name" = "web server"
  }
}
