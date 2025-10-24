# IBM API Connect + Keycloak OAuth Integration Guide

## Overview

This guide provides a complete setup for integrating IBM API Connect v10.0.8.0 with Keycloak v7.6.11.GA as the OAuth 2.0/OIDC provider. The architecture follows best practices where:

- **Keycloak** handles authentication and authorization
- **APIC** validates JWT tokens using JWKS (no introspection calls needed)
- **Developer Portal** manages app registration with automatic client sync to Keycloak

## Architecture

```
┌─────────────┐
│   End User  │
└──────┬──────┘
       │
       │ 1. Request API
       ▼
┌─────────────────┐
│  Application    │
│  (Mobile/Web)   │
└────────┬────────┘
         │
         │ 2. OAuth Flow
         ▼
┌──────────────────────┐         ┌─────────────────┐
│     Keycloak         │◄────────┤  Developer      │
│  (Authentication)    │  Sync   │  Portal         │
└──────────┬───────────┘         └─────────────────┘
           │                     (App Registration)
           │ 3. JWT Token
           ▼
┌──────────────────────┐
│   APIC Gateway       │
│  (JWT Validation)    │
└──────────┬───────────┘
           │
           │ 4. API Request
           ▼
┌──────────────────────┐
│   Backend Service    │
│   (FHIR Server)      │
└──────────────────────┘
```

## Prerequisites

- IBM API Connect v10.0.8.0 installed and running
- Keycloak v7.6.11.GA installed and running
- SSL/TLS certificates configured
- Network connectivity between APIC and Keycloak
- Admin access to both systems

## Setup Steps

### 1. Keycloak Configuration

#### 1.1 Import Realm Configuration

```bash
# Import the realm configuration
docker exec -it keycloak /opt/jboss/keycloak/bin/standalone.sh \
  -Dkeycloak.migration.action=import \
  -Dkeycloak.migration.provider=singleFile \
  -Dkeycloak.migration.file=/tmp/keycloak-realm-config.json \
  -Dkeycloak.migration.strategy=OVERWRITE_EXISTING
```

Or manually:

1. Login to Keycloak Admin Console: `https://keycloak.yourdomain.com:8443/auth/admin`
2. Navigate to **Add Realm**
3. Import `keycloak-realm-config.json`
4. Verify realm `apic-integration` is created

#### 1.2 Configure Clients

The realm configuration includes two clients:

1. **apic-native-oauth**: Used by APIC gateway for OAuth flows
   - Client ID: `apic-native-oauth`
   - Client Secret: Update in configuration
   - Grant Types: Authorization Code, Refresh Token
   - Redirect URIs: Update with your APIC gateway URLs

2. **apic-developer-portal**: Used by developer portal for client management
   - Client ID: `apic-developer-portal`
   - Service Account enabled for admin API access

#### 1.3 Create Test Users

Users are included in the realm config, or create manually:

```bash
# Create user via CLI
docker exec -it keycloak /opt/jboss/keycloak/bin/kcadm.sh create users \
  -r apic-integration \
  -s username=testuser \
  -s email=testuser@example.com \
  -s firstName=Test \
  -s lastName=User \
  -s enabled=true
  
# Set password
docker exec -it keycloak /opt/jboss/keycloak/bin/kcadm.sh set-password \
  -r apic-integration \
  --username testuser \
  --new-password Password123!
```

#### 1.4 Verify JWKS Endpoint

Verify the JWKS endpoint is accessible:

```bash
curl https://keycloak.yourdomain.com:8443/auth/realms/apic-integration/protocol/openid-connect/certs
```

Expected response:
```json
{
  "keys": [
    {
      "kid": "...",
      "kty": "RSA",
      "alg": "RS256",
      "use": "sig",
      "n": "...",
      "e": "AQAB"
    }
  ]
}
```

### 2. IBM API Connect Configuration

#### 2.1 Create OAuth Provider

1. Login to API Manager: `https://your-apic-manager.com`
2. Navigate to **Resources** > **OAuth Providers**
3. Click **Create**
4. Use configuration from `apic-oauth-provider-config.yaml`

