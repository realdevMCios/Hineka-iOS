# Hineka iOS — Security Plan

Status: design baseline for 0.1-dev. These controls are not implemented or security-tested yet.

## Server-authoritative security
- Treat the iOS client as untrusted.
- Verify Premium entitlements, Coin balances, roles, and reward claims on the server.
- Require authorization checks on every protected API route.
- Never embed server secrets in the app.

## Anti-bypass and anti-bot
- Reject expired or invalid sessions.
- Rate-limit login, reward, upload, and sync endpoints.
- Apply cooldowns and anomaly logging to repeated failures.
- Do not trust client-side flags such as isPremium or rewardCompleted.

## Anti-replay and anti-dupe
- Require idempotency keys for every mutating transaction.
- Enforce database uniqueness for reward claims and transaction IDs.
- Credit Coins atomically so retries cannot pay twice.
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
- [ ] Server-side sessions and authorization
- [ ] Server-verified Premium and Coins ledger
- [ ] Atomic, idempotent reward claims
- [ ] Upload hashing and archive validation
- [ ] Versioned sync and conflict handling
- [ ] Rate limits, audit logs, and security tests
