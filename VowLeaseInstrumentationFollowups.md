# Vow lease-instrumentation follow-ups (missing events + schema alignment)

## Operator narrative (what to do + what “done” looks like)
In this follow-up, update Vow’s SwiftPM implementation so telemetry covers (1) the `UnlockRequestStateMachine.evidencePending` moment and (2) the full temporary-unlock lease lifecycle (`leaseGranted`, `leaseExtended`, `leaseExpired`, `leaseReshielded`) exactly as described in `VowSpecV2-QA-and-Rollout.md`.

Prerequisites
- Swift toolchain + XCTest available (SwiftPM build/test works)
- You’re operating in the correct repo: `~/.openclaw/repos/vow`

Operator steps / commands
1) Confirm the repo is compile-clean:
   ```bash
   swift build
   ```
2) Run the current test suite:
   ```bash
   swift test
   ```
3) Implement the missing telemetry items (event enum cases + a lease lifecycle event family + wiring in the relevant coordinator/lease-manager code paths).
4) Add/extend unit tests to lock in ordering + boundary/idempotency semantics (evidencePending, leaseGranted vs leaseExtended, leaseExpired/leaseReshielded on reconciliation).
5) Re-run until green:
   ```bash
   swift test
   ```

Expected outputs
- Telemetry additions that match the QA matrix in `VowSpecV2-QA-and-Rollout.md`.
- Unit tests under `Tests/VowCoreTests` covering lease reconciliation expiry/reshield behaviors (e.g., `UnlockLeaseManagerInstrumentationTests.testReconcileExpiry_expiresWithoutReunlock`) and evidence/ordering expectations.
- `swift test` passes.

Troubleshooting / edge notes
- Evidence failures: ensure `UnlockRequestEvent` includes `evidencePending`, and the recorder is invoked when transitioning into `UnlockRequestStateMachine.evidencePending`.
- Compile/type failures around lease telemetry: verify the new event family + recorder integration is added consistently across `Sources/VowCore/Logging/RequestFunnelMetricsRecorder.swift`, `Sources/VowUI/UnlockRequestFlowCoordinator.swift`, and the reconciliation path in `Sources/VowCore/UnlockLeaseManager.swift`.
- Ordering/idempotency failures: ensure reconciliation emits `leaseExpired` for each newly-expired lease and emits `leaseReshielded` exactly once per reconciliation call; reconciliation must be idempotent under backwards/clock-skew scenarios.

## Usage story (turn this checklist into a PR)
This checklist is the “operator runbook” for translating `VowSpecV2-QA-and-Rollout.md` instrumentation expectations into concrete code changes in the Vow SwiftPM repo.

### Prerequisites
- Swift toolchain + XCTest available (SwiftPM build/test works)
- You’re operating in the correct repo: `~/.openclaw/repos/vow`

### Runbook (commands / steps)
1) Build to confirm the repo is in a compile-clean state:
   ```bash
   swift build
   ```
2) Run current unit tests:
   ```bash
   swift test
   ```
3) Implement the missing telemetry items in the codebase (event enum cases + new lease lifecycle event family + wiring in the relevant coordinator/lease-manager code paths).
4) Add/extend unit tests to lock in the ordering + boundary/idempotency semantics (evidencePending, leaseGranted vs leaseExtended, leaseExpired/leaseReshielded on reconciliation).
5) Re-run until green:
   ```bash
   swift test
   ```

### Expected outputs
- Telemetry additions that match the QA matrix in `VowSpecV2-QA-and-Rollout.md`.
- Unit tests under `Tests/VowCoreTests` covering the lease reconciliation expiry/reshield behaviors and the evidence/ordering expectations.
- `swift test` passes.

### Troubleshooting
- Evidence failures: confirm `UnlockRequestEvent` includes `evidencePending` and the recorder is invoked when transitioning into `UnlockRequestStateMachine.evidencePending`.
- Compile/type failures around lease telemetry: verify the new event family + recorder integration are added consistently across `Sources/VowCore/Logging/RequestFunnelMetricsRecorder.swift`, `Sources/VowUI/UnlockRequestFlowCoordinator.swift`, and the reconciliation path in `Sources/VowCore/UnlockLeaseManager.swift`.
- Ordering/idempotency failures: ensure reconciliation emits `leaseExpired` per newly-expired lease and `leaseReshielded` exactly once per reconciliation call, and that backwards/clock-skew reconciliation is idempotent.

Context: This task is produced as a **follow-up list after the instrumentation integrity check**. Based on the current `main`-ish repo state in this workspace, the v2 QA doc references lease lifecycle events (`leaseGranted/leaseExtended/leaseExpired/leaseReshielded`), but the implementation currently only models **unlock-request funnel** events via `UnlockRequestEvent`.

## 1) Missing events (name → expected lifecycle moment)

### Unlock-request funnel (event completeness)
1) `evidencePending`
- Expected moment: after friction ends with `evidenceRequired == true` and before the evidence runner resolves (i.e., while `UnlockRequestStateMachine` is in `evidencePending`).
- Why: `UnlockRequestStateMachine` has `case .evidencePending`, but the telemetry enum `UnlockRequestEvent` currently lacks an `evidencePending` case.

### Temporary unlock lease lifecycle (event family missing in code)
The QA/instrumentation spec references lease lifecycle telemetry, but the repo snapshot in this workspace does **not** define a lease lifecycle event type or emission hooks.

For each newly-emitted event, expected moment is:
2) `leaseGranted`
- Expected moment: right after a lease is granted/added for a target (i.e., when `UnlockRequestFlowCoordinator.grantLease(...)` calls `leaseManager.grant(...)` and it results in an inactive-at-boundary “new” lease).

