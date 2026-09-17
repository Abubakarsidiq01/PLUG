# AWS staging setup — account handoff and what happens after

This is P0.S6 (manual.docx §27.1), owned by Person One. It has two halves that
are deliberately split: account creation, which only you can do (it needs your
identity, a payment method, and your acceptance of AWS's terms — none of which
an assistant should hold or agree to on your behalf), and everything after
that, which is ordinary infrastructure-as-code work that can be done for you
once you hand over scoped, limited credentials.

## Part A — only you can do this (~15 minutes)

### 1. Create the AWS account

1. Go to **[aws.amazon.com/free](https://aws.amazon.com/free)** and click **Create a Free Account** (or [console.aws.amazon.com](https://console.aws.amazon.com) → **Create a new AWS account** if you prefer starting from the sign-in page).
2. Enter the email you want billing and root alerts to go to, and an account name (e.g. "PLUG").
3. Verify the email (AWS sends a code).
4. Set a strong root password. **Save it in a password manager — this is the one account-recovery credential that can do literally anything, and it's the one thing you never hand to anyone, including me.**
5. Enter contact information, then a payment method. AWS requires a card even to stay entirely within the free tier — there's no way around that part. Check **[aws.amazon.com/free](https://aws.amazon.com/free)** for the current terms of what's free and for how long before assuming a number; AWS has changed this program's structure more than once. The architecture in Part B below is deliberately chosen to keep the running cost close to $0/month regardless — a few small things (see the cost table in Part B) aren't free-tier-eligible even so, on the order of $1–2/month total, not $12–15.
6. Choose the **Basic support plan** (free) unless you want paid support.
7. You'll land in the AWS Console once verification finishes (sometimes takes a few minutes).

### 2. Turn on a budget alert before doing anything else

1. In the console search bar, type **Billing** and open **Billing and Cost Management**.
2. Left sidebar → **Budgets** → **Create budget**.
3. Choose **Zero spend budget** or a **Cost budget** with a threshold like $30/month, alerting your email at 80% and 100%.
4. This doesn't cap spending, it just makes sure nothing runs up a bill silently — worth doing before any resource exists.

### 3. Create a scoped IAM user for infrastructure work

Don't use the root account for this, and don't create an access key for root — AWS itself warns against it.

1. Console search bar → **IAM** → **Users** (left sidebar) → **Create user**.
2. Name it something like `plug-terraform`.
3. **Do not** check "Provide user access to the AWS Management Console" — this user only needs programmatic (API) access.
4. On the permissions step, choose **Attach policies directly**, then click **Create policy** in a new tab and paste this — scoped to exactly the cheap EC2 + RDS design in Part B below (no ECS, load balancer, ECR, ACM or Route 53, since this design doesn't use any of those):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "NetworkAndInstance",
         "Effect": "Allow",
         "Action": [
           "ec2:*SecurityGroup*", "ec2:*Instance*", "ec2:*Address*",
           "ec2:*KeyPair*", "ec2:Describe*", "ec2:CreateTags", "ec2:DeleteTags"
         ],
         "Resource": "*"
       },
       {
         "Sid": "Database",
         "Effect": "Allow",
         "Action": ["rds:*"],
         "Resource": "*"
       },
       {
         "Sid": "ConfigAndSecrets",
         "Effect": "Allow",
         "Action": ["ssm:*Parameter*", "secretsmanager:*"],
         "Resource": "*"
       },
       {
         "Sid": "IamForInstanceRole",
         "Effect": "Allow",
         "Action": ["iam:CreateRole", "iam:DeleteRole", "iam:AttachRolePolicy",
                    "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
                    "iam:GetRole", "iam:PassRole", "iam:TagRole", "iam:ListRolePolicies",
                    "iam:ListAttachedRolePolicies", "iam:CreateInstanceProfile",
                    "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile",
                    "iam:RemoveRoleFromInstanceProfile"],
         "Resource": "*"
       },
       {
         "Sid": "TerraformStateBackend",
         "Effect": "Allow",
         "Action": ["s3:*", "dynamodb:*"],
         "Resource": "*"
       }
     ]
   }
   ```

   Name it `plug-terraform-policy`, create it, then go back to the user tab, refresh the policy list, and attach it.
5. Finish creating the user.
6. Open the new user → **Security credentials** tab → **Access keys** → **Create access key**.
7. Choose **Command Line Interface (CLI)**, acknowledge the warning, create it.
8. You'll see an **Access key ID** and a **Secret access key**. Copy both immediately — the secret is shown exactly once.

### 4. Hand it off

Give me the access key ID, secret access key, and your chosen AWS region (`us-east-1` is the unremarkable default unless you have a reason to pick another — e.g. proximity to Austin would suggest `us-east-1` or `us-east-2`). Paste them directly in chat, or — better — set them as environment variables before starting a session with me so they never appear in the transcript:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1
```

