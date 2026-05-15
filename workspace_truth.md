# Workspace Truth

Last updated: 2026-05-15
Owner surface: `/workspace`
Intent: single source of truth for the active MIM workspace UI so future edits do not fork behavior into duplicate scripts or hidden control paths.

## Authority Rules

- Treat this file as the first stop before changing any workspace UI, workspace rendering, workspace deployment, or workspace control flow.
- Update this file in the same change whenever any active workspace file, dependency, route, deployment path, or behavioral contract changes.
- Do not add a new workspace script unless this file is updated first with the reason the existing active script cannot absorb the change.
- Prefer extending the current clean path instead of reviving legacy duplicated logic.

## Active Control Surface

Current live page flow:

- Route owner: `tmp_remote_mim/routes.py`
  - `@routes.route('/workspace')`
  - renders `workspace.html`
- Active template: `tmp_remote_mim/templates/workspace.html`
- Active browser script: `tmp_remote_mim/static/workspace_setup_clean.js`
- Active model asset: `/static/MIM_full_build.glb`
- Current template script tag:
  - `/static/workspace_setup_clean.js?v=20260515-clean-baseline-v8-lock-always-enabled`

## Inactive Or Legacy Surfaces

These exist in the repo but are not the intended active implementation for the clean workspace path:

- `tmp_remote_mim/static/workspace_setup.js`
  - legacy, duplicate-heavy, previously caused ghost-code style confusion
  - do not route `/workspace` back to this file without explicitly documenting why here
- `MIM Base Footprint` section in the template
  - hidden by clean script at runtime
  - placement controls were intentionally moved under `Setup`

## Current Behavioral Contract

The clean workspace path is simulation-first with explicit mode controls.

- Joint sliders are free 0 to 360 simulation controls.
- Mode `simulation`: free slider movement in sim only, no physical arm writes.
- Mode `Live Sync`: slider movement updates sim and mirrors each changed joint to the physical arm through `/move`.
- `Live Sync Lock` is always available in both modes and performs a one-shot pull from `/get_current_position` to assign live arm degrees into sim sliders/state without issuing movement writes.
- The real rendered GLB arm is used when available.
- Setup flow order is:
  1. Choose units
  2. Set table dimensions
  3. Place arm with directional pad
  4. Lock placement
  5. Adjust arm and table colors
  6. Save, load, rename, or delete named poses in Joint Control
- Saved poses persist in backend workspace state at `/workspace_setup_state` under `clean_ui.saved_poses`.
- Current unsaved live joint pose persists in backend workspace state at `/workspace_setup_state` under `clean_ui.current_pose`.
- Saved default camera view persists in backend workspace state at `/workspace_setup_state` under `clean_ui.default_view`.
- Status panel shows optimistic persistence states (`Saving...`, `Saved.`, `Save failed.`).
- Browser session state persists current page context when navigating away and back:
  - section expanded/collapsed states
  - selected pose dropdown item
  - panel scroll position
  - current camera view (position + target) for same-session return parity
- The clean path is the place to add future features; do not reintroduce old sync complexity into hidden template controls.

## Clean Endpoint Inventory

The clean `/workspace` path currently uses these runtime endpoints:

- `GET /workspace_setup_state`
  - load persisted clean workspace state (`clean_ui` block)
- `POST /workspace_setup_state`
  - save persisted clean workspace state (`clean_ui` block)
- `GET /get_current_position`
  - fetch current physical arm joint degrees for one-shot `Live Sync Lock`
- `POST /move`
  - mirror joint moves to physical arm when mode is `Live Sync`
- `GET /static/MIM_full_build.glb`
  - load rendered arm model

Endpoints intentionally not used by the clean path right now:

- workspace model info or OBJ/MTL asset endpoints from legacy script
- legacy obstacle/wall/marker interactive endpoints from old workspace UI path

## Active File Responsibilities

### `tmp_remote_mim/routes.py`

- Owns the `/workspace` Flask route.
- Must continue to render `workspace.html` unless this file is updated.

### `tmp_remote_mim/templates/workspace.html`

- Owns the visible layout and section structure.
- Current active top-level UI sections:
  - Setup
  - Joint Control
  - Status
