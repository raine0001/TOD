# MIM Arm LAB Image Archive - 2026-05-31

Generated: 2026-06-03

## Purpose

This archive preserves the MIM arm camera and perception images from the late May 2026 pickup, localization, RPLidar, and multi-camera lab runs.

These images are development evidence, not disposable runtime output. They should be used as future reference for:

- visual servoing behavior
- grip scoring and failure analysis
- object localization
- wrist/hand camera calibration
- RPLidar and camera cross-checks
- blue-block pickup reproduction
- white-block search and pickup attempts
- safe-table exploration and workspace awareness

## Archive Contents

- Image count: 574
- Total image size: 70,330,181 bytes
- Supporting run/sensor files: 61 JSON files and 1 Markdown objective note
- Source root: `runtime_remote_training/arm_pickup_run`
- Archive root: `docs/lab/mim-arm-image-archive-2026-05-31/assets`
- Full image manifest: [manifest.json](manifest.json)
- Image directory summary: [directory-summary.json](directory-summary.json)

## Directory Summary

| Directory | Images | Notes |
| --- | ---: | --- |
| `white_block_attempt_20260531` | 328 | White-block search, marker-3 localization, wrist/base probes, pickup attempts, lift checks, and contact sheets. |
| root archive directory | 115 | Blue-block pickup attempts, centerline/deep-seat/final-retry sequences, hand scans, multi-camera frames, and annotated detection images. |
| `pickup_continue_20260531` | 82 | Continued blue-block pickup learning, operator-demonstrated perfect grab position, hook strategy, table-height probes, and retention checks. |
| `pickup_now_20260531` | 46 | Live pickup-now attempt images, RPLidar before/after evidence, hook/lift sequence, and pickup attempt summary images. |
| `exploratory_spatial_interaction_20260531` | 3 | Safe-table exploration pose from MIM box cameras and hand camera. |

## Representative Evidence

- [multi-camera contact sheet](assets/multicamera_contact_sheet.jpg)
- [blue-block grip attempt annotated](assets/grip_attempt_claw_64_annotated.jpg)
- [deep-seat shoulder-back annotated](assets/deep_seat_shoulder_back_82_annotated.jpg)
- [final retry aligned open annotated](assets/final_retry_aligned_open_annotated.jpg)
- [operator demonstrated perfect grab position](assets/pickup_continue_20260531/operator_demonstrated_perfect_grab_position.jpg)
- [pickup-now RPLidar diff](assets/pickup_now_20260531/lidar_before_after_pickup_diff.png)
- [white marker-3 search start](assets/white_block_attempt_20260531/white_marker3_search_start.jpg)
- [white pickup attempt 4 close](assets/white_block_attempt_20260531/white_pickup_attempt4_close_0.jpg)
- [safe exploration hand camera](assets/exploratory_spatial_interaction_20260531/safe_table_exploration_pose_hand_camera.jpg)

## Development Notes

The archive keeps both raw and annotated images when both existed. Annotated images are useful for reviewing detection decisions, while raw images remain the ground truth for future model, calibration, and perception changes.

Supporting JSON files are preserved beside the images when they describe the same run, including RPLidar scans, pickup attempt summaries, distance readings, learning run logs, and objective/status packets. This keeps future review from having to guess which image sequence belonged to which sensor or action state.

This archive should be treated as a LAB reference set. Future robotics work should link back here when changing:

- camera calibration thresholds
- object color segmentation
- base/hand/wrist pose search policies
- pickup success criteria
- distance-sensor fusion
- table-height or obstacle-awareness logic

## Follow-Up

Create a smaller curated benchmark set from this archive before the next visual-servoing iteration. The benchmark should include success, near-miss, failure, occlusion, poor-lighting, and cross-camera disagreement examples.
