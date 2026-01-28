#!/bin/bash
#
# Setup script for Azure Dynamic Credentials with HCP Terraform Module Tests
# This script automates the Azure setup for testing modules in the private registry
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default resource names
APP_NAME="terraform-module-tests"
CREDENTIAL_NAME="terraform-module-tests"

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if az CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    print_success "Azure CLI is installed"

    # Check if user is authenticated
    if ! az account show &>/dev/null; then
        print_error "Not authenticated with Azure CLI. Run 'az login' first"
        exit 1
    fi
    print_success "Azure CLI is authenticated"
}

# Get Azure subscription information
get_azure_info() {
    print_header "Azure Configuration"

    # Auto-detect current subscription
    CURRENT_SUBSCRIPTION=$(az account show --query id -o tsv 2>/dev/null || echo "")
    CURRENT_SUBSCRIPTION_NAME=$(az account show --query name -o tsv 2>/dev/null || echo "")
    CURRENT_TENANT=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")

    if [ -n "$CURRENT_SUBSCRIPTION" ]; then
        echo "Current subscription: $CURRENT_SUBSCRIPTION_NAME ($CURRENT_SUBSCRIPTION)"
        read -p "Use this subscription? (Y/n): " USE_CURRENT
        if [[ "$USE_CURRENT" =~ ^[Nn]$ ]]; then
            echo ""
            echo "Available subscriptions:"
            az account list --query "[].{Name:name, ID:id}" -o table
            echo ""
            read -p "Enter Subscription ID: " SUBSCRIPTION_ID
        else
            SUBSCRIPTION_ID="$CURRENT_SUBSCRIPTION"
        fi
    else
        read -p "Subscription ID: " SUBSCRIPTION_ID
    fi

    if [ -z "$SUBSCRIPTION_ID" ]; then
        print_error "Subscription ID is required"
        exit 1
    fi

    # Set the subscription and get tenant ID
    az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null || {
        print_error "Failed to set subscription '$SUBSCRIPTION_ID'"
        exit 1
    }

    TENANT_ID=$(az account show --query tenantId -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

    print_success "Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    print_success "Tenant ID: $TENANT_ID"
}

# Get HCP Terraform configuration
get_hcp_config() {
    print_header "HCP Terraform Configuration"

    read -p "HCP Terraform Organization ID (e.g., org-abc123xyz): " ORG_ID
    if [ -z "$ORG_ID" ]; then
        print_error "Organization ID is required"
        exit 1
    fi

    echo ""
    echo "Optional: Restrict to a specific module (leave blank to allow all modules)"
    read -p "Module Name (e.g., terraform-azurerm-network): " MODULE_NAME

    print_success "Organization ID: $ORG_ID"
    if [ -n "$MODULE_NAME" ]; then
        print_success "Module: $MODULE_NAME"
    else
        print_success "Modules: All modules in organization"
    fi
}

# Create App Registration
create_app_registration() {
    print_header "Creating App Registration"

    # Check if app already exists
    EXISTING_APP=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING_APP" ]; then
        print_warning "App Registration '$APP_NAME' already exists"
        APP_ID="$EXISTING_APP"
        APP_OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)
    else
        # Create the app registration
        APP_OBJECT_ID=$(az ad app create --display-name "$APP_NAME" --query id -o tsv)
        APP_ID=$(az ad app show --id "$APP_OBJECT_ID" --query appId -o tsv)
        print_success "Created App Registration: $APP_NAME"
    fi

    print_success "App ID (Client ID): $APP_ID"
    print_success "App Object ID: $APP_OBJECT_ID"
}

# Create Service Principal
create_service_principal() {
    print_header "Creating Service Principal"

    # Check if service principal already exists
    EXISTING_SP=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING_SP" ]; then
        print_warning "Service Principal already exists"
        SP_OBJECT_ID="$EXISTING_SP"
    else
        SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
        print_success "Created Service Principal"

        # Wait for propagation
        echo "Waiting for service principal to propagate..."
        sleep 10
    fi

    print_success "Service Principal Object ID: $SP_OBJECT_ID"
}