- Includes the script binding to `workspace_setup_clean.js`.
- Legacy clean-inactive control sections were removed from template to reduce ghost-surface drift.

### `tmp_remote_mim/static/workspace_setup_clean.js`

This is the authoritative workspace behavior file.

Current responsibilities:

- Build and render the 3D scene.
- Load and pose the GLB arm model.
- Maintain clean simulation state for the 6 joints.
- Resize table geometry.
- Move arm placement on the tabletop.
- Lock or unlock placement.
- Apply arm and table color choices.
- Save and load named poses through backend workspace state payload.
- Rename and delete named poses through backend workspace state payload.
- Save and restore default camera view through backend workspace state payload.
- Persist and restore current live joint pose through backend workspace state payload.
- Surface persistence progress/failure in Status UI.
- Persist and restore page context state across navigation via session storage.
- Persist and restore current camera view across same-session navigation via session storage.
- Display camera status indicator showing whether current view matches saved default (`Camera: default` or `Camera: custom`).
- Expose explicit mode toggles (`simulation`, `Live Sync`) in Joint Control.
- Execute one-shot `Live Sync Lock` pose assignment from live hardware state without movement writes.
- Mirror slider changes to physical arm only when `Live Sync` mode is enabled.
- Normalize collapsible section titles before injecting clean-only controls.

Key clean-mode helper areas already in use:

- `normalizedSectionTitle()`
- `disableLegacyControls()`
- `ensureSetupSectionTitle()`
- `buildSetupControlsUi()`
- `buildJointPoseControlsUi()`
- `wireSetupControls()`
- `wireJointControls()`
- scene/model build + pose application helpers

## Dependencies

### Backend / Server

- Flask route rendering from `tmp_remote_mim/routes.py`
- Remote runtime currently served from the Pi at `192.168.1.90:5000`

### Frontend Runtime

- Three.js scene stack used by `workspace_setup_clean.js`
- `THREE.OrbitControls`
- `THREE.GLTFLoader`
- DOM section structure from `workspace.html`
- Backend `/workspace_setup_state` payload for clean workspace and saved poses

### Assets

- GLB arm asset: `MIM_full_build.glb`

### Deployment

Current known deployment target for the workspace UI:

- Remote host: `192.168.1.90`
- Remote app root: `/home/testpilot/mim_arm`
- Deployed template path: `/home/testpilot/mim_arm/templates/workspace.html`
- Deployed script path: `/home/testpilot/mim_arm/static/workspace_setup_clean.js`

Known service restart commands used during this phase:

- `systemctl --user restart mim-mobile-web.service || true`
- `systemctl --user restart mim-arm-web.service || true`

## Anti-Duplication Rules

- One active `/workspace` script: `workspace_setup_clean.js`
- One active `/workspace` template: `workspace.html`
- If a control is visually hidden by JS but still present in the template, either:
  - remove it from the template in a follow-up cleanup, or
  - document why it remains
- Do not copy helper functions under a second name when extending setup or pose behavior.
- Before adding a new function, search this file and the active script for an existing owner.
- If a new dependency is introduced, add it here before or with the code change.

## Known Risks

- Legacy script file still exists in repo (`workspace_setup.js`) and can be accidentally referenced if template script tag is changed.
- Persistence writes currently perform read-then-write on a shared JSON file; concurrent writes could overwrite each other.
- Cache busting must be updated when behavior changes to avoid stale script loads.
- Clean mode and legacy mode are still co-located in the same template, even though only the clean path is intended to drive behavior.
- Live Sync depends on network and hardware availability; temporary move failures can leave sim and hardware briefly out of sync until the next command or lock.

## Change Log

### 2026-05-15 (v7 - Live Sync Lock + Explicit Modes)

**Mode Controls Activated In Clean Path**
- Enabled `simulation` and `Live Sync` checkboxes in Joint Control as active controls.
- Added runtime mode state with explicit UI synchronization and status updates.

**Live Sync Lock Added**
- Added `Live Sync Lock` button in Joint Control.
- Lock behavior is one-shot assignment only:
  - calls `GET /get_current_position`
  - copies live degrees into sim sliders/state
  - does **not** send `/move` writes during lock

