# FamilyControlsCapabilityGate — failure-mode audit checklist

## What the gate guarantees
- **Fail-closed authorization**: only explicit `approved/authorized` runtime values map to `.authorized`; everything else is `.unknown` (or `.notAuthorized` for explicit deny-ish strings).
- **Fail-closed extension readiness**: `ScreenTimeCapabilityVerificationReport.isReady` is `true` only when:
  - authorization is `.authorized`, and
  - **no required extension bundle IDs are missing**.

## Checklist items (runtime failure modes)

### 1) AuthorizationCenter / authorizationStatus runtime drift
**Checklist item**
- `AuthorizationCenter` class not found → `.unknown(...)` (should prevent enablement)
- `authorizationStatus` returns an unexpected string → `.unknown(...)` (should prevent enablement)
- Mapping is **deny-first** and does **not substring-match** `authorized` inside `unauthorized`

**Coverage in this PR**
- **Code:**
  - `FamilyControlsCapabilityGate.currentAuthorizationState()` uses runtime lookup; when `AuthorizationCenter` (or `authorizationStatus`) is missing, it returns `.unknown(message:)`.
  - `stateFromAuthorizationStatusDescription(_:)` is deny-first and only allows explicit `approved/authorized` (no substring allow).
- **Tests:**
  - `test_stateFromAuthorizationStatusDescription_doesNotSubstringMatchAuthorized` asserts `"unauthorized"` maps to `.unknown`.
  - `test_stateFromAuthorizationStatusDescription_mapsDeniedToNotAuthorized` asserts explicit deny-ish strings map to `.notAuthorized`.
- **Docs:**
  - This audit file describes the drift behavior and the substring-safety requirement.

### 2) Extension presence checks correctness
**Checklist item**
- Missing extension IDs must make `isReady == false` even if auth is `.authorized`.
- Required list containing duplicates should not create duplicate “missing” entries.
- Deterministic output: `presentExtensionBundleIdentifiers` + `missingExtensionBundleIdentifiers` are sorted.

**Coverage in this PR**
- **Code:**
  - `computeMissingExtensions(requiredExtensionBundleIdentifiers:presentExtensionBundleIdentifiers:)` treats the required identifiers as a `Set` and returns a `sorted()` list.
  - `verify(...)` sorts both `presentExtensionBundleIdentifiers` (via `Array(present).sorted()`) and `missingExtensionBundleIdentifiers`.
- **Tests:**
  - `test_computeMissingExtensions_dedupesRequiredIdentifiers` covers deduping duplicates.
  - `test_computeMissingExtensions_isSortedDeterministically` covers deterministic ordering.
- **Docs:**
  - This audit file documents both dedupe and deterministic sorting.

### 3) Non-iOS test/runtime behavior
**Checklist item**
- `presentExtensionBundleIdentifiers()` returns `[]` off iOS family targets; callers should treat that as “not ready unless you’re on iOS”.
- Unit tests validate mapping/filter logic without depending on real runtime plug-ins.

**Coverage in this PR**
- **Code:** `presentExtensionBundleIdentifiers()` returns `[]` for non-iOS families (compile-time guarded).
- **Tests:** All coverage is via pure functions (`stateFromAuthorizationStatusDescription`, `computeMissingExtensions`) and does not require runtime FamilyControls/plug-in enumeration.
- **Docs:** This audit file calls out the `[]`-off-iOS behavior.

## Determinism / duplicate-required-extension verification (evidence)
- **Deduplication:** implemented by converting `requiredExtensionBundleIdentifiers` to a `Set` before filtering.
- **Deterministic ordering:** implemented by `sorted()` on the missing identifiers, plus sorting present identifiers in `verify(...)`.
- **Unit test evidence:**
  - `test_computeMissingExtensions_dedupesRequiredIdentifiers`
  - `test_computeMissingExtensions_isSortedDeterministically`

## Uncovered edge cases / suggested follow-up
- **Whitespace / formatting variants:** `stateFromAuthorizationStatusDescription` lowercases but does not trim whitespace (e.g. `"authorized \n"`). Suggested follow-up: `trimmed().lowercased()`.
- **Unknown runtime reflection strings:** `currentAuthorizationState()` uses `String(describing: statusObj)`; real runtime `authorizationStatus` strings could differ from our unit-test inputs. Suggested follow-up: add an abstraction/injection point for the status string provider (or additional integration tests on iOS).

## PASS/NEEDS_CHANGES verdict
**PASS** — All checklist items map to explicit fail-closed code paths, and the key dedupe + deterministic ordering behaviors are now covered by unit tests.
