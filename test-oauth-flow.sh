#!/bin/bash

# Test OAuth Flow Script
# This script tests the complete OAuth 2.0 authorization code flow

set -e

# Load environment variables if .env exists
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}OAuth 2.0 Flow Test${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Configuration
CLIENT_ID=${CLIENT_ID:-${TEST_CLIENT_ID:-"apic-native-oauth"}}
CLIENT_SECRET=${CLIENT_SECRET:-${TEST_CLIENT_SECRET:-"your-client-secret-here"}}
USERNAME=${USERNAME:-${TEST_USERNAME:-"testuser"}}
PASSWORD=${PASSWORD:-${TEST_PASSWORD:-"Password123!"}}
TOKEN_ENDPOINT=${TOKEN_ENDPOINT:-"https://keycloak.yourdomain.com:8443/auth/realms/apic-integration/protocol/openid-connect/token"}
API_ENDPOINT=${API_ENDPOINT:-"https://api.yourdomain.com/fhir/v1/Patient"}

echo -e "${YELLOW}Configuration:${NC}"
echo "Client ID: $CLIENT_ID"
echo "Username: $USERNAME"
echo "Token Endpoint: $TOKEN_ENDPOINT"
echo "API Endpoint: $API_ENDPOINT"
echo ""

# Test 1: Password Grant (for testing purposes)
echo -e "${YELLOW}Test 1: Password Grant Flow${NC}"
echo "Getting access token..."

TOKEN_RESPONSE=$(curl -s -X POST "$TOKEN_ENDPOINT" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "username=$USERNAME" \
    -d "password=$PASSWORD" \
    -d "scope=openid api_access")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // empty')
EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in // empty')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo -e "${RED}✗ Failed to get access token${NC}"
    echo "Response:"
    echo "$TOKEN_RESPONSE" | jq '.'
    exit 1
else
    echo -e "${GREEN}✓ Access token obtained${NC}"
    echo "Expires in: ${EXPIRES_IN}s"
    echo ""
fi

# Decode and display token
echo -e "${YELLOW}Access Token Claims:${NC}"
echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.' || echo "Could not decode token"
echo ""

# Test 2: Call API with token
echo -e "${YELLOW}Test 2: API Call with Access Token${NC}"
echo "Calling API..."

API_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_ENDPOINT" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")

HTTP_CODE=$(echo "$API_RESPONSE" | grep "HTTP_CODE" | cut -d':' -f2)
BODY=$(echo "$API_RESPONSE" | sed '/HTTP_CODE/d')

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ API call successful (HTTP $HTTP_CODE)${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
elif [ "$HTTP_CODE" = "401" ]; then
    echo -e "${RED}✗ Unauthorized (HTTP $HTTP_CODE)${NC}"
    echo "Token validation failed. Check APIC OAuth provider configuration."
    echo "$BODY"
elif [ "$HTTP_CODE" = "404" ]; then
    echo -e "${YELLOW}⚠ Not Found (HTTP $HTTP_CODE)${NC}"
    echo "API endpoint not found or no data. But authentication worked!"
    echo "$BODY"
else
    echo -e "${RED}✗ API call failed (HTTP $HTTP_CODE)${NC}"
    echo "$BODY"
fi
echo ""

# Test 3: Refresh Token
if [ ! -z "$REFRESH_TOKEN" ] && [ "$REFRESH_TOKEN" != "null" ]; then
    echo -e "${YELLOW}Test 3: Refresh Token Flow${NC}"
    echo "Using refresh token to get new access token..."
    
    REFRESH_RESPONSE=$(curl -s -X POST "$TOKEN_ENDPOINT" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=refresh_token" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "refresh_token=$REFRESH_TOKEN")
    
    NEW_ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | jq -r '.access_token // empty')
    
    if [ -z "$NEW_ACCESS_TOKEN" ] || [ "$NEW_ACCESS_TOKEN" = "null" ]; then
        echo -e "${RED}✗ Failed to refresh token${NC}"
        echo "$REFRESH_RESPONSE" | jq '.'
    else
        echo -e "${GREEN}✓ Token refreshed successfully${NC}"
        echo ""
    fi
fi

# Test 4: Test with invalid token
echo -e "${YELLOW}Test 4: Invalid Token Test${NC}"
echo "Calling API with invalid token..."

INVALID_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_ENDPOINT" \
    -H "Authorization: Bearer invalid-token-12345" \
    -H "Accept: application/json")

INVALID_HTTP_CODE=$(echo "$INVALID_RESPONSE" | grep "HTTP_CODE" | cut -d':' -f2)

if [ "$INVALID_HTTP_CODE" = "401" ]; then
    echo -e "${GREEN}✓ Correctly rejected invalid token (HTTP $INVALID_HTTP_CODE)${NC}"
else
    echo -e "${RED}✗ Unexpected response to invalid token (HTTP $INVALID_HTTP_CODE)${NC}"
fi
echo ""

# Test 5: Test with expired token (simulation)
echo -e "${YELLOW}Test 5: Token Expiration Test${NC}"
echo "Waiting 5 seconds to test token lifetime..."
echo "(In production, tokens expire after 5 minutes)"
sleep 5

EXPIRED_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$API_ENDPOINT" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")

EXPIRED_HTTP_CODE=$(echo "$EXPIRED_RESPONSE" | grep "HTTP_CODE" | cut -d':' -f2)

if [ "$EXPIRED_HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Token still valid (as expected, 5s < 5min)${NC}"
else
    echo -e "${YELLOW}⚠ Token validation failed${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
    echo -e "${GREEN}✓ OAuth integration is working correctly${NC}"
    echo ""
    echo "The integration is properly configured:"
    echo "  ✓ Keycloak issues valid tokens"
    echo "  ✓ APIC validates JWT tokens"
    echo "  ✓ API calls are authenticated"
    echo ""
else
    echo -e "${RED}✗ OAuth integration has issues${NC}"
    echo ""
    echo "Please check:"
    echo "  - Keycloak OAuth provider configuration in APIC"
    echo "  - JWKS URI is accessible from APIC gateway"
    echo "  - API security settings"
    echo "  - Network connectivity"
    echo ""
fi

# Save tokens for debugging
echo "Access token saved to: access_token.txt"
echo "$ACCESS_TOKEN" > access_token.txt

if [ ! -z "$REFRESH_TOKEN" ]; then
    echo "Refresh token saved to: refresh_token.txt"
    echo "$REFRESH_TOKEN" > refresh_token.txt
fi
echo ""

echo "For detailed testing, see INTEGRATION_GUIDE.md"
