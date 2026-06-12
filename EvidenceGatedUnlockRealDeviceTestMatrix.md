# Real-device test matrix: evidence-gated Screen Time lock/unlock

## Goal
On a real device, verify that the Vow unlock-request flow correctly gates Screen Time lock/unlock behind evidence completion — and correctly rejects bypass attempts. This covers the full lifecycle from `requestCreated` through terminal state, across all evidence states and common edge cases.

This matrix should be run against a build that has `ShieldConfigurationController` wired to the real `ManagedSettings` backend (not the `NoopShieldConfigurationBackend`).

---

## What to capture per test case
- Device model
- iOS version
- App version/build (git SHA tag)
- Family Controls authorization state:
  - **authorized** / **notAuthorized** / **unknown**
- Presence of all required Screen Time extensions:
  - Managed Settings extension installed? (**yes/no**)
- Evidence configuration for the run (which task type, policy parameters)
- For each step:
  - State machine state after transition
  - Funnel events emitted (in order)
  - Shield/blocking behavior (block active? **yes/no**)
  - User-visible UI: what screen is shown, what affordances exist
  - Logs: authorization state, extension checks, decision log
- Screenshots at evidence_pending, evidence_completed, and each decision point

---

## A) Happy path: evidence required (full cycle)

**Preconditions:**
- Family Controls authorized
- All required Screen Time extensions present
- Evidence policy configured to require evidence (e.g., steps task, targetStepsDelta=50)
- `evidenceRunner` wired to provider that will succeed
- No active lease for the target

| Step | Action | Expected state | Block active? | UI shown | Funnel events |
|------|--------|---------------|---------------|----------|---------------|
| A1 | Tap blocked app → shield intercept → "Request Unlock" | requestCreated | yes | Shield interception screen | requestCreated |
| A2 | Begin request (coordinator.userStartedRequest) | frictionWaiting | yes | Friction countdown screen | frictionTimerStarted |
| A3 | Wait for friction to complete | evidencePending | yes | "Complete evidence task to continue" — evidence task UI (step count / timer / journal) | evidenceRequired |
| A4 | Evidence runner completes successfully | evidenceCompleted | yes | Evidence completion confirmation → AI review screen | evidenceCompleted |
| A5 | AI review completes (auto from markEvidenceCompleted) | aiReviewed | yes | Decision prep screen | aiReviewed |
| A6 | Approve unlock (coordinator.decisionApproved) | decisionApprovedTempUnlock | **no** (for target, within lease window) | "Unlocked — X min remaining" | decisionApproved |
| A7 | Use app normally within lease window | decisionApprovedTempUnlock | no | Countdown timer for lease | sessionObserved |
| A8 | Session ends / lease expires | sessionClosed | yes (re-shielded after expiry) | Shield re-applied | sessionClosed → reviewLogged (terminal) |

**What to log/screenshot:**
- Full funnel event sequence from A1 through A8, with timestamps
- Console log confirming `grantLease(now:)` was called after `decisionApproved`
- Console log confirming `reconcileLeaseExpiry` reshielded the target
- Screenshot of evidence_pending UI (evidence task visible, no unlock affordance)
- Screenshot of the temporary-unlock countdown during the lease window

---

## B) Happy path: evidence NOT required (direct approve)

**Preconditions:**
- Family Controls authorized
- All required Screen Time extensions present
- Evidence policy configured to NOT require evidence (evidenceRequired=false)
- No active lease for the target

| Step | Action | Expected state | Block active? | UI shown | Funnel events |
|------|--------|---------------|---------------|----------|---------------|
| B1 | Tap blocked app → shield intercept → "Request Unlock" | requestCreated | yes | Shield interception screen | requestCreated |
| B2 | Begin request | frictionWaiting | yes | Friction countdown screen | frictionTimerStarted |
| B3 | Friction completes (no evidence required) | evidenceCompleted | yes | Skip evidence — direct to decision prep | evidenceRequired (with evidenceRequired=false) |
| B4 | AI review auto-completes | aiReviewed | yes | Decision prep screen | aiReviewed |
| B5 | Approve unlock | decisionApprovedTempUnlock | **no** (within lease window) | "Unlocked" | decisionApproved |
| B6 | Session close | sessionClosed | yes (after reconciliation) | Shield re-applied | sessionClosed → reviewLogged |

