# On-Device Model Stack Stabilization Plan

## Purpose

This plan tracks stabilization work for LumiSense's on-device model stack in the dual-model architecture branch.

It is intentionally execution-focused:

1. Reduce reliability regressions in assistant and vision inference flows
2. Make model lifecycle behavior predictable and observable
3. Improve user-facing responsiveness during model load and fallback events
4. Ensure command routing and cancellation paths behave correctly under stress

## Scope Boundary

In scope:

1. On-device assistant and vision services
2. Orchestrator routing and cancellation
3. Model management and download reliability
4. Voice command intent precedence and conflict handling
5. UI loading and status feedback related to on-device execution

Out of scope:

1. Full UX redesign
2. New model families unrelated to the existing runtime
3. Major cloud provider architecture changes

## Primary Code Surface

1. [lumisense/lib/services/on_device_assistant_service.dart](lumisense/lib/services/on_device_assistant_service.dart)
2. [lumisense/lib/services/on_device_vision_service.dart](lumisense/lib/services/on_device_vision_service.dart)
3. [lumisense/lib/services/on_device_orchestrator.dart](lumisense/lib/services/on_device_orchestrator.dart)
4. [lumisense/lib/services/model_manager.dart](lumisense/lib/services/model_manager.dart)
5. [lumisense/lib/services/stt_service.dart](lumisense/lib/services/stt_service.dart)
6. [lumisense/lib/screens/camera_screen.dart](lumisense/lib/screens/camera_screen.dart)
7. [lumisense/lib/screens/settings_screen.dart](lumisense/lib/screens/settings_screen.dart)

## Delivery Phases

## Phase 1: Correctness and Safety

Objective: fix logic paths that can silently fail or produce incorrect actions.

- [ ] Implement tool-call aware assistant flow in [lumisense/lib/services/on_device_assistant_service.dart](lumisense/lib/services/on_device_assistant_service.dart)
Acceptance criteria:
1. Tool call deltas are accumulated from stream events
2. Handlers are invoked for resolved tool definitions
3. Tool results are added back into model context before final response
4. Final response parsing returns deterministic action markers

- [ ] Add single-flight model loading in assistant and vision services
Acceptance criteria:
1. Concurrent load requests do not create duplicate engine instances
2. Callers await a shared in-flight load future
3. Load future is safely reset after success or failure

- [ ] Harden dispose and unload behavior in orchestrator path
Acceptance criteria:
1. Unload operations are awaited before teardown completes
2. Native resources are not left in fire-and-forget cleanup paths

## Phase 2: User Experience During On-Device Transitions

Objective: eliminate invisible waiting and confusing state transitions.

- [ ] Add model-loading status feedback in camera action flows
Acceptance criteria:
1. On-device first-hit load announces status to user
2. Status message is visible and spoken when load delay is expected
3. Post-load state returns to normal interaction state

- [ ] Remove settings source-of-truth drift around on-device toggle
Acceptance criteria:
1. Toggle state is controlled by a single authoritative settings path
2. Model manager no longer acts as a shadow settings store
3. Toggle updates are awaited where needed to prevent stale reads

- [ ] Replace rebuild-sensitive model readiness checks in settings screen
Acceptance criteria:
1. Model readiness state is cached and refreshed explicitly
2. UI does not flicker due to repeated future recreation

## Phase 3: Download and Runtime Robustness

Objective: make model acquisition and inference lifecycle robust under real mobile constraints.

- [ ] Implement resumable model downloads in [lumisense/lib/services/model_manager.dart](lumisense/lib/services/model_manager.dart)
Acceptance criteria:
1. Partial file continuation via HTTP range requests
2. Append-mode write path for valid resume scenarios
3. Graceful reset on invalid range responses
4. User-facing insufficient-space failure signaling

- [ ] Add cancellation support across on-device inference flows
Acceptance criteria:
1. Assistant and vision services expose cancellation hooks
2. Orchestrator can cancel all in-flight inference operations
3. Camera lifecycle calls cancellation during teardown/navigation changes

## Phase 4: Voice Command Reliability

Objective: reduce false intent matches and improve command predictability.

- [ ] Reorder and tighten command matching in [lumisense/lib/services/stt_service.dart](lumisense/lib/services/stt_service.dart)
Acceptance criteria:
1. Specific commands are evaluated before broad/ambiguous patterns
2. SOS/emergency precedence is safe and deterministic
3. Scan intent and read intent conflicts are minimized

## Verification Checklist

Use this checklist after each completed phase.

- [ ] Static verification: run `flutter analyze` in [lumisense](lumisense)
- [ ] Unit tests: run `flutter test` in [lumisense](lumisense)
- [ ] Focused voice tests: run `flutter test test/stt_service_test.dart` in [lumisense](lumisense)
- [ ] Manual camera flow check:
1. First on-device describe flow gives clear loading feedback
2. Subsequent requests avoid repeated warmup speech unless necessary
3. Navigation away during inference does not leave lingering CPU load

Note: APK builds are optional for this plan and should only run when explicitly requested.

## Risk Register

1. Concurrent stream and cancellation interactions may introduce race bugs if not serialized carefully.
2. Tool-call streaming format changes in dependency updates can break parser assumptions.
3. Mid-download interruption behavior can vary across Android versions and storage backends.
4. Voice intent regressions are easy to reintroduce without explicit precedence tests.

## Change Management Rules

1. Keep each fix scoped and reviewable.
2. Add or update tests whenever behavior changes are deterministic enough to assert.
3. Document behavior changes in [lumisense/FEATURES.md](lumisense/FEATURES.md) or [lumisense/ARCHITECTURE.md](lumisense/ARCHITECTURE.md) when user-visible behavior shifts.
4. Avoid introducing new settings keys if existing provider state can represent the same intent.

## Definition of Done

This plan is complete when all phase checkboxes are done and the following hold:

1. Assistant tool-calling and follow-up response flow is stable in manual and test scenarios.
2. No duplicate model engine initialization under concurrent load requests.
3. User receives explicit feedback during model warmup and fallback transitions.
4. Download interruption and resume behavior works reliably on-device.
5. Voice command conflicts covered in tests no longer produce known false matches.
