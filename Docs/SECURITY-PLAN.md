# Hineka iOS — Security Plan

Status: design baseline for 0.1-dev. These controls are not implemented or security-tested yet.

## Server-authoritative security
- Treat the iOS client as untrusted.
- Verify Hineka Premium entitlements, Coin balances, roles, and claims on the server.
- Require authorization checks on every protected API route.
- Never embed server secrets in the app.
- A Microsoft/Minecraft login or entitlement status must not be forged by a client-provided boolean.

## Microsoft/Minecraft account safety
- Hineka is bring-your-own-license only; do not buy, sell, broker, transfer, rent, share, or deliver Minecraft/Microsoft accounts.
- Use only an official supported sign-in and game-entitlement verification flow after its current requirements have been reviewed.
- Never collect or store Microsoft passwords, OTPs, recovery codes, session cookies, or credentials received from sellers.
- Use system/official authentication UI; protect any required tokens using iOS Keychain and minimum scopes/lifetimes.
- Do not log tokens, account secrets, or sensitive profile data. Provide sign-out/unlink and clear local credentials.
- A successful Microsoft sign-in alone does not prove ownership of Minecraft Java Edition.

## Anti-bypass and anti-bot
- Reject expired or invalid sessions.
- Rate-limit login, upload, and sync endpoints.
- Apply cooldowns and anomaly logging to repeated failures.
- Do not trust client-side flags such as isPremium, ownsMinecraftJava, or uploadCompleted.

## Anti-replay and anti-dupe
- Require idempotency keys for every mutating transaction.
- Enforce database uniqueness for transaction IDs and state-changing requests.
- Credit Hineka Coins atomically so retries cannot pay twice.
- Hash files server-side and deduplicate within the correct account/scope.
- Use version/ETag checks to detect conflicting cloud-sync writes.
- Validate temporary uploads before publishing them to the sync manifest.

## File safety and privacy
- Treat mods and resource packs as untrusted files.
- Enforce upload and decompression limits; reject archive path traversal.
- Never execute uploaded files on the backend.
- Ask for consent before uploading local files to cloud storage.
- Username-only login is an impersonable guest identity; it must not protect Premium, Coins, or private files.

## Scope limits
Hineka can prevent duplicate reward claims, cloud uploads, and sync records. It cannot prevent item-duplication glitches on third-party Minecraft servers; those servers control gameplay validation.

## iOS platform integrity
Keep the iOS sandbox and code-signing protections intact. Do not rely on private entitlements or security bypasses.

## Implementation checklist
- [ ] Official Microsoft/Minecraft sign-in and Java entitlement verification
- [ ] Secure token storage, revocation/unlink, and privacy controls
- [ ] Server-side Hineka sessions and authorization
- [ ] Server-verified Hineka Premium and Coins ledger
- [ ] Atomic, idempotent transaction processing
- [ ] Upload hashing and archive validation
- [ ] Versioned sync and conflict handling
- [ ] Rate limits, audit logs, and security tests
