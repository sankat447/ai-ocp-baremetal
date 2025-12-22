#!/bin/bash
# =============================================================================
# MongoDB User Setup Script for OpsTree Labs MongoDB Operator
# =============================================================================
# This script creates additional users in MongoDB after the cluster is deployed
# The OpsTree Labs operator only creates the admin user, so we need to manually
# create application-specific users.
# =============================================================================

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-aitp-data}"
MONGODB_CLUSTER_NAME="${MONGODB_CLUSTER_NAME:-aitp-mongodb}"
ADMIN_USER="${ADMIN_USER:-aitp-admin}"
ADMIN_SECRET="${ADMIN_SECRET:-mongodb-admin-password}"
ADMIN_SECRET_KEY="${ADMIN_SECRET_KEY:-password}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Wait for MongoDB to be ready
# =============================================================================
wait_for_mongodb() {
    log_info "Waiting for MongoDB cluster to be ready..."
    
    local max_attempts=60
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        # Check if the primary pod is running and ready
        local ready=$(oc get pod ${MONGODB_CLUSTER_NAME}-0 -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        
        if [[ "${ready}" == "True" ]]; then
            log_info "MongoDB pod ${MONGODB_CLUSTER_NAME}-0 is ready!"
            
            # Additional check: wait for MongoDB to accept connections
            log_info "Checking MongoDB connectivity..."
            if oc exec ${MONGODB_CLUSTER_NAME}-0 -n ${NAMESPACE} -- mongosh --eval "db.runCommand({ping: 1})" &>/dev/null; then
                log_info "MongoDB is accepting connections!"
                return 0
            fi
        fi
        
        echo "Attempt ${attempt}/${max_attempts}: MongoDB not ready yet, waiting..."
        sleep 10
        ((attempt++))
    done
    
    log_error "MongoDB did not become ready in time"
    return 1
}

# =============================================================================
# Get admin password from secret
# =============================================================================
get_admin_password() {
    local password=$(oc get secret ${ADMIN_SECRET} -n ${NAMESPACE} -o jsonpath="{.data.${ADMIN_SECRET_KEY}}" 2>/dev/null | base64 -d)
    
    if [[ -z "${password}" ]]; then
        log_error "Could not retrieve admin password from secret ${ADMIN_SECRET}"
        exit 1
    fi
    
    echo "${password}"
}

# =============================================================================
# Get password from a secret
# =============================================================================
get_password_from_secret() {
    local secret_name=$1
    local key=${2:-password}
    
    local password=$(oc get secret ${secret_name} -n ${NAMESPACE} -o jsonpath="{.data.${key}}" 2>/dev/null | base64 -d)
    
    if [[ -z "${password}" ]]; then
        log_warn "Could not retrieve password from secret ${secret_name}, generating random password..."
        password=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)
        
        # Create the secret
        oc create secret generic ${secret_name} \
            --from-literal=${key}="${password}" \
            -n ${NAMESPACE} 2>/dev/null || true
    fi
    
    echo "${password}"
}

# =============================================================================
# Create MongoDB user
# =============================================================================
create_mongodb_user() {
    local username=$1
    local password=$2
    local database=$3
    local roles=$4  # JSON array of roles
    
    log_info "Creating user '${username}' in database '${database}'..."
    
    local admin_password=$(get_admin_password)
    
    # Create the user using mongosh
    oc exec ${MONGODB_CLUSTER_NAME}-0 -n ${NAMESPACE} -- mongosh \
        -u "${ADMIN_USER}" \
        -p "${admin_password}" \
        --authenticationDatabase admin \
        --eval "
            use ${database};
            
            // Drop user if exists (for idempotency)
            try {
                db.dropUser('${username}');
            } catch(e) {
                // User doesn't exist, that's fine
            }
            
            // Create the user
            db.createUser({
                user: '${username}',
                pwd: '${password}',
                roles: ${roles}
            });
            
            print('User ${username} created successfully in database ${database}');
        "
    
    if [[ $? -eq 0 ]]; then
        log_info "✅ User '${username}' created successfully!"
    else
        log_error "Failed to create user '${username}'"
        return 1
    fi
}

# =============================================================================
# Main function
# =============================================================================
main() {
    echo "=============================================="
    echo "MongoDB User Setup Script"
    echo "=============================================="
    echo "Namespace: ${NAMESPACE}"
    echo "MongoDB Cluster: ${MONGODB_CLUSTER_NAME}"
    echo "=============================================="
    echo ""
    
    # Wait for MongoDB to be ready
    wait_for_mongodb
    
    # Get passwords from secrets (or generate if not exist)
    log_info "Retrieving passwords from secrets..."
    LANGCHAIN_PASSWORD=$(get_password_from_secret "mongodb-langchain-password")
    LIBRECHAT_PASSWORD=$(get_password_from_secret "mongodb-librechat-password")
    
    # -------------------------------------------------------------------------
    # Create langchain user
    # -------------------------------------------------------------------------
    create_mongodb_user "langchain" "${LANGCHAIN_PASSWORD}" "conversations" '[
        { "role": "readWrite", "db": "conversations" },
        { "role": "readWrite", "db": "memory" }
    ]'
    
    # -------------------------------------------------------------------------
    # Create librechat user
    # -------------------------------------------------------------------------
    create_mongodb_user "librechat" "${LIBRECHAT_PASSWORD}" "librechat" '[
        { "role": "readWrite", "db": "librechat" }
    ]'
    
    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    echo ""
    echo "=============================================="
    log_info "✅ All MongoDB users created successfully!"
    echo "=============================================="
    echo ""
    echo "Users created:"
    echo "  - langchain (databases: conversations, memory)"
    echo "  - librechat (database: librechat)"
    echo ""
    echo "Connection strings:"
    echo "  - langchain: mongodb://langchain:<password>@${MONGODB_CLUSTER_NAME}-0.${MONGODB_CLUSTER_NAME}.${NAMESPACE}.svc.cluster.local:27017/conversations"
    echo "  - librechat: mongodb://librechat:<password>@${MONGODB_CLUSTER_NAME}-0.${MONGODB_CLUSTER_NAME}.${NAMESPACE}.svc.cluster.local:27017/librechat"
    echo ""
}

# =============================================================================
# Run main function
# =============================================================================
main "$@"
