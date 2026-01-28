#!/bin/bash
#
# Setup script for GCP Dynamic Credentials with HCP Terraform Module Tests
# This script automates the GCP setup for testing modules in the private registry
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resource names
POOL_NAME="terraform-module-tests"
PROVIDER_NAME="terraform-cloud"
SERVICE_ACCOUNT_NAME="terraform-module-test-sa"

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

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    print_success "gcloud CLI is installed"

    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 | grep -q .; then
        print_error "Not authenticated with gcloud. Run 'gcloud auth login' first"
        exit 1
    fi
    print_success "gcloud is authenticated"
}

# Get project information
get_project_info() {
    print_header "Project Configuration"

    # Auto-detect current project
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")

    if [ -n "$CURRENT_PROJECT" ]; then
        read -p "GCP Project ID [$CURRENT_PROJECT]: " PROJECT_ID
        PROJECT_ID=${PROJECT_ID:-$CURRENT_PROJECT}
    else
        read -p "GCP Project ID: " PROJECT_ID
        if [ -z "$PROJECT_ID" ]; then
            print_error "Project ID is required"
            exit 1
        fi
    fi

    # Verify project exists and get project number
    if ! PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)" 2>/dev/null); then
        print_error "Project '$PROJECT_ID' not found or you don't have access"
        exit 1
    fi
    print_success "Project verified: $PROJECT_ID (Project Number: $PROJECT_NUMBER)"
}

# Get HCP Terraform configuration
get_hcp_config() {
    print_header "HCP Terraform Configuration"

    read -p "HCP Terraform Organization Name: " ORG_NAME
    if [ -z "$ORG_NAME" ]; then
        print_error "Organization name is required"
        exit 1
    fi

    echo ""
    echo "Optional: Restrict to a specific module (leave blank to allow all modules)"
    read -p "Module Name (e.g., terraform-gcp-vpc): " MODULE_NAME

    print_success "Organization: $ORG_NAME"
    if [ -n "$MODULE_NAME" ]; then
        print_success "Module: $MODULE_NAME"
    else
        print_success "Modules: All modules in organization"
    fi
}

# Create Workload Identity Pool
create_workload_identity_pool() {
    print_header "Creating Workload Identity Pool"

    if gcloud iam workload-identity-pools describe "$POOL_NAME" --location="global" --project="$PROJECT_ID" &>/dev/null; then
        print_warning "Workload Identity Pool '$POOL_NAME' already exists"
    else
        gcloud iam workload-identity-pools create "$POOL_NAME" \
            --location="global" \
            --display-name="Terraform Module Tests" \
            --project="$PROJECT_ID"
        print_success "Created Workload Identity Pool: $POOL_NAME"
    fi
}

# Create OIDC Provider
create_oidc_provider() {
    print_header "Creating OIDC Provider"

    if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
        --location="global" \
        --workload-identity-pool="$POOL_NAME" \
        --project="$PROJECT_ID" &>/dev/null; then
        print_warning "OIDC Provider '$PROVIDER_NAME' already exists"
    else
        local attribute_condition="assertion.terraform_test_run == 'true' && assertion.terraform_organization_name == '$ORG_NAME'"

        gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
            --location="global" \
            --workload-identity-pool="$POOL_NAME" \
            --issuer-uri="https://app.terraform.io" \
            --allowed-audiences="gcp.workload.identity" \
            --attribute-mapping="google.subject=assertion.sub,attribute.terraform_run_id=assertion.terraform_run_id,attribute.terraform_module_name=assertion.terraform_module_name,attribute.terraform_test_run=assertion.terraform_test_run,attribute.terraform_organization_id=assertion.terraform_organization_id,attribute.terraform_organization_name=assertion.terraform_organization_name" \
            --attribute-condition="$attribute_condition" \
            --project="$PROJECT_ID"
        print_success "Created OIDC Provider: $PROVIDER_NAME"
    fi
}

# Create Service Account
create_service_account() {
    print_header "Creating Service Account"

    SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
        print_warning "Service Account '$SERVICE_ACCOUNT_NAME' already exists"
    else
        gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --display-name="Terraform Module Test Service Account" \
            --project="$PROJECT_ID"
        print_success "Created Service Account: $SERVICE_ACCOUNT_EMAIL"

        # Wait for service account to propagate
        echo "Waiting for service account to propagate..."
        sleep 10
    fi
}

# Grant Workload Identity User role
grant_workload_identity_user() {
    print_header "Granting Workload Identity User Role"

    local member
    if [ -n "$MODULE_NAME" ]; then
        # Specific module
        member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.terraform_module_name/${MODULE_NAME}"
    else
        # All module tests (terraform_test_run == true)
        member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.terraform_test_run/true"
    fi

    gcloud iam service-accounts add-iam-policy-binding \
        "$SERVICE_ACCOUNT_EMAIL" \
        --role="roles/iam.workloadIdentityUser" \
        --member="$member" \
        --project="$PROJECT_ID" \
        --condition=None
    print_success "Granted Workload Identity User role"
}

# Grant IAM Role Admin permission
grant_iam_role_admin() {
    print_header "Granting IAM Role Admin Permission"

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --role="roles/iam.roleAdmin" \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --condition=None
    print_success "Granted roles/iam.roleAdmin to service account"
}

# Print HCP Terraform configuration
print_hcp_config() {
    print_header "HCP Terraform Environment Variables"

    WORKLOAD_PROVIDER_NAME="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"

    echo -e "Configure these environment variables in your HCP Terraform module test settings:\n"
    echo -e "${YELLOW}Variable${NC}                               ${YELLOW}Value${NC}"
    echo -e "─────────────────────────────────────────────────────────────────────────────"
    echo -e "TFC_GCP_PROVIDER_AUTH                     ${GREEN}true${NC}"
    echo -e "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL         ${GREEN}${SERVICE_ACCOUNT_EMAIL}${NC}"
    echo -e "TFC_GCP_WORKLOAD_PROVIDER_NAME            ${GREEN}${WORKLOAD_PROVIDER_NAME}${NC}"
    echo -e "TFC_GCP_WORKLOAD_IDENTITY_AUDIENCE        ${GREEN}gcp.workload.identity${NC}"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║   GCP Dynamic Credentials Setup for HCP Terraform Module Tests ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_prerequisites
    get_project_info
    get_hcp_config

    echo ""
    echo -e "${YELLOW}The following resources will be created:${NC}"
    echo "  - Workload Identity Pool: $POOL_NAME"
    echo "  - OIDC Provider: $PROVIDER_NAME"
    echo "  - Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    read -p "Continue? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    create_workload_identity_pool
    create_oidc_provider
    create_service_account
    grant_workload_identity_user
    grant_iam_role_admin
    print_hcp_config

    print_header "Setup Complete"
    echo -e "${GREEN}GCP resources have been created successfully!${NC}"
    echo -e "Configure the settings above in your registry module's test configuration."
}

main "$@"
