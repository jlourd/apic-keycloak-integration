/**
 * Keycloak Client Manager for APIC Developer Portal
 * Handles client registration and lifecycle management
 */

const axios = require('axios');

class KeycloakClientManager {
  constructor(config) {
    this.baseUrl = config.baseUrl;
    this.realm = config.realm;
    this.adminUsername = config.adminUsername;
    this.adminPassword = config.adminPassword;
    this.accessToken = null;
  }

  /**
   * Authenticate with Keycloak Admin API
   */
  async authenticate() {
    try {
      const response = await axios.post(
        `${this.baseUrl}/realms/master/protocol/openid-connect/token`,
        new URLSearchParams({
          grant_type: 'password',
          client_id: 'admin-cli',
          username: this.adminUsername,
          password: this.adminPassword
        }),
        {
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded'
          }
        }
      );
      
      this.accessToken = response.data.access_token;
      return this.accessToken;
    } catch (error) {
      console.error('Keycloak authentication failed:', error.response?.data || error.message);
      throw new Error('Failed to authenticate with Keycloak');
    }
  }

  /**
   * Create a new client in Keycloak
   */
  async createClient(appData) {
    if (!this.accessToken) {
      await this.authenticate();
    }

    const clientConfig = {
      clientId: this.generateClientId(appData.name),
      name: appData.name,
      description: appData.description,
      enabled: true,
      clientAuthenticatorType: 'client-secret',
      redirectUris: appData.redirectUris,
      webOrigins: this.extractOrigins(appData.redirectUris),
      standardFlowEnabled: true,
      implicitFlowEnabled: false,
      directAccessGrantsEnabled: appData.type === 'service',
      serviceAccountsEnabled: appData.type === 'service',
      publicClient: appData.type === 'spa',
      protocol: 'openid-connect',
      attributes: {
        'access.token.lifespan': '300',
        'organization': appData.organization || ''
      },
      defaultClientScopes: ['openid', 'profile', 'email', 'api_access'],
      fullScopeAllowed: false
    };

    try {
      const response = await axios.post(
        `${this.baseUrl}/admin/realms/${this.realm}/clients`,
        clientConfig,
        {
          headers: {
            'Authorization': `Bearer ${this.accessToken}`,
            'Content-Type': 'application/json'
          }
        }
      );

      // Get the created client ID
      const locationHeader = response.headers.location;
      const keycloakClientId = locationHeader.split('/').pop();

      // Get client secret
      const secret = await this.getClientSecret(keycloakClientId);

      return {
        clientId: clientConfig.clientId,
        keycloakClientId: keycloakClientId,
        clientSecret: secret,
        redirectUris: appData.redirectUris
      };
    } catch (error) {
      console.error('Failed to create client:', error.response?.data || error.message);
      throw new Error('Failed to create client in Keycloak');
    }
  }

  /**
   * Get client secret
   */
  async getClientSecret(keycloakClientId) {
    try {
      const response = await axios.get(
        `${this.baseUrl}/admin/realms/${this.realm}/clients/${keycloakClientId}/client-secret`,
        {
          headers: {
            'Authorization': `Bearer ${this.accessToken}`
          }
        }
      );

      return response.data.value;
    } catch (error) {
      console.error('Failed to get client secret:', error.response?.data || error.message);
      return null;
    }
  }

  /**
   * Update client configuration
   */
  async updateClient(keycloakClientId, updates) {
    if (!this.accessToken) {
      await this.authenticate();
    }

    try {
      // Get current client config
      const currentClient = await axios.get(
        `${this.baseUrl}/admin/realms/${this.realm}/clients/${keycloakClientId}`,
        {
          headers: {
            'Authorization': `Bearer ${this.accessToken}`
          }
        }
      );

      // Merge updates
      const updatedConfig = {
        ...currentClient.data,
        ...updates
      };

      await axios.put(
        `${this.baseUrl}/admin/realms/${this.realm}/clients/${keycloakClientId}`,
        updatedConfig,
        {
          headers: {
            'Authorization': `Bearer ${this.accessToken}`,
            'Content-Type': 'application/json'
          }
        }
      );

      return { success: true };
    } catch (error) {
      console.error('Failed to update client:', error.response?.data || error.message);
      throw new Error('Failed to update client in Keycloak');
    }
  }

  /**
   * Delete client
   */
  async deleteClient(keycloakClientId) {
    if (!this.accessToken) {
      await this.authenticate();
    }

    try {
      await axios.delete(
        `${this.baseUrl}/admin/realms/${this.realm}/clients/${keycloakClientId}`,
        {
          headers: {
            'Authorization': `Bearer ${this.accessToken}`
          }
        }
      );

      return { success: true };
    } catch (error) {
      console.error('Failed to delete client:', error.response?.data || error.message);
      throw new Error('Failed to delete client in Keycloak');
    }
  }

  /**
   * Regenerate client secret
   */
  async regenerateClientSecret(keycloakClientId) {
    if (!this.accessToken) {
      await this.authenticate();
    }

    try {
      const response = await axios.post(
        `${this.baseUrl}/admin/realms/${this.realm}/clients/${keycloakClientId}/client-secret`,
        {},
        {
          headers: {
            'Authorization': `Bearer ${this.accessToken}`,
            'Content-Type': 'application/json'
          }
        }
      );

      return response.data.value;
    } catch (error) {
      console.error('Failed to regenerate secret:', error.response?.data || error.message);
      throw new Error('Failed to regenerate client secret');
    }
  }

  /**
   * Helper: Generate client ID from app name
   */
  generateClientId(appName) {
    return `apic-app-${appName.toLowerCase().replace(/[^a-z0-9]/g, '-')}-${Date.now()}`;
  }

  /**
   * Helper: Extract origins from redirect URIs
   */
  extractOrigins(redirectUris) {
    return redirectUris.map(uri => {
      const url = new URL(uri);
      return `${url.protocol}//${url.host}`;
    });
  }
}

module.exports = KeycloakClientManager;
