# Deployment Guide: GitHub → AWS Infrastructure

This guide explains how to push your code to GitHub and deploy the infrastructure to AWS.

## Overview

**Workflow:**
1. Push Terraform code to GitHub repository
2. Deploy infrastructure from your local machine using Terraform CLI
3. After deployment, the pipeline will auto-trigger on future git pushes

**Important:** The first deployment must be done locally via Terraform CLI, not through the pipeline. This is because the pipeline infrastructure (CodePipeline, CodeBuild, etc.) doesn't exist yet.

## Step 1: Initialize Git Repository (if not already done)

```bash
# Initialize git repository
git init

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit: AWS DevSecOps pipeline infrastructure

- Complete Terraform configuration for CI/CD pipeline
- Security scanning with Checkov and tfsec
- AWS Config compliance monitoring
- Lambda-based self-healing for Security Groups
- Full documentation and quickstart guide
"
```

## Step 2: Push to GitHub

```bash
# Add your GitHub repository as remote
git remote add origin https://github.com/YOUR_USERNAME/aws-devsecops-pipeline-with-self-healing.git

# Verify remote is correct
git remote -v

# Push to GitHub
git push -u origin main
```

If you encounter authentication errors:

**Option A: Using Personal Access Token (PAT)**
```bash
# Generate PAT at: https://github.com/settings/tokens
# Required scopes: repo (full control)

# Use PAT when prompted for password
git push -u origin main
# Username: YOUR_USERNAME
# Password: ghp_YOUR_PERSONAL_ACCESS_TOKEN
```

**Option B: Using SSH**
```bash
# Change remote to SSH
git remote set-url origin git@github.com:YOUR_USERNAME/aws-devsecops-pipeline-with-self-healing.git

# Push
git push -u origin main
```

## Step 3: Deploy Infrastructure from Local Machine

**IMPORTANT:** Deploy from your local machine first, not through the pipeline.

### 3.1: Verify AWS Credentials

```bash
# Check AWS credentials are configured
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "935595346298",
#     "Arn": "arn:aws:iam::935595346298:user/your-username"
# }
```

### 3.2: Initialize Terraform

```bash
# Initialize Terraform (downloads providers)
terraform init

# You should see:
# Terraform has been successfully initialized!
```

### 3.3: Review Deployment Plan

```bash
# Generate and review the execution plan
terraform plan

# This shows what will be created:
# - 3 S3 buckets (state, artifacts, config)
# - CodePipeline with 3 stages
# - 2 CodeBuild projects
# - AWS Config recorder and rules
# - Lambda function for self-healing
# - EventBridge rule
# - IAM roles and policies
# - ~20-25 resources total
```

### 3.4: Deploy Infrastructure

```bash
# Apply the configuration
terraform apply

# Review the plan and type 'yes' when prompted
```

**Deployment takes approximately 3-5 minutes.**

### 3.5: Verify Deployment

```bash
# Check outputs
terraform output

# Expected outputs:
# pipeline_name = "devsecops-pipeline-pipeline"
# state_bucket_name = "devsecops-pipeline-tfstate-935595346298"
# artifacts_bucket_name = "devsecops-pipeline-artifacts-935595346298"
# security_scan_project_name = "devsecops-pipeline-security-scan"
# deploy_project_name = "devsecops-pipeline-terraform-deploy"
# lambda_function_name = "devsecops-pipeline-self-healing"
# config_recorder_name = "devsecops-pipeline-recorder"
# eventbridge_rule_name = "devsecops-pipeline-config-compliance-change"
```

### 3.6: Verify CodeStar Connection Status

```bash
# Check connection status
aws codestar-connections get-connection \
  --connection-arn "arn:aws:codestar-connections:us-east-1:935595346298:connection/8095595f-8d7e-4491-bbab-c5686c927184"

# Look for: "ConnectionStatus": "AVAILABLE"
# If "PENDING", complete OAuth in AWS Console
```

