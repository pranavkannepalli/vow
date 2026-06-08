# Vow spec v2 — QA, instrumentation, and rollout

## Scope
End-to-end validation of the v1 unlock-request state machine and its host-facing QA hooks:
- happy paths and edge cases (evidence/no-evidence)
- funnel instrumentation for unlock-request lifecycle
- performance sanity checks

## What to test (happy paths)
1) **Low/medium/high risk, evidence not required**
   - shield intercept → unlock request flow starts
   - friction completes
   - transitions: `requestCreated → frictionWaiting → evidenceCompleted → aiReviewed → decisionApprovedTempUnlock → sessionClosed → reviewLogged`

2) **Evidence required**
   - friction completes
   - transitions: `requestCreated → frictionWaiting → evidencePending → evidenceCompleted → aiReviewed → (approved/deferred/denied) → terminal`

## Edge cases
- **Invalid transitions are ignored** (e.g., decisions before `aiReviewed`).
- **Evidence runner failure / throws** should force terminal denial (scaffold behavior).
- **Restore/resume**: if snapshot is in `evidenceCompleted`, the coordinator should advance through `aiReviewed`.

## Temporary unlock lease lifecycle edge cases (expiry + reshield)
These validate the integrated behavior: reconciliation-driven expiry must trigger reshielding without accidentally re-unlocking/reshielding multiple times, even with renewals or clock-skew.

1) **Expiry without re-unlock**
   - Preconditions: an active lease has `expiresAt < reconcileNow`; no new grant happens before reconciliation.
   - Expected:
     - reconciliation returns `reshieldedTargetIDs` containing the targetID(s)
     - exactly one `leaseExpired` event per newly-expired lease
     - exactly one `leaseReshielded` event per reconciliation call (aggregated)
     - temporarily-unlocked state becomes `false` at `reconcileNow`
     - no grant/extend events emitted during reconciliation
   - Unit test coverage:
     - `UnlockLeaseManagerInstrumentationTests.testReconcileExpiry_expiresWithoutReunlock`

2) **Renew/extend interactions around expiresAt boundary**
   - Preconditions: existing lease is active until exactly `T = expiresAt` (exclusive boundary); an incoming grant/renew occurs at `now == T`.
   - Expected:
     - the incoming grant at `T` is treated as a *new* (inactive-at-boundary) lease (`leaseGranted` not `leaseExtended`)
     - reconciliation at `T + ε` expires the old lease only (no resurrection/extension)
   - Unit test coverage:
     - `UnlockLeaseManagerInstrumentationTests.testGrant_renewsLease_whenExistingLeaseExpiresAtBoundary`

3) **Rapid repeated unlock attempts**
   - Preconditions: multiple grant requests for the same target inside the active window (including shorter-then-longer expiry requests).
   - Expected:
     - manager merges into a single stored lease with correct max expiry semantics
     - after expiry, reconciliation emits `leaseExpired` once per newly-expired lease; `leaseReshielded` once per reconciliation call
     - no “double-expire” / resurrection across consecutive reconciliation cycles
   - Unit test coverage:
     - `UnlockLeaseManagerInstrumentationTests.testGrant_rapidRepeats_preservesLeaseID_andMaxExpiry`

4) **Clock skew / backwards reconciliation assumptions**
   - Preconditions: first reconciliation runs `nowForward` (past expiry) then later a second reconciliation runs `nowBackwards` (earlier than the last reconcile).
   - Expected:
     - second `reconcileExpiry` is idempotent: `reshieldedTargetIDs` is empty
     - no additional `leaseExpired` / `leaseReshielded` events emitted on the backwards call
   - Unit test coverage:
     - `UnlockLeaseManagerInstrumentationTests.testReconcileExpiry_clockSkew_backwards_doesNotReshieldAgain`

## Instrumentation (funnel metrics)
### Added API
- `VowCore.RequestFunnelMetricsRecorder`
- default: `NoopRequestFunnelMetricsRecorder` (no-op)

### Host integration
`UnlockRequestFlowCoordinator` now accepts an optional `funnelMetricsRecorder` and records funnel events (request lifecycle) on successful state transitions.

