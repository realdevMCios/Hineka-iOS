# Hineka monetization plan

Status: product specification only. The storefront, top-up gateway, and server-side Coins ledger are not implemented yet.

## Product scope
- Product: **Hineka iOS**, a launcher for Minecraft Java on iPhone/iPad. Coins and Premium belong to Hineka's launcher catalogue; they are not Minecraft Java accounts or Mojang/Microsoft licenses.
- Remove the Link4M / watch-or-visit-links-to-earn-Coins feature entirely.
- Coins are credited only after a paid transaction is verified by Hineka's server. There are no task/ad rewards.
- Premium target price: **100,000 VND for one month**. Before selling, choose fixed 30-day access or an auto-renewing subscription and state renewal/cancellation clearly.
- Keep basic launcher features available without payment.

## Coin top-up catalogue

The owner's confirmed mapping is **top-up denomination in VND → Coins credited**:

| Top-up denomination | Coins credited |
|---:|---:|
| 10,000 VND | 40 Coins |
| 20,000 VND | 90 Coins |
| 50,000 VND | 150 Coins |
| 100,000 VND | 1,700 Coins |
| 200,000 VND | 500 Coins |
| 500,000 VND | 900 Coins |
| 1,000,000 VND | 1,500 Coins |

- These are owner-approved draft catalogue values. They are not live payment products until each provider/store mapping and server verification are configured.
- Show a package as purchasable only when its denomination, Coin grant, provider product/configuration, and server verification are all configured.
- Reconcile a submitted card against the provider's confirmed denomination/value before granting the mapped Coins.
- Keep all balances in integer Coins; never use floating point for the ledger.

## Mod catalogue: Chinese Java mods
- This catalogue is for Minecraft Java mods used through Hineka iOS. Each listing must state supported Minecraft version, loader (Forge/Fabric/other), mod version, author, source, license, file hash, and compatibility notes.
- The owner wants Coin prices to vary with mod quality, from polished/high-quality Chinese mods to simpler/low-quality mods. Set each mod's price individually; do not automatically price by nationality.
- Quality labels (for example Featured / Recommended / Basic) are editorial labels and must be separate from the Coin price.
- Show the exact Coin price before confirmation. Do not sell or mirror a mod unless its license/author permits redistribution. Otherwise link to the official author/project download.
- Scan files for malware and validate archive/file type, size, and compatibility before making them available.
- Do not sell pirated, unauthorized, or modified-without-permission files. Coins must not be required for basic launcher functionality or for Minecraft itself.

## Requested top-up methods and iOS distribution rules

### Requested card types
- The owner requested **Viettel, MobiFone, and Zing prepaid cards**.
- These are not integrated yet. Hineka needs a legitimate payment/top-up provider, a merchant agreement/account, API documentation, fee and denomination schedule, callback/status verification, and a completed legal/security review before activation.
- A public API guide from a third-party card-exchange gateway is not itself proof that Hineka has an approved merchant account, that the provider is trustworthy, or that fees/settlement are acceptable. Do not hard-code a provider URL or credentials into the iOS app.
- Card PIN/serial must never be sent in chat, logs, analytics, or crash reports. If a lawful provider is selected, collect it only through a secure HTTPS backend flow, protect it in transit, avoid persistent storage, and never expose partner secrets in the client. Handle rejected, pending, duplicate, underpaid, and mismatched-denomination transactions.
- A parent/guardian must handle any merchant registration, contracts, settlement account, and financial obligations while the developer is a minor.

### If distributed through the iOS App Store
- Digital Coins and Premium normally require Apple In-App Purchase / StoreKit. Apple Guideline 3.1.1 says in-app digital currencies, features, subscriptions, and digital vouchers must use IAP in the general case, with limited entitlements/region-specific programs. Do not put direct Viettel/MobiFone/Zing code redemption or an external checkout link into an App Store build unless Apple has approved the exact applicable entitlement/program and storefront.
- Apple's current Vietnam Apple Account payment-method page lists Apple Account balance, MoMo, most credit/debit cards, ShopeePay, VNPAY, and ZaloPay. This describes ways customers can pay Apple; it does **not** mean Hineka can independently take MoMo/ZaloPay/card payments for its own digital Coins outside StoreKit.
- Apple also says purchased IAP credits may not expire. The App Store build's StoreKit product IDs and server-side receipt verification must be configured before real purchases are enabled.
- References: [Apple App Review Guidelines, section 3.1](https://developer.apple.com/app-store/review/guidelines/) and [Apple Account payment methods for Vietnam](https://support.apple.com/vi-vn/111741).

### If distributed outside the App Store (for example, a directly installed IPA)
- Do not assume direct installation makes every payment flow lawful or safe. Viettel/MobiFone/Zing card redemption still requires a provider contract/API, anti-fraud controls, consumer disclosures, local-law review, and guardian-managed merchant setup.
- Keep the payment-provider adapter on the server. The iOS client should only create a top-up intent and check its status; it must never decide that a card is valid or credit Coins by itself.
- Keep App Store and direct-distribution payment configurations separated so an unsupported card-payment option cannot accidentally ship in the App Store build.

## Server-side payment and Coins ledger
- A top-up request gets a unique server-generated ID/idempotency key and a pending state.
- Verify provider callbacks/signatures and query the provider server-to-server when needed. Do not trust screenshots, client callbacks, or user-entered success status.
- Grant Coins only once, after the provider confirms success and the confirmed denomination exactly matches an enabled catalogue row.
- Repeated callbacks/retries must never grant twice. Store provider transaction IDs uniquely.
- Record every top-up, grant, spend, refund, rejection, and adjustment in an append-only audit ledger.
- Reconcile refunds, reversals, chargebacks, and card disputes according to provider contract. Never leave reversed value spendable.
- Never let the iOS client submit an arbitrary Coin quantity or edit a balance.

## Premium
- Target price: **100,000 VND / one month**.
- Choose fixed 30-day access or auto-renewing subscription before implementation.
- Premium must have continuing, clearly described value (for example more cloud storage, launcher themes, or advanced profile tools); do not paywall basic launching or imply it supplies a Minecraft license.
- Entitlements are server-authoritative and include start, expiry, renewal, cancellation, refund/revocation states.

## Safety and UX
- Display the exact price, Coins received, processing time/possible provider fees, and refund/support terms before a top-up confirmation.
- Avoid promising instant credit when card processing can be pending.
- Never ask a user to post card PIN, serial, OTP, payment credentials, or account passwords to support.
- Require parent/guardian involvement for purchases and payment-provider contracts involving a minor.
- Follow applicable platform age, privacy, consumer-protection, payment, and tax rules.

## Pending owner decisions
- [ ] Decide fixed 30-day Premium or auto-renewing 100,000 VND/month.
- [ ] Select and vet a card-top-up provider; confirm its fees, payout rules, API status model, supported denominations, and contracts.
- [ ] Confirm the actual distribution route for the iOS app: App Store, direct IPA, or separately configured builds.
- [ ] Confirm legal permission and licenses for each paid Chinese Java mod listing.
