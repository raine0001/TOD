# MIM Arm Workspace Project Roadmap V1

## Purpose

Build the MIM workspace at `http://192.168.1.90:5000/workspace` into a reliable safety, calibration, simulation, and training environment for the real MIM arm.

The workspace should let the operator align the simulated MIM arm to the real arm, safely preview movement, manage servo limits, add real-world objects and barriers, and eventually let MIM build a living 3D model of its environment from perception.

## Current Live Baseline

Live endpoint checks on `http://192.168.1.90:5000`:

- `GET /workspace`: reachable, returns the workspace HTML page.
- `GET /workspace_setup_state`: reachable, returns saved geometry/settings.
- `GET /workspace_map.json`: reachable, returns persisted workspace map data.
- `GET /workspace_model_info`: reachable, reports OBJ/MTL model discovery.
- `GET /servo_config`: reachable, returns servo limit configuration.
- `GET /arm_state`: reachable, returns arm/app state.

Observed live UI/runtime capabilities:

- Three.js scene is present.
- OrbitControls are loaded.
- OBJLoader and MTLLoader are loaded.
- Bundled model paths reference `MIM_full_build.obj` and `MIM_full_build.mtl`.
- Desktop model discovery exists through `/workspace_model_info`.
- Servo limit editor exists.
- Servo recovery controls exist.
- Live sync controls exist.
- Obstacle box and wall drawing tools exist.
- `/move`, `/servo_config`, `/save_servo_config`, `/servo_recovery`, and `/arm_state` are referenced by the frontend.

Important reconciliation note:

- The legacy Flask-style mirror includes `tmp_remote_mim/routes.py` with `/workspace`, `/move`, `/servo_config`, `/servo_recovery`, and model routes.
- The newer MIM router mirror includes `tmp_remote_mim/core/routers/workspace.py`, which is much larger and handles workspace planning, proposals, action plans, safety gates, object memory, and execution policy.
- Before deploying the next live patch, MIM/TOD must identify the exact files serving the live `192.168.1.90:5000/workspace` app so work is applied to the right surface.

## Operator Requirements

1. The 3D view should stay in frame while controls scroll.
2. Mouse wheel should zoom in and out.
3. Left mouse button should navigate/rotate the view.
4. Reset view should center the MIM arm on screen.
5. MIM ARM should use the same real OBJ/MTL build files:
   - `MIM_full_build.obj`
   - `MIM_full_build.mtl`
6. The user should be able to position the simulated arm to match the real arm, apply sync, and fine tune alignment.
7. Once in sync, real MIM arm movements by the user or MIM should be reflected in the simulation model.
8. Sync mode should be toggleable for direct simulation testing and runs.
9. The workspace should include a common object library. Users should be able to size and drop 3D objects into the simulation.
10. Objects placed in the real arm environment should be reflected in the simulation space after detection and confirmation.
11. Object movement limits should be configurable, including too far forward/backward and turns or reaches that might hit fixed objects or knock objects over.
12. Users should be able to add boxes, circles, walls, and work areas into the 3D space and label them as solid, forbidden, or focus/work zones.
13. Future goal: MIM should build its own 3D room/workspace map automatically, likely requiring additional sensors or camera improvements.

## Safety Boundary

No autonomous real arm movement is enabled by this roadmap.

All real hardware movement must remain:

- operator initiated
- limit checked
- recoverable
- previewable in simulation first
- blocked or warned when outside safe range, near a table edge, or near a forbidden/solid zone

Dry-run and simulation-only validation should be preferred until the safety envelope is proven.

## Phase 0: Active Surface Reconciliation

Objective:

`MIM-ARM-WORKSPACE-ACTIVE-SURFACE-RECONCILIATION-V1`

Goal:

Identify the actual live files and routes serving `http://192.168.1.90:5000/workspace` before patching UI or movement behavior.

Tasks:

- Identify the live backend file serving `GET /workspace`.
- Identify the live frontend JS file serving `/static/workspace_setup.js`.
- Identify the live `/move` implementation.
- Identify the live `/servo_config`, `/save_servo_config`, `/servo_recovery`, and `/arm_state` implementations.
- Compare live app behavior with local mirrors.
- Report exact deployment target and restart procedure.

Acceptance:

- Exact live backend target is known.
- Exact live frontend target is known.
- Exact live servo movement target is known.
- No servo movement is performed.
- Next patch target is unambiguous.

## Phase 1: Viewport And Navigation

Objective:

`MIM-ARM-WORKSPACE-VIEWPORT-CONTROLS-V1`

Goal:

Make the workspace usable before deeper safety tuning.

Tasks:

- Keep 3D viewport fixed/sticky while the controls panel scrolls.
- Confirm mouse wheel zoom.
- Confirm left mouse drag rotates/navigates.
- Ensure reset view centers the MIM arm, not only the table.
- Add visible sync/view status.
- Validate across browser reload.

