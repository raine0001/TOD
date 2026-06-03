# MIM Studio Systems EKG V1

Generated: 2026-06-02

## Objective

Make `/studio/systems` a real operational health page instead of a placeholder.

## What Changed

- Added a compact Systems / Health page for Studio.
- Added MIM host EKG metrics:
  - load average
  - RAM usage
  - disk usage
  - uptime
- Added Studio database reachability and row counts.
- Added app fleet health from the MIM Apps registry and TOD source scan.
- Added PythonAnywhere / MIM Robotics provider status from the verified status artifact.
- Added hourly reflection visibility so training outcome warnings appear directly in Systems.
- Added top five Needs Attention items instead of raw artifact sprawl.
- Added TOD local machine awareness. TOD is Dave's local Windows workstation, not a remote abstract worker.
- Added TOD local snapshot support for CPU, RAM, disk, GPU, and source-scan timing.
- Added Training Reflection Resolution panel when the reflection layer reports yellow/needs-attention.
- Added evidence/action links from Systems into Training, Reports, Documents, Objectives, and TOD blocker reports.
- Added next instrumentation steps for automated TOD local metric publishing, Render service checks, and H.A.L. repair handoff.

## Important Behavior

The page does not duplicate the Training, Apps, Reports, or Objectives pages. It gives a top-down EKG view:

- is the ecosystem healthy?
- what needs attention?
- what systems are green?
- what instrumentation is still missing?
- when a yellow state appears, what evidence explains it and what action path gets it back to green?

## Known Follow-Up

TOD local machine metrics are now represented by `TOD_LOCAL_MACHINE_STATUS.latest.json`. The current snapshot is generated from the local Windows machine and synced to MIM shared runtime. The next improvement is automation so the snapshot refreshes continuously.

## Verification

- `python -m py_compile tmp_remote_mim/core/routers/studio.py`
- Encoding scan for mojibake and rejected labels passed.
- TOD local snapshot generated at `runtime_remote_training/TOD_LOCAL_MACHINE_STATUS.latest.json`.
- TOD local snapshot copied to `out/context-sync/TOD_LOCAL_MACHINE_STATUS.latest.json`.
- Training Reflection yellow state now shows blocked count, stale artifact count, judgment score, evidence links, and resolution actions.
