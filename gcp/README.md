# GCP Dynamic Credentials Test Module

A minimal Terraform module to verify GCP dynamic credentials work with HCP Terraform registry module testing.

## What This Module Does

- Uses `google_client_config` to verify GCP authentication (read permission)
- Creates a custom IAM role to verify write permissions (free, no charges)
- Outputs the project, access token status, and test role ID
- Includes tests that verify both read and write permissions

## Quick Setup

Run the setup script to automatically configure GCP for dynamic credentials:

```bash
chmod +x setup-gcp-dynamic-creds.sh
./setup-gcp-dynamic-creds.sh
```

The script will:
1. Create a Workload Identity Pool
2. Create an OIDC Provider for HCP Terraform
3. Create a Service Account
4. Grant the Workload Identity User role
5. Grant IAM Role Admin permission (for the write test)
6. Output the HCP Terraform environment variables

## Manual Setup

### 1. Create Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "terraform-module-tests" \
  --location="global" \
  --display-name="Terraform Module Tests"
```

### 2. Create OIDC Provider

```bash
gcloud iam workload-identity-pools providers create-oidc "terraform-cloud" \
  --location="global" \
  --workload-identity-pool="terraform-module-tests" \
  --issuer-uri="https://app.terraform.io" \
  --allowed-audiences="gcp.workload.identity" \
  --attribute-mapping="google.subject=assertion.sub,attribute.terraform_run_id=assertion.terraform_run_id,attribute.terraform_module_name=assertion.terraform_module_name,attribute.terraform_test_run=assertion.terraform_test_run,attribute.terraform_organization_id=assertion.terraform_organization_id,attribute.terraform_organization_name=assertion.terraform_organization_name" \
  --attribute-condition="assertion.terraform_test_run == 'true' && assertion.terraform_organization_name == '<YOUR_ORG>'"
```

### 3. Create Service Account

```bash
gcloud iam service-accounts create terraform-module-test-sa \
  --display-name="Terraform Module Test Service Account"
```

### 4. Grant Workload Identity User Role

```bash
gcloud iam service-accounts add-iam-policy-binding \
  terraform-module-test-sa@<PROJECT_ID>.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/terraform-module-tests/attribute.terraform_test_run/true"
```

### 5. Grant IAM Role Admin Permission

```bash
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --role="roles/iam.roleAdmin" \
  --member="serviceAccount:terraform-module-test-sa@<PROJECT_ID>.iam.gserviceaccount.com"
```

## Configure Test Settings

After publishing to HCP Terraform registry:

1. Go to the module in the registry
2. Click "Tests" tab → "Test settings"
3. Add these environment variables:

| Key | Value | Sensitive |
|-----|-------|-----------|
| `TFC_GCP_PROVIDER_AUTH` | `true` | No |
| `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` | `terraform-module-test-sa@<PROJECT_ID>.iam.gserviceaccount.com` | No |
| `TFC_GCP_WORKLOAD_PROVIDER_NAME` | `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/terraform-module-tests/providers/terraform-cloud` | No |
| `TFC_GCP_WORKLOAD_IDENTITY_AUDIENCE` | `gcp.workload.identity` | No |

4. Add a Terraform variable:

| Key | Value | Sensitive |
|-----|-------|-----------|
| `gcp_project_id` | `<PROJECT_ID>` | No |

5. Save and trigger a test run

## Expected Results

The test should pass and show output like:

```
project = "my-project-id"
access_token_set = true
test_role_id = "projects/my-project-id/roles/terraformDynamicCredsTest..."
```

## References

- [HCP Terraform GCP Dynamic Credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/gcp-configuration)