**What to log/screenshot:**
- Full funnel event sequence B1→B6
- Confirm that `evidencePending` state was **never entered** (evidence_pending skipped)
- Confirm `evidenceRequired` was emitted with `evidenceRequired=false` payload flag

---

## C) evidencePending: verify no premature unlock

**Preconditions:**
- Family Controls authorized, all extensions present
- Evidence required (e.g., steps task with targetStepsDelta=50)
- Evidence runner wired to a provider that will **not** complete yet (e.g., 0 steps recorded)

| Step | Action | Expected state | Block active? | UI shown |
|------|--------|---------------|---------------|----------|
| C1 | Start request → friction completes | evidencePending | **yes** | Evidence task UI: "Complete the required evidence to continue" |
| C2 | Try to call coordinator.decisionApproved() from evidencePending | **evidencePending (unchanged)** | yes | No decision — invalid transition ignored |
| C3 | Try to call coordinator.decisionDeferred() from evidencePending | **evidencePending (unchanged)** | yes | No decision — invalid transition ignored |
| C4 | Try to call coordinator.decisionDenied() from evidencePending | **evidencePending (unchanged)** | yes | No decision — invalid transition ignored |
| C5 | Verify target app is still blocked (try to open it) | blocked | **yes** | Shield interception still fires |

**What to log/screenshot:**
- Confirm that no `decisionApproved`, `decisionDeferred`, or `decisionDenied` events were emitted while in `evidencePending`
- Console log: `setPolicy(policy)` still active (blocking in effect)
- Screenshot: user is on evidence task screen, no "Approve/Unlock" button available

---

## D) Bypass attempts (fail-closed)

### D1 — Approve before AI review (skip evidence entirely)

**Preconditions:** Evidence required. Evidence not yet completed (or friction not yet passed).

| Step | Action | Expected outcome |
|------|--------|-----------------|
| D1.1 | Call coordinator.decisionApproved() while state is requestCreated | state stays requestCreated — invalid transition ignored |
| D1.2 | Advance to frictionWaiting, call decisionApproved() | state stays frictionWaiting — invalid transition ignored |
| D1.3 | Advance to evidencePending, call decisionApproved() | state stays evidencePending — invalid transition ignored |

**Expected:** No funnel `decisionApproved` event emitted in any of these steps. Target remains blocked.

### D2 — Evidence runner throws / fails / returns false

**Preconditions:** Evidence required. `evidenceRunner` wired to throw an error or return `false`.

| Step | Action | Expected outcome |
|------|--------|-----------------|
| D2.1 | Start request → friction completes → evidence runs → fails | State transitions: evidenceCompleted → aiReviewed → decisionDenied |
| D2.2 | Verify target is blocked | Target remains blocked. No lease granted. |
| D2.3 | Verify no funnel events for decisionApproved | Only decisionDenied appears. |

**What to capture:**
- Full error from evidence runner in console logs
- Confirm `decisionDenied` is the terminal event (not `decisionApproved`)
- Screenshot: denial screen shown to user (no unlock affordance)

### D3 — Evidence required but no evidence runner provided by host

**Preconditions:** Evidence required=true, but `evidenceRunner` is `nil`.

| Step | Action | Expected outcome |
|------|--------|-----------------|
| D3.1 | Start request → friction completes | State: evidencePending |
| D3.2 | Evidence work starts with `evidenceRunner == nil` | Scaffold behavior: `completed = true` (auto-complete) → flows to evidenceCompleted → aiReviewed |

**Note:** v1 scaffold allows this. The production requirement is to deny if evidence is required but not provided. This test case documents the **current** v1 behavior and flags it as needing a production guardrail.

**What to capture:**
- Log evidence runner was nil → auto-completed
- Note in test results: v1 scaffold auto-completes; production must deny

### D4 — Missing Family Controls capability / entitlements

