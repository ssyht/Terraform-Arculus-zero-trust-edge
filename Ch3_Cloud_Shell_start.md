## Student steps (CloudShell)
```
mkdir -p ~/mizzou/arculus/ch3 && cd ~/mizzou/arculus/ch3
```

## After copying/pasting the command for chapter 3 main.tf file: 

```
terraform init
terraform apply -auto-approve \
  -var vpc_id="$(cd ../ch2 && terraform output -raw vpc_id)" \
  -var subnet_id="$(cd ../ch2 && terraform output -raw subnet_id)" \
  -var mgmt_instance_id="$(cd ../ch2 && terraform output -raw mgmt_instance_id)"
```