Key settings:
- **Provider Type**: Third Party OAuth
- **Authorization Endpoint**: Keycloak auth endpoint
- **Token Endpoint**: Keycloak token endpoint
- **JWKS URI**: Keycloak certs endpoint
- **Token Validation**: JWT with JWKS

#### 2.2 Configure TLS Client Profile

1. Navigate to **Resources** > **TLS Client Profiles**
2. Create profile `keycloak-tls-profile`
3. Upload Keycloak CA certificate or configure trust

#### 2.3 Deploy Sample API

1. Navigate to **Develop** > **APIs**
2. Click **Add** > **API from file**
3. Upload `sample-patient-api.yaml`
4. Review and save
5. Publish to Sandbox catalog

#### 2.4 Test OAuth Flow

Using API Designer test tool:
1. Open the Patient API
2. Click **Test**
3. Authenticate with OAuth
4. Use test credentials: `testuser` / `Password123!`
5. Execute API call

### 3. Developer Portal Configuration

#### 3.1 Enable OAuth in Portal

1. Login to Developer Portal admin
2. Navigate to **Configuration** > **OAuth**
3. Enable OAuth provider
4. Configure settings from `developer-portal-config.json`

#### 3.2 Deploy Client Manager

Deploy the Keycloak client manager script:

```bash
# Copy the client manager
cp keycloak-client-manager.js /path/to/portal/extensions/

# Install dependencies
cd /path/to/portal/extensions/
npm install axios

# Configure environment variables
export KEYCLOAK_BASE_URL=https://keycloak.yourdomain.com:8443/auth
export KEYCLOAK_REALM=apic-integration
export KEYCLOAK_ADMIN_USER=admin
export KEYCLOAK_ADMIN_PASSWORD=admin-password
```

#### 3.3 Test App Registration

1. Login to Developer Portal as a developer
2. Navigate to **Apps** > **Create App**
3. Fill in app details:
   - Name: Test Application
   - Description: Test app for OAuth
   - Redirect URIs: https://example.com/callback
   - Application Type: Web Application

4. Submit and verify:
   - Client ID is generated
   - Client Secret is displayed
   - Client is created in Keycloak

### 4. Integration Testing

#### 4.1 Test Authorization Code Flow

```bash
# 1. Get authorization code
# Open in browser:
https://keycloak.yourdomain.com:8443/auth/realms/apic-integration/protocol/openid-connect/auth?client_id=YOUR_CLIENT_ID&redirect_uri=https://example.com/callback&response_type=code&scope=openid%20api_access

# 2. Exchange code for token
curl -X POST https://keycloak.yourdomain.com:8443/auth/realms/apic-integration/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "code=AUTHORIZATION_CODE" \
  -d "redirect_uri=https://example.com/callback"

# 3. Use access token to call API
curl -X GET https://api.yourdomain.com/fhir/v1/Patient \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

#### 4.2 Test JWT Validation

Verify APIC is validating JWT tokens correctly:

```bash
# Call API with valid token - should succeed
curl -X GET https://api.yourdomain.com/fhir/v1/Patient \
  -H "Authorization: Bearer VALID_TOKEN"

# Call API with expired token - should fail with 401
curl -X GET https://api.yourdomain.com/fhir/v1/Patient \
  -H "Authorization: Bearer EXPIRED_TOKEN"

# Call API with invalid signature - should fail with 401
curl -X GET https://api.yourdomain.com/fhir/v1/Patient \
  -H "Authorization: Bearer TAMPERED_TOKEN"
```

#### 4.3 Verify Token Claims

Decode JWT token to verify claims:

```bash
# Decode JWT (use jwt.io or jwt-cli)
echo "ACCESS_TOKEN" | jwt decode -

