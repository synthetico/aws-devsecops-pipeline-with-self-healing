# Quick Start Guide

Get your AWS DevSecOps pipeline running in under 15 minutes.

## Prerequisites Checklist

- [ ] AWS account with admin access
- [ ] AWS CLI configured with credentials
- [ ] Terraform >= 1.0 installed
- [ ] GitHub repository created for your infrastructure code

## Step-by-Step Setup

### 1. Create CodeStar Connection (5 minutes)

**Option A: AWS Console (Recommended)**

1. Open [AWS CodeStar Connections](https://console.aws.amazon.com/codesuite/settings/connections)
2. Click **Create connection**
3. Choose **GitHub** → Name it `github-connection` → **Connect to GitHub**
4. Authorize AWS in the GitHub popup
5. **Copy the Connection ARN** (you'll need this next)

**Option B: AWS CLI**

```bash
aws codestar-connections create-connection \
  --provider-type GitHub \
  --connection-name github-connection
```

Then complete the OAuth flow in the AWS Console using the provided link.

### 2. Configure Variables (2 minutes)

```bash
# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Minimum required variables:**

```hcl
github_repo             = "your-username/your-repo-name"
codestar_connection_arn = "arn:aws:codestar-connections:us-east-1:123456789012:connection/abc123..."
```

### 3. Deploy Infrastructure (5 minutes)

```bash
# Initialize Terraform
terraform init

# Review plan
terraform plan

# Deploy (auto-approves after review)
terraform apply
```

Type `yes` when prompted.

### 4. Test the Pipeline (3 minutes)

**Trigger a pipeline run:**

```bash
# Make a change and push to GitHub
echo "# Test" >> test.txt
git add test.txt
git commit -m "Test pipeline trigger"
git push origin main
```

**Watch the pipeline:**

```bash
# Get pipeline status
aws codepipeline get-pipeline-state --name devsecops-pipeline-pipeline

# Or view in the console
open https://console.aws.amazon.com/codesuite/codepipeline/pipelines
```

## What Gets Created

**Pipeline Components:**
- CodePipeline with 3 stages (Source → Security Scan → Deploy)
- 2 CodeBuild projects (security scanning, Terraform deployment)
- 3 S3 buckets (state, artifacts, config data)

**Security & Governance:**
- AWS Config with 3 compliance rules
- EventBridge rule for compliance events
- Lambda function for self-healing
- CloudWatch log groups for all services

**IAM Roles:**
- CodePipeline execution role
- 2 CodeBuild execution roles
- AWS Config recorder role
- Lambda execution role

## Pipeline Behavior

**When you push to GitHub:**

1. **Source Stage**: CodePipeline detects the push via webhook
2. **Security Scan Stage**:
   - Installs Checkov and tfsec
   - Scans Terraform code for security issues
   - Runs `terraform plan` and scans the plan JSON
   - Outputs findings to CloudWatch (soft-fail mode)
3. **Deploy Stage**:
   - Runs `terraform plan`
   - Executes `terraform apply` automatically
   - Updates infrastructure

**Security scan in soft-fail mode means:**
- Security findings are logged but don't block deployment
- Review findings in CloudWatch Logs
- Perfect for prototyping

## Testing Self-Healing

**1. Create a test Security Group:**

Add to your Terraform code:

```hcl
resource "aws_security_group" "test" {
  name_prefix = "test-self-healing-"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "test-sg"
    SelfHealing = "true"  # Enables self-healing
  }
}
```

**2. Manually break it:**

```bash
# Get the security group ID
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=test-sg" \
  --query 'SecurityGroups[0].GroupId' --output text)

# Add unauthorized SSH access
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

**3. Watch it self-heal:**

```bash
# Monitor Lambda logs
aws logs tail /aws/lambda/devsecops-pipeline-self-healing --follow
```

Within 10-15 minutes, AWS Config will detect the violation, trigger EventBridge, invoke Lambda, and restore the security group to its golden state.

## Common Issues

### Pipeline stuck in "Source" stage

**Problem:** CodeStar Connection in PENDING state

**Fix:** Complete GitHub OAuth in AWS Console

### Security scan fails

**Problem:** Python/Checkov installation error

**Fix:** Check CodeBuild logs in CloudWatch. Verify buildspec is using Python 3.12

### Deploy fails with "backend not configured"

**Problem:** S3 backend not initialized

**Fix:** This is expected on first run. After infrastructure is created, migrate state:

```bash
BUCKET=$(terraform output -raw state_bucket_name)
terraform init \
  -backend-config="bucket=$BUCKET" \
  -backend-config="key=devsecops-pipeline/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -migrate-state
```

### Lambda not triggering

**Problem:** Self-healing not working

**Fix Checklist:**
- [ ] Security Group has `SelfHealing = "true"` tag
- [ ] AWS Config is enabled and recording
- [ ] EventBridge rule is enabled
- [ ] Lambda has correct permissions

Check Lambda logs:
```bash
aws logs tail /aws/lambda/devsecops-pipeline-self-healing
```

## Viewing Logs

**CodeBuild Security Scan:**
```bash
aws logs tail /aws/codebuild/devsecops-pipeline-security-scan/build-log
```

**CodeBuild Deploy:**
```bash
aws logs tail /aws/codebuild/devsecops-pipeline-terraform-deploy/build-log
```

**Lambda Self-Healing:**
```bash
aws logs tail /aws/lambda/devsecops-pipeline-self-healing
```

## Cost Estimate

**Free Tier Usage:**
- CodeBuild: 100 build minutes/month free
- Lambda: 1M requests/month free
- S3: 5GB storage free
- CloudWatch: 5GB logs free

**After Free Tier:**
- ~$5-10/month for moderate usage (5-10 pipeline runs/day)
- CodeBuild: $0.005/minute
- AWS Config: $0.003/evaluation
- S3 storage: $0.023/GB/month

## Next Steps

**Production Hardening:**
1. Enable security scan failures to block deployment
2. Add manual approval stage before Deploy
3. Implement DynamoDB state locking
4. Add SNS notifications for pipeline failures
5. Configure AWS Backup for S3 state bucket

**Enhanced Security:**
1. Add more AWS Config rules
2. Integrate with AWS Security Hub
3. Add SAST/DAST scanning tools
4. Implement secrets scanning (git-secrets, truffleHog)

**Monitoring:**
1. Create CloudWatch dashboards
2. Set up alarms for pipeline failures
3. Configure X-Ray tracing for Lambda

## Cleanup

**To destroy everything:**

```bash
# Empty S3 buckets first
aws s3 rm s3://$(terraform output -raw state_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw artifacts_bucket_name) --recursive

# Destroy infrastructure
terraform destroy

# Manually delete CodeStar Connection in AWS Console
```

## Support

**Check these resources:**
- [Full README](./README.md) - Detailed documentation
- [AWS CodePipeline Docs](https://docs.aws.amazon.com/codepipeline/)
- [Checkov Documentation](https://www.checkov.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

**Troubleshooting:**
1. Check CloudWatch logs for detailed error messages
2. Review AWS Config compliance dashboard
3. Verify IAM role permissions
4. Ensure all required tags are present