Acceptance:

- 3D view stays in frame.
- Controls scroll independently.
- Wheel zoom works.
- Left drag rotates or navigates consistently.
- Reset view centers the arm.
- No real servo command is sent.

## Phase 2: Servo Safety And Recovery

Objective:

`MIM-ARM-WORKSPACE-SERVO-SAFETY-RECOVERY-V1`

Goal:

Prevent unsafe shoulder motion and make recovery simple.

Tasks:

- Enforce min/max per-servo limits before `/move`.
- Return safety metadata for requested, clamped, and blocked movement.
- Add dry-run/no-motion validation mode.
- Add clear shoulder recovery control.
- Add recover-all safe pose flow.
- Show exact blocked reason in UI.

Acceptance:

- Shoulder cannot be commanded outside configured safe range.
- Unsafe command is blocked or clamped before hardware access.
- Dry-run validates without hardware motion.
- Recovery uses configured safe position.
- UI shows limit and recovery status.

## Phase 3: Real Model And Alignment

Objective:

`MIM-ARM-WORKSPACE-REAL-MODEL-ALIGNMENT-V1`

Goal:

Use the real MIM OBJ/MTL model and let the operator align it to the physical arm.

Tasks:

- Load `MIM_full_build.obj` and `MIM_full_build.mtl`.
- Allow model origin, rotation, scale, and height adjustments.
- Save alignment values into workspace setup state or calibration profile.
- Add fine adjustment controls.
- Add "apply sync" control after alignment.

Acceptance:

- Real model loads or reports exact missing asset.
- Alignment survives refresh.
- Operator can match simulated base to real base.
- Fine adjustments are possible without moving hardware.

## Phase 4: Sync Mode

Objective:

`MIM-ARM-WORKSPACE-SYNC-MODE-V1`

Goal:

Separate simulation-only work from real/sim synchronized work.

Tasks:

- Add explicit sync on/off state.
- When sync is on, `/arm_state` updates the simulation.
- When sync is off, simulation can be manipulated without real motion.
- Display sync freshness and last arm-state timestamp.
- Warn when real state is stale.

Acceptance:

- Sync state is visible.
- Real movement is reflected in sim when sync is on.
- Sim-only tests do not call hardware.
- Stale real state is visible.

## Phase 5: Object Library And Barriers

Objective:

`MIM-ARM-WORKSPACE-OBJECTS-AND-BARRIERS-V1`

Goal:

Represent useful real-world objects and solid constraints in simulation.

Tasks:

- Add common object library: block, cup, bottle, box, tool, plate.
- Allow size, drag, rotate, and delete.
- Add box, circle/cylinder, wall, table edge, and focus/work zone tools.
- Mark objects as solid, movable, forbidden, target, or training object.
- Persist object layout.

Acceptance:

- User can add and persist a solid wall.
- User can add and persist a block/cup/box.
- Objects have dimensions and type.
- Workspace reload preserves layout.

## Phase 6: Movement Constraint Awareness

Objective:

`MIM-ARM-WORKSPACE-MOVEMENT-CONSTRAINTS-V1`

Goal:

Use configured objects/zones to warn or block unsafe movement.

Tasks:

- Detect requested pose near table edge or solid object.
- Warn on likely collision or knock-over risk.
- Block forbidden-zone movement.
- Record reason codes and evidence.

Acceptance:

- Unsafe movement has exact reason.
- Solid objects affect movement validation.
- Work/focus zones guide behavior without becoming hard blockers.

## Phase 7: Object Detection Proposals

Objective:

`MIM-ARM-WORKSPACE-DETECTED-OBJECT-PROPOSALS-V1`

Goal:

Reflect real-world objects in the simulation after perception detects them.

Tasks:

- Accept camera/object detection proposals.
- Place tentative object with confidence.
- Let operator confirm, move, resize, or reject.
- Store source evidence and timestamp.

Acceptance:

- Detected block can become proposed object.
- Operator confirmation is required before authoritative placement.
- Source and confidence are visible.

## Phase 8: Future Room Mapping

Objective:

`MIM-ARM-WORKSPACE-ROOM-MAPPING-FOUNDATION-V1`

Goal:

Prepare for MIM to build and update its own 3D workspace map.

Tasks:

- Define room map schema.
- Track sensor/camera evidence source.
- Mark confidence per object/barrier.
- Plan sensor requirements.

Acceptance:

- Mapping is designed but not treated as authoritative.
- MIM can distinguish observed, inferred, and operator-confirmed geometry.

## Current Next Step

Start with:

`MIM-ARM-WORKSPACE-ACTIVE-SURFACE-RECONCILIATION-V1`

This keeps the project grounded. Once the live source files are confirmed, proceed to:

`MIM-ARM-WORKSPACE-VIEWPORT-CONTROLS-V1`

Then:

`MIM-ARM-WORKSPACE-SERVO-SAFETY-RECOVERY-V1`

