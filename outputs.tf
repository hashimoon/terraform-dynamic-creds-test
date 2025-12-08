output "account_id" {
  description = "The AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  description = "The ARN of the caller (assumed role)"
  value       = data.aws_caller_identity.current.arn
}

output "user_id" {
  description = "The unique identifier of the caller"
  value       = data.aws_caller_identity.current.user_id
}

output "region" {
  description = "The AWS region"
  value       = data.aws_region.current.name
}

output "test_policy_arn" {
  description = "ARN of the test IAM policy (verifies write permissions)"
  value       = aws_iam_policy.test_write_permission.arn
}
