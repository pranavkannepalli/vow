# Vow — Technical PRD

## 1. Product Summary

**Vow** is an iOS-native digital wellbeing app that uses Apple's Screen Time APIs to make distracting app access a structured, logged, temporary, and evidence-gated action rather than an instant override.

The product does **not** attempt to replace the iPhone launcher or fully brick the device. It uses Apple's supported frameworks to:
- block selected apps, categories, and web domains
- intercept distraction attempts with shield UI
- route unblock attempts into a request flow
- require evidence tasks before temporary access
- score the day using objective and semi-objective signals
- tighten or loosen friction dynamically based on behavior

## 2. Product Goals

### Primary goal
Reduce impulsive access to high-risk apps by converting app opening into a deliberate process with friction, evidence, and post-use accountability.

### Secondary goals
- produce a trustworthy daily life/productivity score
- connect real-world behavior to digital access rules
- create logs and review loops that expose rationalization patterns
- support optional accountability escalation without requiring it for normal usage

## 3. Platform Scope

### In scope
- iPhone app built with SwiftUI
- Screen Time integration using:
  - `FamilyControls`
  - `ManagedSettings`
  - `DeviceActivity`
- local persistence + lightweight backend sync
- AI-assisted request classification
- HealthKit signals for evidence tasks and scoring
- widgets / notifications / daily review UI
- TestFlight and App Store distribution

### Out of scope
- custom home screen / launcher replacement
- total device lockdown beyond supported Screen Time APIs
- MDM-only enterprise device controls
- jailbreak-dependent features
- trying to hide all installed apps from the user

## 4. Technical Constraints

### iOS / Apple constraints
The app is built around Apple's Family Controls / Screen Time stack. These APIs require the Family Controls entitlement and app extensions, and apps can be distributed for testing on registered devices and through TestFlight before App Store release. The gating issue is entitlement/capability approval and profile setup, not being live on the App Store. citeturn304706search1turn362405view1

### Practical implication
You can build and test the Screen Time functionality during development. You do **not** need to be on the App Store first. What you do need:
- an Apple Developer account
- the Family Controls capability/entitlement configured for the app and relevant extensions
- real-device testing
- correct provisioning profiles for all targets

## 5. Users

### Primary user
A user who has already tried Screen Time / blockers and has learned to bypass them quickly.

### User characteristics
- understands their own avoidance patterns
- wants more structure than self-control-only apps
- values measurable evidence over vague self-report
- is willing to accept friction if it actually works

## 6. Product Requirements

## 6.1 App Blocking

### Functional requirements
- user can select blocked apps using Apple-provided picker flow
- user can select blocked categories
- user can select blocked web domains if supported by chosen architecture
- system stores selected opaque tokens, not raw app identifiers where Apple does not expose them
- system can apply and remove shields dynamically
- system supports rule tiers per target:
  - low
  - medium
  - high

### Technical implementation
Use:
- `FamilyActivityPicker` for target selection
- `ManagedSettingsStore` for shields

Core storage shape:

```swift
struct BlockedTarget: Codable, Hashable {
    enum RiskLevel: String, Codable {
        case low, medium, high
    }

    let id: UUID
    let type: TargetType
    let riskLevel: RiskLevel
    let label: String?
}

enum TargetType: Codable, Hashable {
    case application(Data)
    case category(Data)
    case webDomain(Data)
}
```

Implementation note:
Opaque tokens from Screen Time APIs should be stored in serialized form where permitted and associated with local metadata like risk level, label, and policy.

## 6.2 Shield Interception

### Functional requirements
- when a blocked target is opened, user sees a shield rather than direct access
- shield presents high-level rationale and next action
- shield routes user into Vow unlock flow
- shield can show contextual messaging based on risk tier, time of day, and relapse history

### Technical implementation
Use shield extensions and `ManagedSettings` configuration.

Required targets:
- main iOS app
- Shield Configuration extension
- Shield Action extension
- Device Activity Monitor extension

## 6.3 Unlock Request Flow

### Functional requirements
Every blocked access attempt must go through a request flow with:
- target being requested
- declared reason
- requested duration
- optional declared intent category
- current context snapshot
- friction timer
- evidence task requirement when applicable
- approval / deny / defer outcome

### Request fields
- target
- timestamp
- local time bucket
- reason text
- duration requested
- recent relapse score
- current daily score
- prior unlock count today
- AI classification result
- final decision

