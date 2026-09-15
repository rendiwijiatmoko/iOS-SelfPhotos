# Single sign-on with Immich

SelfPhotos uses Immich's OAuth/OIDC mobile API. Enable OAuth on the Immich server. The authorization request uses Immich's standard `app.immich:///oauth-callback` URI. The callback is captured by SelfPhotos' `ASWebAuthenticationSession`, which delivers it to the app that started the login session even if the official Immich app is installed. SelfPhotos does not register `app.immich` as a general-purpose URL scheme.

After connecting to a compatible server, SelfPhotos shows an OAuth button when `GET /server/features` reports `oauth: true`. Its title comes from `oauthButtonText` in public `GET /server/config`, falling back to **Sign In with OAuth** if the config is unavailable or blank. A server may disable password login and still allow OAuth. The browser sign-in returns an authorization code to SelfPhotos, which exchanges it with Immich for an access token.

For providers such as Google that require an HTTPS redirect, enable Immich's **Mobile Redirect URI Override** and set it to `https://YOUR-IMMICH-DOMAIN/api/oauth/mobile-redirect`. Whitelist that exact HTTPS URL in the provider's OAuth client. Immich's bridge forwards the result to `app.immich:///oauth-callback`, which the authentication session captures.
