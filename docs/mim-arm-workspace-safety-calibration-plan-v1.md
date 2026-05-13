# MIM Arm Workspace Safety And Calibration Plan V1

## Purpose

Improve the MIM workspace app at `/workspace` so it becomes a reliable safety, calibration, simulation, and training environment for the real MIM arm.

The first priority is not visual polish. The first priority is making sure the workspace model can prevent unsafe arm motion, especially shoulder motion that can drive into the table edge or mechanical limits.

## Current Baseline

Workspace app surface:

- Page: `GET /workspace`
- UI: `workspace.html`
- Frontend logic: `workspace_setup.js`
- Backend/API routes: `routes.py`
- Servo limits: `servo_config.json`
- Flask registration: `app.py`

Known useful routes:

- `GET /workspace_setup_state`
- `POST /workspace_setup_state`
- `GET /workspace_map.json`
- `GET /workspace_model_info`
- `GET /workspace_model_asset/<filename>`
- `POST /move`
- `GET /arm_state`
- `GET /servo_config`
- `POST /save_servo_config`
- `POST /servo_recovery`

Known current issue:

- All servos are working except shoulder.
- Shoulder can move too far forward, hit or lock against the table edge, and then stop responding.
- Current workspace needs better recovery, calibration, limit setup, and sim-to-real alignment before training use.

## Safety Boundary

No autonomous arm motion should be added in this phase.

All real arm movement must be:

- explicitly operator initiated
- limit checked
- recoverable
- visible in simulation before apply
- blocked when outside safe range or forbidden workspace zones

Simulation improvements may run freely, but real servo commands must remain gated.

## Development Phases

### Phase 1: Servo Safety And Recovery

Goal:

Prevent unsafe shoulder movement and make recovery simple.

Tasks:

- Add clear shoulder recovery control.
- Add disable/enable shoulder control.
- Enforce per-servo min/max limits before `/move`.
- Show command clamping in the UI.
- Add safe neutral pose and recovery pose.
- Add visible warning when a requested movement is blocked.
- Add "recover all servos" flow using configured safe positions.

Acceptance:

- Shoulder cannot be commanded outside configured safe range.
- Unsafe command reports exact blocked reason.
- Recovery moves to configured safe pose.
- UI shows current limits and recovery state.
- No automatic arm motion is introduced.

### Phase 2: Calibration Wizard

Goal:

Make sim and real arm alignment explicit and repeatable.

Tasks:

- Create guided setup flow:
  - set neutral pose
  - verify servo direction
  - jog each servo in small increments
  - record min/max safe angle
  - record safe pose
  - mark table edge and forbidden zones
- Save calibration to a durable profile.

Suggested artifact:

`workspace_calibration_profile.json`

Fields:

- calibration_id
- created_at
- arm_origin
- scale_factor
- servo_direction
- servo_min
- servo_max
- safe_pose
- forbidden_zones
- table_bounds
- notes

Acceptance:

- Calibration survives refresh/reload.
- Operator can tune one servo at a time.
- UI shows sim pose and real pose side by side.
- Shoulder safe range can be tuned without editing files manually.

### Phase 3: Fine Movement And Simulation Preview

Goal:

Make small adjustments easy and reduce jumpy control behavior.

Tasks:

- Add fine/coarse step size.
- Add press-and-hold repeat rate control.
- Add numeric angle inputs.
- Add ghost preview before real movement.
- Add "apply preview to real arm" button.
- Add undo last preview.
- Smooth model animation with damped interpolation.

Acceptance:

- Small adjustments are predictable.
- Preview movement does not move the real arm.
- Real movement only happens after explicit apply.
- Model movement is smooth enough for fine alignment.

### Phase 4: Workspace Barriers And Object Layout

Goal:

Represent the real workspace as a useful collision/safety map.

Tasks:

- Add solid object tools:
  - box
  - cylinder
  - wall/barrier
  - table edge
- Allow drag, rotate, scale, and delete.
- Allow marking objects:
  - solid
  - forbidden
  - movable
  - target
  - training object
- Persist objects into workspace setup state.

Acceptance:

- Operator can draw table and wall constraints.
- Unsafe arm paths into forbidden zones are blocked or warned.
- Workspace layout persists across reloads.

### Phase 5: Real Object Import And Household Object Library

Goal:

Support simulation/training with real-world objects.

Tasks:

- Add object library panel.
- Add common household object presets:
  - block
  - cup
  - bottle
  - small box
  - tool
  - plate
- Add create custom object flow.
- Later: import OBJ/GLB.

Acceptance:

- Operator can place a block/cup/box on table in simulation.
- Objects have dimensions and collision type.
- Objects are saved and reload correctly.

### Phase 6: Camera Detection To Workspace Placement

Goal:

Allow MIM to update the workspace model from visual observations.

Tasks:

- Accept detected object proposals from camera pipeline.
- Display proposed object with confidence.
- Let operator confirm, adjust, or reject placement.
- Record source evidence.

Acceptance:

- MIM can propose "block detected on table".
- UI places a tentative object.
- Operator can confirm before it becomes authoritative.
- Workspace state records detection source and confidence.

### Phase 7: Real-To-Sim Movement Verification

Goal:

Compare commanded pose, simulated pose, and real arm state.

Tasks:

- Show commanded pose.
- Show latest physical `/arm_state`.
- Show delta/error.
- Flag mismatch.
- Require recovery/recalibration if mismatch exceeds threshold.

Acceptance:

- UI shows whether sim and real arm agree.
- Failed or stale real arm state is visible.
- MIM does not trust simulation alone when physical feedback disagrees.

## First Executable Objective

`MIM-ARM-WORKSPACE-SAFETY-CALIBRATION-V1`

Goal:

Add a safety-first calibration and recovery layer to the workspace app, focused on shoulder protection and explicit servo limits.

Target surfaces:

- `routes.py`
- `workspace.html`
- `workspace_setup.js`
- `servo_config.json`

Required outputs:

- shoulder-safe recovery flow
- per-servo safe limit enforcement
- sim-only preview before real movement
- calibration profile draft
- visible blocked reason for unsafe movement
- validation evidence

Acceptance:

- Shoulder cannot move beyond configured safe range.
- Real movement is gated by limits.
- Recovery can return shoulder/all servos to safe pose.
- Calibration values persist.
- UI can preview movement without moving physical hardware.
- No autonomous arm motion is enabled.

## Suggested Validation Strategy

Validation should run in this order:

1. Static validation:
   - routes load
   - JSON config loads
   - save/load calibration artifact works

2. Simulation-only validation:
   - preview movement works
   - out-of-range shoulder movement is blocked
   - forbidden zone warning appears

3. Dry-run real command validation:
   - `/move` request is clamped or rejected before hardware call
   - blocked reason is returned

4. Operator-supervised physical validation:
   - shoulder safe pose recovery
   - small jog only
   - confirm direction and limit behavior

## What Not To Work On Yet

Do not start with:

- autonomous object manipulation
- automatic camera-to-object placement as authoritative truth
- broad 3D import support
- path planning
- unrestricted MIM-initiated arm movement
- training loops that move the real arm

These depend on the safety envelope, calibration profile, and sim-to-real verification being trustworthy first.

## Next Recommended Step

Start `MIM-ARM-WORKSPACE-SAFETY-CALIBRATION-V1`.

Implement Phase 1 and a minimal Phase 2 calibration profile skeleton before adding more object/simulation features.

