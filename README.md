# Hineka iOS

**Hineka** is a planned Minecraft Java launcher for iPhone and iPad.

Current development label: **0.1-dev** (not a release).

## Source layout

- `App/Hineka/` — SwiftUI app entry point and initial tab/navigation shell.
- `App/Wallet/` — Coin package model and draft Wallet screen.
- `Docs/MONETIZATION-PLAN.md` — Coin packages, Premium, and payment requirements.
- `Docs/API-DRAFT.md` — proposed backend API contract.
- `Docs/SECURITY-PLAN.md` — security design notes.

## Current Coin top-up draft

| Top-up | Coins |
|---:|---:|
| 10,000 VND | 40 |
| 20,000 VND | 90 |
| 50,000 VND | 150 |
| 100,000 VND | Not set |
| 200,000 VND | 500 |
| 500,000 VND | 900 |
| 1,000,000 VND | 1,500 |

Requested card brands: Viettel, MobiFone, and Zing. They are **not integrated**. Purchase controls remain disabled until a lawful payment route, provider account, and server verification are in place.

## Build and runtime status

This repository currently contains an early SwiftUI shell, not a complete Minecraft launcher. The Java runtime, game renderer, version installer, Forge/Fabric installation, mod/resource-pack management, authentication, backend, and real payments are not implemented. The source has not been built with Xcode, run on a device, or packaged as an IPA.

Add the Swift files to an iOS App target in Xcode, then build and test on supported devices before calling it installable. Do not distribute a release IPA until runtime licensing, security, signing, and device testing are completed.
