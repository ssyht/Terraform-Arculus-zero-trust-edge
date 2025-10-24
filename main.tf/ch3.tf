terraform { required_version = ">= 1.6.0" }
provider "aws" { region = var.region }

variable "region"         { default = "us-east-1" }
variable "project"        { default = "arculus" }
variable "vpc_id"         { description = "Paste from ch2 output" }
variable "subnet_id"      { description = "Paste from ch2 output" }
variable "mgmt_instance_id" { description = "Paste from ch2 output" }
variable "instance_type"  { default = "t3.small" }
variable "ui_port"        { default = 8080 }
variable "api_port"       { default = 8080 }
variable "allow_web_cidr" { default = "0.0.0.0/0" } # tighten to /32 in class

# 3.1 Configure the Chapter-2 MGMT host via SSM (install Docker, clone repo)
resource "aws_ssm_document" "cfg_mgmt" {
  name          = "Arculus-Configure-Mgmt"
  document_type = "Command"
  content = jsonencode({
    schemaVersion = "2.2",
    description   = "Install Docker & clone arculus-sw on MGMT",
    mainSteps = [{
      action = "aws:runShellScript", name = "cfg", inputs = { runCommand = [
        "set -euxo pipefail",
        "sudo apt-get update -y",
        "sudo apt-get install -y git ca-certificates curl gnupg lsb-release",
        "sudo install -m 0755 -d /etc/apt/keyrings",
        "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
        "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release; echo $UBUNTU_CODENAME) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
        "sudo apt-get update -y",
        "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin awscli",
        "sudo usermod -aG docker ubuntu || true",
        "cd /opt && sudo git clone https://github.com/arculus-zt/arculus-sw.git || true",
        "cd /opt/arculus-sw && sudo git pull --ff-only || true",
        "sudo chmod +x /opt/arculus-sw/arculus-setup.sh",
        "cd /opt/arculus-sw && sudo docker compose config --services || true"
      ]}}
    ]}
  })
}
resource "aws_ssm_association" "cfg_mgmt_now" {
  name   = aws_ssm_document.cfg_mgmt.name
  targets = [{ key = "InstanceIds", values = [var.mgmt_instance_id] }]
}

# 3.2 IAM for the three new instances (SSM + read /arculus/* params)
data "aws_iam_policy_document" "trust" {
  statement { actions=["sts:AssumeRole"] principals { type="Service" identifiers=["ec2.amazonaws.com"] } }
}
resource "aws_iam_role" "tier" { name="${var.project}-tier-role" assume_role_policy=data.aws_iam_policy_document.trust.json }
resource "aws_iam_role_policy_attachment" "ssm" {
  role = aws_iam_role.tier.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
data "aws_caller_identity" "me" {}
resource "aws_iam_policy" "ps_read" {
  name = "${var.project}-ps-read"
  policy = jsonencode({
    Version="2012-10-17",
    Statement=[{
      Effect="Allow",
      Action=["ssm:GetParameter","ssm:GetParameters","ssm:GetParametersByPath"],
      Resource="arn:aws:ssm:${var.region}:${data.aws_caller_identity.me.account_id}:parameter/arculus/*"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "attach_read" {
  role = aws_iam_role.tier.name
  policy_arn = aws_iam_policy.ps_read.arn
}
resource "aws_iam_instance_profile" "tier" { name="${var.project}-tier-ip" role=aws_iam_role.tier.name }

# 3.3 Security Groups (micro-segmentation)
resource "aws_security_group" "ui"  { name="sg-ui"  vpc_id=var.vpc_id }
resource "aws_security_group" "api" { name="sg-api" vpc_id=var.vpc_id }
resource "aws_security_group" "db"  { name="sg-db"  vpc_id=var.vpc_id }

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  security_group_id = aws_security_group.ui.id
  ip_protocol="tcp" from_port=var.ui_port to_port=var.ui_port
  cidr_ipv4 = var.allow_web_cidr
}
resource "aws_vpc_security_group_egress_rule" "ui_to_api" {
  security_group_id = aws_security_group.ui.id
  ip_protocol="tcp" from_port=var.api_port to_port=var.api_port
  referenced_security_group_id = aws_security_group.api.id
}
resource "aws_vpc_security_group_ingress_rule" "api_from_ui" {
  security_group_id = aws_security_group.api.id
  ip_protocol="tcp" from_port=var.api_port to_port=var.api_port
  referenced_security_group_id = aws_security_group.ui.id
}
resource "aws_vpc_security_group_egress_rule" "api_to_db" {
  security_group_id = aws_security_group.api.id
  ip_protocol="tcp" from_port=3306 to_port=3306
  referenced_security_group_id = aws_security_group.db.id
}
resource "aws_vpc_security_group_ingress_rule" "db_from_api" {
  security_group_id = aws_security_group.db.id
  ip_protocol="tcp" from_port=3306 to_port=3306
  referenced_security_group_id = aws_security_group.api.id
}
# (Keep API/DB default egress for package pulls; replace with VPC endpoints in a later chapter)

# 3.4 Secrets in Parameter Store
resource "random_password" "db_root" { length=16 special=false }
resource "random_password" "db_app"  { length=16 special=false }
resource "aws_ssm_parameter" "root" { name="/arculus/db/mysql_root_password" type="SecureString" value=random_password.db_root.result }
resource "aws_ssm_parameter" "app"  { name="/arculus/db/app_password"  type="SecureString" value=random_password.db_app.result }

# 3.5 Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners=["099720109477"]
  filter { name="name" values=["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"] }
}

# 3.6 EC2s: ui, api, db (no user_data; configure via SSM)
resource "aws_instance" "ui" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ui.id]
  iam_instance_profile = aws_iam_instance_profile.tier.name
  associate_public_ip_address = true
  tags = { Name="ui", role="ui", project=var.project }
}
resource "aws_instance" "api" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = var.subnet_id
  vpc_security_group_ids = [aws_security_group.api.id]
  iam_instance_profile = aws_iam_instance_profile.tier.name
  associate_public_ip_address = true
  tags = { Name="api", role="api", project=var.project }
}
resource "aws_instance" "db" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id = var.subnet_id
  vpc_security_group_ids = [aws_security_group.db.id]
  iam_instance_profile = aws_iam_instance_profile.tier.name
  associate_public_ip_address = false
  tags = { Name="db", role="db", project=var.project }
}