# Expected claims:
# - iss: https://keycloak.yourdomain.com:8443/auth/realms/apic-integration
# - sub: user-id
# - azp: client-id
# - email: user@example.com
# - organization: Test Organization
```

## Security Considerations

### 1. Token Validation

- **Use JWT validation with JWKS** (not introspection) for better performance
- APIC caches public keys from JWKS endpoint
- Verify signature, expiration, issuer, and audience

### 2. Client Credentials

- Store client secrets securely (use secrets management)
- Rotate client secrets periodically (90 days recommended)
- Use different credentials for each environment

### 3. TLS/SSL

- Enable TLS 1.2 or higher
- Use valid certificates (not self-signed in production)
- Configure mutual TLS if required

### 4. Token Expiration

- Access token: 5 minutes (300 seconds)
- Refresh token: 30 days (2592000 seconds)
- Adjust based on security requirements

### 5. Scopes and Roles

- Use scopes to control API access
- Map Keycloak roles to API permissions
- Implement least privilege principle

## Troubleshooting

### Issue: APIC cannot reach Keycloak

**Solution:**
```bash
# Test connectivity from APIC gateway
curl -v https://keycloak.yourdomain.com:8443/auth/realms/apic-integration/.well-known/openid-configuration

# Check TLS certificate
openssl s_client -connect keycloak.yourdomain.com:8443

# Verify DNS resolution
nslookup keycloak.yourdomain.com
```

### Issue: JWT validation fails

**Solution:**
1. Verify JWKS endpoint is accessible
2. Check token issuer matches expected value
3. Verify token audience includes client ID
4. Check clock skew settings (allow 60 seconds)

### Issue: Client registration fails

**Solution:**
1. Verify Keycloak admin credentials
2. Check service account permissions
3. Review Keycloak logs: `/opt/jboss/keycloak/standalone/log/server.log`
4. Test admin API access manually

### Issue: Redirect URI mismatch

**Solution:**
- Ensure redirect URIs in client config match exactly
- Include all callback URLs (trailing slashes matter)
- Use wildcards only in development

## Performance Optimization

### 1. JWKS Caching

APIC caches JWKS keys to reduce calls to Keycloak:
- Cache duration: 600 seconds (default)
- Adjust in OAuth provider configuration

### 2. Token Caching

Enable token caching in applications:
- Cache access tokens until expiration
- Use refresh tokens to get new access tokens
- Implement token refresh before expiration

### 3. Rate Limiting

Configure rate limits per plan:
- Bronze: 100 requests/hour
- Silver: 1000 requests/hour
- Gold: 10000 requests/hour

## Monitoring and Logging

### 1. APIC Analytics

Monitor OAuth metrics:
- Token validation success/failure rate
- API calls per client
- Response times

### 2. Keycloak Events

Enable event logging in Keycloak:
- Login events
- Token generation
- Client registration

### 3. Alerts

Set up alerts for:
- High token validation failure rate
- Keycloak service unavailability
- Unusual API access patterns

## Best Practices

1. **Use JWT validation** instead of token introspection
2. **Implement PKCE** for public clients (mobile/SPA)
3. **Rotate secrets regularly** (90-day cycle)
4. **Monitor token validation** metrics
5. **Use separate realms** for different environments
6. **Implement proper error handling** in applications
7. **Test OAuth flows** thoroughly before production
8. **Document redirect URIs** for each application
9. **Use state parameter** to prevent CSRF attacks
10. **Implement proper logout** (single sign-out)

## References

- [IBM API Connect Documentation](https://www.ibm.com/docs/en/api-connect/10.0.8)
- [Keycloak Documentation](https://www.keycloak.org/docs/7.0/)
- [OAuth 2.0 RFC 6749](https://tools.ietf.org/html/rfc6749)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)
- [JWT RFC 7519](https://tools.ietf.org/html/rfc7519)

## Support

For issues or questions:
- APIC Support: api-support@example.com
- Keycloak Support: keycloak-support@example.com
- Documentation: https://docs.example.com

## Appendix: Configuration Files

All configuration files are included in this repository:

1. `keycloak-realm-config.json` - Keycloak realm configuration
2. `apic-oauth-provider-config.yaml` - APIC OAuth provider settings
3. `developer-portal-config.json` - Developer portal configuration
4. `keycloak-client-manager.js` - Client management script
5. `sample-patient-api.yaml` - Sample FHIR API definition
6. `what_to_do.txt` - Original requirements

## Version History

- **v1.0.0** (2025-10-23): Initial setup guide
  - APIC v10.0.8.0
  - Keycloak v7.6.11.GA
  - JWT validation with JWKS
  - Developer portal integration
