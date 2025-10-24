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

## Validate & grade

Session Manager → ui/api/db:

sudo docker compose ps shows only the expected service per host.

Browser: open ui_url (e.g., http://<UI_PUBLIC_IP>:8080) — UI should load.

Path tests:

From ui host: nc -zv <DB_PRIVATE_IP> 3306 → fail (blocked).

From api host: nc -zv <DB_PRIVATE_IP> 3306 → success.

No SSH anywhere; all admin via SSM.

Rubric (example)

30% Infra: VPC + mgmt (Ch2), plus 3 EC2s + SG rules (Ch3)

30% Config: Docker installed via SSM, repo cloned, right services bound per host

20% Security: secrets in Parameter Store, SG micro-segmentation enforced

20% Documentation: diagram + commands + brief “what broke/how I fixed it”
