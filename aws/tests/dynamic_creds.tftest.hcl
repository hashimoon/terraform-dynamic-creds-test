run "verify_aws_identity" {
  command = plan

  assert {
    condition     = data.aws_caller_identity.current.account_id != ""
    error_message = "AWS caller identity should return an account ID"
  }

  assert {
    condition     = can(regex("arn:aws", data.aws_caller_identity.current.arn))
    error_message = "Caller ARN should be a valid AWS ARN"
  }
}

run "verify_aws_write_permission" {
  command = apply

  assert {
    condition     = aws_iam_policy.test_write_permission.arn != ""
    error_message = "IAM policy should be created with a valid ARN"
  }

  assert {
    condition     = can(regex("arn:aws:iam::", aws_iam_policy.test_write_permission.arn))
    error_message = "Policy ARN should be a valid IAM ARN"
  }
}
