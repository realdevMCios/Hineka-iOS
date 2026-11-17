# Hineka account-linking plan

Status: design only. Microsoft/Minecraft authentication and entitlement verification are **not implemented**.

## Goal

Let a user connect a Microsoft account they personally control, then determine whether the account has the Minecraft Java Edition entitlement required by Hineka's planned Java launcher. This is a bring-your-own-license design, not an account shop.

## Non-negotiable safeguards

- Use only a currently supported Microsoft/Minecraft authentication flow and follow the current developer requirements for client registration, redirect URIs, scopes, and token exchange.
- The user must sign in on the official Microsoft-controlled authentication surface. Never build a Hineka password field for Microsoft credentials.
- Never ask for, accept, log, or store Microsoft passwords, OTPs, recovery codes, backup codes, session cookies, or credentials supplied by a seller.
- Never let a user transfer an account to another Hineka user, and never offer accounts for sale, rent, sharing, or resale.
- Do not store long-lived tokens on Hineka's backend unless the official integration explicitly requires it and the security/privacy review approves it. If the native app must retain a token, use the iOS Keychain and the minimum required lifetime/scopes.
- Support unlink/sign-out, token revocation where supported, clear consent, and privacy disclosures.
- Do not treat a successful Microsoft sign-in, Xbox profile, gamertag, or username as proof of Minecraft Java ownership. Verify the game entitlement through the documented Minecraft service flow.
- Keep the launcher disabled when authentication or entitlement verification is unavailable or inconclusive. Never bypass authentication checks.

## Planned flow

1. Present a clear "Connect your Microsoft account" explanation and privacy notice.
2. Start the official Microsoft sign-in flow using the approved app registration and redirect configuration.
3. Complete the required Microsoft/Xbox/Minecraft token exchange exactly as documented by the supported service flow.
4. Retrieve the minimum profile data required by the launcher.
5. Check the Java Edition entitlement using the official documented entitlement mechanism.
6. Store only a minimal linked-account identifier and entitlement result needed for the session. Protect any necessary tokens with Keychain; do not persist raw passwords or one-time codes.
7. Let the user disconnect the account and clear local tokens/data.

## UI requirements

- Explain that the user must own and control their own Minecraft account/license.
- Link to official purchase/account pages for users who do not own Minecraft; do not offer third-party accounts or credentials.
- Show clear states: Not connected, Authentication cancelled, Connected, Java entitlement confirmed, No Java entitlement detected, and Verification unavailable.
- Do not expose raw tokens, email addresses, or sensitive authentication data in logs or screenshots.
- Do not claim "Premium account for sale" or imply Hineka includes the Minecraft license.

## Implementation gate

Before writing the authentication client, verify the current Microsoft identity platform and Minecraft Services documentation, app-registration requirements, permitted use, redirect behavior on iOS, token lifetime/refresh rules, and Java entitlement endpoint. Obtain any required registration/permission and have a parent/guardian review the legal/privacy implications. Until that work is complete, account linking and Minecraft launch must remain unavailable.
