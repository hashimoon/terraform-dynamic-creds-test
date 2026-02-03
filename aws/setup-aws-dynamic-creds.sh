#!/bin/bash
#
# Setup script for AWS Dynamic Credentials with HCP Terraform Module Tests
# This script automates the AWS setup for testing modules in the private registry
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resource names
ROLE_NAME="terraform-module-test-role"
POLICY_NAME="terraform-module-test-policy"
OIDC_PROVIDER_URL="app.terraform.io"

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

    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    print_success "AWS CLI is installed"

    local caller_identity_err
    if ! caller_identity_err=$(aws sts get-caller-identity 2>&1); then
        print_error "Not authenticated with AWS CLI:"
        echo "  $caller_identity_err"
        echo ""
        echo "  Try: 'aws configure' or 'aws sso login'"
        exit 1
    fi
    print_success "AWS CLI is authenticated"
}

# Get AWS account information
get_aws_info() {
    print_header "AWS Configuration"

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    CURRENT_REGION=$(aws configure get region 2>/dev/null || echo "")

    print_success "Account ID: $ACCOUNT_ID"

    if [ -n "$CURRENT_REGION" ]; then
        read -p "AWS Region [$CURRENT_REGION]: " AWS_REGION
        AWS_REGION=${AWS_REGION:-$CURRENT_REGION}
    else
        read -p "AWS Region: " AWS_REGION
        if [ -z "$AWS_REGION" ]; then
            print_error "AWS Region is required"
            exit 1
        fi
    fi

    print_success "Region: $AWS_REGION"
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
    read -p "Module Name (e.g., terraform-aws-vpc): " MODULE_NAME

    print_success "Organization: $ORG_NAME"
    if [ -n "$MODULE_NAME" ]; then
        print_success "Module: $MODULE_NAME"
    else
        print_success "Modules: All modules in organization"
    fi
}

# Create OIDC Provider
create_oidc_provider() {
    print_header "Creating OIDC Identity Provider"

    OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"

    # Check if OIDC provider already exists
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" &>/dev/null; then
        print_warning "OIDC Provider '${OIDC_PROVIDER_URL}' already exists"

        # Ensure aws.workload.identity is in the audience list
        EXISTING_AUDIENCES=$(aws iam get-open-id-connect-provider \
            --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" \
            --query "ClientIDList" --output text)

        if echo "$EXISTING_AUDIENCES" | grep -q "aws.workload.identity"; then
            print_success "Audience 'aws.workload.identity' already configured"
        else
            aws iam add-client-id-to-open-id-connect-provider \
                --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" \
                --client-id "aws.workload.identity"
            print_success "Added 'aws.workload.identity' audience to existing provider"
        fi
    else
        # Get the thumbprint
        THUMBPRINT=$(openssl s_client -connect "${OIDC_PROVIDER_URL}:443" -servername "${OIDC_PROVIDER_URL}" \
            </dev/null 2>/dev/null | openssl x509 -fingerprint -sha1 -noout 2>/dev/null | \
            sed 's/sha1 Fingerprint=//;s/://g' | tr '[:upper:]' '[:lower:]')

        if [ -z "$THUMBPRINT" ]; then
            print_warning "Could not auto-detect thumbprint, using known value"
            THUMBPRINT="9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
        fi

        aws iam create-open-id-connect-provider \
            --url "https://${OIDC_PROVIDER_URL}" \
            --client-id-list "aws.workload.identity" \
            --thumbprint-list "$THUMBPRINT"
        print_success "Created OIDC Identity Provider: ${OIDC_PROVIDER_URL}"
    fi
}

# Create IAM Role with trust policy
create_iam_role() {
    print_header "Creating IAM Role"

    # Build the subject condition
    local sub_condition
    if [ -n "$MODULE_NAME" ]; then
        sub_condition="organization:${ORG_NAME}:module:${MODULE_NAME}:operation:test_run"
    else
        sub_condition="organization:${ORG_NAME}:module:*:operation:test_run"
    fi

    # Build trust policy - use StringLike for both when wildcards present,
    # otherwise merge aud and sub into a single StringEquals block
    if [[ "$sub_condition" == *"*"* ]]; then
        TRUST_POLICY=$(cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER_URL}:aud": "aws.workload.identity"
        },
        "StringLike": {
          "${OIDC_PROVIDER_URL}:sub": "${sub_condition}"
        }
      }
    }
  ]
}
EOF
)
    else
        TRUST_POLICY=$(cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER_URL}:aud": "aws.workload.identity",
          "${OIDC_PROVIDER_URL}:sub": "${sub_condition}"
        }
      }
    }
  ]
}
EOF
)
    fi

    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        print_warning "IAM Role '$ROLE_NAME' already exists"

        read -p "Update trust policy on existing role? (y/N): " UPDATE_ROLE
        if [[ "$UPDATE_ROLE" =~ ^[Yy]$ ]]; then
            aws iam update-assume-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-document "$TRUST_POLICY"
            print_success "Updated trust policy on role: $ROLE_NAME"
        fi
    else
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document "$TRUST_POLICY" \
            --description "IAM role for HCP Terraform module test dynamic credentials"
        print_success "Created IAM Role: $ROLE_NAME"
    fi

    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    print_success "Role ARN: $ROLE_ARN"
}

