# MIM Assist TOD Stewardship Architecture Map

Date: 2026-04-16
Primary target: `E:/mim_wall`
Primary owner surface: TOD stewardship lane for MIM Assist

## Purpose

This document defines the current TOD stewardship model for MIM Assist so TOD can act as the default engineering executor for the Android app and its integration surfaces without treating the repo like an unknown codebase on every task.

It is grounded in the current MIM Assist repository shape, the project registry entry in `tod/config/project-registry.json`, and the active validation gates already codified in the repo.

## Architecture Summary

MIM Assist is a device-first Android app written in Kotlin with a single application module and a Compose-driven operator shell.

The runtime is split into six practical layers.

### UI and Operator Shell

- Primary entry point: `app/src/main/java/com/dave/callguardian/MainActivity.kt`
- Compose UI owns dashboard, configuration, communicator, operations, queue visibility, provider settings, and workstation controls.
- Current risk: `MainActivity.kt` is a large orchestration surface and acts as both UI composition root and a high-level coordination layer.

### Telephony and Live-Call Runtime

- Primary entry points: `GuardianCallScreeningService.kt`, `MimInCallService.kt`, `LiveCallSessionManager.kt`, `LiveCallAudioSessionController.kt`, `LiveCallSpeechController.kt`, `LiveCallTurnCaptureController.kt`, `LiveCallTurnCoordinator.kt`
- This layer handles inbound call screening, active-call transitions, audio lifecycle, speech-turn capture, and the live call loop.
- Current risk: Android telephony role state, audio lifecycle churn, and interruption timing can break runtime behavior without obvious compile-time signals.

### Messaging and Dialog Orchestration

- Primary files: `TextMessageManager.kt`, `IncomingSmsReceiver.kt`, `MimAiOrchestrator.kt`, `MimConversationEngine.kt`, `CallerInteractionPolicyEngine.kt`
- This layer owns SMS intake, suppression, solicitation handling, owner action routing, handoff creation, and fallback conversational behavior.
- Current risk: policy, classification, queue state, and owner-action behavior are tightly coupled across messaging and session state.

### Domain Policy and Persisted App State

- Primary files: `CallDecisionEngine.kt`, `ScreeningRulesStore.kt`, `ScreeningBehaviorStore.kt`, `AssistantPolicyStore.kt`, `DeviceActionGuardrailStore.kt`, `LiveCallRolloutStore.kt`, `MimMasterControlStore.kt`, `MessageTemplateStore.kt`, `SpamLearningStore.kt`, `SpamWatchListRepository.kt`, `CallSessionStore.kt`
- This layer contains preferences, guardrails, rollout gates, spam learning, queue persistence, and owner-control state.
- Current risk: state is intentionally distributed across multiple local stores, which improves modularity but raises drift risk across runtime, UI, and automation paths.

### Voice and Provider Abstraction

- Primary files: `VoiceAgentFactory.kt`, `AiVoiceAgent.kt`, `LocalRuleBasedVoiceAgent.kt`, `RemoteVoiceProviders.kt`, `OpenAiProviders.kt`, `ProviderConnectivityTester.kt`, `VoiceSettingsStore.kt`
- This layer decides whether MIM Assist runs locally, against MIM endpoints, or against OpenAI-backed provider paths.
- Current risk: provider mode, endpoint configuration, and network availability directly affect runtime quality and can degrade both live-call and text behavior.

### TOD and Workstation Bridge Surfaces

- Primary files: `MimWallStateAdapterSnapshotBuilder.kt`, `MimWorkstationPlaceholderClient.kt`, `MimWorkstationStore.kt`
- Supporting TOD integration docs: `docs/mim-wall-state-adapter-v1.md`, `docs/mim-wall-development-status-2026-04-13.md`
- This layer exports app state into a read-only adapter snapshot so TOD and the wider MIM ecosystem can consume queue, timeline, and feedback state without direct Android-side mutation.
- Current risk: snapshot freshness can lag behind live device behavior, which makes stale-state diagnosis and orchestration sensitive to timestamp quality.

## Major Code Areas

### Frontend Entry Points

- `app/src/main/java/com/dave/callguardian/MainActivity.kt`
- `app/src/main/java/com/dave/callguardian/ui/theme/Theme.kt`
- `app/src/main/AndroidManifest.xml`

### Runtime and Device Entry Points

- `app/src/main/java/com/dave/callguardian/callscreening/GuardianCallScreeningService.kt`
- `app/src/main/java/com/dave/callguardian/callscreening/MimInCallService.kt`
- `app/src/main/java/com/dave/callguardian/messaging/IncomingSmsReceiver.kt`
- `app/src/main/java/com/dave/callguardian/testing/AutomationSimulationReceiver.kt`

### Remote Route and Provider Surfaces