**Preconditions:** Deny Family Controls authorization, or build the app without the Family Controls entitlement.

| Step | Action | Expected outcome |
|------|--------|-----------------|
| D4.1 | Launch app | ShieldConfigurationController.setPolicy(...) is a no-op |
| D4.2 | Try to navigate to shield/interception flow | App must not offer unlock-request flow |
| D4.3 | Verify no funnel events | No requestCreated / frictionTimerStarted etc. emitted |

**What to capture:**
- Console log: capability verification failed → reason (authorization state, missing extensions)
- Screenshot: user-visible message — "Screen Time / Family Controls not verified—complete setup to use unlock requests"
- Confirm `FamilyControlsCapabilityGate` returns `notVerified`

### D5 — Wrong entitlement state (authorized revoked mid-session)

**Preconditions:** App was authorized; then Family Controls is revoked from Settings while app is backgrounded/suspended.

| Step | Action | Expected outcome |
|------|--------|-----------------|
| D5.1 | Start app with Family Controls authorized | Normal flow works |
| D5.2 | Background app; revoke Family Controls from Settings.app | — |
| D5.3 | Return to app; trigger unlock request | Capability gate re-checks → `notVerified` → no-op |
| D5.4 | Verify no blocking is applied | Targets are NOT blocked |

**What to capture:**
- Console log: authorization changed to notAuthorized mid-session
- Confirm funnel events STOP being emitted after revocation
- Screenshot: app shows "Screen Time / Family Controls not verified" after re-check

### D6 — Repeated rapid unlock attempts within active lease

**Preconditions:** An active lease exists for the target.

| Step | Action | Expected outcome |
|------|--------|-----------------|
| D6.1 | Grant first unlock for target A | leaseGranted emitted. Target A is unlocked. |
| D6.2 | Before expiry, initiate another unlock request for target A | New request starts normally (friction + evidence). |
| D6.3 | Approve the second unlock | leaseExtended emitted (not leaseGranted). New expiresAt = merged max. |
| D6.4 | Let original lease time pass; check target | Target remains unlocked under extended lease window. |
| D6.5 | Let extended lease time pass; reconcile | leaseExpired + leaseReshielded. Target re-blocked. **One** reshield, not two. |

**What to capture:**
- Confirm exactly `leaseExtended` (not `leaseGranted`) for the second approval
- Confirm `previousExpiresAt` and `newExpiresAt` match expected values
- Confirm only one `leaseExpired` + one `leaseReshielded` on final reconciliation
- No double-reshield or resurrection

---

## E) Decision variant paths (post aiReviewed)

**Preconditions:** Evidence completed, state = aiReviewed.

### E1 — Approved: grant lease, verify temporary unlock

| Step | Action | Expected outcome |
|------|--------|-----------------|
| E1.1 | coordinator.decisionApproved() | state → decisionApprovedTempUnlock. leaseGranted. Target unlocked for approvedDurationSeconds. |
| E1.2 | Verify target app opens | App opens without shield interception during lease window. |
| E1.3 | Wait for lease expiry → reconcile | Target re-shielded. |

**Capture:** Lease grant payload (leaseID, targetID, requestID, startAt, expiresAt). Screenshot of active lease countdown.

### E2 — Deferred: keep blocked, no lease

| Step | Action | Expected outcome |
|------|--------|-----------------|
| E2.1 | coordinator.decisionDeferred() | state → decisionDeferred (terminal). No lease granted. |
| E2.2 | Verify target | Target remains blocked. |
| E2.3 | Verify no leaseGranted/leaseExtended emitted | Only decisionDeferred. |

**Capture:** Screenshot of deferral UI. Confirm funnel event is `decisionDeferred` not `decisionApproved`.

### E3 — Denied: keep blocked, no lease, show explanation

| Step | Action | Expected outcome |
|------|--------|-----------------|
| E3.1 | coordinator.decisionDenied() | state → decisionDenied (terminal). No lease granted. |
| E3.2 | Verify target | Target remains blocked. |
| E3.3 | Verify no leaseGranted/leaseExtended emitted | Only decisionDenied. |

