# AWS DevSecOps Pipeline Infrastructure

Complete Terraform-based infrastructure for an automated DevSecOps pipeline on AWS with security scanning, governance monitoring, and self-healing capabilities.

## Architecture Overview

This project provisions:

**Core Pipeline:**
- GitHub repository integration via AWS CodeStar Connections
- 3-stage AWS CodePipeline: Source → Security Scan → Deploy
- CodeBuild projects for security scanning (Checkov/tfsec) and Terraform deployment
- S3 buckets for Terraform state and pipeline artifacts

**Security & Governance:**
- AWS Config rules monitoring S3 public access and Security Group configurations
- EventBridge rules capturing Config compliance changes
- Lambda-based self-healing automation for Security Group drift detection

**IAM Security:**
- Least-privilege IAM roles for all services
- Encrypted S3 buckets with versioning enabled
- CloudWatch logging for all pipeline activities

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured with credentials
3. **Terraform** >= 1.0 installed
4. **GitHub repository** containing your Terraform infrastructure code
5. **AWS workspace secrets** configured:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_DEFAULT_REGION`

## Setup Instructions

### Step 1: Create AWS CodeStar Connection to GitHub

The AWS CodeStar Connection enables secure webhook integration between GitHub and CodePipeline. This **must be created manually** before running Terraform.

**Via AWS Console:**

1. Navigate to [AWS CodeStar Connections](https://console.aws.amazon.com/codesuite/settings/connections)
2. Click **Create connection**
3. Select **GitHub** as the provider
4. Enter a connection name: `github-connection`
5. Click **Connect to GitHub**
6. Authorize AWS access to your GitHub account
7. Select the repositories to grant access to
8. Complete the installation
9. **Copy the Connection ARN** (format: `arn:aws:codestar-connections:REGION:ACCOUNT:connection/ID`)

**Via AWS CLI:**

```bash
# Create a pending connection
aws codestar-connections create-connection \
  --provider-type GitHub \
  --connection-name github-connection

# Note the ConnectionArn from the output
# You'll need to complete the handshake in the AWS Console (link will be provided)
```

After creation, the connection will be in `PENDING` state. You must complete the OAuth handshake via the AWS Console.

### Step 2: Configure Terraform Variables

1. Copy the example variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Edit `terraform.tfvars` and provide your values:

```hcl
aws_region  = "us-east-1"
project_name = "devsecops-pipeline"

# Your GitHub repository
github_repo = "your-username/your-repo-name"
github_branch = "main"

# CodeStar Connection ARN from Step 1
codestar_connection_arn = "arn:aws:codestar-connections:us-east-1:123456789012:connection/abc123..."

# Customize security rules for self-healing
golden_security_group_rules = [
  {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from anywhere"
  }
]
```

### Step 3: Initialize and Deploy Infrastructure

1. **Initialize Terraform:**

```bash
terraform init
```

Note: The S3 backend for state storage will be created by this Terraform configuration. On first run, state is stored locally. After the infrastructure is created, you can migrate to remote state:

2. **Review the execution plan:**

```bash
terraform plan
```

3. **Deploy the infrastructure:**

```bash
terraform apply
```

Review the changes and type `yes` to confirm.

4. **Migrate to S3 remote state (optional but recommended):**

After the first successful apply, uncomment the backend configuration in `provider.tf` and run:

```bash
# Get the S3 bucket name from outputs
BUCKET_NAME=$(terraform output -raw state_bucket_name)

# Re-initialize with S3 backend
terraform init \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="key=devsecops-pipeline/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -migrate-state
```

### Step 4: Verify Pipeline Setup

1. **Check CodePipeline status:**

```bash
aws codepipeline list-pipelines
aws codepipeline get-pipeline-state --name devsecops-pipeline-pipeline
```

2. **View pipeline in AWS Console:**

Navigate to [AWS CodePipeline Console](https://console.aws.amazon.com/codesuite/codepipeline/pipelines)

3. **Trigger the pipeline:**

Push a commit to your GitHub repository to trigger the pipeline automatically via webhook.

### Step 5: Test Self-Healing (Optional)

To test the self-healing automation:

1. **Create a test Security Group with self-healing enabled:**

```hcl
# Add to your Terraform code being deployed
resource "aws_security_group" "test_self_healing" {
  name_prefix = "test-self-healing-"
  description = "Test security group for self-healing demo"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from anywhere"
  }

  tags = {
    Name        = "test-self-healing-sg"
    SelfHealing = "true"  # This enables self-healing for this SG
  }
}
```

2. **Manually modify the security group** (to simulate drift):

```bash
# Add an unauthorized SSH rule
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

3. **Watch AWS Config detect the violation:**

Within 10-15 minutes, AWS Config will evaluate the security group and mark it as `NON_COMPLIANT`.

4. **Observe self-healing in action:**

- EventBridge captures the Config compliance change event
- Lambda function is triggered automatically
- Lambda reverts the security group rules to the golden state
- Check CloudWatch Logs for Lambda execution details:

```bash
aws logs tail /aws/lambda/devsecops-pipeline-self-healing --follow
```

## Pipeline Workflow

### Stage 1: Source
- Monitors GitHub repository for changes
- Triggers automatically on git push via CodeStar Connection webhook
- Downloads source code to CodePipeline artifacts S3 bucket