### Request rules
- no instant unblock for high-risk targets
- system may allow instant access only for approved safe-list utilities
- high-risk targets always require at least delay + logging
- repeated abuse increases friction automatically

### State machine

```text
blocked_attempt
  -> request_created
  -> friction_waiting
  -> evidence_required? (yes/no)
      -> evidence_pending
      -> evidence_completed
  -> ai_reviewed
  -> decision
      -> approved_temp_unlock
      -> deferred
      -> denied
  -> session_observed
  -> session_closed
  -> review_logged
```

## 6.4 Friction Engine

### Functional requirements
The app must apply time cost before access is granted.

Default policy:
- low risk: 10–30 seconds
- medium risk: 60–120 seconds
- high risk: 180–300 seconds or deny

### Dynamic modifiers
Increase friction when:
- request occurs late at night
- target has high relapse history
- today's score is low
- user already consumed entertainment budget
- recent unlock honesty is poor

Decrease friction when:
- target is utility-class and historically legitimate
- user's score is strong
- request occurs in a previously safe window

## 6.5 Evidence Tasks

### Functional requirements
Unlocks above a threshold require at least one evidence task.

Initial supported tasks:
- steps task via HealthKit
- focus timer task
- journal task with minimum text threshold

### Validation rules
#### Steps task
- user must exceed threshold delta relative to unlock-request timestamp
- threshold configurable by policy
- HealthKit authorization required

#### Focus timer task
- timer must run to completion in foreground or resilient background-supported mode
- interruption invalidates task unless policy allows pause

#### Journal task
- minimum character count
- optional minimum meaningful token count
- anti-spam heuristics to reject nonsense repetition

### Technical note
The system should never let self-report alone unlock a high-risk target.

## 6.6 Temporary Unlocks

### Functional requirements
- approved unlocks are temporary and scoped
- system tracks start time, granted duration, actual observed session time, and timeout
- target is reshielded automatically at expiry
- repeated relaunch inside active window respects granted session policy

### Policy options
- exact target only
- category-wide temporary unlock
- web-only temporary unlock

### Technical implementation
Unlock manager modifies shield set for approved token(s), persists lease, and reinstates shield on timer expiry / next app lifecycle event / extension callback.

Core model:

```swift
struct UnlockLease: Codable {
    let id: UUID
    let targetID: UUID
    let startAt: Date
    let expiresAt: Date
    let reason: String
    let requestID: UUID
}
```

## 6.7 Session Observation

### Functional requirements
For every approved unlock, track:
- requested duration
- actual usage duration
- whether the session exceeded requested limit
- whether the usage matched stated purpose if inferable
- whether session occurred in high-risk context

### Derived measures
- honesty ratio
- overrun ratio
- relapse score contribution
- target risk adjustment

### Technical implementation
Use `DeviceActivity` where appropriate for aggregate and event-driven monitoring, plus internal lease tracking and app lifecycle events.

## 6.8 Daily Score / Life Tracker

### Product definition
A single daily score representing how aligned the user's day was with meaningful behavior and controlled phone use.

### Inputs
Objective or semi-objective inputs only.

#### Objective inputs
- step count
- workout count / activity minutes if enabled
- focus session completion count
- blocked app session durations
- number of unlock requests
- late-night entertainment usage
- abstinence streaks

#### Semi-objective inputs
- journal completion
- reflection quality checks
- planned-task completion if tied to verifiable workflows later

### Initial score formula

```text
score = 50
+ movement_points
+ focus_points
+ journal_points
+ sleep_regularity_points (optional later)
- high_risk_usage_penalty
- overrun_penalty
- late_night_penalty
- repeated_request_penalty
```

Clamp to `0...100`.

### Requirements
- score recalculates incrementally during day
- score history stored daily
- score directly affects friction multipliers
- score breakdown visible to user
- score inputs must be inspectable, not opaque

## 6.9 Relapse Detection

### Functional requirements
The system detects when the user consistently misuses unlocks.

### Initial relapse signals
- repeated requests for same high-risk target
- high ratio of actual usage > requested usage
- repeated late-night access
- repeated weak justifications
- frequent deny/defer outcomes followed by more requests

### Outputs
- increased friction tier
- harder evidence tasks
- shorter allowed durations
- optional accountability escalation

