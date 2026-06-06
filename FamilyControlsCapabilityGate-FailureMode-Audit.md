# FamilyControlsCapabilityGate — failure-mode audit checklist

## What the gate guarantees
- **Fail-closed authorization**: only explicit `approved/authorized` runtime values map to `.authorized`; everything else is `.unknown` (or `.notAuthorized` for explicit deny-ish strings).
- **Fail-closed extension readiness**: `ScreenTimeCapabilityVerificationReport.isReady` is `true` only when:
  - authorization is `.authorized`, and
  - **no required extension bundle IDs are missing**.

## Key edge cases to verify in runtime
### 1) AuthorizationCenter / authorizationStatus runtime drift
- `AuthorizationCenter` class not found → `.unknown(...)` (should prevent enablement).
- `authorizationStatus` returns an unexpected string → `.unknown(...)` (should prevent enablement).
- Ensure mapping is **deny-first** and does **not** substring-match `authorized` inside `unauthorized`.

### 2) Extension presence checks correctness
- Missing extension IDs must make `isReady == false` even if auth is `.authorized`.
- Required list containing duplicates should not create duplicated “missing” entries (deduped in `computeMissingExtensions`).
- Deterministic output: `presentExtensionBundleIdentifiers` + `missingExtensionBundleIdentifiers` are sorted.

### 3) Non-iOS test/runtime behavior
- `presentExtensionBundleIdentifiers()` returns `[]` off iOS family targets; callers should treat that as “not ready unless you’re on iOS”.
- Unit tests should validate mapping/filter logic without depending on real runtime plug-ins.

## Suggested regression tests (unit)
- `stateFromAuthorizationStatusDescription`:
  - `approved` / `authorized` → `.authorized`
  - `denied` / `not authorized` → `.notAuthorized`
  - `unauthorized` → `.unknown` (no substring allow)
- `computeMissingExtensions`:
  - returns only missing IDs
  - dedupes required IDs

## Implementation notes
- Gate is intentionally defensive: best-effort runtime inspection + conservative mapping + explicit missing-extension checks.
