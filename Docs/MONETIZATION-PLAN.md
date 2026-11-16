# Hineka monetization plan

Status: product specification only. No payment processing, store products, or Coins ledger is implemented.

## Product decisions
- Remove the Link4M / watch-or-visit-links-to-earn-Coins feature entirely.
- Coins are granted only after a successful, verified purchase/top-up.
- Premium subscription target price: **100,000 VND per month** (replaces the earlier 20,000 VND/month draft).
- Coin pack prices and quantities are not decided yet; do not invent or publish prices until the owner approves a price table.
- Do not grant Coins based only on a client callback, screenshot, or editable local balance.

## Payment channels — platform review required
- iOS: use Apple In-App Purchase for digital Premium and digital Coins unless the app and storefront qualify for a specific Apple-approved alternative.
- Android distributed through Google Play: use Google Play Billing for digital Premium and Coins unless an applicable exception/program is confirmed.
- MoMo and ZaloPay: consider only in regions/distribution channels where store policies and local law permit the proposed flow. Do not add an external checkout button to an iOS or Play build until the exact storefront policy has been reviewed.
- Apple currently requires In-App Purchase for digital subscriptions, virtual currency, and app features in the general case; regional entitlements/programs can create limited alternatives. See [Apple App Review Guidelines, section 3.1](https://developer.apple.com/app-store/review/guidelines/).
- Google Play generally requires Play Billing for digital goods, virtual currency, subscriptions, and app functionality, subject to listed exceptions/programs. See [Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738).
- Never collect card, bank, MoMo, ZaloPay, Apple, or Google credentials directly in Hineka.
- Verify purchase receipts/tokens server-side with the relevant store/provider before granting Premium or Coins.

## Entitlement and ledger logic
- Premium is a time-bounded server entitlement with start, expiry, renewal, cancellation, and refund/revocation states.
- Coins are a server-side ledger, not a client-editable number.
- Each purchase has a unique provider transaction ID and idempotency key.
- A repeated store notification or API retry must not grant Coins twice.
- Refunds, chargebacks, and revoked purchases must be reconciled; never silently leave refunded value spendable.
- Keep an audit trail for grants, spends, refunds, and administrative adjustments.

## Safety and UX
- Show the total price, billing period, renewal behavior, and cancellation instructions before confirmation.
- Do not imply that buying Premium is required to play Minecraft or use basic launcher functions.
- Require appropriate parent/guardian involvement for purchases by minors and follow applicable store age and family-payment controls.
- Do not ask users to send payment credentials, one-time codes, or receipts containing personal information to support chat.

## Pending owner decisions
- [ ] Define Coins packages (VND price and Coins granted).
- [ ] Define which cosmetic/launcher features Coins can purchase.
- [ ] Confirm whether Premium is auto-renewing subscription or fixed 30-day access.
- [ ] Confirm Android distribution target; Hineka is currently described as an iOS project.
- [ ] Review current Apple, Google Play, MoMo, and ZaloPay terms before implementation.
