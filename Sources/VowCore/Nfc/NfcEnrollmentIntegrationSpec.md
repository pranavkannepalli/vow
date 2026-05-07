# NFC Card Enforced Alarm — Integration Spec

## Goal
Provide a coherent path from:
- **Enrollment UX** (user adds an NFC card)
- to **Runtime verification** (unlock request checks NFC)
- to **Enforcement alarm** (deny + schedule when NFC is not verified).

## Components
### 1) Enrollment UI
- Lets user enroll one or more cards for a specific Vow target.
- Produces a persisted `NfcCardFingerprint` for `targetID`.

### 2) Enrollment store
Protocol:
- `NfcEnrollmentStore.enroll(targetID:fingerprint:)`
- `NfcEnrollmentStore.isEnrolled(targetID:fingerprint:)`

### 3) Verification factory
`NfcVerificationFactory.makeVerifier(...)` returns a closure:
- Reads fingerprint via an abstract `cardReader` closure.
- Returns `true` iff the fingerprint is enrolled for the requested `targetID`.
- Fail-safe: card read errors => `false`.

### 4) Runtime enforcement
`NfcRuntimeEnforcer` is already the enforcement brain:
- calls verifier
- if `false`, schedules alarm and returns `notVerified(violation)`.

## Wiring (runtime)
At unlock-request time (`UnlockRequestFlowCoordinator.decisionApprovedAsync`):
1. Build `NfcRuntimeEnforcer` for the unlock target (`targetID`).
2. Inject it into `UnlockRequestFlowCoordinator(nfcEnforcer: ...)`.
3. When `decisionApproved` runs:
   - `verify(targetID: requestID)` calls verifier
   - `verified == true` => lease granted
   - `verified == false` => enforcement alarm scheduled + deny

## Wiring (enrollment)
When the user enrolls a card for a target:
1. Enrollment UX reads the card’s presented identifier.
2. Convert identifier => `NfcCardFingerprint`.
3. Persist: `store.enroll(targetID: target.id, fingerprint:)`.
4. Update UI state (success/failure; show which target was enrolled).

## Example (non-iOS / test)
- Use `InMemoryNfcEnrollmentStore`
- Provide a fake `cardReader` closure returning a deterministic `NfcCardFingerprint`.
- Construct verifier via `NfcVerificationFactory.makeVerifier`.
- Construct enforcer via `makeRuntimeEnforcer` with `NoopAlarmScheduler`.

## Acceptance criteria
- Fail-safe behavior: NFC read errors never allow unlock.
- Enrollment UI never enrolls a card for an unshown/unknown target.
- Runtime alarm scheduling uses trusted runtime state (`targetID`, `requestID`, `now`).