**If you'd rather run it yourself instead of handing over keys**, that's a completely reasonable call — skip to Part B and follow it directly; everything there is copy-pasteable.

## Part B — what happens once there are credentials (I do this, or you do, following the same steps)

You said budget is genuinely tight right now, so this is deliberately the
cheapest real design that still satisfies Phase 0 — not the fuller
production-grade setup (load balancer, private subnets behind a NAT gateway,
a purchased domain) that belongs later, around the phase where the app
actually needs to call out to Twilio/Apple/a model provider and where uptime
starts mattering for real users. A load balancer alone runs ~$16–20/month and
a NAT gateway ~$32/month **just for existing**, whether or not any traffic
uses them — neither is worth paying for to satisfy one connectivity gate.

**What Phase 0 actually needs:** one reachable HTTPS backend, a private
database, and a request ID visible in both an app log and a server log. That's it.

| Piece | Design choice | Why |
|---|---|---|
| Network | The account's **default VPC** (every AWS account already has one) | Skips building a custom VPC/subnet module entirely |
| Compute | One **EC2 t3.micro** (or `t4g.micro`), public IP, running the backend directly (no container registry, no orchestrator) | Free-tier-eligible; no ALB needed for one instance |
| HTTPS | **Caddy** reverse-proxying to the app, using the EC2 instance's own AWS-assigned public DNS name (`ec2-x-x-x-x.compute-1.amazonaws.com`) | Caddy gets a real Let's Encrypt certificate automatically — no domain purchase needed |
| Database | `infra/terraform/database.tf` (already written), `publicly_accessible = false`, security group only allows the EC2 instance's security group on 5432 | Private in the sense that matters (unreachable from the internet), without needing a NAT-gated private subnet |
| Secrets | **SSM Parameter Store** (`SecureString`, default AWS-managed key) for the app's runtime config, instead of a second Secrets Manager entry | Parameter Store is free; Secrets Manager charges per secret |
| State | S3 bucket + DynamoDB lock table | Pennies |

**The only line item that isn't free regardless of account age:** RDS's own
managed-master-password feature (`manage_master_user_password = true`,
already set in `database.tf`) stores that one password in Secrets Manager —
about $0.40/month. Total realistic cost: **roughly $0–2/month**, and the
budget alert from Part A catches it immediately if anything's misconfigured.

Steps, in order:

1. **Remote Terraform state** — S3 bucket + DynamoDB table for locking. `infra/terraform/versions.tf` has no backend configured yet; this is the first thing applied, before anything else.
2. **Security groups** in the default VPC — one for the EC2 instance (443 from anywhere, 22 from your IP only), one for the database (5432 from the EC2 security group only, nothing else).
3. **The database** — `infra/terraform/database.tf`, pointed at two of the default VPC's existing subnets (RDS requires two availability zones even for a single instance) and the new security group.
4. **The EC2 instance** — Amazon Linux 2023, `t3.micro`, an IAM instance role scoped to read its Parameter Store values, user-data that installs Docker + Caddy and pulls the backend image on boot.
5. **SSM parameters** — `PLUG_DATABASE_URL`, `PLUG_DATABASE_USER`, migration credentials, `PLUG_JWT_ISSUER`/`AUDIENCE` once Phase 1 needs them.
6. **Verify**: `curl https://<the-ec2-public-dns>/health` and `/health/ready` from your own machine (i.e., from outside AWS), confirm the database has *no* public route, then update `PROJECT_STATE.json.environments.staging` and `contracts/openapi.yaml`'s `servers:` entry to the real hostname.

Once you're ready and I (or you) have credentials: `cd infra/terraform && terraform init && terraform plan -out=phase0-staging.tfplan`. **Nothing gets applied without you seeing that plan first** — it lists every resource it would create. Review it, then `terraform apply phase0-staging.tfplan`.

**When it's worth upgrading past this:** once Twilio (Phase 3) needs a stable webhook URL, or once this stops being "one engineer's connectivity proof" and starts being something real users hit, move to a purchased domain + ALB + private subnets. Not before — that's paying for headroom nobody's using yet.
