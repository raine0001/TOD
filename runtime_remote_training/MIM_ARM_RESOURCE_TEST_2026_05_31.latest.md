# MIM ARM Resource Test - 2026-05-31

## Summary

MIM ARM resource sweep completed after installing the RPLIDAR C1 and reassembling the arm.

## Results

| Resource | Result | Evidence |
| --- | --- | --- |
| ARM app | PASS | `http://192.168.1.90:5000/ping` returned `ok=true`; `mim.service` active. |
| Arduino control board | PASS | `/serial_health` reports `/dev/ttyACM0`, `serial_ready=true`, `status=ok`. |
| Hand C12 I2C distance sensor | PASS | `/distance/status` reports `ok=true`, `source=arduino_i2c_0x10`, `address=0x10`, latest reading `940 mm`, signal `1448`. |
| RPLIDAR C1 | PASS | `/lidar/status` reports CP2102N on `/dev/ttyUSB0`, firmware `1.2`, health code `0`, status `ok`. |
| RPLIDAR scan | PASS | `/lidar/scan?duration=3&max_points=800` returned `800` points, descriptor `a55a0500004081`, min `24.0 mm`, max `7220.0 mm`. |
| Hand camera | PASS | Camera stream sampled at `1280 x 960`; wide format is active. |
| Arm command path | PASS | `/move` dry-run accepted servo `0`, angle `109`, validated servo limits, no motion sent. |

## Fix Applied

The RPLIDAR route update initially broke `/distance/status` because `distance_routes.py` imports `parse_i2c_distance_line` from `routes.py`, and the local LIDAR-enabled route file did not include that helper. The parser was restored and deployed to `/home/testpilot/mim_arm/routes.py`.

The LIDAR scan route was also tuned for the new sensor by setting the default scan duration to `3.0` seconds and adding a longer post-scan-command warmup so scans reliably return points after motor spin-up.

## Current Endpoints

- `GET /lidar/status`
- `GET /lidar/scan?duration=3&max_points=800`
- `GET /distance/status`
- `GET /serial_health`
- `GET /arm_state`
- `GET /camera_feed`

## Notes

No broad physical motion test was run. The arm control path was validated with `dry_run=true` to avoid accidental table contact while confirming the API, serial guard, and servo limit logic are active.
