#!/bin/bash
# Quick Command Reference for AWS DevSecOps Pipeline Deployment
# Run these commands in sequence

set -e  # Exit on any error

echo "========================================="
echo "AWS DevSecOps Pipeline Deployment"
echo "========================================="
echo ""

# Configuration
GITHUB_REPO="aws-devsecops-pipeline-with-self-healing"
GITHUB_USER="YOUR_GITHUB_USERNAME"  # UPDATE THIS
AWS_REGION="us-east-1"
PIPELINE_NAME="devsecops-pipeline-pipeline"

echo "Step 1: Push Code to GitHub"
echo "----------------------------"
echo "Run these commands to push your code:"
echo ""
echo "# Initialize git (if not done)"
echo "git init"
echo ""
echo "# Add all files"
echo "git add ."
echo ""
echo "# Create initial commit"
echo "git commit -m 'Initial commit: AWS DevSecOps pipeline infrastructure'"
echo ""
echo "# Add GitHub remote (UPDATE YOUR_GITHUB_USERNAME)"
echo "git remote add origin https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
echo ""
echo "# Push to GitHub"
echo "git push -u origin main"
echo ""
echo "Press Enter when code is pushed to GitHub..."
read

echo ""
echo "Step 2: Verify AWS Credentials"
echo "-------------------------------"
aws sts get-caller-identity
echo ""
echo "Verified! AWS Account: $(aws sts get-caller-identity --query Account --output text)"
echo ""

echo "Step 3: Initialize Terraform"
echo "----------------------------"
terraform init
echo ""

echo "Step 4: Validate Configuration"
echo "-------------------------------"
terraform validate
echo "✓ Configuration is valid!"
echo ""

echo "Step 5: Review Deployment Plan"
echo "-------------------------------"
echo "This will show all resources to be created..."
terraform plan
echo ""
echo "Review the plan above. Press Enter to continue to deployment..."
read

echo ""
echo "Step 6: Deploy Infrastructure"
echo "------------------------------"
echo "Deploying infrastructure to AWS..."
echo "This will take approximately 3-5 minutes."
echo ""
terraform apply -auto-approve

echo ""
echo "========================================="
echo "✓ Deployment Complete!"
echo "========================================="
echo ""

# Get outputs
echo "Infrastructure Details:"
echo "----------------------"
STATE_BUCKET=$(terraform output -raw state_bucket_name)
ARTIFACTS_BUCKET=$(terraform output -raw artifacts_bucket_name)
SECURITY_SCAN_PROJECT=$(terraform output -raw security_scan_project_name)
DEPLOY_PROJECT=$(terraform output -raw deploy_project_name)
LAMBDA_FUNCTION=$(terraform output -raw lambda_function_name)

echo "Pipeline Name:           ${PIPELINE_NAME}"
echo "State S3 Bucket:         ${STATE_BUCKET}"
echo "Artifacts S3 Bucket:     ${ARTIFACTS_BUCKET}"
echo "Security Scan Project:   ${SECURITY_SCAN_PROJECT}"
echo "Deploy Project:          ${DEPLOY_PROJECT}"
echo "Lambda Function:         ${LAMBDA_FUNCTION}"
echo ""

echo "Step 7: Verify CodeStar Connection"
echo "-----------------------------------"
CONNECTION_STATUS=$(aws codestar-connections get-connection \
  --connection-arn "arn:aws:codestar-connections:us-east-1:935595346298:connection/8095595f-8d7e-4491-bbab-c5686c927184" \
  --query 'Connection.ConnectionStatus' --output text)

echo "CodeStar Connection Status: ${CONNECTION_STATUS}"

if [ "$CONNECTION_STATUS" != "AVAILABLE" ]; then
  echo ""
  echo "⚠️  WARNING: CodeStar Connection is not AVAILABLE"
  echo "   Please complete GitHub OAuth authorization:"
  echo "   1. Go to: https://console.aws.amazon.com/codesuite/settings/connections"
  echo "   2. Click on your connection"
  echo "   3. Click 'Update pending connection'"
  echo "   4. Complete GitHub authorization"
  echo ""
  echo "Press Enter when connection is AVAILABLE..."
  read
fi

echo ""
echo "Step 8: Migrate State to S3 (Optional)"
echo "---------------------------------------"
echo "Migrate Terraform state to S3 for team collaboration?"
echo "This allows the pipeline to share state with your local environment."
echo ""
read -p "Migrate state to S3? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  terraform init \
    -backend-config="bucket=${STATE_BUCKET}" \
    -backend-config="key=devsecops-pipeline/terraform.tfstate" \
    -backend-config="region=${AWS_REGION}" \
    -migrate-state
  echo "✓ State migrated to S3: ${STATE_BUCKET}"
fi

echo ""
echo "Step 9: Test Pipeline"
echo "---------------------"
echo "Testing pipeline with manual trigger..."
aws codepipeline start-pipeline-execution --name ${PIPELINE_NAME}
echo "✓ Pipeline execution started!"
echo ""

echo "Monitor pipeline status:"
echo "  AWS Console: https://console.aws.amazon.com/codesuite/codepipeline/pipelines"
echo "  Or run: aws codepipeline get-pipeline-state --name ${PIPELINE_NAME}"
echo ""

echo "View logs:"
echo "  Security Scan: aws logs tail /aws/codebuild/${SECURITY_SCAN_PROJECT} --follow"
echo "  Deploy:        aws logs tail /aws/codebuild/${DEPLOY_PROJECT} --follow"
echo "  Lambda:        aws logs tail /aws/lambda/${LAMBDA_FUNCTION} --follow"
echo ""

echo "========================================="
echo "✓ Setup Complete!"
echo "========================================="
echo ""
echo "What happens next:"
echo ""
echo "1. The pipeline is now running (check AWS Console)"
echo "2. Every git push to 'main' will trigger the pipeline automatically"
echo "3. Security scans will run on every change"
echo "4. AWS Config will monitor your resources"
echo "5. Lambda will auto-heal Security Group drift"
echo ""
echo "Test automatic trigger:"
echo "  echo '# Test' >> TEST.md"
echo "  git add TEST.md"
echo "  git commit -m 'Test: Trigger pipeline'"
echo "  git push origin main"
echo ""
echo "Next steps:"
echo "  - See QUICKSTART.md for testing self-healing"
echo "  - See DEPLOYMENT.md for detailed workflows"
echo "  - See README.md for complete documentation"
echo ""
echo "Happy automating! 🚀"