**Live Sync Writes Scoped By Mode**
- In `Live Sync` mode, slider changes now mirror joint updates to physical hardware via `POST /move`.
- In `simulation` mode, slider changes remain sim-only.
- Added per-joint debounce to reduce rapid write bursts while dragging sliders.

**Script Token Updated**
- `v6-camera-status` → `v7-live-sync-lock`
- Cache busting bumped to force immediate client refresh.

### 2026-05-15 (v8 - Lock Always Available + Placement Tweak)

**Live Sync Lock UX Correction**
- Removed mode-based lock disable so `Live Sync Lock` works while `simulation` is selected.
- Repositioned `Live Sync Lock` to sit directly above the servo slider block for clearer control proximity.
- Improved lock status text to show loaded live pose values for visible confirmation.

**Script Token Updated**
- `v7-live-sync-lock` → `v8-lock-always-enabled`

### 2026-05-15 (v6 - Camera Status & Constants Refactor)

**Camera Status Readout Feature**
- Added `updateCameraStatus()` function that compares current camera (position + target) against saved default view.
- Displays "Camera: default" (green) when view matches saved default within 0.5 unit threshold.
- Displays "Camera: custom" (blue) when view has been modified.
- Status updates in real-time on camera/view changes.
- New `cameraStatus` element added to Status section in template.

**Code Quality Improvements**
- Extracted hardcoded magic numbers to named constants for maintainability:
  - `CAMERA_MATCH_THRESHOLD = 0.5`
  - `ORBIT_DAMPING = 0.08`
  - `PERSIST_DEBOUNCE_MS = 220`
  - `SCROLL_PERSIST_MS = 120`
  - `SCROLL_APPLY_DELAY_MS = 180`
  - `ARM_MOVE_STEP = 20`
  - `ARM_PLACEMENT_MARGIN = 40`
  - `MIN_ARM_BOUNDARY = 80`
  - `TABLE_*` min/max constants
- Comprehensive code review completed; documented in WORKSPACE_CODE_REVIEW.md
- Identified 10 minor cleanup opportunities for future iterations

**Script Token Updated**
- `v5` → `v6-camera-status`
- Cache busting bumped to force reload

### 2026-05-15 (Previous Updates)

Established the clean workspace truth baseline.

- `/workspace` confirmed to render `workspace.html`.
- Template confirmed to load `workspace_setup_clean.js`.
- `Setup` is the active first section name.
- Added clean Setup flow controls:
  - unit selection
  - table sizing
  - arm placement pad
  - placement lock
  - table and arm color selectors
- Added Joint Control pose save/load UI.
- Confirmed the clean path uses the rendered GLB model.
- Confirmed clean mode is simulation-first with live sync disabled.
- Cleaned a local duplicate helper splice in `workspace_setup_clean.js` so one authoritative Setup/pose helper block remains.
- Removed clean-inactive legacy sections from `workspace.html` (footprint, obstacle, wall, marker, link approximation, extra action panel).
- Moved saved pose persistence from browser local storage to backend `/workspace_setup_state` (`clean_ui.saved_poses`).
- Added explicit clean endpoint inventory to avoid accidental endpoint sprawl.
- Added pose rename/delete actions in Joint Control.
- Added optimistic persistence indicator in Status (`Saving...`, `Saved.`, `Save failed.`).
- Bumped clean script token to `v3` to avoid stale browser script loads.
- Enabled `Save Default View` and made `Reset View` apply the saved default view.
- Persisted default view in backend workspace state (`clean_ui.default_view`).
- Bumped clean script token to `v4` to avoid stale browser script loads.
- Persisted current live pose in backend workspace state (`clean_ui.current_pose`).
- Added page session persistence for panel section state, selected pose, and scroll position.
- Bumped clean script token to `v5` to avoid stale browser script loads.

## Update Checklist

When changing the workspace system, update the relevant items here:

- active route
- active template
- active script
- asset dependencies
- backend endpoints actually used by the clean path
- deployment target or restart procedure
- behavioral contract
- known risks
- dated change log entry
