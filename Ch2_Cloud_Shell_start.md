# Pick region & prep workspace
export AWS_REGION=us-east-1
aws configure set region $AWS_REGION
mkdir -p ~/mizzou/arculus/ch2 && cd ~/mizzou/arculus/ch2

# Install Terraform into CloudShell (one-time)
TFV=1.9.5
curl -LO https://releases.hashicorp.com/terraform/${TFV}/terraform_${TFV}_linux_amd64.zip
unzip -o terraform_${TFV}_linux_amd64.zip && sudo mv terraform /usr/local/bin/ && terraform -version