Recorded events cover: `requestCreated`, `frictionTimerStarted`, `evidenceRequired`, `evidenceCompleted`, `aiReviewed`, and decision/session/review events when they transition the state machine.

### Lease lifecycle instrumentation (temporary unlock leases)
Host/mobile layer can opt into privacy-safe instrumentation for temporary unlock leases.

#### Added API / hooks
- `VowCore.UnlockLeaseLifecycleEventType` + `VowCore.UnlockLeaseLifecycleEvent`
- `UnlockLeaseManager.grant(..., record:)` emits:
  - `leaseGranted` when a new active lease is granted
  - `leaseExtended` when `mergeActive` extends an existing active lease
- `UnlockLeaseManager.reconcileExpiry(..., record:)` emits:
  - `leaseExpired` once per newly-expired lease
  - `leaseReshielded` once per reconciliation call (aggregated)
- `UnlockRequestFlowCoordinator` accepts an optional `leaseLifecycleRecorder` to auto-record grant/extend events when it grants leases.

#### Event fields (and privacy notes)
All correlation fields are UUIDs.
- `type`, `occurredAt`
- `requestID`, `leaseID`, `targetID` (UUID correlation keys; not personal data)
- `startAt`, `expiresAt` (timestamps for debugging)
- `reason` (coarse, privacy-safe unlock rationale; **host should avoid sensitive personal/child data**)
- `expiredLeaseIDs`, `reshieldedTargetIDs` (UUID arrays; aggregated reconciliation details)

#### What to test
- Grant/extend events fire exactly once per lease grant/merge.
- Expiry/reshield events fire only for newly expired leases on reconciliation.
- `reason` is coarse / privacy-safe when provided.

## Performance checks
- `FrictionEngine.seconds(for:)` should behave as constant-time and return the policy lower bounds.
- (Unit tests) performance sanity via `XCTest.measure` + correctness assertions.

## Rollout plan (staged)
1) **Stage 0 — Local / internal dogfood**
   - enable recorder + verify event ordering matches the state machine.
   - confirm evidence gating behaves correctly under delays/errors.

2) **Stage 1 — Limited cohort**
   - roll out unlock-request flow to a small set of test users/dev devices.
   - monitor:
     - funnel drop-offs (evidence pending duration, decision outcomes)
     - denial rates vs. expected baselines
     - any crash/regression in the coordinator path

3) **Stage 2 — Broader internal rollout**
   - expand cohort gradually.
   - gate by risk tier (start with low/medium, then add high).

4) **Stage 3 — Pre-release / TestFlight**
   - require evidence tasks logging + reviewLogged counts to be non-zero and stable.

## Definition of done (for PR review)
- Automated unit tests for core state machine and friction/evidence logic added under `VowCoreTests`.
- Funnel instrumentation interface + coordinator event recording added.
- This document updated with QA matrix + rollout stages.

## Family Controls entitlement/provisioning verification (real-device)
This is the safe “capability gate” for enabling Screen Time / Family Controls flows.

### Host-app behavior
- `ShieldConfigurationController.setPolicy(_:)` is a no-op unless the runtime verification report is `isReady == true`.
- `isReady` requires:
  - Family Controls authorization appears approved
  - all required Screen Time extensions (best-effort bundle presence) are found in the host app’s built-in plug-ins

### How to verify on a real device
1) **Enable capabilities everywhere**
   - In Xcode: for the iOS app target and every required Screen Time extension target, enable the **Family Controls** capability/entitlement.
2) **Regenerate provisioning profiles after entitlement changes**
   - Xcode: **Product → Clean Build Folder**
   - Update provisioning profiles for the correct Team/device set
   - (If needed) delete DerivedData and rebuild
3) **Install via Xcode onto a registered device**
   - Do not rely on simulator for this check.
4) **Check the runtime verification report**
   - Wire `ShieldConfigurationController(requiredExtensionBundleIdentifiers: [...])` with the expected extension bundle identifiers.
   - On the device, log the result of `FamilyControlsCapabilityGate.verify(...)` (or expose it in a debug view) and confirm `isReady == true` before applying the shield policy.

Notes:
- If `isReady` is `false`, the app should avoid entering partially-enabled states (i.e., it should not apply shield configuration / should fail closed).
