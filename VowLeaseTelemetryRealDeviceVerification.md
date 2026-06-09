# Real-device telemetry verification: temporary-unlock lease lifecycle (Vow)

## Goal
On a real device, verify that Vow emits **complete, correctly ordered, and privacy-minimized** telemetry for the temporary-unlock lease lifecycle:
- `leaseGranted`
- `leaseExtended`
- `leaseExpired`
- `leaseReshielded`

This checklist is meant to be run against the host-provided `LeaseLifecycleMetricsRecorder`.

## What to collect per run
- Device model, iOS version, app version/build
- For each telemetry callback, capture (at minimum):
  - event type (`leaseGranted` / `leaseExtended` / `leaseExpired` / `leaseReshielded`)
  - serialized payload fields (as sent by `UnlockLeaseLifecycleEvent`)
  - emission timestamp (`at`)
- Any in-app logs that show the corresponding coordinator actions:
  - decision approval (`decisionApproved` / the moment the coordinator calls `grantLease(now:)`)
  - reconciliation call (`reconcileLeaseExpiry(now:)`)

## Expected payload schema + data minimization (must match exactly)
Each event payload must contain only the fields below (UUID identifiers + Dates), with no sensitive identifiers.

1) `leaseGranted(LeaseGrantedPayload)`
- `leaseID` (UUID)
- `targetID` (UUID)
- `requestID` (UUID)
- `startAt` (Date)
- `expiresAt` (Date)
- `at` (Date)

2) `leaseExtended(LeaseExtendedPayload)`
- `leaseID` (UUID)
- `targetID` (UUID)
- `requestID` (UUID)
- `previousExpiresAt` (Date)
- `newExpiresAt` (Date)
- `at` (Date)

3) `leaseExpired(LeaseExpiredPayload)`
- `leaseID` (UUID)
- `targetID` (UUID)
- `requestID` (UUID)
- `startAt` (Date)
- `expiresAt` (Date)
- `at` (Date)

4) `leaseReshielded(LeaseReshieldedPayload)`
- `reshieldTargetIDs` ([UUID])
- `at` (Date)

## Ordering rules (what must come before/after what)
These are the ordering expectations from the coordinator + lease manager emission points:

### A) After unlock approval
When a decision transitions to “approved temp unlock” (i.e., the coordinator’s `completeDecisionApprovedAsync` path reaches `grantLease(now:)`):
- `leaseGranted` **or** `leaseExtended` must be emitted as part of the same grant operation.
- The lease event emission must occur **after** the coordinator has applied/recorded `decisionApproved` (the coordinator calls `applyAndRecord(.decisionApproved)` before `grantLease(now:)`).

### B) On reconciliation expiry
When the host calls `reconcileLeaseExpiry(now:)` and reconciliation detects newly-expired leases:
- For each newly-expired lease: emit exactly one `leaseExpired` (per lease).
- After emitting all `leaseExpired` events for that reconciliation call: emit exactly one aggregated `leaseReshielded`.
- If reconciliation time moves backwards (clock skew): emit **no** `leaseExpired` and **no** `leaseReshielded`.

## Completeness rules (events must/ must-not appear)
Run the following scenarios and confirm expected events:

### 1) New grant (no existing active lease for same target)
Preconditions:
- No active lease exists for the target at `now`.
Action:
- Approve temp unlock for the target.
Expected:
- Exactly one `leaseGranted`.
- No `leaseExtended`, no `leaseExpired`, no `leaseReshielded` during the grant.

### 2) Extend/merge (existing active lease for same target)
Preconditions:
- An active lease exists for the target at `now`.
Action:
- Approve another temp unlock for the same target before expiry.
Expected:
- Exactly one `leaseExtended`.
- The payload must show:
  - `previousExpiresAt` equals the pre-existing active lease’s `expiresAt`.
  - `newExpiresAt` equals the merged max expiry.
- No `leaseGranted` for that merge.

### 3) Expiry + reshield via reconciliation
Preconditions:
- A lease becomes expired relative to reconciliation `now`.
Action:
- Call `reconcileLeaseExpiry(now:)` at `now > expiresAt`.
Expected:
- One `leaseExpired` per newly-expired lease.
- Exactly one `leaseReshielded` for the same reconciliation call (aggregated `reshieldTargetIDs`).
- No grant/extend events are emitted by reconciliation itself.

### 4) Idempotency under clock skew / backwards reconciliation
Preconditions:
- A reconciliation has already run at `lastReconcileAt`.
Action:
- Call `reconcileLeaseExpiry(now:)` with `now < lastReconcileAt`.
Expected:
- No `leaseExpired` and no `leaseReshielded`.

## PASS criteria (how to mark result)
Mark this run **PASS** only if all are true:
- All required events were emitted for each scenario.
- Ordering rules above hold (especially: `leaseReshielded` after all `leaseExpired` for the call).
- Payload schema matches the exact field lists (UUIDs + Dates only).
- Privacy minimization holds (no sensitive identifiers beyond UUIDs).

If anything is missing/incorrect, mark **NEEDS_CHANGES** and record:
- which event(s) deviated
- the exact received payload fields
- which coordinator/manager method call the deviation mapped to

## Edge-case risk log (record any remaining concerns)
During the run, check and record outcomes for:
- clock skew handling: `UnlockLeaseManager.reconcileExpiryWithLifecycleEvents` suppresses events when `now < lastReconcileAt`
- reshield aggregation determinism: `reshieldTargetIDs` is sorted by UUID string
- event emission when `LeaseLifecycleMetricsRecorder` is unset (should safely no-op)
