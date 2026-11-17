# Hineka API draft

Status: proposed contract for Hineka iOS (Minecraft Java launcher). No production API, Microsoft/Minecraft authentication, or payment gateway is connected.

## Principles
- The iOS client is untrusted. Server validates all inputs, permissions, catalogue prices, provider callbacks, and balances.
- Use HTTPS only. Authenticate Hineka guest sessions with a random, revocable token; never rely on a username alone for payment or private files.
- Never include provider partner keys, StoreKit private keys, Microsoft client secrets, or signing secrets in the app bundle.
- Use integer VND and integer Hineka Coins. Server owns the catalogue and ledger.
- Do not build endpoints that credit Coins directly from a client-provided amount.
- Hineka is bring-your-own-Minecraft-license only. No account marketplace, account transfer, account rental, password collection, or account-delivery endpoints.

## Guest session
### POST /v1/guest-sessions
Request:
```json
{ "display_name": "PlayerName" }
```
Response:
```json
{ "access_token": "opaque-random-token", "account_id": "acct_...", "account_type": "guest" }
```
The display name is not proof of identity. Guest accounts cannot securely own transferable value until upgraded to a stronger authentication method. Apply rate limits and device/session abuse controls.

## Microsoft/Minecraft account linking (planned; no endpoint approved yet)

The client must use a currently documented official Microsoft/Minecraft authentication flow. Before defining endpoints, verify the supported iOS OAuth/client registration requirements, token exchange, scopes, redirect handling, and Java Edition entitlement API.

Requirements:
- Authentication must happen on the official Microsoft-controlled sign-in surface.
- Do not accept Microsoft passwords, one-time codes, recovery codes, or seller-provided credentials in Hineka API requests.
- Do not treat Microsoft sign-in alone as proof of Minecraft Java ownership; validate entitlement through the official documented service.
- Keep only minimal account identifiers and entitlement state. Protect required client tokens in iOS Keychain; backend token retention requires a separate security/privacy decision.
- Provide unlink/revoke handling where supported.
- Do not expose endpoints for listing, selling, transferring, renting, or delivering accounts.

## Catalogue
### GET /v1/catalog/minecraft-versions
Returns supported Minecraft Java versions and compatible runtime metadata.

### GET /v1/catalog/mods
Optional query fields: `minecraft_version`, `loader`, `category`, `locale`.
Returns mod metadata: ID, title, author, version, Minecraft version, loader, description, quality label, Hineka Coin price, source URL, license, file size, SHA-256, compatibility and review state.
Only list files that have passed license/permission review and security scanning.

### GET /v1/catalog/resource-packs
Returns resource-pack metadata, supported versions, preview data, license, source, size, and integrity hash.

## Hineka Coins and purchase history (draft; not for Minecraft accounts)

### GET /v1/me/wallet
Returns current server-calculated Hineka Coin balance and latest ledger entries. Balance is read-only to the client.

### GET /v1/catalog/coin-packages
Returns enabled Hineka Coin packages. Draft mapping:
- 20,000 VND -> 90 Coins
- 50,000 VND -> 130 Coins
- 100,000 VND -> 200 Coins
- 200,000 VND -> 500 Coins
- 500,000 VND -> 900 Coins
- 1,000,000 VND -> 1,800 Coins

Coins are Hineka-only catalogue credits. They cannot purchase Minecraft accounts, licenses, or the Minecraft game. Do not return a package as purchasable until its lawful payment route and server verification are configured.

## Card top-up — disabled draft only

The owner previously asked about Viettel, MobiFone, and Zing prepaid cards. This is not approval to process payments. Only enable after guardian-managed merchant setup, a valid provider contract, legal review, platform review, and provider API security review. Keep unsupported card payment out of an App Store build.

Any provider flow must:
- Redact card PIN/serial from logs, traces, analytics, error reports, and support tooling.
- Keep partner credentials and request signing only on the server.
- Verify provider callbacks/status server-to-server.
- Grant Hineka Coins only once after confirmed success and exact denomination match.
- Reject unknown, pending, declined, replayed, or mismatched transactions without granting Coins.

## Apple In-App Purchase (App Store build)

### GET /v1/store/apple/products
Returns StoreKit product identifiers and server-approved mappings for Hineka digital features/Coins only.

### POST /v1/store/apple/transactions/verify
Request:
```json
{ "signed_transaction_info": "<StoreKit-signed-transaction>" }
```
Server verifies signed transaction data with Apple's supported APIs, checks bundle/product/environment/ownership and transaction uniqueness, then grants the mapped Hineka Coins or Hineka Premium entitlement once. Never trust a client-only success callback.

## Hineka Premium (not Minecraft Premium)

### GET /v1/me/entitlements
Returns active Hineka Premium state, product, start/end timestamps, renewal state, and revocation state.

The previous target of 100,000 VND/month is a draft for Hineka launcher features only. It does not include Minecraft Java Edition or a Microsoft account. Do not implement renewal assumptions before fixed 30-day vs auto-renewing access is decided.

## Mod and resource-pack storage
### POST /v1/files/uploads
Creates an upload intent for a permitted `.jar` mod or `.zip` resource pack. Enforce extension, MIME/content sniffing, size, quota, per-user rate limits, and version/loader metadata.

### POST /v1/files/uploads/{upload_id}/complete
Server verifies hash, scans the file, validates archive paths (including zip-slip), checks license/permission metadata, and publishes only if all checks pass.

### GET /v1/sync/manifest
Returns the user's cloud-synced mod/resource-pack manifest only. Minecraft worlds and Microsoft account credentials are out of scope for this sync feature.

## Obsolete endpoint
- Do not implement `POST /v1/rewards/claims`. Link4M/task-based Coin rewards have been removed.

## Required backend safeguards
- Append-only Hineka Coin ledger; every grant/spend/reversal is traceable.
- Unique constraints for provider transaction IDs, StoreKit transaction IDs, and idempotency keys.
- Database transaction for state transition plus Coin grant.
- Server-authoritative catalogue prices and product-to-Coin mappings.
- Admin actions require least privilege, multi-factor authentication, and audit logging.
- No secrets, tokens, payment card PINs, serials, or user passwords in client logs.
