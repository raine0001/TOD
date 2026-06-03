# MIM ARM MPC-Inspired Obstacle-Aware Planning Reference

Date: 2026-05-31

Source paper:
`E:\MIM Robotics\08718327.pdf`

Paper title:
Semi-Autonomous Robot Teleoperation with Obstacle Avoidance via Model Predictive Control

Use classification:
Training reference for MIM ARM motion planning and obstacle-aware behavior.

Do not treat this as direct arm math. The paper uses a UR5 industrial manipulator with formal kinematics, known geometry, and model predictive control. MIM ARM is a servo-driven learning arm with empirical movement memory, cameras, C12 distance sensing, and RPLIDAR table-height perception.

## Transferable Ideas

- Replan continuously instead of sending one blind movement.
- Track a target while respecting constraints.
- Treat obstacles as zones that candidate movements must avoid.
- Check multiple points along the robot body, not only the claw tip.
- Prefer smooth movement by limiting joint velocity and acceleration.
- Accept imperfect target tracking when safety or collision avoidance requires it.
- Predict short future motion before executing the next bounded step.
- Validate after each movement using fresh sensor evidence.

## Non-Transferable Assumptions

- UR5 kinematics do not directly apply to MIM ARM.
- Industrial joint dynamics do not match hobby servo behavior.
- Formal MPC optimization is too heavy for the first MIM ARM learning loop.
- The paper assumes cleaner obstacle geometry than MIM currently has.
- The paper's collision model should be converted into practical sensor checks.

## Practical MIM ARM Translation

MIM should use an MPC-inspired loop:

1. Observe the workspace.
2. Identify the target object with cameras.
3. Map nearby physical surfaces with table-height RPLIDAR.
4. Check claw/object approach distance with the C12 sensor.
5. Retrieve similar successful poses from movement memory.
6. Generate several small candidate next moves.
7. Reject candidates that violate safety or collision constraints.
8. Prefer the candidate that moves closer to the target with the least servo change.
9. Execute one bounded movement.
10. Re-observe, compare expected vs actual result, and replan.

## MIM ARM Constraint Types

Hard constraints:
- Do not exceed servo limits.
- Do not continue downward pressure when C12/camera evidence indicates table contact.
- Do not move blindly when all perception sources are stale.
- Do not claim object pickup without fresh visual or motion evidence.

Soft constraints:
- Prefer smoother joint changes.
- Prefer known-good movement memory poses.
- Prefer keeping the hand camera view of the grip/object.
- Prefer staying within the current 1 meter table-height RPLIDAR workspace.

Evidence constraints:
- Camera identifies color/object class.
- RPLIDAR identifies physical edge/cluster location.
- C12 confirms approach range near the claw.
- Movement memory confirms the pose has been attempted or learned.

## Learning Objective Seed

Objective name:
MIM-ARM-MPC-INSPIRED-OBSTACLE-AWARE-PLANNING-V1

Goal:
Teach MIM to use MPC-inspired candidate motion ranking for safe arm exploration and block manipulation.

Acceptance:
- MIM reads this reference summary.
- MIM does not copy UR5 equations as direct MIM ARM kinematics.
- MIM creates a candidate-move planner using movement memory, cameras, C12, and RPLIDAR.
- MIM executes only bounded moves with post-move validation.
- MIM records failures as motion lessons rather than repeating the same failed approach.

## Current Best Application

For blue-block pickup:

- Camera chooses the blue block.
- RPLIDAR table-height scan confirms the block edge cluster.
- C12 checks claw distance during approach.
- Movement memory proposes candidate approach poses.
- MIM executes one small motion at a time and rescans.
- If the block moves or pickup fails, MIM stores the failed pose and adjusts the next candidate.
