# Vow

Vow is an iOS-native digital wellbeing app that uses Apple's Screen Time stack to convert blocked app access into a deliberate, logged, temporary, evidence-gated unlock flow.

This repo currently contains the **v1 SwiftPM scaffold**:
- **VowCore**: data models + request/friction/session state machine + scoring/evidence interfaces
- **VowUI**: SwiftUI placeholders for the shield + unlock request flow (no real Screen Time/ManagedSettings wiring yet)

## Repo layout
- `vow_prd.md`: Technical PRD (unchanged)
- `Package.swift`: SwiftPM manifest
- `Sources/VowCore/*`: core logic
- `Sources/VowUI/*`: UI placeholders

## Next wiring steps (to reach PRD “real” behavior)
1. Replace placeholders with Screen Time integrations:
   - FamilyControls / ManagedSettings for blocking + shields
   - DeviceActivity for session observation
2. Persist/restore:
   - blocked policy (selected targets)
   - active unlock leases + expiry
   - daily score inputs and history
3. Connect evidence tasks:
   - Steps / focus timer / journal completion signals
4. Add AI classification:
   - structured JSON output + timeout fallback

## Build (from any SwiftPM-capable environment)
```bash
swift build
```