- MIM provider mode via `VoiceAgentFactory.kt`
- OpenAI provider mode via `OpenAiProviders.kt`
- Workstation sync placeholder via `MimWorkstationPlaceholderClient.kt`

### Runtime and State Modules

- `app/src/main/java/com/dave/callguardian/domain/*`
- `app/src/main/java/com/dave/callguardian/session/*`
- `app/src/main/java/com/dave/callguardian/workstation/MimWorkstationStore.kt`

### Initiative and Autonomy Modules

- `CallDecisionEngine.kt`
- `MultiChannelHandoffPlanner.kt`
- `CallerInteractionPolicyEngine.kt`
- `MimAiOrchestrator.kt`
- `MimConversationEngine.kt`
- `TextMessageManager.kt`

### Media, Image, and Voice Modules

- `LiveCallAudioSessionController.kt`
- `LiveCallSpeechController.kt`
- `LiveCallTurnCaptureController.kt`
- `LiveCallTurnCoordinator.kt`
- `app/src/main/java/com/dave/callguardian/voice/*`

### Shared-State and TOD Bridge Modules

- `MimWallStateAdapterSnapshotBuilder.kt`
- `MimWorkstationPlaceholderClient.kt`
- `MimWorkstationStore.kt`
- `scripts/automated_dialog_regression.ps1`
- `scripts/device_smoke_test.ps1`

### Health and Recovery Modules

- `MimMasterControlStore.kt`
- `LiveCallRolloutStore.kt`
- `ProviderConnectivityTester.kt`
- `scripts/device_smoke_test.ps1`
- `scripts/verify_busy_intercept.ps1`
- `scripts/automated_dialog_regression.ps1`

## Key Dependencies

### Platform and Build

- Android application plugin `8.5.2`
- Kotlin Android plugin `1.9.24`
- `compileSdk 34`, `targetSdk 34`, `minSdk 29`
- Java and Kotlin runtime target `17`

### UI and Runtime

- Jetpack Compose
- Material3
- Lifecycle runtime and viewmodel compose
- Coroutines Android

### Networking and Serialization

- OkHttp `4.12.0`
- Kotlin serialization JSON `1.7.3`

### Device and Runtime Reliance

- Telephony features and Android roles
- SMS receive, read, and send permissions
- Record audio permission
- Local or remote TTS, STT, and LLM providers
- ADB-driven smoke and regression scripts for publish validation

## Risky Coupling Points

- `MainActivity.kt` is both shell UI and operational orchestration surface. A single change can affect configuration, communicator UX, queue controls, workstation sync, and validation affordances.
- `TextMessageManager.kt` is the core behavior hub. It blends policy, spam heuristics, owner handoff logic, queue updates, follow-up scheduling, and provider-assisted dialog.
- Telephony and live-call classes depend on Android runtime roles. Behavior can regress from role or permission drift even when the Kotlin build stays green.
- Multiple local stores define the runtime truth. Rules, guardrails, rollout, templates, spam learning, master control, and session state are intentionally separated and require coordinated updates.
- Provider mode changes alter both runtime behavior and failure posture. Switching between `local`, `mim`, and `openai` changes latency, failure modes, and confidence surfaces.
- TOD and MIM bridge visibility depends on exported snapshot freshness. The snapshot builder is safe by design, but stale adapter output can mislead downstream orchestration.

## Known Stale-State Failure Zones

- Capability drift. Dialer role, call-screening role, SMS role, or permissions can silently invalidate runtime assumptions.
- Live-call state churn. Audio session, speech capture, and in-call service behavior are sensitive to interrupt, hold, and disconnect timing.
- Queue vs thread state divergence. Queue entries, timeline state, and owner handoff status can drift if message policy or cleanup logic changes without coordinated validation.
- Provider-mode mismatch. UI configuration may imply one mode while the effective runtime is operating with local fallback or degraded remote behavior.
- Snapshot lag. `mim_wall_state_adapter_v1` export is safe and read-only, but stale exports can produce false conclusions for TOD or MIM orchestration.

## TOD Stewardship Boundaries

### Safe Edit Zones

- `README.md`
- `MIM_ASSIST_SPEC.md`
- `DEVELOPMENT_PLAN.md`
- `SPRINT_1_PLAN.md`
- `scripts/*.ps1`
- `app/src/main/java/com/dave/callguardian/ui/theme/*`

### Guarded Edit Zones

- `app/src/main/java/com/dave/callguardian/MainActivity.kt`
- `app/src/main/java/com/dave/callguardian/messaging/*`
- `app/src/main/java/com/dave/callguardian/callscreening/*`
- `app/src/main/java/com/dave/callguardian/voice/*`
- `app/src/main/java/com/dave/callguardian/session/*`
- `app/src/main/java/com/dave/callguardian/domain/*`

