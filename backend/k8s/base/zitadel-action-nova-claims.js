/**
 * Zitadel Action: Nova User Claims Enrichment
 *
 * This Action is executed during OIDC token issuance (Pre-Token Creation flow)
 * to fetch user claims from Nova's identity-service and inject them into the
 * OIDC ID token and UserInfo response.
 *
 * Flow:
 * 1. Extract Zitadel user ID (which will be mapped to Nova user ID)
 * 2. Call Nova identity-service HTTP endpoint to fetch user claims
 * 3. Inject claims into the OIDC token (sub, preferred_username, name, email, etc.)
 *
 * Configuration Required:
 * - Action Name: nova_claims_enrichment
 * - Flow Type: Complement Token
 * - Triggers: Pre Userinfo creation, Pre access token creation
 * - Environment Variables:
 *   - IDENTITY_SERVICE_URL: http://identity-service:8081
 *   - INTERNAL_API_KEY: <secret-key>
 */

/**
 * Main function - executed by Zitadel Actions runtime
 * @param {object} ctx - Zitadel context object
 * @param {object} api - Zitadel API helpers
 */
function enrichClaims(ctx, api) {
  // Configuration from environment variables
  const identityServiceUrl = process.env.IDENTITY_SERVICE_URL || 'http://identity-service:8081';
  const internalApiKey = process.env.INTERNAL_API_KEY;

  if (!internalApiKey) {
    api.v1.log('ERROR: INTERNAL_API_KEY not configured');
    return; // Fail gracefully - don't block token issuance
  }

  // Get user ID from Zitadel context
  // In Zitadel, the user ID is available in ctx.user.id
  const zitadelUserId = ctx.user?.id;
  if (!zitadelUserId) {
    api.v1.log('WARNING: No user ID found in context');
    return;
  }

  // Map Zitadel user ID to Nova user ID
  // IMPORTANT: This assumes Zitadel users are created with their ID matching Nova user UUIDs
  // OR you need to maintain a mapping table (user metadata in Zitadel)
  const novaUserId = ctx.user.metadata?.nova_user_id || zitadelUserId;

  api.v1.log(`Fetching Nova user claims for user: ${novaUserId}`);

  try {
    // Fetch user claims from Nova identity-service
    const response = fetch(
      `${identityServiceUrl}/internal/zitadel/user-claims/${novaUserId}`,
      {
        method: 'GET',
        headers: {
          'X-Internal-API-Key': internalApiKey,
          'Content-Type': 'application/json',
        },
      }
    );

    if (!response.ok) {
      api.v1.log(`ERROR: Failed to fetch user claims: HTTP ${response.status}`);
      // Fail gracefully - use fallback claims from Zitadel
      setFallbackClaims(ctx, api);
      return;
    }

    const claims = response.json();
    api.v1.log(`Successfully fetched Nova user claims for ${claims.preferred_username}`);

    // Set standard OIDC claims
    api.v1.claims.setClaim('sub', claims.sub); // Nova user UUID
    api.v1.claims.setClaim('preferred_username', claims.preferred_username);
    api.v1.claims.setClaim('name', claims.name || claims.preferred_username);
    api.v1.claims.setClaim('email', claims.email);
    api.v1.claims.setClaim('email_verified', claims.email_verified);

    // Set optional claims
    if (claims.picture) {
      api.v1.claims.setClaim('picture', claims.picture);
    }
    if (claims.given_name) {
      api.v1.claims.setClaim('given_name', claims.given_name);
    }
    if (claims.family_name) {
      api.v1.claims.setClaim('family_name', claims.family_name);
    }
    if (claims.locale) {
      api.v1.claims.setClaim('locale', claims.locale);
    }
    if (claims.phone_number) {
      api.v1.claims.setClaim('phone_number', claims.phone_number);
      api.v1.claims.setClaim('phone_number_verified', claims.phone_number_verified || false);
    }

    // Set custom Nova claims (namespaced)
    if (claims.bio) {
      api.v1.claims.setClaim('https://nova.app/claims/bio', claims.bio);
    }
    api.v1.claims.setClaim('https://nova.app/claims/created_at', claims.created_at);
    api.v1.claims.setClaim('https://nova.app/claims/updated_at', claims.updated_at);

    api.v1.log('Nova user claims enrichment completed successfully');
  } catch (error) {
    api.v1.log(`ERROR: Exception during claims fetch: ${error.message}`);
    // Fail gracefully - use fallback claims
    setFallbackClaims(ctx, api);
  }
}

/**
 * Set fallback claims from Zitadel user data
 * Used when Nova identity-service is unavailable
 */
function setFallbackClaims(ctx, api) {
  api.v1.log('Using fallback claims from Zitadel user data');

  // Use Zitadel's built-in user data as fallback
  if (ctx.user?.preferredUsername) {
    api.v1.claims.setClaim('preferred_username', ctx.user.preferredUsername);
  }
  if (ctx.user?.email) {
    api.v1.claims.setClaim('email', ctx.user.email);
    api.v1.claims.setClaim('email_verified', ctx.user.emailVerified || false);
  }
  if (ctx.user?.displayName) {
    api.v1.claims.setClaim('name', ctx.user.displayName);
  }
}

// Execute the enrichment
enrichClaims(ctx, api);