If status is PENDING:
1. Go to [AWS CodeStar Connections Console](https://console.aws.amazon.com/codesuite/settings/connections)
2. Click on your connection
3. Click **Update pending connection**
4. Complete GitHub authorization

## Step 4: Configure Terraform Remote State (Optional but Recommended)

After the first deployment, migrate your state to S3 for team collaboration:

```bash
# Get the S3 bucket name
STATE_BUCKET=$(terraform output -raw state_bucket_name)
echo "State bucket: $STATE_BUCKET"

# Re-initialize with S3 backend
terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="key=devsecops-pipeline/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -migrate-state

# Type 'yes' when asked to migrate state
```

Now your Terraform state is stored in S3 with versioning enabled.

## Step 5: Test the Pipeline

### 5.1: Trigger Pipeline Manually (First Test)

```bash
# View pipeline in AWS Console
aws codepipeline get-pipeline-state \
  --name devsecops-pipeline-pipeline

# Or trigger it manually
aws codepipeline start-pipeline-execution \
  --name devsecops-pipeline-pipeline
```

**Or via AWS Console:**
[Open CodePipeline Console](https://console.aws.amazon.com/codesuite/codepipeline/pipelines)

### 5.2: Watch Pipeline Execution

```bash
# Monitor pipeline status
watch -n 5 'aws codepipeline get-pipeline-state --name devsecops-pipeline-pipeline --query "stageStates[*].[stageName,latestExecution.status]" --output table'
```

**Pipeline Stages:**
1. **Source** (1-2 min): Pulls code from GitHub
2. **SecurityScan** (3-5 min): Runs Checkov and tfsec scans
3. **Deploy** (2-4 min): Runs terraform plan and apply

**Total duration: 6-11 minutes**

### 5.3: View Build Logs

**Security Scan Logs:**
```bash
# View latest security scan logs
aws logs tail /aws/codebuild/devsecops-pipeline-security-scan --follow
```

**Deploy Logs:**
```bash
# View latest deployment logs
aws logs tail /aws/codebuild/devsecops-pipeline-terraform-deploy --follow
```

### 5.4: Trigger via Git Push (Automatic)

```bash
# Make a change
echo "# DevSecOps Pipeline" > README-PIPELINE.md
git add README-PIPELINE.md
git commit -m "Test: Trigger pipeline via git push"
git push origin main

# Pipeline should trigger automatically within 30 seconds
# Watch it in the console or via CLI
```

## Step 6: Verify Security & Governance Components

### 6.1: Check AWS Config Status

```bash
# Verify Config recorder is running
aws configservice describe-configuration-recorder-status

# Expected: "recording": true, "lastStatus": "SUCCESS"
```

### 6.2: View Config Rules

```bash
# List Config rules
aws configservice describe-config-rules \
  --query 'ConfigRules[*].[ConfigRuleName,ConfigRuleState]' \
  --output table

# Expected rules:
# - devsecops-pipeline-s3-public-read-prohibited
# - devsecops-pipeline-restricted-ssh
# - devsecops-pipeline-restricted-common-ports
```

### 6.3: Verify Lambda Function

```bash
# Check Lambda function exists
aws lambda get-function \
  --function-name devsecops-pipeline-self-healing

# Test invoke (optional)
aws lambda invoke \
  --function-name devsecops-pipeline-self-healing \
  --payload '{"detail-type":"Config Rules Compliance Change","source":"aws.config","detail":{"newEvaluationResult":{"complianceType":"NON_COMPLIANT"},"resourceType":"AWS::EC2::SecurityGroup","resourceId":"sg-test"}}' \
  response.json

# View response
cat response.json
```

### 6.4: Check EventBridge Rule

```bash
# Verify EventBridge rule
aws events describe-rule \
  --name devsecops-pipeline-config-compliance-change

# Expected: "State": "ENABLED"
```

## Architecture Deployed

You now have a complete DevSecOps pipeline running in AWS:

```
GitHub Repository
    ↓ (git push)
CodeStar Connection
    ↓ (webhook trigger)
CodePipeline
    ├─→ Stage 1: Source (checkout code)
    ├─→ Stage 2: SecurityScan (Checkov + tfsec)
    └─→ Stage 3: Deploy (Terraform apply)
         ↓
    AWS Infrastructure Changes

Parallel Security Flow:
AWS Config (monitors resources)
    ↓ (detects NON_COMPLIANT)
EventBridge
    ↓ (triggers)
Lambda Function
    ↓ (restores)
Security Groups → Golden State
```

## What Happens on Future Git Pushes

**Every time you push to GitHub main branch:**

1. ✅ CodeStar Connection detects the push via webhook
2. ✅ CodePipeline starts automatically
3. ✅ Source stage pulls latest code
4. ✅ SecurityScan stage:
   - Installs Checkov and tfsec
   - Scans Terraform files
   - Runs `terraform plan`
   - Scans plan JSON for deep security analysis
   - Logs all findings (soft-fail mode)
5. ✅ Deploy stage:
   - Runs `terraform init` with S3 backend
   - Runs `terraform plan`
   - Executes `terraform apply -auto-approve`
   - Updates your infrastructure

**Important:** The pipeline will manage infrastructure defined in your repo. If you make changes locally via `terraform apply`, commit and push them to keep the repo in sync.

## Best Practices for Ongoing Use

### Development Workflow

```bash
# 1. Make infrastructure changes
vim main.tf

# 2. Test locally first
terraform plan

# 3. Commit changes
git add main.tf
git commit -m "Add new S3 bucket for application logs"

# 4. Push to trigger pipeline
git push origin main

# 5. Monitor pipeline execution
aws codepipeline get-pipeline-state --name devsecops-pipeline-pipeline
```

### Keeping State in Sync

**Option A: Always deploy via pipeline (recommended)**
- Make changes locally
- Commit and push
- Let pipeline apply changes
- State stays in S3, always in sync

**Option B: Deploy locally**
- Ensure you've migrated to S3 backend (Step 4)
- Run `terraform apply` locally
- Commit and push changes
- State is already in S3, shared with pipeline

## Troubleshooting

### Pipeline fails at Source stage

**Error:** `Could not access the GitHub repository`

**Fix:**
```bash
# Check CodeStar Connection status
aws codestar-connections get-connection \
  --connection-arn "arn:aws:codestar-connections:us-east-1:935595346298:connection/8095595f-8d7e-4491-bbab-c5686c927184"

# If PENDING, complete OAuth in AWS Console
```

### Pipeline fails at SecurityScan stage

**Error:** `pip install checkov failed`

**Fix:** Check CloudWatch logs:
```bash
aws logs tail /aws/codebuild/devsecops-pipeline-security-scan --follow
```

Common causes:
- Network timeout (retry)
- Python version mismatch (check buildspec)

### Pipeline fails at Deploy stage

**Error:** `Error acquiring state lock`

**Cause:** Another terraform process is running or crashed

**Fix:**
```bash
# Force unlock (use with caution)
terraform force-unlock LOCK_ID

# Get LOCK_ID from error message
```

### Pipeline not triggering on push

**Checklist:**
- [ ] CodeStar Connection status is AVAILABLE
- [ ] Pipeline detectChanges is enabled
- [ ] Pushing to the correct branch (main)
- [ ] GitHub webhook is active

**Verify webhook:**
1. Go to your GitHub repo → Settings → Webhooks
2. Look for AWS CodePipeline webhook
3. Check Recent Deliveries for errors

## Cost Monitoring

### View Current Costs

```bash
# Get AWS Cost Explorer data for CodePipeline
aws ce get-cost-and-usage \
  --time-period Start=2024-03-01,End=2024-03-26 \
  --granularity DAILY \
  --metrics BlendedCost \
  --filter file://filter.json

# filter.json:
# {
#   "Dimensions": {
#     "Key": "SERVICE",
#     "Values": ["AWS CodePipeline", "AWS CodeBuild", "AWS Config"]
#   }
# }
```

### Set Up Budget Alert

```bash
# Create budget for $10/month
aws budgets create-budget \
  --account-id 935595346298 \
  --budget file://budget.json

# budget.json - see AWS Budgets documentation
```

## Next Steps

### Production Hardening

1. **Add manual approval before Deploy:**
   - Add approval stage in CodePipeline
   - Require human review of terraform plan

2. **Enhance security scanning:**
   - Make security failures block deployment
   - Add custom Checkov policies
   - Integrate with AWS Security Hub

3. **Add notifications:**
   - SNS topic for pipeline failures
   - Slack/email alerts for compliance violations
   - Lambda failures to PagerDuty

4. **Implement branch strategy:**
   - Create dev/staging/prod branches
   - Separate pipelines per environment
   - Terraform workspaces for environment isolation

5. **Add testing:**
   - Terraform validation in pre-commit hook
   - Integration tests after deployment
   - Automated rollback on test failures

### Monitoring Enhancements

```bash
# Create CloudWatch dashboard
aws cloudwatch put-dashboard \
  --dashboard-name DevsecOps-Pipeline \
  --dashboard-body file://dashboard.json
```

## Summary

You've successfully deployed a complete DevSecOps pipeline:

✅ **Infrastructure deployed** to AWS
✅ **Pipeline connected** to GitHub
✅ **Security scanning** enabled (Checkov + tfsec)
✅ **Governance monitoring** active (AWS Config)
✅ **Self-healing** configured (Lambda + EventBridge)
✅ **Logging** enabled (CloudWatch)

**Total Resources Created:** ~25 AWS resources
**Monthly Cost:** $5-10 (after Free Tier)
**Deployment Time:** 3-5 minutes

Every git push to main will now automatically:
1. Scan for security issues
2. Run terraform plan
3. Deploy infrastructure changes
4. Log all actions

Your infrastructure is now fully automated with security built-in!