# Create Federated Credential
create_federated_credential() {
    print_header "Creating Federated Credential"

    # Build the subject identifier for module tests
    if [ -n "$MODULE_NAME" ]; then
        # Specific module, all versions
        SUBJECT="organization:${ORG_ID}:module:${MODULE_NAME}:*"
    else
        # All modules in the organization
        SUBJECT="organization:${ORG_ID}:module:*:*"
    fi

    # Check if federated credential already exists
    EXISTING_CRED=$(az ad app federated-credential list --id "$APP_OBJECT_ID" --query "[?name=='$CREDENTIAL_NAME'].id" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING_CRED" ]; then
        print_warning "Federated credential '$CREDENTIAL_NAME' already exists"

        # Ask if user wants to update it
        read -p "Update existing credential? (y/N): " UPDATE_CRED
        if [[ "$UPDATE_CRED" =~ ^[Yy]$ ]]; then
            az ad app federated-credential delete --id "$APP_OBJECT_ID" --federated-credential-id "$CREDENTIAL_NAME" 2>/dev/null || true
            sleep 2
        else
            return
        fi
    fi

    # Create temp file for credential parameters
    CRED_FILE=$(mktemp)
    cat > "$CRED_FILE" << EOF
{
    "name": "$CREDENTIAL_NAME",
    "issuer": "https://app.terraform.io",
    "subject": "$SUBJECT",
    "description": "HCP Terraform Module Tests",
    "audiences": ["azure.workload.identity"]
}
EOF

    az ad app federated-credential create --id "$APP_OBJECT_ID" --parameters "$CRED_FILE"
    rm -f "$CRED_FILE"

    print_success "Created Federated Credential"
    print_success "Subject: $SUBJECT"
}

# Assign Role to Subscription
assign_role() {
    print_header "Assigning Contributor Role"

    # Check if role assignment already exists
    EXISTING_ROLE=$(az role assignment list --assignee "$APP_ID" --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[0].id" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING_ROLE" ]; then
        print_warning "Contributor role already assigned to subscription"
    else
        az role assignment create \
            --assignee "$APP_ID" \
            --role "Contributor" \
            --scope "/subscriptions/$SUBSCRIPTION_ID"
        print_success "Assigned Contributor role to subscription"
    fi
}

# Print HCP Terraform configuration
print_hcp_config() {
    print_header "HCP Terraform Environment Variables"

    echo -e "Configure these environment variables in your HCP Terraform module test settings:\n"
    echo -e "${YELLOW}Variable${NC}                               ${YELLOW}Value${NC}"
    echo -e "─────────────────────────────────────────────────────────────────────────────"
    echo -e "TFC_AZURE_PROVIDER_AUTH                   ${GREEN}true${NC}"
    echo -e "TFC_AZURE_RUN_CLIENT_ID                   ${GREEN}${APP_ID}${NC}"
    echo -e "ARM_TENANT_ID                             ${GREEN}${TENANT_ID}${NC}"
    echo -e "ARM_SUBSCRIPTION_ID                       ${GREEN}${SUBSCRIPTION_ID}${NC}"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  Azure Dynamic Credentials Setup for HCP Terraform Module Tests ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_prerequisites
    get_azure_info
    get_hcp_config

    echo ""
    echo -e "${YELLOW}The following resources will be created:${NC}"
    echo "  - App Registration: $APP_NAME"
    echo "  - Service Principal for the app"
    echo "  - Federated Credential: $CREDENTIAL_NAME"
    echo "  - Contributor role assignment on subscription"
    echo ""
    read -p "Continue? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    create_app_registration
    create_service_principal
    create_federated_credential
    assign_role
    print_hcp_config

    print_header "Setup Complete"
    echo -e "${GREEN}Azure resources have been created successfully!${NC}"
    echo -e "Configure the settings above in your registry module's test configuration."
}

main "$@"