### Stage 2: Security Scan
- **CodeBuild project:** `devsecops-pipeline-security-scan`
- **Tools:** Checkov, tfsec
- **Process:**
  1. Install Checkov via pip and tfsec
  2. Run tfsec on Terraform code
  3. Run Checkov on Terraform code
  4. Execute `terraform plan` and convert to JSON
  5. Run Checkov on plan JSON for deep analysis
  6. Output security findings to CloudWatch Logs
- **Behavior:** Soft-fail mode (warnings don't block pipeline)

### Stage 3: Deploy
- **CodeBuild project:** `devsecops-pipeline-terraform-deploy`
- **Process:**
  1. Initialize Terraform with S3 backend
  2. Run `terraform plan`
  3. Apply Terraform changes with auto-approve
  4. Output results to CloudWatch Logs

## Security Features

### AWS Config Rules

1. **S3_BUCKET_PUBLIC_READ_PROHIBITED**
   - Monitors S3 buckets for public read access
   - Flags non-compliant buckets

2. **INCOMING_SSH_DISABLED**
   - Monitors Security Groups for unrestricted SSH (port 22)
   - Flags Security Groups allowing 0.0.0.0/0 on port 22

3. **RESTRICTED_INCOMING_TRAFFIC**
   - Monitors Security Groups for unrestricted access to common ports
   - Checks ports: 22 (SSH), 3389 (RDP), 3306 (MySQL), 5432 (PostgreSQL), 1433 (SQL Server)

### Self-Healing Lambda Function

**Trigger:** EventBridge rule listening for Config compliance change events with `NON_COMPLIANT` status

**Behavior:**
1. Receives Config compliance event
2. Checks if resource is a Security Group
3. Verifies Security Group has `SelfHealing = "true"` tag
4. Retrieves golden state rules from environment variable
5. Revokes all current ingress rules
6. Applies golden state rules
7. Logs actions to CloudWatch

**Safety Features:**
- Only processes resources explicitly tagged for self-healing
- Comprehensive error handling and logging
- Detailed CloudWatch logs for audit trail

## File Structure

```
.
├── provider.tf              # Terraform provider and backend configuration
├── variables.tf             # Input variables
├── outputs.tf               # Output values
├── main.tf                  # Main infrastructure resources
├── buildspec-security.yml   # CodeBuild spec for security scanning
├── buildspec-deploy.yml     # CodeBuild spec for Terraform deployment
├── lambda/
│   └── self_healing.py      # Lambda function for self-healing
├── terraform.tfvars.example # Example variables file
└── README.md                # This file
```

## Resource Naming Convention

All resources follow the pattern: `{project_name}-{resource-type}-{account-id}`

Example:
- S3 Bucket: `devsecops-pipeline-tfstate-123456789012`
- CodePipeline: `devsecops-pipeline-pipeline`
- Lambda: `devsecops-pipeline-self-healing`

## Cost Optimization

This infrastructure is designed for prototyping with Free Tier eligibility:

**Free Tier Resources:**
- CodeBuild: BUILD_GENERAL1_SMALL (100 build minutes/month free)
- Lambda: 1M requests/month free
- S3: 5GB storage, 20,000 GET requests free
- AWS Config: Limited free tier available
- CloudWatch Logs: 5GB ingestion, 5GB storage free

**Estimated Monthly Cost (beyond Free Tier):**
- CodeBuild: ~$0.005/minute (after 100 free minutes)
- AWS Config: ~$0.003/config rule evaluation
- S3: ~$0.023/GB/month
- Lambda: ~$0.20/1M requests (after free tier)

Total: ~$5-10/month for moderate usage

## Cleanup

To destroy all infrastructure:

```bash
terraform destroy
```

**Manual cleanup required:**
1. Delete the AWS CodeStar Connection via the AWS Console
2. Empty S3 buckets before destruction (Terraform won't delete non-empty buckets)

```bash
# Empty buckets
aws s3 rm s3://devsecops-pipeline-tfstate-ACCOUNT-ID --recursive
aws s3 rm s3://devsecops-pipeline-artifacts-ACCOUNT-ID --recursive
aws s3 rm s3://devsecops-pipeline-config-ACCOUNT-ID --recursive
```

## Troubleshooting

### Pipeline fails at Source stage

**Error:** `Connection is in PENDING state`

**Solution:** Complete the GitHub OAuth handshake in the AWS Console for the CodeStar Connection.

### Security scan phase fails

**Error:** `pip install checkov failed`

**Solution:** Check CodeBuild CloudWatch logs. Ensure the buildspec is using Python 3.12 runtime.

### Self-healing not triggering

**Checklist:**
1. Verify Security Group has `SelfHealing = "true"` tag
2. Check AWS Config is enabled and recording
3. Wait 10-15 minutes for Config evaluation
4. Check EventBridge rule is enabled
5. Review Lambda CloudWatch logs for errors

### Terraform state locking errors

**Error:** `Error acquiring the state lock`

**Solution:** Check for stuck DynamoDB state lock items (if using DynamoDB for locking) or ensure no other Terraform processes are running.

## References

- [AWS DevSecOps Blog - Security Checks with Terraform](https://aws.amazon.com/blogs/infrastructure-and-automation/save-time-with-automated-security-checks-of-terraform-scripts/)
- [AWS Security Response Automation](https://aws.amazon.com/blogs/security/how-get-started-security-response-automation-aws/)
- [AWS Security Hub CloudWatch Events](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-cloudwatch-events.html)
- [Checkov Documentation](https://www.checkov.io/documentation.html)
- [tfsec Documentation](https://aquasecurity.github.io/tfsec/)

## License

MIT License - See LICENSE file for details

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request