# 3.7 Publish API/DB hosts to Parameter Store (for UI/API to read)
resource "aws_ssm_parameter" "api_host" { name="/arculus/api/host" type="SecureString" value=aws_instance.api.private_ip }
resource "aws_ssm_parameter" "api_port" { name="/arculus/api/port" type="SecureString" value=tostring(var.api_port) }
resource "aws_ssm_parameter" "db_host"  { name="/arculus/db/host"  type="SecureString" value=aws_instance.db.private_ip }

# 3.8 SSM Documents per role — install Docker + clone repo + run only the right service
locals {
  common = [
    "set -euxo pipefail",
    "sudo apt-get update -y",
    "sudo apt-get install -y git ca-certificates curl gnupg lsb-release awscli",
    "sudo install -m 0755 -d /etc/apt/keyrings",
    "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
    "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release; echo $UBUNTU_CODENAME) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
    "sudo apt-get update -y",
    "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
    "sudo usermod -aG docker ubuntu || true",
    "cd /opt && sudo git clone https://github.com/arculus-zt/arculus-sw.git || true",
    "cd /opt/arculus-sw && sudo git pull --ff-only || true",
    "sudo chmod +x /opt/arculus-sw/arculus-setup.sh",
    "cd /opt/arculus-sw && sudo ./arculus-setup.sh || true",
    "cd /opt/arculus-sw && sudo docker compose config --services || true"
  ]
}

resource "aws_ssm_document" "cfg_db" {
  name="Arculus-DB-Configure" document_type="Command"
  content = jsonencode({ schemaVersion="2.2", mainSteps=[{
    action="aws:runShellScript", name="db", inputs={ runCommand = concat(local.common, [
      "ROOT=$(aws ssm get-parameter --name /arculus/db/mysql_root_password --with-decryption --query Parameter.Value --output text)",
      "APP=$(aws ssm get-parameter --name /arculus/db/app_password --with-decryption --query Parameter.Value --output text)",
      "# Adjust service name if compose uses a different one than 'mysql'",
      "cd /opt/arculus-sw && sudo MYSQL_ROOT_PASSWORD=$ROOT MYSQL_PASSWORD=$APP docker compose up -d mysql"
    ])}
  }]})
}
resource "aws_ssm_document" "cfg_api" {
  name="Arculus-API-Configure" document_type="Command"
  content = jsonencode({ schemaVersion="2.2", mainSteps=[{
    action="aws:runShellScript", name="api", inputs={ runCommand = concat(local.common, [
      "DBH=$(aws ssm get-parameter --name /arculus/db/host --with-decryption --query Parameter.Value --output text)",
      "DBP=$(aws ssm get-parameter --name /arculus/db/mysql_root_password --with-decryption --query Parameter.Value --output text)",
      "# Adjust service name if compose uses a different one than 'api'",
      "cd /opt/arculus-sw && sudo DB_HOST=$DBH DB_USER=root DB_PASSWORD=$DBP DB_PORT=3306 docker compose up -d api"
    ])}
  }]})
}
resource "aws_ssm_document" "cfg_ui" {
  name="Arculus-UI-Configure" document_type="Command"
  content = jsonencode({ schemaVersion="2.2", mainSteps=[{
    action="aws:runShellScript", name="ui", inputs={ runCommand = concat(local.common, [
      "APH=$(aws ssm get-parameter --name /arculus/api/host --with-decryption --query Parameter.Value --output text)",
      "APP=$(aws ssm get-parameter --name /arculus/api/port --with-decryption --query Parameter.Value --output text)",
      "# Adjust service name if compose uses a different one than 'ui'",
      "cd /opt/arculus-sw && sudo API_URL=http://$APH:$APP docker compose up -d ui"
    ])}
  }]})
}

# Run them now
resource "aws_ssm_association" "db_now"  { name=aws_ssm_document.cfg_db.name  targets=[{key="InstanceIds", values=[aws_instance.db.id]}] }
resource "aws_ssm_association" "api_now" { name=aws_ssm_document.cfg_api.name targets=[{key="InstanceIds", values=[aws_instance.api.id]}] }
resource "aws_ssm_association" "ui_now"  { name=aws_ssm_document.cfg_ui.name  targets=[{key="InstanceIds", values=[aws_instance.ui.id]}] }

output "ui_public_ip"  { value = aws_instance.ui.public_ip }
output "ui_url"        { value = "http://${aws_instance.ui.public_ip}:${var.ui_port}" }
output "api_private_ip"{ value = aws_instance.api.private_ip }
output "db_private_ip" { value = aws_instance.db.private_ip }