# Attach permissions policy
attach_permissions() {
    print_header "Attaching Permissions Policy"

    echo "Select a permissions level for module tests:"
    echo ""
    echo "  1) Read-only (sts:GetCallerIdentity only)"
    echo "  2) IAM role admin (for modules that create IAM custom roles)"
    echo "  3) PowerUser (broad access, excludes IAM management)"
    echo "  4) Skip (attach policies manually later)"
    echo ""
    read -p "Select option [1/2/3/4]: " PERM_OPTION

    case "$PERM_OPTION" in
        1)
            PERMISSIONS_POLICY=$(cat << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
EOF
)
            # Create or update inline policy
            aws iam put-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-name "$POLICY_NAME" \
                --policy-document "$PERMISSIONS_POLICY"
            print_success "Attached read-only permissions"
            ;;
        2)
            PERMISSIONS_POLICY=$(cat << 'EOF'
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
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)
            aws iam put-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-name "$POLICY_NAME" \
                --policy-document "$PERMISSIONS_POLICY"
            print_success "Attached IAM role admin permissions"
            ;;
        3)
            aws iam attach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn "arn:aws:iam::aws:policy/PowerUserAccess"
            print_success "Attached PowerUserAccess managed policy"
            ;;
        4)
            print_warning "Skipping permissions. Attach policies manually to role: $ROLE_NAME"
            ;;
        *)
            print_warning "Invalid option. Skipping permissions. Attach policies manually to role: $ROLE_NAME"
            ;;
    esac
}

# Print HCP Terraform configuration
print_hcp_config() {
    print_header "HCP Terraform Environment Variables"

    echo -e "Configure these environment variables in your HCP Terraform module test settings:\n"
    echo -e "${YELLOW}Variable${NC}                               ${YELLOW}Value${NC}"
    echo -e "─────────────────────────────────────────────────────────────────────────────"
    echo -e "TFC_AWS_PROVIDER_AUTH                     ${GREEN}true${NC}"
    echo -e "TFC_AWS_RUN_ROLE_ARN                      ${GREEN}${ROLE_ARN}${NC}"
    echo -e "TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE        ${GREEN}aws.workload.identity${NC}"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║   AWS Dynamic Credentials Setup for HCP Terraform Module Tests ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_prerequisites
    get_aws_info
    get_hcp_config

    echo ""
    echo -e "${YELLOW}The following resources will be created:${NC}"
    echo "  - OIDC Identity Provider: ${OIDC_PROVIDER_URL}"
    echo "  - IAM Role: ${ROLE_NAME}"
    echo ""
    read -p "Continue? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    create_oidc_provider
    create_iam_role
    attach_permissions
    print_hcp_config

    print_header "Setup Complete"
    echo -e "${GREEN}AWS resources have been created successfully!${NC}"
    echo -e "Configure the settings above in your registry module's test configuration."
}

main "$@"
