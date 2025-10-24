# Quick Start Guide

## Prerequisites Check

Before starting, ensure you have:
- [ ] IBM API Connect v10.0.8.0 running
- [ ] Keycloak v7.6.11.GA running  
- [ ] SSL certificates configured
- [ ] Admin access to both systems

## 5-Minute Setup

### Step 1: Import Keycloak Realm (2 min)

```bash
# Import realm configuration
docker exec -it keycloak /opt/jboss/keycloak/bin/standalone.sh \
  -Dkeycloak.migration.action=import \
  -Dkeycloak.migration.provider=singleFile \
  -Dkeycloak.migration.file=/path/to/keycloak-realm-config.json
```

Or via Admin Console:
1. Login: https://keycloak.yourdomain.com:8443/auth/admin
2. **Add Realm** → Import `keycloak-realm-config.json`

### Step 2: Configure APIC OAuth Provider (2 min)

1. Login to API Manager
2. **Resources** → **OAuth Providers** → **Create**
3. Use settings from `apic-oauth-provider-config.yaml`:
   - Authorization URL: `https://keycloak.yourdomain.com:8443/auth/realms/apic-integration/protocol/openid-connect/auth`
   - Token URL: `https://keycloak.yourdomain.com:8443/auth/realms/apic-integration/protocol/openid-connect/token`
   - JWKS URL: `https://keycloak.yourdomain.com:8443/auth/realms/apic-integration/protocol/openid-connect/certs`

### Step 3: Deploy Sample API (1 min)

1. **Develop** → **Add API from file**
2. Upload `sample-patient-api.yaml`
3. **Publish** to Sandbox catalog

### Step 4: Test (30 seconds)

```bash
# Get token
TOKEN=$(curl -X POST https://keycloak.yourdomain.com:8443/auth/realms/apic-integration/protocol/openid-connect/token \
  -d "grant_type=password" \
  -d "client_id=apic-native-oauth" \
  -d "client_secret=your-client-secret-here" \
  -d "username=testuser" \
  -d "password=Password123!" \
  | jq -r '.access_token')

# Call API
curl -H "Authorization: Bearer $TOKEN" \
  https://api.yourdomain.com/fhir/v1/Patient
```

## What You Get

✅ **Keycloak** handling authentication  
✅ **APIC** validating JWT tokens with JWKS  
✅ **Sample FHIR API** secured with OAuth  
✅ **Developer Portal** ready for app registration  
✅ **Production-ready** architecture

## Next Steps

1. Customize realm settings in `keycloak-realm-config.json`
2. Update URLs in configuration files
3. Deploy developer portal with `keycloak-client-manager.js`
4. Review full `INTEGRATION_GUIDE.md` for details

## Need Help?

See `INTEGRATION_GUIDE.md` for:
- Detailed setup instructions
- Troubleshooting guide
- Security considerations
- Performance optimization
