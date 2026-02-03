# Azure Dynamic Credentials Test Module

A minimal Terraform module to verify Azure dynamic credentials work with HCP Terraform registry module testing.

## What This Module Does

- Uses `azurerm_client_config` and `azurerm_subscription` to verify Azure authentication (read permission)
- Creates a resource group to verify write permissions (free, no charges)
- Outputs the tenant ID, subscription ID, client ID, subscription name, and test resource group ID
- Includes tests that verify both read and write permissions

## Quick Setup

Run the setup script to automatically configure Azure for dynamic credentials:

```bash
chmod +x setup-azure-dynamic-creds.sh
./setup-azure-dynamic-creds.sh
```

The script will:
1. Create an App Registration
2. Create a Service Principal
3. Create a Federated Credential for HCP Terraform
4. Assign the Contributor role to your subscription
5. Output the HCP Terraform environment variables

## Manual Setup

### 1. Create App Registration

In Azure Portal → Microsoft Entra ID → App registrations:
- Click "New registration"
- Name: `terraform-module-tests`
- Supported account types: Single tenant
- Click "Register"

Note the **Application (client) ID** - you'll need it for HCP Terraform configuration.

### 2. Add Federated Credential

In the app registration → Certificates & secrets → Federated credentials:
- Click "Add credential"
- Federated credential scenario: "Other issuer"
- Issuer: `https://app.terraform.io`
- Subject identifier: `organization:<ORG_ID>:module:*:*` (all modules) or `organization:<ORG_ID>:module:<MODULE_NAME>:*` (specific module)
- Audience: `azure.workload.identity`
- Name: `terraform-module-tests`
- Click "Add"

### 3. Create Service Principal

If not automatically created:

```bash
az ad sp create --id <APP_ID>
```

### 4. Assign Role to Subscription

In Azure Portal → Subscriptions → Your subscription → Access control (IAM):
- Click "Add" → "Add role assignment"
- Role: "Contributor"
- Members: Select the app registration you created
- Click "Review + assign"

Or via CLI:

```bash
az role assignment create \
  --assignee <APP_ID> \
  --role "Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>"
```

## Configure Test Settings

After publishing to HCP Terraform registry:

1. Go to the module in the registry
2. Click "Tests" tab → "Test settings"
3. Add these environment variables:

| Key | Value | Sensitive |
|-----|-------|-----------|
| `TFC_AZURE_PROVIDER_AUTH` | `true` | No |
| `TFC_AZURE_RUN_CLIENT_ID` | `<APP_CLIENT_ID>` | No |
| `ARM_TENANT_ID` | `<TENANT_ID>` | No |
| `ARM_SUBSCRIPTION_ID` | `<SUBSCRIPTION_ID>` | No |

4. Save and trigger a test run

## Expected Results

The test should pass and show output like:

```
tenant_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
client_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
subscription_name = "My Subscription"
test_resource_group_id = "/subscriptions/.../resourceGroups/terraform-dynamic-creds-test-..."
```

## References

- [HCP Terraform Azure Dynamic Credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/azure-configuration)
