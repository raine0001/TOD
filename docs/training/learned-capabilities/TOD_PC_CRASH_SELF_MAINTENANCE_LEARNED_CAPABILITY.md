# Learned Capability: TOD PC Crash Self-Maintenance V1

Capability Name: Windows crash self-maintenance evidence triage for DRIVER_POWER_STATE_FAILURE.

Trigger: Windows PC crash/restart, bugcheck 0x9F, UASPStor/storport evidence, Realtek RTL9210B storage bridge, or repeated overnight instability while TOD is running.

Reality: The July 1 crash evidence pointed to DRIVER_POWER_STATE_FAILURE involving uaspstor/storport and a Realtek RTL9210B NVME SCSI Disk Device mapped to F:. Power-risk containment was applied, but future stability is not proven until observation passes.

Observation: Codex emergency maintenance analyzed the dump and applied containment. TOD later created training artifacts, authored scaffolded patch packet fields, applied a narrow safe-root patch, and recorded evidence-only status. TOD failed conversational self-check synthesis and several patch-authoring/formatting rungs.

Root Cause: The machine crash class appears storage-power related. The training failure class is different: TOD lacked independent crash-diagnostic reasoning, safe evidence-path access, and evidence-grounded self-assessment without scaffolding.

Blocker Class: capability_blocker plus infrastructure_authority_boundary for elevated dump access.

Decomposition Ladder:
1. Read formal crash evidence summary.
2. Produce five-field patch-packet scaffold.
3. Add validation command.
4. Add rollback note.
5. Add prevention lesson.
6. Assemble patch packet.
7. Apply approved narrow safe-root patch.
8. Report from evidence only.
9. Define machine diagnostics authority ladder.
10. Classify containment vs repair.
11. Freeze learned capability.
12. Pass simulations before claiming independence.

Smallest Successful Rung: TOD successfully appended structured training sections when given explicit target file, section title, validation command, and bounded docs append mode.

Implementation Summary: TOD changed scripts/engines/LocalExecutionEngine.ps1 to add tod/out/pc-maintenance/ as a narrow safe root so PC maintenance evidence can be read without granting broad tod/out or C:\Windows access. TOD also created docs/training/TOD_PC_CRASH_SELF_MAINTENANCE_TRAINING_PLAN.md and docs/training/TOD_PC_CRASH_SAFE_ROOT_PATCH_PACKET.md.

Validation: Latest confirmed validations include PowerShell parse/static safe-root validation, Gate 4 evidence-only assessment validation, and Gate 5/6 ladder validation. Formatting cleanup for one overindented safe-root line remains separate source-quality debt because whitespace-only replacement was rejected or rolled back by the bounded edit tool.

General Rule Learned: Diagnostic containment is not permanent repair. Evidence access must be narrow. Crash reports must distinguish system root cause from training root cause.

Prevention Rule: TOD must not claim PC crash independence until it can inspect crash evidence, classify authority boundaries, run or request approved debugger analysis, extract device/driver facts, and produce containment-vs-repair classification without Codex-provided source anchors.

Reuse Trigger: Reuse this capability when new evidence mentions 0x9F, DRIVER_POWER_STATE_FAILURE, UASPStor, storport, RTL9210B, USB NVMe bridge, disk power transition, overnight crash, or dump-analysis access boundary.

Dependent Capabilities: elevated diagnostic authority handling; evidence-only self-assessment; patch packet authoring from source anchors; LocalExecutionEngine safe-root management; simulation retest.

Capability Confidence: 4/10 overall. 6/10 for narrow scaffolded local source changes. 3/10 for independent crash diagnosis.

Independent Pass Rate: not yet proven. Current run was scaffolded by Codex and emergency analysis was Codex-performed.

Date Frozen: 2026-07-01.

Separate Debt: Normalize indentation in scripts/engines/LocalExecutionEngine.ps1 safe-root list after LocalExecutionEngine can support whitespace-only formatting cleanup, or through a separately approved formatting path.

Generalized Principle: Readers and validators need narrow, safe access to evidence artifacts. Elevated/system evidence should be mirrored into safe evidence paths. Training success requires proving independent reasoning, not only preserving the result of emergency maintenance.

## Scheduler Observation Capability Update - 2026-07-01

Capability Name: TOD recurring crash observation via Windows Task Scheduler.
Trigger: TOD has a clean observation script but no proof that observation will continue without manual Codex checks.
Reality: Windows Task Scheduler can run scripts/Invoke-TODPcCrashObservation.ps1 from E:\TOD and update tod/out/pc-maintenance/TOD_PC_CRASH_OBSERVATION_1H.latest.json.
Observation: One-shot proof passed first, then recurring observation install passed after stale active-lane preservation was cleared.
Root Cause: The scheduler capability was blocked by stale active-lane preservation and by TOD command-authoring/synthesis weakness, not by the observation script itself.
Blocker Class: coordination_blocker for stale active lane plus capability_blocker for runtime proof command authoring.
Decomposition Ladder:
1. Prove the current observation script runs manually.
2. Prove a temporary one-shot scheduled task can run it.
3. Verify artifact timestamp moves after scheduled task start.
4. Verify permanent_fix_claim remains false.
5. Clear stale active lane that protected the already-completed one-shot proof.
6. Run recurring installer package after arbitration promotes it.
7. Verify persistent scheduled task exists and last result is 0.
8. Verify observation artifact updates and still avoids permanent-fix claims.
Smallest Successful Rung: one-shot scheduled task proof updated the observation artifact and cleaned up its temporary task.
Implementation Summary: TOD installed persistent scheduled task TOD PC Crash Observation with 30-minute repetition, ran it once immediately, and left it installed for ongoing observation.
Validation: Get-ScheduledTask shows TOD PC Crash Observation exists; state Ready; last task result 0; next run scheduled. Observation artifact last_write_utc 2026-07-01T20:10:52.3723529Z; status no_new_crash_signal_detected; permanent_fix_claim false; required_continuation continue_observation_window_monitoring.
General Rule Learned: A successful one-shot proof is not recurring automation. Recurring automation is only proven when the persistent task exists after validation and an immediate run updates the expected artifact.
Prevention Rule: If a new continuation is queued behind a terminal active lane, terminalize or drain the stale active lane before retrying; do not call the queued work complete.
Reuse Trigger: Reuse this capability whenever TOD needs to prove scheduled observation, watchdog, or maintenance automation from an existing script.
Dependent Capabilities: runtime proof command authoring; active-lane stale preservation recovery; evidence-only reporting; Task Scheduler validation.
Capability Confidence: 7/10 for scaffolded scheduler execution and validation. 4/10 for independent command authoring.
Independent Pass Rate: scheduler execution proof passed with Codex-scaffolded validation command; independent authoring not yet proven.
Date Frozen: 2026-07-01.
Separate Debt: Train TOD to author the scheduled-task validation command itself without Codex scaffolding.
Generalized Principle: Automation is not proven by task creation alone; it requires run evidence, artifact movement, current-state readback, and non-overclaiming language.
