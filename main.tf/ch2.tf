terraform { required_version = ">= 1.6.0" }
provider "aws" { region = var.region }

variable "region"        { default = "us-east-1" }
variable "vpc_cidr"      { default = "10.42.0.0/16" }
variable "subnet_cidr"   { default = "10.42.1.0/24" }
variable "instance_type" { default = "t3.small" }
variable "project"       { default = "arculus" }

# Network (public subnet for demo)
resource "aws_vpc" "v" { cidr_block = var.vpc_cidr  enable_dns_hostnames = true  tags = { project = var.project } }
resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.v.id }
resource "aws_subnet" "pub" { vpc_id = aws_vpc.v.id cidr_block = var.subnet_cidr map_public_ip_on_launch = true }
resource "aws_route_table" "rt" { vpc_id = aws_vpc.v.id route { cidr_block="0.0.0.0/0" gateway_id=aws_internet_gateway.igw.id } }
resource "aws_route_table_association" "a" { subnet_id = aws_subnet.pub.id route_table_id = aws_route_table.rt.id }

# Security Group: no inbound (we'll manage via SSM), allow egress
resource "aws_security_group" "mgmt" {
  name  = "sg-mgmt"  vpc_id = aws_vpc.v.id
  egress { from_port=0 to_port=0 protocol="-1" cidr_blocks=["0.0.0.0/0"] }
  tags = { role="mgmt", project = var.project }
}

# IAM for SSM
data "aws_iam_policy_document" "trust" {
  statement { actions=["sts:AssumeRole"] principals { type="Service" identifiers=["ec2.amazonaws.com"] } }
}
resource "aws_iam_role" "ec2" { name="${var.project}-mgmt-role" assume_role_policy = data.aws_iam_policy_document.trust.json }
resource "aws_iam_role_policy_attachment" "ssm" {
  role = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "ip" { name="${var.project}-mgmt-ip" role = aws_iam_role.ec2.name }

# Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["099720109477"]
  filter { name="name" values=["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"] }
}

# EC2 (no user_data; we’ll configure in Chapter 3 via SSM)
resource "aws_instance" "mgmt" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.pub.id
  vpc_security_group_ids = [aws_security_group.mgmt.id]
  iam_instance_profile = aws_iam_instance_profile.ip.name
  associate_public_ip_address = true
  tags = { Name="mgmt", role="mgmt", project=var.project }
}

output "vpc_id"           { value = aws_vpc.v.id }
output "subnet_id"        { value = aws_subnet.pub.id }
output "mgmt_instance_id" { value = aws_instance.mgmt.id }
output "mgmt_public_ip"   { value = aws_instance.mgmt.public_ip }
