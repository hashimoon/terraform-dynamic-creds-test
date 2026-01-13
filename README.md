# AWS Dynamic Credentials Test Module

A minimal Terraform module to verify AWS dynamic credentials work with HCP Terraform registry module testing.

## What This Module Does

- Calls `sts:GetCallerIdentity` to verify AWS authentication (read permission)
- Creates an IAM policy to verify write permissions
- Outputs the account ID, ARN, region, and test policy ARN
- Includes tests that verify both read and write permissions

## AWS Setup

### 1. Create OIDC Identity Provider (if not exists)

In AWS IAM Console:
- Go to Identity Providers → Add Provider
- Type: OpenID Connect
- Provider URL: `https://app.terraform.io`
- Audience: `aws.workload.identity`

### 2. Create IAM Role

Create a role with this trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "<OIDC_PRODIVER_ARN>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:<YOUR_ORG>:*"
        }
      }
    }
  ]
}
```

Attach this minimal policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions"
      ],
      "Resource": "arn:aws:iam::*:policy/terraform-dynamic-creds-test-policy-*"
    }
  ]
}
```

## Publishing to HCP Terraform

1. Push this repo to GitHub/GitLab
2. In HCP Terraform, go to Registry → Publish → Module
3. Connect to your VCS and select this repo

## Configure Test Settings

After publishing:

1. Go to the module in the registry
2. Click "Tests" tab → "Test settings"
3. Add these environment variables:

| Key | Value | Sensitive |
|-----|-------|-----------|
| `TFC_AWS_PROVIDER_AUTH` | `true` | No |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>` | No |

4. Save and trigger a test run

## Expected Results

The test should pass and show output like:

```
account_id = "123456789012"
caller_arn = "arn:aws:sts::123456789012:assumed-role/tfc-dynamic-creds-role/..."
user_id = "AROAEXAMPLE:..."
region = "us-east-1"
```
