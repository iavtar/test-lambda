# test-lambda

A Quarkus-based AWS Lambda function that greets a person by name, deployed inside a VPC using Terraform.

---

## Project structure

```
test-lambda/
├── src/main/java/com/iavtar/lambda/
│   ├── GreetingLambda.java      # Lambda handler
│   └── Person.java              # Input model
├── src/main/resources/
│   └── application.properties   # quarkus.lambda.handler=greeting
├── infrastructure/
│   ├── backend.tf               # S3 remote state + DynamoDB lock
│   ├── provider.tf              # AWS provider
│   ├── variables.tf             # All configurable values
│   ├── vpc.tf                   # VPC, subnets, IGW, NAT gateways, route tables
│   ├── lambda.tf                # IAM role, security group, Lambda function, CloudWatch log group
│   └── outputs.tf               # Printed values after apply
├── build.gradle
└── README.md
```

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Java | 21 | [Adoptium](https://adoptium.net) |
| Gradle | bundled (`./gradlew`) | — |
| Terraform | >= 1.6 | [terraform.io/downloads](https://developer.hashicorp.com/terraform/downloads) |
| AWS CLI | any | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |

### AWS credentials

Configure credentials before running Terraform:

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, region (ap-south-1), output format (json)
```

Or use environment variables:

```bash
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_DEFAULT_REGION=ap-south-1
```

### Required pre-existing AWS resources

The Terraform backend in `infrastructure/backend.tf` expects these to already exist in `ap-south-1`:

| Resource | Name |
|---|---|
| S3 bucket (for state) | `gfj-prod-tfstate` |
| DynamoDB table (for locking) | `dev-terraform-lock` |

Create them once if they don't exist:

```bash
aws s3api create-bucket \
  --bucket gfj-prod-tfstate \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

aws s3api put-bucket-versioning \
  --bucket gfj-prod-tfstate \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name dev-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```

---

## Step 1 — Build the Lambda artifact

Quarkus produces `build/function.zip` which Terraform uploads to Lambda.

```bash
./gradlew build
```

Verify the zip was created:

```bash
ls build/function.zip
```

---

## Step 2 — Deploy infrastructure

```bash
cd infrastructure
```

### 2a. Init — connect to the S3 backend and download providers

```bash
terraform init
```

Expected output:

```
Initializing the backend...
Successfully configured the backend "s3"!

Initializing provider plugins...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

### 2b. Plan — preview what will be created

```bash
terraform plan
```

This creates no resources. Review the output and confirm the list matches what you expect.

### 2c. Apply — create all resources

```bash
terraform apply
```

Type `yes` when prompted. The full apply takes ~3–5 minutes (NAT gateways are the slowest).

---

## What Terraform creates

### VPC (`vpc.tf`)

```
10.0.0.0/16  (ap-south-1)
├── public  10.0.1.0/24   (ap-south-1a)  ← NAT Gateway 1
├── public  10.0.2.0/24   (ap-south-1b)  ← NAT Gateway 2
├── private 10.0.101.0/24 (ap-south-1a)  ← Lambda ENIs
└── private 10.0.102.0/24 (ap-south-1b)  ← Lambda ENIs
```

| Resource | Purpose |
|---|---|
| VPC | Network boundary |
| Internet Gateway | Public subnet internet access |
| NAT Gateways (x2) | Private subnet outbound internet |
| Elastic IPs (x2) | Static IPs for NAT gateways |
| Public route table | Routes 0.0.0.0/0 → IGW |
| Private route tables (x2) | Routes 0.0.0.0/0 → NAT GW per AZ |

### Lambda (`lambda.tf`)

| Resource | Purpose |
|---|---|
| IAM Role | Identity the Lambda assumes at runtime |
| `AWSLambdaBasicExecutionRole` | Permission to write logs to CloudWatch |
| `AWSLambdaVPCAccessExecutionRole` | Permission to create/delete ENIs in the VPC |
| Security Group | Controls Lambda egress (all outbound allowed) |
| CloudWatch Log Group | `/aws/lambda/test-lambda-greeting` — 1 day retention |
| Lambda Function | The Quarkus greeting handler running on Java 21 |

---

## How CloudWatch logging works

Lambda automatically pipes all stdout/stderr to CloudWatch — no SDK calls needed in your Java code.

```
GreetingLambda (stdout / java.util.logging / Quarkus logs)
        │
        ▼  captured by Lambda runtime
        │
        ▼  IAM: AWSLambdaBasicExecutionRole
        │   logs:CreateLogGroup
        │   logs:CreateLogStream
        │   logs:PutLogEvents
        │
        ▼
CloudWatch Log Group: /aws/lambda/test-lambda-greeting
        └── Log Stream: one stream per Lambda container instance
```

View logs:

```bash
aws logs tail /aws/lambda/test-lambda-greeting --follow --region ap-south-1
```

---

## Step 3 — Test the deployed Lambda

```bash
aws lambda invoke \
  --function-name test-lambda-greeting \
  --payload '{"name":"World"}' \
  --cli-binary-format raw-in-base64-out \
  --region ap-south-1 \
  response.json

cat response.json
# "Hello World"
```

---

## Customising variables

Override any default by passing `-var` flags or creating a `terraform.tfvars` file:

```hcl
# infrastructure/terraform.tfvars
aws_region             = "ap-south-1"
project_name           = "test-lambda"
lambda_memory_mb       = 1024
lambda_timeout_seconds = 60
log_retention_days     = 1
```

Then apply:

```bash
terraform apply -var-file="terraform.tfvars"
```

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `ap-south-1` | AWS region |
| `project_name` | `test-lambda` | Prefix for all resource names |
| `vpc_cidr` | `10.0.0.0/16` | VPC address space |
| `public_subnet_cidrs` | `["10.0.1.0/24","10.0.2.0/24"]` | Public subnet CIDRs |
| `private_subnet_cidrs` | `["10.0.101.0/24","10.0.102.0/24"]` | Private subnet CIDRs (Lambda) |
| `availability_zones` | `["ap-south-1a","ap-south-1b"]` | AZs to spread across |
| `lambda_memory_mb` | `512` | Lambda memory in MB |
| `lambda_timeout_seconds` | `30` | Lambda timeout in seconds |
| `log_retention_days` | `1` | CloudWatch log retention (minimum) |

---

## Outputs

After `terraform apply`, these values are printed:

| Output | Description |
|---|---|
| `vpc_id` | VPC ID |
| `public_subnet_ids` | Public subnet IDs |
| `private_subnet_ids` | Private subnet IDs |
| `lambda_security_group_id` | Lambda security group ID |
| `lambda_function_name` | Lambda function name |
| `lambda_function_arn` | Lambda function ARN |
| `lambda_role_arn` | IAM role ARN |

Retrieve them any time:

```bash
terraform output
```

---

## Redeploying after code changes

```bash
# 1. Rebuild the artifact
./gradlew build

# 2. Apply — Terraform detects the zip hash changed and redeploys
cd infrastructure
terraform apply
```

---

## Teardown

Destroy all resources created by Terraform:

```bash
cd infrastructure
terraform destroy
```

Type `yes` when prompted. This does **not** delete the S3 bucket or DynamoDB table used for state.
