# NFC Card Enforced Alarm — Threat Model (Enrollment UX)

## Scope
User enrolls one or more NFC cards to unlock *specific* Vow targets (i.e., `BlockedTarget.id`).
When unlocking is attempted and NFC verification fails, the app schedules an enforcement alarm and denies the unlock.

This document focuses on the **enrollment + verification pipeline**, not Screen Time policy enforcement itself.

## Assets
- Enrolled-card fingerprints (must not leak raw identifiers)
- Mapping: `targetID -> allowed fingerprints`
- Verification decision: verified vs notVerified
- Enforcement alarm payload (must not be spoofable)

## Trust boundaries
- NFC reader/session (CoreNFC / secure element APIs) outputs a card identifier.
- Enrollment UI captures the presented identifier and persists a fingerprint.
- Runtime verification is performed at unlock-request time.

## Attacker models
1. **Physical attacker**: can present cards to the device during enrollment/unlock.
2. **Replay attacker**: can re-present a previously seen card identifier.
3. **Data leakage attacker**: obtains stored enrollment data.
4. **UX confusion attacker**: exploits unclear enrollment state (“which target was this card added to?”).
5. **Fault injection / failures**: induces reader errors to change behavior.

## Threats & mitigations
### 1) Enrollment mix-up (wrong target)
**Threat:** A card is enrolled for the wrong `targetID` due to UI ambiguity.

**Mitigations:**
- Enrollment UI must explicitly show the current target label + identifier context.
- Enrollment confirmation screen should reflect the target context and show last enrolled time.
- Disable concurrent enrollment requests.

### 2) Raw identifier leakage
**Threat:** Persisting raw card UID enables cloning or correlation.

**Mitigations:**
- Store **hashed fingerprints** (e.g., SHA-256(card UID + domain salt)).
- Store per-user salt (or key) so fingerprints are not portable across users.
- Limit logs to non-sensitive fingerprints.

### 3) Replay / cloning
**Threat:** Re-presenting an enrolled card causes “verified”.

**Mitigations:**
- NFC verification should be “presence” based; replay is equivalent to presenting a card.
- To reduce casual cloning, use reader modes that produce stable-but-opaque identifiers (as allowed).
- Consider adding optional *second factor* (e.g., device possession + time-of-day risk gating) in a future iteration.

### 4) Reader spoof / false negatives
**Threat:** Attacker causes reader errors; if failures are treated as “verified”, unlock could proceed.

**Mitigations:**
- Fail-safe default: reader failure => `verified == false`.
- Never treat “unknown read” as verified.

### 5) Alarm payload spoofing
**Threat:** If violation metadata can be forged, alarms might target the wrong session.

**Mitigations:**
- Violation payload should be constructed from trusted runtime state (`targetID`, `requestID`, `now`).
- Scheduler payload should be signed/validated where OS APIs allow.

## Residual risks
- If the threat model assumes a physical attacker can present NFC cards, “verified” will necessarily succeed for those cards.
- Mitigations focus on making enrollment unambiguous and protecting enrolled identifiers.

## Open questions
- What exact NFC identifier is used as fingerprint (UID, NDEF record hash, secure-element token)?
- Whether to bind enrollment to risk level tiers.
- How to handle enrollment revocation (removing fingerprints) and UI state.
