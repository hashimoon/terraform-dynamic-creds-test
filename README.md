# Dynamic Credentials Test Modules

Minimal Terraform modules to verify dynamic credentials work with HCP Terraform for AWS, GCP, and Azure.

## Overview

Each provider has its own module that:
- Verifies authentication via a read operation (data source)
- Verifies write permissions by creating a free resource
- Includes tests that validate both read and write capabilities

| Provider | Read Operations | Write Operations |
|----------|----------------|------------------|
| AWS | `aws_caller_identity`, `aws_region` | `aws_iam_policy` |
| GCP | `google_client_config` | `google_project_iam_custom_role` |
| Azure | `azurerm_client_config`, `azurerm_subscription` | `azurerm_resource_group` |

## Directory Structure

```
terraform-dynamic-creds-test/
├── aws/
│   ├── main.tf
│   ├── outputs.tf
│   └── tests/dynamic_creds.tftest.hcl
├── gcp/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── tests/dynamic_creds.tftest.hcl
├── azure/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── tests/dynamic_creds.tftest.hcl
└── README.md
```

## HCP Terraform Workspace Configuration

Each provider should have its own workspace with "Working Directory" set to its subdirectory.

| Workspace | Working Directory | Required Variables |
|-----------|-------------------|-------------------|
| `dynamic-creds-aws` | `aws` | `TFC_AWS_PROVIDER_AUTH=true`, `TFC_AWS_RUN_ROLE_ARN` |
| `dynamic-creds-gcp` | `gcp` | `TFC_GCP_PROVIDER_AUTH=true`, `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL`, `TFC_GCP_WORKLOAD_PROVIDER_NAME`, `gcp_project_id` |
| `dynamic-creds-azure` | `azure` | `TFC_AZURE_PROVIDER_AUTH=true`, `TFC_AZURE_RUN_CLIENT_ID`, `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` |

---

## AWS Setup

### 1. Create OIDC Identity Provider

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
        "Federated": "<OIDC_PROVIDER_ARN>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:<YOUR_ORG>:project:<YOUR_PROJECT>:workspace:<YOUR_WORKSPACE>:run_phase:*"
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

### 3. Configure HCP Terraform Variables

| Key | Value | Sensitive |
|-----|-------|-----------|
| `TFC_AWS_PROVIDER_AUTH` | `true` | No |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>` | No |

---

## GCP Setup

### 1. Create Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "hcp-terraform-pool" \
  --location="global" \
  --display-name="HCP Terraform Pool"
```

### 2. Create Workload Identity Provider

```bash
gcloud iam workload-identity-pools providers create-oidc "hcp-terraform-provider" \
  --location="global" \
  --workload-identity-pool="hcp-terraform-pool" \
  --issuer-uri="https://app.terraform.io" \
  --attribute-mapping="google.subject=assertion.sub,attribute.terraform_organization=assertion.terraform_organization_name,attribute.terraform_workspace=assertion.terraform_workspace_name" \
  --attribute-condition="assertion.terraform_organization_name == '<YOUR_ORG>'"
```

### 3. Create Service Account

```bash
gcloud iam service-accounts create hcp-terraform-dynamic-creds \
  --display-name="HCP Terraform Dynamic Creds"
```

### 4. Grant Workload Identity User Role

```bash
gcloud iam service-accounts add-iam-policy-binding \
  hcp-terraform-dynamic-creds@<PROJECT_ID>.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/hcp-terraform-pool/attribute.terraform_workspace/<WORKSPACE_NAME>"
```

### 5. Grant Required Permissions

```bash
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --role="roles/iam.roleAdmin" \
  --member="serviceAccount:hcp-terraform-dynamic-creds@<PROJECT_ID>.iam.gserviceaccount.com"
```

### 6. Configure HCP Terraform Variables

| Key | Value | Sensitive |
|-----|-------|-----------|
| `TFC_GCP_PROVIDER_AUTH` | `true` | No |
| `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` | `hcp-terraform-dynamic-creds@<PROJECT_ID>.iam.gserviceaccount.com` | No |
| `TFC_GCP_WORKLOAD_PROVIDER_NAME` | `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/hcp-terraform-pool/providers/hcp-terraform-provider` | No |
| `gcp_project_id` | `<PROJECT_ID>` | No |

---

## Azure Setup

### 1. Create App Registration

In Azure Portal → Microsoft Entra ID → App registrations:
- Click "New registration"
- Name: `hcp-terraform-dynamic-creds`
- Supported account types: Single tenant
- Click "Register"

### 2. Add Federated Credential

In the app registration → Certificates & secrets → Federated credentials:
- Click "Add credential"
- Federated credential scenario: "Other issuer"
- Issuer: `https://app.terraform.io`
- Subject identifier: `organization:<YOUR_ORG>:project:<YOUR_PROJECT>:workspace:<YOUR_WORKSPACE>:run_phase:*`
- Name: `hcp-terraform-workspace`
- Click "Add"

### 3. Assign Role to Subscription

In Azure Portal → Subscriptions → Your subscription → Access control (IAM):
- Click "Add" → "Add role assignment"
- Role: "Contributor" (or a custom role with minimal permissions)
- Members: Select the app registration you created
- Click "Review + assign"

### 4. Configure HCP Terraform Variables

| Key | Value | Sensitive |
|-----|-------|-----------|
| `TFC_AZURE_PROVIDER_AUTH` | `true` | No |
| `TFC_AZURE_RUN_CLIENT_ID` | `<APP_CLIENT_ID>` | No |
| `ARM_SUBSCRIPTION_ID` | `<SUBSCRIPTION_ID>` | No |
| `ARM_TENANT_ID` | `<TENANT_ID>` | No |

---

## Running Tests

### Locally (requires credentials)

```bash
cd aws && terraform init && terraform test
cd ../gcp && terraform init && terraform test
cd ../azure && terraform init && terraform test
```

### Via HCP Terraform

Tests run automatically on the configured workspace when triggered through the HCP Terraform UI or API.

## Expected Results

### AWS
```
account_id = "123456789012"
caller_arn = "arn:aws:sts::123456789012:assumed-role/..."
region = "us-east-1"
test_policy_arn = "arn:aws:iam::123456789012:policy/terraform-dynamic-creds-test-policy-..."
```

### GCP
```
project = "my-project-id"
access_token_set = true
test_role_id = "projects/my-project-id/roles/terraformDynamicCredsTest..."
```

### Azure
```
tenant_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
client_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
subscription_name = "My Subscription"
test_resource_group_id = "/subscriptions/.../resourceGroups/terraform-dynamic-creds-test-..."
```

## References

- [HCP Terraform AWS Dynamic Credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration)
- [HCP Terraform GCP Dynamic Credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/gcp-configuration)
- [HCP Terraform Azure Dynamic Credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/azure-configuration)
- [HCP Terraform Workspace Settings](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/settings)