### Validation-Required Zones

- Any file under `app/src/main/`
- `app/build.gradle.kts`
- `AndroidManifest.xml`
- Any automation or publish script under `scripts/`

### Operator-Approval Zones

- Permission or role model changes in `AndroidManifest.xml`
- Build system or SDK target changes
- Behavior that changes spam opt-out, sensitive action policy, or owner-routing rules
- Changes that alter remote provider auth or route semantics

## Runtime Health Checklist

Minimum recurring stewardship checks for MIM Assist:

- Repo and build presence: `gradlew.bat`, `app/build.gradle.kts`, and `AndroidManifest.xml` present.
- Operator shell presence: `MainActivity.kt` present and buildable, with theme resources present.
- Runtime component presence: call screening service, in-call service, SMS receiver, and automation simulation receiver declared.
- Voice and provider readiness: provider factory, provider connectivity tester, and settings store present.
- Stewardship bridge readiness: workstation snapshot builder, workstation store, and regression scripts present.
- Validation gate: `./gradlew.bat assembleDebug`, `./gradlew.bat lintDebug`, and `powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/automated_dialog_regression.ps1 -Iterations 1`.

## Recovery Playbook

- Soft restart path: force-stop the app via ADB, relaunch `MainActivity`, then re-run device smoke and capability preflight.
- Stale-state clear path: rebuild and reinstall the debug APK, re-run automated dialog regression with artifact output, and compare fresh output to the prior scenario summary.
- Shell-state refresh path: relaunch the app, re-check dashboard capability state, and confirm queue, timeline, and communicator surfaces load.
- Deployment freshness verification: confirm current git head against `TOD.md`, re-run the build gate, and re-run regression artifact generation.

## Validated Runtime Status

- Full TOD-driven health pass executed on 2026-04-16 with build, lint, device smoke, and automated dialog regression enabled.
- `assembleDebug` passed.
- `lintDebug` passed.
- Device-bound validation did not hang; it now fails closed with an explicit blocker when ADB has no connected device.
- Current runtime blocker: no connected Android device was present, so device smoke and automated dialog regression could not execute end-to-end.
- Evidence artifact: `tod/out/stewardship/mim_assist/health/mim-assist-health-check.latest.json` and matching markdown report.

## Prioritized MIM Engineering Backlog

### Stale-State Prevention

- Break `MainActivity.kt` into smaller shell modules with explicit state owners.
- Add a machine-readable capability drift artifact so role and permission loss is visible outside the app UI.
- Export snapshot freshness and queue age metadata directly into the workstation adapter payload.

### Execution Continuity

- Harden live-call interruption and resume state transitions around `LiveCallSpeechController.kt` and `LiveCallTurnCoordinator.kt`.
- Add explicit session consistency checks between queue state and handoff state.

### UI Formatting and Render Stability

- Split communicator, dashboard, and operations cards into focused Compose components.
- Add screenshot or semantic UI assertions for communicator mode and action queue counts.

### Multimodal and Image Support

- Add explicit surface mapping for future image and document context if MIM Assist expands beyond current telephony-first flows.
- Keep workstation snapshot contract ready for richer media metadata without direct mutation.

### Voice Usability

- Add a dedicated voice failure and status summary card instead of burying state inside the main shell.
- Make provider degradation and fallback mode visible in one deterministic operator indicator.

### Shell and Shared Truth Integration

- Tighten the bridge from `MimWallStateAdapterSnapshotBuilder.kt` into TOD-side stewardship artifacts.
- Add a repeated export freshness check and stale-warning threshold.

### Recovery and Resume Behavior

- Add a scripted device restart and recovery path that chains smoke, capability preflight, and regression.
- Add a publish-blocking signal when live-call capability is missing but rollout state still appears enabled.
- Keep runtime validation fail-closed when ADB has no connected device so stewardship gates return a clear blocker instead of hanging.
- Connect a validation device and rerun smoke plus automated dialog regression to produce the first full runtime evidence pack.

## Recommended First Bounded Multi-File Slice

Target slice: capability and runtime drift visibility.

Touch points:

- Runtime: add a compact device and runtime capability export in app code.
- UI: add one operator-visible health card in the dashboard.
- Validation: extend `automated_dialog_regression.ps1` or a companion health script to assert the artifact is present.

Why this slice first:

- It improves TOD stewardship immediately.
- It reduces operator debugging.
- It creates a cleaner handoff path for later execution automation.

## Stewardship Outcome

TOD can now treat MIM Assist as a managed engineering target with:

- A stable architecture summary.
- Explicit stewardship boundaries.
- A current runtime health checklist.
- A prioritized backlog for future bounded work.

The remaining gap is not understanding the app. The remaining gap is continuing to operationalize that understanding into repeatable validation and smaller execution slices.
