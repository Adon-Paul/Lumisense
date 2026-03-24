# LumiSense Future Context

## Purpose

This file captures where LumiSense should evolve next.

It is not the baseline implementation document. For current shipped behavior, use:

1. [lumisense/README.md](lumisense/README.md)
2. [lumisense/FEATURES.md](lumisense/FEATURES.md)
3. [lumisense/ARCHITECTURE.md](lumisense/ARCHITECTURE.md)
4. [lumisense/PROJECT_SPEC.md](lumisense/PROJECT_SPEC.md)
5. [lumisense/SETUP.md](lumisense/SETUP.md)

## Current Baseline Snapshot

LumiSense already includes:

1. Camera-first assistive interaction flow
2. OCR, object detection, and scene description pipelines
3. Voice command routing and spoken feedback
4. SOS and safety-oriented utility flows
5. On-device plus cloud hybrid inference paths
6. Settings, history, and caregiver-facing surfaces

Future work should build on this baseline, not re-plan it from zero.

## Product Direction (Next 2 Iterations)

## Iteration A: Reliability and Trust Layer

Goal: make existing features more dependable in noisy, real-world conditions.

Priority outcomes:

1. Fewer false or repeated announcements in navigation mode
2. Better command recognition under accent/noise variability
3. More graceful degradation when a model/provider is unavailable
4. Stronger user confidence via explicit spoken status states

Expected technical workstreams:

1. Navigation persistence and confidence scoring refinements in [lumisense/lib/services/navigation_mode_controller.dart](lumisense/lib/services/navigation_mode_controller.dart)
2. Command precedence and phrase disambiguation improvements in [lumisense/lib/services/stt_service.dart](lumisense/lib/services/stt_service.dart)
3. Unified fallback response contract in [lumisense/lib/services/gemini_service.dart](lumisense/lib/services/gemini_service.dart) and [lumisense/lib/services/on_device_orchestrator.dart](lumisense/lib/services/on_device_orchestrator.dart)
4. More explicit voice UX states in [lumisense/lib/screens/camera_screen.dart](lumisense/lib/screens/camera_screen.dart)

## Iteration B: Mobility and Context Intelligence

Goal: improve real-world usefulness while walking and completing daily tasks.

Priority outcomes:

1. Higher quality route guidance with better step progression
2. Context-aware prompts around hazards and navigation decisions
3. Faster user handoff between read, describe, navigate, and SOS modes
4. Better destination and intent extraction from natural speech

Expected technical workstreams:

1. Route recalc and tracking improvements in [lumisense/lib/services/directions_service.dart](lumisense/lib/services/directions_service.dart)
2. Map and speech sync hardening in [lumisense/lib/screens/route_map_screen.dart](lumisense/lib/screens/route_map_screen.dart)
3. Cross-feature action routing policy in [lumisense/lib/screens/camera_screen.dart](lumisense/lib/screens/camera_screen.dart)
4. Context prompt shaping in [lumisense/lib/services/on_device_assistant_service.dart](lumisense/lib/services/on_device_assistant_service.dart)

## Technical Strategy Bets

## 1. Local-first critical path

For key safety interactions, keep a local-first path where feasible.

Implications:

1. Prefer on-device response for immediate guidance
2. Use cloud as augmentation, not hard dependency
3. Keep provider fallback chain stable and observable

## 2. Deterministic orchestration over raw model output

Model output should pass through deterministic post-processing before user speech.

Implications:

1. Confidence thresholds and cooldown logic remain policy-driven
2. Ambiguous outputs should trigger clarification prompts
3. User-facing phrasing should be concise and consistent

## 3. Instrumentation before expansion

Add telemetry-quality local logs and debug counters before adding new large features.

Implications:

1. Measure false positives/negatives in navigation speech
2. Track command misfires and retries
3. Track cloud fallback frequency and failure categories

## Candidate Enhancements (Not Yet Committed)

These are options, not promises.

1. Offline "quick mode" with reduced model set for low-end devices
2. Personalized command vocabulary per user profile
3. Context memory for short multi-turn spoken interactions
4. Assisted route confidence scoring from multi-signal fusion
5. Expanded language support beyond current defaults

## Research Backlog

## High-value questions

1. Which speech command conflicts happen most often in the field?
2. What confidence threshold best balances missed detections vs noise?
3. Which tasks gain most from on-device multimodal inference?
4. What spoken response structure is fastest for users to act on?

## Evaluation plan outline

1. Build a repeatable scenario matrix (indoor, street, low light, noise)
2. Record outcome quality and response latency per feature
3. Compare on-device path vs cloud path for each scenario
4. Feed findings into threshold and prompt updates

## Engineering Guardrails

1. Keep accessibility-first interaction as non-negotiable
2. Do not introduce dependencies that break Android-first demo reliability
3. Do not regress existing user flows while adding future features
4. Keep docs synchronized when behavior changes

## Risks to Watch

1. Model size and memory pressure on mid-range devices
2. Speech recognition variance across accents/environments
3. API dependency churn and quota limits for cloud providers
4. Documentation drift as features evolve rapidly

## Future Milestone Definition of Done

A future milestone is complete only when all of the following are true:

1. Feature behavior is stable in at least 3 scenario classes
2. Speech UX is deterministic and understandable under normal noise
3. Failure mode behavior is explicit, spoken, and recoverable
4. Documentation updates are merged in the same change window
5. Tests are added or updated where practical for changed logic

## How to Use This File

Use this file to decide what to build next.

Use implementation docs to understand what already exists.

If this file conflicts with code behavior, code and implementation docs win; then update this file to reflect the new forward plan.

