# Hineka monetization plan

Status: design only. No real-money store, Microsoft account linking, or payment backend is implemented.

## Important product boundary: Minecraft Premium accounts are not for resale

Hineka must **not** sell, broker, transfer, rent, share, or deliver Minecraft Premium / Microsoft accounts or their login credentials.

Minecraft Help says buying and selling Minecraft accounts goes against its Terms of Service and that third-party account purchases do not make the buyer the legitimate owner of the license. Microsoft's Services Agreement also says Microsoft account credentials cannot be transferred to another user or entity. Hineka is not an authorized Minecraft account reseller.

- Do not create a Minecraft-account inventory, account listing, account checkout, or account-delivery endpoint.
- Do not collect, display, send, or store Microsoft passwords, one-time codes, recovery codes, session cookies, or seller-provided account credentials.
- Do not promise that a third-party account is permanent, transferable, recoverable, or safe from suspension.
- Users should obtain Minecraft from Minecraft/Microsoft or a retailer explicitly authorized to sell the relevant product, using an account they control.
- Do not sell gift cards, activation codes, or licenses as a workaround unless Hineka later has written authorization from the relevant issuer/reseller program and a separate legal/platform review.

References:
- [Minecraft Help: Can I Buy or Sell Minecraft Accounts?](https://help.minecraft.net/hc/en-us/articles/360042692852-Posso-comprar-ou-vender-contas-do-Minecraft)
- [Microsoft Services Agreement, section 4.a.i](https://www.microsoft.com/en/servicesagreement)
- [Minecraft EULA](https://www.minecraft.net/en-us/eula)

## What Hineka may offer instead

### 1. Bring-your-own Minecraft license

- A user obtains and controls their own legitimate Minecraft account/license through official channels.
- Hineka may add Microsoft/Minecraft account linking only through an official, currently supported authentication flow after its requirements have been researched and reviewed.
- The user authenticates with Microsoft through the approved sign-in surface. Hineka must never ask the user to type a Microsoft password or one-time code into a Hineka form or send those credentials to Hineka support.
- The app may display only the minimum account/profile and license-entitlement status returned through the approved flow. A successful sign-in alone must not be described as proof of a Java Edition license.
- Account linking is not implemented yet. See [ACCOUNT-LINKING-PLAN.md](ACCOUNT-LINKING-PLAN.md).

### 2. Hineka Premium (separate from Minecraft Premium)

- Previous target price: **100,000 VND / month**, still only a draft.
- This is for Hineka launcher features only. It must never claim to include Minecraft Java Edition, a Microsoft account, or a Minecraft license.
- Possible paid Hineka features: additional cloud storage for permitted mods/resource packs, launcher themes, and advanced profile-management tools.
- Basic launcher functionality and the ability to use a user's own licensed Minecraft copy should not be paywalled.
- Decide fixed 30-day access vs auto-renewing subscription before implementation. Explain price, renewal, cancellation, expiry, and refunds clearly.
- For an App Store build, digital subscriptions/features generally require Apple In-App Purchase under the applicable App Review rules. No external checkout should be enabled unless the exact storefront/program/entitlement permits it.

### 3. Hineka Coins (optional future catalogue currency)

Coins, if retained, are Hineka-only catalogue credits. They are **not** Minecraft currency, a Minecraft license, an account, or a way to unlock Minecraft itself. They may only be used for permitted Hineka catalogue items such as mods/resource packs where the author/license permits the sale or redistribution.

Draft denomination mapping (not live):

| Top-up denomination | Coins credited |
|---:|---:|
| 20,000 VND | 90 Coins |
| 50,000 VND | 130 Coins |
| 100,000 VND | 200 Coins |
| 200,000 VND | 500 Coins |
| 500,000 VND | 900 Coins |
| 1,000,000 VND | 1,800 Coins |

Do not activate any package until its lawful payment route, provider/store mapping, server verification, refunds, and local-law review are complete. If Coins are not needed for the launch, remove the Wallet purchase UI rather than presenting a nonfunctional shop.

## Mod/resource-pack catalogue

- Each listing must state supported Minecraft version, loader (Forge/Fabric/other), mod/resource-pack version, author, source, license, file hash, size, and compatibility notes.
- Do not price by nationality. Set an individual price only where the license/author permits commercial distribution.
- Do not sell or mirror a file unless its license or explicit author permission permits it. Otherwise link to the official author/project download.
- Scan files for malware and validate archive/file type, size, and compatibility before making them available.
- Never bundle Minecraft game files, paid game content, account credentials, or unauthorized modified game clients.

## Payments and platform requirements

- The earlier request for Viettel, MobiFone, and Zing prepaid-card top-ups remains unimplemented and is not approval to accept payments.
- Any merchant setup, contracts, settlement account, payment credentials, and tax/legal obligations must be handled by a parent/guardian while the developer is a minor.
- Keep provider secrets on a backend. Never let the iOS client decide a payment succeeded or grant a balance.
- For App Store digital goods/features/subscriptions, follow the currently applicable Apple IAP requirements and region-specific programs. Re-check the guideline before release.
- For direct distribution, do not assume that sideloading removes payment, consumer-protection, privacy, or licensing obligations.

## Security and customer support

- Never request Microsoft passwords, OTPs, recovery codes, card PINs/serials, or payment credentials in chat or support.
- Keep entitlements and any Hineka Coin ledger server-authoritative.
- Use unique transaction IDs, idempotency, callback verification, audit records, refunds/reversals, and a clear support process before enabling payments.
- Disclose that Hineka is an independent third-party launcher and is not an official Minecraft/Microsoft product. Do not use Minecraft branding in a way that implies endorsement.

## Pending decisions

- [ ] Decide whether Hineka Coins are needed at all for the first release.
- [ ] Decide which Hineka-only Premium features provide ongoing value and whether the 100,000 VND/month draft remains.
- [ ] Research and implement only an official Microsoft/Minecraft account-linking flow; do not build an account marketplace.
- [ ] Have a parent/guardian review contracts, platform rules, privacy, consumer law, tax, and payment setup before any sale.