## 6.10 Daily Review

### Functional requirements
At end of day or next-morning open, show:
- score
- total blocked attempts
- total approved unlocks
- total denied / deferred requests
- time spent in high-risk targets
- overrun count
- short reflection prompt

### Non-functional requirement
Review must be fast and readable in under 60 seconds.

## 6.11 Accountability Mode

### Functional requirements
- optional user-configured accountability partner
- only used for selected high-risk cases
- partner receives request summary and can approve or deny
- system supports timeout / fallback behavior

### Scope note
Not required for all unlocks. It is escalation-only.

## 6.12 AI Classification

### Role of AI
AI is not the final source of truth. It is a classifier and friction mechanism.

### Initial responsibilities
- classify request as legitimate / weak / distraction
- generate one short follow-up challenge when needed
- suggest safer alternative
- produce structured output only

### Requirements
- deterministic structured JSON output
- low latency
- no verbose chat during unlock flow
- server-side prompt versioning

### Suggested output schema

```json
{
  "classification": "weak",
  "confidence": 0.81,
  "follow_up": "What exact message or task are you opening this app for?",
  "recommended_action": "require_evidence_task"
}
```

## 7. Non-Functional Requirements

### Performance
- shield actions should feel immediate
- unlock decision path under 2 seconds excluding intentional friction timer
- score calculation under 200ms locally for current day snapshot

### Reliability
- active leases must survive app restart
- blocked set must be reconstructable on cold launch
- background extension failures should degrade safely toward stricter behavior

### Privacy
- minimize collection of sensitive data
- store opaque tokens and derived metadata rather than unnecessary raw identifiers
- all analytics opt-in if externalized
- no selling or ad-tech usage of behavior data

### Explainability
- user must be able to see why a request was denied or delayed
- score must expose contributing factors
- no black-box punishments without visible reason

## 8. Technical Architecture

## 8.1 Client

### Stack
- Swift
- SwiftUI
- Observation / Combine as needed
- App Groups for shared state across app and extensions
- HealthKit
- FamilyControls
- ManagedSettings
- DeviceActivity
- UserNotifications
- Keychain for secrets
- local persistence via SwiftData or Core Data

### Recommended choice
Use **SwiftData** if you want speed and the schema stays modest. Use **Core Data** if extension sharing becomes awkward and you need more mature control. For two-week speed, SwiftData + App Group backed storage wrapper is acceptable if validated early.

## 8.2 Extensions

Required extension targets:
- Shield Configuration Extension
- Shield Action Extension
- Device Activity Monitor Extension

Potential later extension:
- Device Activity Report Extension if richer reports are needed

## 8.3 Shared Storage

Use App Group container for:
- current block policy
- active unlock leases
- daily metrics cache
- latest score snapshot
- request queue state

Suggested shared persistence split:
- lightweight key-value: `UserDefaults(suiteName:)`
- structured durable data: SQLite / SwiftData store in App Group container

## 8.4 Backend

### Purpose
Backend is for sync, AI review, accountability routing, remote config, and future cross-device analytics.

### Recommended stack
- Supabase Postgres
- Supabase Auth or Sign in with Apple + custom backend
- Edge Functions / lightweight server for AI orchestration

### Minimal backend tables

#### users
- id
- created_at
- timezone
- settings_blob

#### unlock_requests
- id
- user_id
- created_at
- target_label
- target_type
- reason
- requested_minutes
- classification
- decision
- score_snapshot
- friction_seconds

#### unlock_sessions
- id
- request_id
- granted_at
- expires_at
- observed_minutes
- overrun_minutes

#### daily_scores
- id
- user_id
- date
- total_score
- breakdown_json

#### accountability_requests
- id
- user_id
- partner_contact
- request_id
- status
- responded_at

## 8.5 AI Service

### Input
- reason text
- target label
- time context
- today's summary metrics
- recent pattern summary

### Output
- classification
- confidence
- follow-up question
- recommended action

### Requirements
- strict schema validation
- timeout fallback to deterministic local rules
- prompt and model version persisted with decision

## 9. Data Models

