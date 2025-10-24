#!/bin/bash

# APIC + Keycloak Integration - Setup Script
# This script automates the setup process for the integration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
KEYCLOAK_URL=${KEYCLOAK_URL:-"https://keycloak.yourdomain.com:8443"}
APIC_MANAGER_URL=${APIC_MANAGER_URL:-"https://your-apic-manager.com"}
REALM_NAME=${REALM_NAME:-"apic-integration"}

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}APIC + Keycloak Integration Setup${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command_exists curl; then
    echo -e "${RED}Error: curl is not installed${NC}"
    exit 1
fi

if ! command_exists jq; then
    echo -e "${RED}Error: jq is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites checked${NC}"
echo ""

# Test Keycloak connectivity
echo -e "${YELLOW}Testing Keycloak connectivity...${NC}"
if curl -f -s "${KEYCLOAK_URL}/auth" > /dev/null; then
    echo -e "${GREEN}✓ Keycloak is accessible${NC}"
else
    echo -e "${RED}✗ Cannot reach Keycloak at ${KEYCLOAK_URL}${NC}"
    exit 1
fi
echo ""

# Check if realm exists
echo -e "${YELLOW}Checking if realm '${REALM_NAME}' exists...${NC}"
REALM_CHECK=$(curl -s "${KEYCLOAK_URL}/auth/realms/${REALM_NAME}" | jq -r '.realm // empty')

if [ -z "$REALM_CHECK" ]; then
    echo -e "${YELLOW}Realm does not exist. Would you like to import it? (y/n)${NC}"
    read -r IMPORT_REALM
    
    if [ "$IMPORT_REALM" = "y" ]; then
        echo -e "${YELLOW}Please import keycloak-realm-config.json manually via Keycloak Admin Console${NC}"
        echo -e "${YELLOW}URL: ${KEYCLOAK_URL}/auth/admin${NC}"
        echo ""
        echo "Press Enter when done..."
        read -r
    else
        echo -e "${RED}Setup cannot continue without realm${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Realm '${REALM_NAME}' exists${NC}"
fi
echo ""

# Get OIDC configuration
echo -e "${YELLOW}Fetching OIDC configuration...${NC}"
OIDC_CONFIG=$(curl -s "${KEYCLOAK_URL}/auth/realms/${REALM_NAME}/.well-known/openid-configuration")

AUTH_ENDPOINT=$(echo "$OIDC_CONFIG" | jq -r '.authorization_endpoint')
TOKEN_ENDPOINT=$(echo "$OIDC_CONFIG" | jq -r '.token_endpoint')
JWKS_URI=$(echo "$OIDC_CONFIG" | jq -r '.jwks_uri')

echo "Authorization Endpoint: $AUTH_ENDPOINT"
echo "Token Endpoint: $TOKEN_ENDPOINT"
echo "JWKS URI: $JWKS_URI"
echo ""

# Verify JWKS endpoint
echo -e "${YELLOW}Verifying JWKS endpoint...${NC}"
JWKS_RESPONSE=$(curl -s "$JWKS_URI")
KEY_COUNT=$(echo "$JWKS_RESPONSE" | jq '.keys | length')

if [ "$KEY_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ JWKS endpoint is working (${KEY_COUNT} keys found)${NC}"
else
    echo -e "${RED}✗ JWKS endpoint returned no keys${NC}"
    exit 1
fi
echo ""

# Test user credentials
echo -e "${YELLOW}Testing default user credentials...${NC}"
TOKEN_RESPONSE=$(curl -s -X POST "$TOKEN_ENDPOINT" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=apic-native-oauth" \
    -d "client_secret=your-client-secret-here" \
    -d "username=testuser" \
    -d "password=Password123!")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo -e "${RED}✗ Failed to get access token${NC}"
    echo "Response: $TOKEN_RESPONSE"
    echo ""
    echo -e "${YELLOW}Please update client secret in keycloak-realm-config.json${NC}"
else
    echo -e "${GREEN}✓ Successfully obtained access token${NC}"
    echo ""
    
    # Decode and display token claims
    echo -e "${YELLOW}Token claims:${NC}"
    echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.' || echo "Could not decode token"
fi
echo ""

# Generate configuration summary
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Configuration Summary${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Copy these values to your APIC OAuth Provider configuration:"
echo ""
echo "Authorization Endpoint: $AUTH_ENDPOINT"
echo "Token Endpoint: $TOKEN_ENDPOINT"
echo "JWKS URI: $JWKS_URI"
echo "Issuer: ${KEYCLOAK_URL}/auth/realms/${REALM_NAME}"
echo ""

# Create environment variables file
echo -e "${YELLOW}Creating .env file...${NC}"
cat > .env << EOF
# APIC + Keycloak Integration Environment Variables
# Generated on $(date)

KEYCLOAK_URL=${KEYCLOAK_URL}
KEYCLOAK_REALM=${REALM_NAME}
APIC_MANAGER_URL=${APIC_MANAGER_URL}

# OAuth Endpoints
AUTHORIZATION_ENDPOINT=${AUTH_ENDPOINT}
TOKEN_ENDPOINT=${TOKEN_ENDPOINT}
JWKS_URI=${JWKS_URI}
ISSUER=${KEYCLOAK_URL}/auth/realms/${REALM_NAME}

# Test Credentials
TEST_USERNAME=testuser
TEST_PASSWORD=Password123!
TEST_CLIENT_ID=apic-native-oauth
TEST_CLIENT_SECRET=your-client-secret-here
EOF

echo -e "${GREEN}✓ .env file created${NC}"
echo ""

# Next steps
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Next Steps${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "1. Update client secrets in .env file"
echo "2. Import OAuth Provider in APIC Manager"
echo "3. Deploy sample API (sample-patient-api.yaml)"
echo "4. Configure Developer Portal"
echo "5. Test the integration with test-oauth-flow.sh"
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "For detailed instructions, see INTEGRATION_GUIDE.md"