**Capture:** Screenshot of denial explanation UI.

---

## F) Session close + review logging (post-approval terminal)

**Preconditions:** Unlock approved, lease is active.

| Step | Action | Expected outcome |
|------|--------|-----------------|
| F1 | coordinator.sessionObserved() | State stays decisionApprovedTempUnlock. sessionObserved recorded. |
| F2 | coordinator.sessionClosed() | State → sessionClosed. sessionClosed recorded. Block stays inactive until lease expires. |
| F3 | coordinator.reviewLogged() | State → reviewLogged (terminal). reviewLogged recorded. |

**Capture:** Full terminal funnel: sessionObserved → sessionClosed → reviewLogged. Confirm `reviewLogged` === terminal state.

---

## G) Restore/resume from snapshot

**Preconditions:** App was killed/restarted mid-flow. A snapshot was saved.

### G1 — Restore from evidencePending

| Step | Action | Expected outcome |
|------|--------|-----------------|
| G1.1 | Save snapshot with state=evidencePending | — |
| G1.2 | Restore coordinator from snapshot | Evidence work restarts. State stays evidencePending. |
| G1.3 | Evidence completes | Flows to evidenceCompleted → aiReviewed as normal. |

### G2 — Restore from evidenceCompleted

| Step | Action | Expected outcome |
|------|--------|-----------------|
| G2.1 | Save snapshot with state=evidenceCompleted | — |
| G2.2 | Restore coordinator from snapshot | Auto-advances: evidenceCompleted → aiReviewed (no re-run of evidence) |
| G2.3 | Approve | Normal decision flow. |

### G3 — Restore from frictionWaiting

| Step | Action | Expected outcome |
|------|--------|-----------------|
| G3.1 | Save snapshot with state=frictionWaiting, frictionEndsAt in the past | — |
| G3.2 | Restore coordinator | Friction completes immediately (remaining ≤ 0). Transitions to evidencePending or evidenceCompleted. |

**Capture:** For each restore test, screenshot the initial restored state and confirm funnel events pick up where they left off.

---

## Summary: what must NEVER happen (fail-closed invariants)

These invariants should hold across ALL test cases above:

1. ❌ **Never** grant a lease while in `evidencePending` (evidence not yet completed)
2. ❌ **Never** emit `decisionApproved` before `aiReviewed`
3. ❌ **Never** apply blocking policy when Family Controls capability is `notVerified`
4. ❌ **Never** emit `requestCreated` / funnel events when capability is `notVerified`
5. ❌ **Never** grant a lease when `evidenceRunner` fails (terminal denial instead)
6. ❌ **Never** double-emit `leaseReshielded` for the same reconciliation cycle
7. ❌ **Never** leave a target unlocked past its lease expiry without reconciliation reshielding

---

## Logging / evidence checklist (per device run)

For each complete run, collect and attach:
- [ ] Device model + iOS version + app build number
- [ ] Family Controls authorization state at start of run
- [ ] Full console log with timestamps (filtered to `VowCore` / `VowUI` subsystem)
- [ ] Funnel event log: every `RequestFunnelMetricsRecorder.record(...)` call captured with event type + timestamp
- [ ] Lease lifecycle telemetry: `leaseGranted` / `leaseExtended` / `leaseExpired` / `leaseReshielded` payloads
- [ ] Screenshots at: shield interception, evidence task view, decision screen, unlock countdown, denial/deferral screen
- [ ] Screen recording of the full happy-path run (A1→A8)

---

## Notes for the implementer/operator

- The `NoopShieldConfigurationBackend` still exists in the repo as v1 placeholder. This matrix assumes `ManagedSettings` wiring is in place. Tests run against Noop will always produce no-op results — that's expected.
- Section D3 documents a known v1 scaffold weakness (nil evidence runner auto-completes). Flag if this matrix is run pre-production-guardrail.
- For reproducible runs: set `frictionEngine.policy` to minimum values (e.g., lowSeconds=1) to skip friction delays during verification.
- Evidence runner configs for each test scenario should be documented alongside the run results.