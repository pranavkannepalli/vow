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

## Instrumentation (funnel metrics)
### Added API
- `VowCore.RequestFunnelMetricsRecorder`
- default: `NoopRequestFunnelMetricsRecorder` (no-op)

### Host integration
`UnlockRequestFlowCoordinator` now accepts an optional `funnelMetricsRecorder` and records funnel events (request lifecycle) on successful state transitions.

Recorded events cover: `requestCreated`, `frictionTimerStarted`, `evidenceRequired`, `evidenceCompleted`, `aiReviewed`, and decision/session/review events when they transition the state machine.

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