```swift
struct UnlockRequestRecord: Codable, Identifiable {
    let id: UUID
    let targetID: UUID
    let targetLabel: String
    let createdAt: Date
    let reason: String
    let requestedMinutes: Int
    let localHour: Int
    let scoreSnapshot: Int
    let recentRelapseScore: Double
    let classification: RequestClassification
    let decision: RequestDecision
    let frictionSeconds: Int
}

enum RequestClassification: String, Codable {
    case legitimate
    case weak
    case distraction
    case unknown
}

enum RequestDecision: String, Codable {
    case approved
    case denied
    case deferred
}
```

```swift
struct DailyScoreRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let total: Int
    let movementPoints: Int
    let focusPoints: Int
    let journalPoints: Int
    let highRiskUsagePenalty: Int
    let overrunPenalty: Int
    let lateNightPenalty: Int
    let repeatedRequestPenalty: Int
}
```

## 10. Screens / UX Requirements

## 10.1 Onboarding
Must include:
- explanation of what the app can and cannot do on iPhone
- Screen Time / Family Controls authorization flow
- HealthKit permission prompts only when needed
- blocked target selection
- safe-list utilities selection
- initial friction policy

## 10.2 Home
Must show:
- today's score
- current blocked state summary
- today's unlock count
- last request outcome
- quick start focus timer
- journal entry CTA

## 10.3 Request Flow
Must show in sequence:
- target requested
- reason entry
- duration selection
- friction timer
- evidence task if required
- decision screen

## 10.4 Daily Review
Must show:
- score and breakdown
- usage summary
- relapse insights
- short reflection field

## 10.5 Settings
Must include:
- blocked targets
- utilities allowlist
- risk rules
- accountability settings
- data/privacy export and delete
- AI toggle if needed for fallback mode

## 11. Testing Requirements

## 11.1 Device testing
This feature set requires real-device testing. Simulator coverage is insufficient for Screen Time behaviors.

### Required test matrix
- latest iOS stable version
- at least one older supported iOS version if you support it
- app installed through Xcode on development device
- TestFlight build on same or second device

## 11.2 Functional test cases

### Blocking
- app token selected and shielded correctly
- category token selected and shielded correctly
- shield remains after relaunch
- shield reinstates after reboot / relaunch where supported

### Unlock flow
- request creation persists
- friction timer enforces wait
- evidence task completion unlocks next step
- deny and defer states behave correctly
- approved unlock expires exactly when expected

### Scoring
- steps update score correctly
- focus timer updates score correctly
- journal passes/fails heuristics correctly
- penalties apply correctly for overruns and late-night access

### Relapse logic
- repeated weak requests increase friction
- repeated overruns shorten future unlocks
- accountability escalation triggers correctly

### Failure handling
- AI timeout falls back safely
- HealthKit unavailable path still works
- extension crash does not silently grant broad access
- app restart reconstructs active leases

## 11.3 Instrumentation
Log the following internally:
- request lifecycle timestamps
- extension callback failures
- shield apply/remove success state
- lease expiry events
- score recomputation events

## 12. Shipping Requirements

### Distribution sequence
You can start development and Screen Time testing before App Store release, using registered devices and later TestFlight. Apple permits distribution on registered devices, via TestFlight, and via the App Store under the Developer Program agreement. citeturn362405view1

### Requirements before broader beta
- entitlement/capability correctly enabled for app and extensions
- provisioning profiles regenerated after entitlement changes
- privacy strings completed
- core lock/unlock flows verified on real hardware

### App Store positioning
Position as:
- digital wellbeing
- focus / intentional technology use
- behavior change / commitment device

Not as:
- jailbreak-style device control
- full parental control over arbitrary third-party users without proper framing

## 13. Open Technical Decisions

These need final answers before implementation locks in:
- SwiftData vs Core Data for App Group-backed persistence
- whether AI classification is mandatory or optional fallback-enhanced
- whether accountability review uses SMS, email, push, or shareable web link
- whether sleep regularity is included in v1 scoring
- whether web-domain blocking is v1 or app/category only
- whether daily score is fully local-first or server-synced source of truth

## 14. Recommended Initial Cut

For fastest technically sound implementation, include exactly:
- app/category blocking
- shield interception
- request flow
- friction timer
- 3 evidence tasks: steps, focus timer, journal
- temporary unlock leases
- daily score
- relapse penalties
- daily review
- lightweight AI classifier
- optional accountability escalation hook

Do not expand v1 into:
- social graph features
- complex gamification
- cross-platform clients
- full task-manager replacement
- custom launcher fantasies that iOS does not allow
