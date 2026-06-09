# Operator mini runbook: Vow lease-instrumentation follow-ups

## Prerequisites
- Swift toolchain + XCTest available (SwiftPM build/test works)
- You’re operating in the correct repo: `~/.openclaw/repos/vow`

## Runbook (commands / steps)
1) Confirm the repo is compile-clean:
   ```bash
   swift build
   ```
2) Run the current unit tests:
   ```bash
   swift test
   ```
3) Implement the missing telemetry items (event enum cases + a lease lifecycle event family + wiring in the relevant coordinator/lease-manager code paths).
4) Add/extend unit tests to lock in the ordering + boundary/idempotency semantics (evidencePending, leaseGranted vs leaseExtended, leaseExpired/leaseReshielded on reconciliation).
5) Re-run until green:
   ```bash
   swift test
   ```

## What “done” looks like (expected outputs)
- Telemetry additions that match the QA matrix in `VowSpecV2-QA-and-Rollout.md`.
- Unit tests under `Tests/VowCoreTests` covering lease reconciliation expiry/reshield behaviors (e.g., `UnlockLeaseManagerInstrumentationTests.testReconcileExpiry_expiresWithoutReunlock`) and evidence/ordering expectations.
- `swift test` passes.

## Troubleshooting / edge notes (common failure modes)
- **Evidence failures**: ensure `UnlockRequestEvent` includes `evidencePending`, and the recorder is invoked when transitioning into `UnlockRequestStateMachine.evidencePending`.
- **Compile/type failures around lease telemetry**: verify the new event family + recorder integration is added consistently across:
  - `Sources/VowCore/Logging/RequestFunnelMetricsRecorder.swift`
  - `Sources/VowUI/UnlockRequestFlowCoordinator.swift`
  - `Sources/VowCore/UnlockLeaseManager.swift`
- **Ordering/idempotency failures**: ensure reconciliation emits `leaseExpired` for each newly-expired lease and emits `leaseReshielded` exactly once per reconciliation call; reconciliation must be idempotent under backwards/clock-skew scenarios.

## FAQ (top 3 mistakes)
1) **“I added `evidencePending` to the state machine, but analytics still fail.”**
   - Add/extend `UnlockRequestEvent` to include `evidencePending`, then record it when entering `UnlockRequestStateMachine.evidencePending`.

2) **“It compiles, but telemetry wiring is inconsistent.”**
   - Make sure the new lease lifecycle event family + recorder integration is applied across all three targets:
     - `RequestFunnelMetricsRecorder.swift`
     - `UnlockRequestFlowCoordinator.swift`
     - `UnlockLeaseManager.swift`

3) **“Reconciliation emits the wrong number of lease events.”**
   - During `UnlockLeaseManager.reconcileExpiry(now:)`, ensure `leaseExpired` is emitted per newly-expired lease and `leaseReshielded` is emitted exactly once per reconciliation call, with idempotent behavior under clock skew/backwards time.
