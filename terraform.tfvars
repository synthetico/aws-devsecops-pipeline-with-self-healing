# AWS DevSecOps Pipeline Configuration

aws_region  = "us-east-1"
environment = "dev"
project_name = "devsecops-pipeline"

# GitHub repository configuration
github_repo   = "aws-devsecops-pipeline-with-self-healing"
github_branch = "main"

# AWS CodeStar Connection ARN
codestar_connection_arn = "arn:aws:codestar-connections:us-east-1:935595346298:connection/8095595f-8d7e-4491-bbab-c5686c927184"

# CodeBuild configuration (Free Tier compatible)
codebuild_compute_type = "BUILD_GENERAL1_SMALL"
codebuild_image        = "aws/codebuild/standard:7.0"

# Golden state security group rules for self-healing
# These rules will be enforced when drift is detected
golden_security_group_rules = [
  {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from anywhere"
  },
  {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from anywhere"
  }
]

# Enable self-healing automation
enable_self_healing = true

# Additional tags
tags = {
  Owner      = "DevOps Team"
  CostCenter = "Engineering"
  Purpose    = "DevSecOps Pipeline Prototype"
}
