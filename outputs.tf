output "pipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.main.name
}

output "pipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = aws_codepipeline.main.arn
}

output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "artifacts_bucket_name" {
  description = "S3 bucket name for CodePipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.bucket
}

output "security_scan_project_name" {
  description = "CodeBuild project name for security scanning"
  value       = aws_codebuild_project.security_scan.name
}

output "deploy_project_name" {
  description = "CodeBuild project name for Terraform deployment"
  value       = aws_codebuild_project.terraform_deploy.name
}

output "lambda_function_name" {
  description = "Lambda function name for self-healing"
  value       = var.enable_self_healing ? aws_lambda_function.self_healing[0].function_name : null
}

output "config_recorder_name" {
  description = "AWS Config recorder name"
  value       = aws_config_configuration_recorder.main.name
}

output "eventbridge_rule_name" {
  description = "EventBridge rule name for compliance events"
  value       = var.enable_self_healing ? aws_cloudwatch_event_rule.config_compliance[0].name : null
}
