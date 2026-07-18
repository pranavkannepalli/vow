# Real-device provisioning verification: Family Controls gating (fail-closed)

## Goal
Create a real-device test matrix to verify that **Family Controls / Screen Time provisioning** behaves **fail-closed**: when the required capability/provisioning is **not verified** (or required Screen Time extensions are missing), the app must **not apply any blocking policy**.

This repo currently ships a **NoopShieldConfigurationBackend** (v1 placeholder). The matrix below is intended to guide and validate the eventual ManagedSettings integration.

---

## What to capture per test case
- Device model
- iOS version
- App version/build
- Whether Family Controls authorization is:
  - **authorized**
  - **notAuthorized**
  - **unknown** (e.g., first run / ambiguous callbacks)
- Presence of required Screen Time extensions:
  - Screen Time / Managed Settings extension installed? (**yes/no**) 
  - Any additional required extension(s) present? (**yes/no**)
- Observed Shield behavior:
  - Does `ShieldConfigurationController.setPolicy(...)` result in ManagedSettings blocks?
  - Any console/runtime errors?

---

## Expected behavior (fail-closed)
When **capability/provisioning is not verified** OR **required extensions are missing**, the app should:
- Treat the policy application as a **no-op** (i.e., do not block target apps/content)
- Avoid raising user-visible “unblock” affordances that contradict the fail-closed behavior

In code terms, once the real backend exists:
- `ShieldConfigurationController.setPolicy(policy)` must effectively become `clear()` / no-op when verification fails.

---

## Real-device test matrix
Fill one row per phone/tablet.

### A) Authorization state: authorized
- **Setup**:
  - Family Controls authorized for the app
  - Required Screen Time extensions present
- **Action**:
  1. Launch app
  2. Navigate to shielding flow (or call into policy application)
  3. Call `ShieldConfigurationController.setPolicy(...)` with a representative `BlockedTargetsPolicy`
- **Expected**:
  - Blocking occurs for the specified targets (ManagedSettings-backed)

### B) Authorization state: notAuthorized
- **Setup**:
  - Deny Family Controls authorization
  - (Extensions may be present)
- **Action**:
  1. Launch app
  2. Attempt to apply a blocking policy
- **Expected (fail-closed)**:
  - No blocking is applied
  - App does not enter an inconsistent state

### C) Authorization state: unknown (ambiguous / first-run)
- **Setup**:
  - Install fresh / clear relevant permissions so callbacks are ambiguous
- **Action**:
  1. Attempt to apply a blocking policy as soon as possible after launch
- **Expected (fail-closed)**:
  - Until verification resolves, do not block (no-op)

### D) Missing required extensions
Test separately for:
- **D1**: Screen Time / Managed Settings extension missing
- **D2**: Additional required extension missing (if applicable)

- **Setup**:
  - Authorization state may be authorized or notAuthorized (record which)
  - Required extension(s) missing
- **Action**:
  1. Attempt to apply blocking policy
- **Expected (fail-closed)**:
  - No blocking applied
  - Clear logs indicating verification failed (without crashing)

---

## Logging / evidence checklist
For each test case, capture:
- Device screenshots (optional)
- App logs showing:
  - authorization status
  - extension presence checks
  - final decision to apply vs no-op
- If blocking happens: what exactly became blocked

---

## Current repo status
- `ShieldConfigurationController` delegates to a backend.
- This repo includes:
  - `NoopShieldConfigurationBackend` (always no-ops)

Until ManagedSettings integration is implemented, real-device outcomes should align with **no-op / fail-closed** expectations.

---

## Notes for the eventual implementation PR
When the real backend is added, the following should be instrumented to satisfy the matrix:
- A single verification function that returns **verified / not_verified** with reasons
- Extension presence checks before applying any policy
- A “decision log” emitted right before backend.apply/clear
