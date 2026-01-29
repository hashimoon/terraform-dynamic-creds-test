# Dynamic Credentials Test Modules

Minimal Terraform modules to verify dynamic credentials work with HCP Terraform registry module testing.

Each provider lives in its own subdirectory and is imported as a separate registry module using the source directory setting.

## Overview

Each module:
- Verifies authentication via a read operation (data source)
- Verifies write permissions by creating a free resource
- Includes tests that validate both read and write capabilities

| Provider | Directory | Read Operations | Write Operations |
|----------|-----------|----------------|------------------|
| AWS | `aws/` | `aws_caller_identity`, `aws_region` | `aws_iam_policy` |
| GCP | `gcp/` | `google_client_config` | `google_project_iam_custom_role` |
| Azure | `azure/` | `azurerm_client_config`, `azurerm_subscription` | `azurerm_resource_group` |

## Publishing to HCP Terraform

When importing each module from the registry, set the **source directory** to the provider subdirectory (`aws`, `gcp`, or `azure`).

## Setup

Each provider directory includes a README with setup instructions. GCP and Azure also include setup scripts:

- **AWS**: See [`aws/README.md`](aws/README.md)
- **GCP**: See [`gcp/README.md`](gcp/README.md) or run `gcp/setup-gcp-dynamic-creds.sh`
- **Azure**: See [`azure/README.md`](azure/README.md) or run `azure/setup-azure-dynamic-creds.sh`

## References

- [HCP Terraform AWS Dynamic Credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration)
- [HCP Terraform GCP Dynamic Credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/gcp-configuration)
- [HCP Terraform Azure Dynamic Credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/azure-configuration)
