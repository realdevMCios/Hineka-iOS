# Hineka API draft

Status: proposed contract for Hineka iOS (Minecraft Java launcher). No production API or payment gateway is connected.

## Principles
- The iOS client is untrusted. Server validates all inputs, permissions, catalogue prices, provider callbacks, and balances.
- Use HTTPS only. Authenticate guest sessions with a random, revocable, device-bound token; never rely on a username alone for payment or private files.
- Never include provider partner keys, StoreKit private keys, or signing secrets in the app bundle.
- Use integer VND and integer Coins. Server owns the catalogue and ledger.
- Do not build endpoints that credit Coins directly from a client-provided amount.

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

## Catalogue
### GET /v1/catalog/minecraft-versions
Returns supported Minecraft Java versions and compatible runtime metadata.

### GET /v1/catalog/mods
Optional query fields: `minecraft_version`, `loader`, `category`, `locale`.
Returns mod metadata: ID, title, author, version, Minecraft version, loader, description, quality label, Coin price, source URL, license, file size, SHA-256, compatibility and review state.
Only list files that have passed license/permission review and security scanning.

### GET /v1/catalog/resource-packs
Returns resource-pack metadata, supported versions, preview data, license, source, size, and integrity hash.

## Coins and purchase history
### GET /v1/me/wallet
Returns current server-calculated Coin balance and latest ledger entries. Balance is read-only to the client.

### GET /v1/catalog/coin-packages
Returns enabled packages from the server. Current owner-approved draft:
- 10,000 VND -> 40 Coins
- 20,000 VND -> 90 Coins
- 50,000 VND -> 150 Coins
- 100,000 VND -> 1,700 Coins
- 200,000 VND -> 500 Coins
- 500,000 VND -> 900 Coins
- 1,000,000 VND -> 1,500 Coins

Do not return a package as purchasable until its payment route is enabled and its mapping is complete.

## Card top-up — direct-distribution build only, gated
The owner requested Viettel, MobiFone, and Zing prepaid cards. This is not an implementation approval. Only enable after a guardian-managed merchant account, valid provider contract, legal review, and provider API security review exist. Keep this feature disabled in an App Store build unless the required Apple approval/entitlement explicitly permits the flow.

### POST /v1/topups/card
Request (conceptual; card fields are accepted only over TLS and only after an approved provider has been configured):
```json
{
  "provider": "viettel",
  "denomination_vnd": 10000,
  "serial": "<entered securely>",
  "pin": "<entered securely>",
  "idempotency_key": "client-generated-unique-value"
}
```
Response:
```json
{
  "topup_id": "topup_...",
  "status": "pending",
  "denomination_vnd": 10000
}
```
Requirements:
- The API gateway must redact PIN/serial from logs, traces, analytics, error reports, and support tooling. Do not persist raw PIN/serial beyond what the approved provider flow strictly requires.
- Partner credentials and request signing exist only on the server.
- Validate provider, denomination, request signature, unique request ID, rate limits, account/device limits, replay protection, and fraud signals.
- Provider result states include pending, success, rejected, expired, and manual_review. Do not infer success from an HTTP 200 alone.
- Confirm provider callback signatures and/or query provider status server-to-server.
- Only on confirmed success and exact denomination match, create one ledger credit using a unique provider transaction ID and a database transaction. Idempotency must prevent duplicate credits after retries or replay.
- If the confirmed value differs from the declared denomination, do not silently grant the mapped Coins; flag for manual reconciliation.
- A declined, unknown, pending, or mismatched transaction grants zero Coins.

### GET /v1/topups/{topup_id}
Returns server-owned top-up status and, after success, the credited Coin quantity. The client cannot change status.

## Apple In-App Purchase (App Store build)
### GET /v1/store/apple/products
Returns StoreKit product identifiers and server-approved product mappings.

### POST /v1/store/apple/transactions/verify
Request:
```json
{ "signed_transaction_info": "<StoreKit-signed-transaction>" }
```
Server verifies the signed transaction with Apple's supported server APIs, checks bundle/product/environment/ownership and transaction uniqueness, then grants the mapped Coins or Premium entitlement once. Never trust a client-only success callback. Persist original transaction ID and transaction ID for reconciliation.

## Premium
### GET /v1/me/entitlements
Returns active Premium state, product, start/end timestamps, renewal state, and revocation state.

Fixed 30-day access vs auto-renewing 100,000 VND/month remains an owner decision. Do not implement renewal assumptions before the decision is made.

## Mod and resource-pack storage
### POST /v1/files/uploads
Creates an upload intent for a permitted `.jar` mod or `.zip` resource pack. Enforce extension, MIME/content sniffing, size, quota, per-user rate limits, and version/loader metadata.

### POST /v1/files/uploads/{upload_id}/complete
Server verifies hash, scans the file, validates archive paths (including zip-slip), checks license/permission metadata, and publishes only if all checks pass.

### GET /v1/sync/manifest
Returns the user's cloud-synced mod/resource-pack manifest only. Minecraft worlds and Microsoft accounts are out of scope for this sync feature.

## Obsolete endpoint
- Do not implement `POST /v1/rewards/claims`. Link4M/task-based Coin rewards have been removed.

## Required backend safeguards
- Append-only Coin ledger; every grant/spend/reversal is traceable.
- Unique constraints for provider transaction IDs, StoreKit transaction IDs, and idempotency keys.
- Database transaction for state transition plus Coin grant.
- Server-authoritative catalogue prices and product-to-Coin mappings.
- Admin actions require least privilege, multi-factor authentication, and audit logging.
- No secrets, tokens, payment card PINs, serials, or user passwords in client logs.
