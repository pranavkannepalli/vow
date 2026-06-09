# Vow lease-instrumentation follow-ups — operator checklist (compact)

## Goal
Make Vow’s SwiftPM instrumentation match the QA expectations in `VowSpecV2-QA-and-Rollout.md`, as described operationally in `VowLeaseInstrumentationFollowups.md`.

## Preflight (confirm these paths exist)
From `~/.openclaw/repos/vow`:
- `VowLeaseInstrumentationFollowups.md`
- `VowSpecV2-QA-and-Rollout.md`
- `Sources/VowCore/Logging/RequestFunnelMetricsRecorder.swift`
- `Sources/VowUI/UnlockRequestFlowCoordinator.swift`
- `Sources/VowCore/UnlockLeaseManager.swift`
- `Tests/VowCoreTests/UnlockLeaseManagerInstrumentationTests.swift`

## Commands (steady-throughput sweep)
1) Build:
   ```bash
   swift build
   ```
2) Run the lease/instrumentation boundary suite:
   ```bash
   swift test --filter UnlockLeaseManagerInstrumentationTests
   ```

## Telemetry to verify (and where it should appear)

### 1) Evidence funnel: `evidencePending`
**Expected**
- `UnlockRequestEvent` includes `evidencePending`.
- `UnlockRequestFlowCoordinator` records the event when transitioning into `RequestState.evidencePending`.

**Where to check**
- `Sources/VowCore/State/RequestState.swift` (event enum case)
- `Sources/VowUI/UnlockRequestFlowCoordinator.swift` (apply/record on transition)
- `Sources/VowCore/Logging/RequestFunnelMetricsRecorder.swift` (record() receives the event)

### 2) Temporary unlock lease lifecycle: `leaseGranted/leaseExtended/leaseExpired/leaseReshielded`
**Expected**
- `leaseGranted`: emitted when granting creates a *new* lease at the boundary (inactive-at-boundary renew should not count as an extension).
- `leaseExtended`: emitted when `mergeActive` merges into an existing active lease (extends `expiresAt`).
- `leaseExpired`: emitted during reconciliation **per newly-expired lease**.
- `leaseReshielded`: emitted during reconciliation **once per reconciliation call** (aggregated target IDs).

**Where to check**
- Grant path: `Sources/VowUI/UnlockRequestFlowCoordinator.swift` (`grantLease(now:)`)
- Lease logic + expiry detection: `Sources/VowCore/UnlockLeaseManager.swift` (`grant`, `reconcileExpiry`)

**How to verify**
- Use a test/local recorder (or extend the suite) that captures the ordered event stream(s) during:
  - `frictionWaiting → evidencePending → evidenceCompleted`
  - lease `grant` (including boundary-at-`expiresAt`) and `reconcileExpiry`

## Failure modes → exact troubleshooting path

1) **`evidencePending` missing from telemetry**
- Symptom: recorded event stream skips `evidencePending`.
- Fix path:
  - Add `case evidencePending` to `Sources/VowCore/State/RequestState.swift` (`UnlockRequestEvent`).
  - Ensure `UnlockRequestFlowCoordinator` records it when entering `.evidencePending` (search for `.evidencePending` / `applyAndRecord`).

2) **Wrong ordering (e.g., `evidenceCompleted` before `evidencePending`)**
- Symptom: event sequence violates the state transitions.
- Fix path:
  - Confirm the coordinator only records on real state changes (the `applyAndRecord` pattern).

3) **`leaseGranted` vs `leaseExtended` swapped at the `expiresAt` boundary**
- Symptom: boundary renew behaves like an extension.
- Fix path:
  - Verify boundary semantics in `Sources/VowCore/Models/UnlockLease.swift` (`isActive` should be `date < expiresAt`).
  - Verify `grant`’s “merge active” condition uses `isActive(at: now)`.

4) **`leaseExpired` emitted too many times**
- Symptom: reconciliation emits duplicates.
- Fix path:
  - In `Sources/VowCore/UnlockLeaseManager.swift`, base expiry emissions on:
    - `activeLeaseIDs.subtracting(stillActiveIDs)` (newly-expired set), not total expired.

5) **`leaseReshielded` emitted multiple times per reconciliation call**
- Symptom: reshield events show up again during the same reconcile.
- Fix path:
  - Ensure reconciliation updates `activeLeaseIDs` and `lastReconcileAt` once per call.
  - Keep backwards/clock-skew guard: `if now < lastReconcileAt { return [] }`.

## Worked examples

### Good example ✅
- Scenario: evidenceRequired=true and the evidence runner returns `true`.
- Expect (captured ordered funnel events):
  - `requestCreated → frictionTimerStarted → evidenceRequired → evidencePending → evidenceCompleted → aiReviewed`

- Scenario: lease boundary renew
  - Grant a lease exactly at `expiresAt` (boundary moment).
  - Expect: new lease path (`leaseGranted`, not `leaseExtended`).
  - Then run reconciliation at `T + ε`.
  - Expect: `leaseExpired` includes the old lease target, and reconciliation returns the reshield target IDs (aggregated once per call).

### Bad example ❌
- Symptom: second `reconcileExpiry` call with backwards time still triggers `leaseReshielded` / `leaseExpired` again.
- Likely cause:
  - `lastReconcileAt` isn’t updated correctly, or the backwards guard (`now < lastReconcileAt`) is missing/incorrect.
- Fix path:
  - Edit `Sources/VowCore/UnlockLeaseManager.swift` `reconcileExpiry(now:)`:
    - keep the early return on backwards time
    - update `activeLeaseIDs` + `lastReconcileAt` for idempotency.