3) `leaseExtended`
- Expected moment: when `UnlockLeaseManager.grant(…, mergeActive: true, …)` merges into an **existing active** lease (i.e., active-at-`now` for the same `targetID`), extending `expiresAt`.

4) `leaseExpired`
- Expected moment: during reconciliation when leases newly transition from active → inactive (`UnlockLeaseManager.reconcileExpiry(now:)` computes newly-expired lease IDs).

5) `leaseReshielded`
- Expected moment: during reconciliation whenever reshielding is triggered for reconciliation-created newly-expired leases.
- Note: the spec doc expects **one reshield event per reconciliation call** (aggregated).

## 2) Schema mismatches (field name/type/semantics) to align

### 2.1 Event-family mismatch: `UnlockRequestEvent` vs lease lifecycle events
- Current implementation:
  - `Sources/VowCore/State/RequestState.swift` defines `enum UnlockRequestEvent` (request lifecycle + decisions + session + review logging).
  - `Sources/VowCore/Logging/RequestFunnelMetricsRecorder.swift` records only `UnlockRequestEvent`.
- Spec expectation (from `VowSpecV2-QA-and-Rollout.md`): lease lifecycle events exist.
- Mismatch:
  - There is no `UnlockLeaseLifecycleEvent` (or equivalent) type.
  - There is no recorder interface or emission path for `leaseGranted/leaseExtended/leaseExpired/leaseReshielded`.

### 2.2 Missing `evidencePending` event case + semantics
- `UnlockRequestStateMachine` includes `.evidencePending`, but `UnlockRequestEvent` does not.
- Mismatch:
  - Hosts/analytics that key off `evidencePending` cannot compute durations correctly.

### 2.3 Lease lifecycle payload field expectations (proposed schema)
Because `UnlockLease` already contains a privacy-safe core (`id`, `targetID`, `startAt`, `expiresAt`, `requestID`, `reason`), the minimal privacy-safe payload for lease lifecycle events should be:

- `leaseID`: UUID
- `targetID`: UUID (blocked-target identifier; non-sensitive/pseudonymous)
- `requestID`: UUID (unlock-request identifier)
- `startAt`: Date (lease start)
- `expiresAt`: Date (lease expiry boundary)
- `at`: Date (event emission time)
- Event-specific:
  - `leaseExtended`: include both `previousExpiresAt` and `newExpiresAt` (so “extend vs renew” is auditable)
  - `leaseReshielded`: include `reshieldTargetIDs: [UUID]` (aggregated), or an aggregated count if you prefer tighter data minimization

(If the privacy-safe spec requires dropping some fields, this list should be reduced; but the semantics should remain sufficient to validate ordering + boundary behavior.)

## 3) Proposed corrections (with concrete code/file targets)

### 3.1 Add `evidencePending` telemetry
- File: `Sources/VowCore/State/RequestState.swift`
  - Add `case evidencePending` to `enum UnlockRequestEvent`.
- File: `Sources/VowUI/UnlockRequestFlowCoordinator.swift`
  - Emit/record `evidencePending` when evidence work starts (i.e., inside `startEvidenceIfNeeded()` after moving into `evidencePending` state, before awaiting the evidence runner).

### 3.2 Add a lease lifecycle event family + recorder interface
- New file (suggested): `Sources/VowCore/Logging/UnlockLeaseLifecycleEvent.swift`
  - Define `Codable` event enum, e.g.:
    - `.leaseGranted(LeasePayload)`
    - `.leaseExtended(LeaseExtendedPayload)`
    - `.leaseExpired(LeaseExpiredPayload)`
    - `.leaseReshielded(LeaseReshieldedPayload)`
- File: `Sources/VowCore/Logging/RequestFunnelMetricsRecorder.swift`
  - Option A (recommended): broaden recorder protocol into a single `VowInstrumentationEvent` enum.
  - Option B: add a second protocol, e.g. `LeaseLifecycleMetricsRecorder`, so hosts can wire it separately.
- File: `Sources/VowUI/UnlockRequestFlowCoordinator.swift`
  - Emit `leaseGranted` / `leaseExtended` inside `grantLease(now:)` based on whether `leaseManager.grant(...)` merged an existing active lease vs appended a new one.
  - Emit/forward reconciliation-derived events on the lease-reconciliation path (currently reconciliation logic exists in `UnlockLeaseManager.reconcileExpiry`, but lease lifecycle emission hooks are not present in this repo snapshot).
- File: `Sources/VowCore/UnlockLeaseManager.swift`
  - Consider returning richer reconciliation output to support `leaseExpired` (per-lease) and `leaseReshielded` (aggregated), e.g.:
    - return `(expiredLeases: [UnlockLease], reshieldTargetIDs: [UUID])` or `expiredLeaseIDs` and let caller map to payload.
  - This avoids recomputation and ensures consistent boundary semantics.

### 3.3 Add unit tests for missing event emissions and ordering
- New/updated test file: `Tests/VowCoreTests/UnlockLeaseManagerInstrumentationTests.swift`
  - Add tests to validate:
    1) `leaseGranted` fires for a new inactive-at-boundary grant
    2) `leaseExtended` fires when merging active leases
    3) `leaseExpired` fires exactly once per newly-expired lease on reconciliation
    4) `leaseReshielded` fires exactly once per reconciliation call (aggregated)
    5) clock-skew/backwards reconciliation emits no additional reshield/expired events

## 4) “Pass/Fail” engineering checklist for the next PR
- [ ] Telemetry event family exists for lease lifecycle and is wired into grant/merge/reconcile code paths.
- [ ] `evidencePending` is emitted and matches `UnlockRequestStateMachine` `.evidencePending`.
- [ ] Event ordering and boundary semantics are validated with deterministic `now` injections.
- [ ] Privacy minimization is maintained (no sensitive child data; UUIDs only; aggregate reshield where possible).

