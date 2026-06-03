"""
Distance Sensor Routes
Provides REST API endpoints for TF Luna distance sensor data
"""

from flask import Blueprint, jsonify
import time
import shared

distance_bp = Blueprint('distance', __name__)


def _read_arduino_i2c_distance():
    from routes import SERIAL_MOVE_LOCK, parse_i2c_distance_line, update_serial_runtime

    serial_connection = shared.ser
    if not serial_connection or not serial_connection.is_open:
        return {
            "ok": False,
            "status": "unavailable",
            "message": "Arduino serial port unavailable",
            "connected": False,
            "source": "arduino_i2c_0x10",
        }, 503

    acquired = SERIAL_MOVE_LOCK.acquire(timeout=5)
    if not acquired:
        return {
            "ok": False,
            "status": "busy",
            "message": "Serial command lane busy; retry the read.",
            "connected": True,
            "source": "arduino_i2c_0x10",
        }, 429

    try:
        command = "I2C_DIST_READ\n"
        update_serial_runtime("distance_i2c_command_sent", command=command.strip())
        serial_connection.reset_input_buffer()
        serial_connection.write(command.encode("utf-8"))
        serial_connection.flush()

        timeout = time.time() + 2.0
        raw_lines = []
        reading = None
        while time.time() < timeout:
            if serial_connection.in_waiting > 0:
                line = serial_connection.readline().decode("utf-8", errors="replace").strip()
                if line:
                    raw_lines.append(line)
                    reading = parse_i2c_distance_line(line)
                    if reading is not None:
                        break
            time.sleep(0.01)

        if not reading:
            update_serial_runtime("distance_i2c_no_response", error="No I2C distance response from Arduino")
            return {
                "ok": False,
                "status": "error",
                "message": "No I2C distance response from Arduino",
                "connected": True,
                "source": "arduino_i2c_0x10",
                "raw_lines": raw_lines,
            }, 504

        if not reading.get("ok"):
            update_serial_runtime("distance_i2c_no_read", ack=True)
            return {
                "ok": False,
                "status": "no_read",
                "message": reading.get("reason", "no_read"),
                "connected": True,
                "source": "arduino_i2c_0x10",
                "raw_lines": raw_lines,
            }, 200

        distance_mm = int(reading.get("mm") or 0)
        shared.last_distance_mm = distance_mm
        update_serial_runtime("distance_i2c_read_complete", ack=True)
        return {
            "ok": True,
            "status": "ok",
            "connected": True,
            "source": "arduino_i2c_0x10",
            "address": reading.get("addr", "0x10"),
            "distance_mm": distance_mm,
            "distance_cm": reading.get("cm"),
            "signal_strength": reading.get("strength"),
            "temperature_raw": reading.get("temp_raw"),
            "registers_0_7": reading.get("reg0_7"),
            "raw_lines": raw_lines,
        }, 200
    finally:
        SERIAL_MOVE_LOCK.release()


@distance_bp.route('/distance', methods=['GET'])
def get_distance():
    """
    Get current distance reading from TF Luna

    Returns:
        {
            "distance_mm": int,
            "signal_strength": int,
            "temperature_c": float,
            "connected": bool
        }
    """
    payload, status_code = _read_arduino_i2c_distance()
    if payload.get("ok"):
        return jsonify(payload), status_code

    if not shared.tf_luna:
        return jsonify(payload), status_code

    dist = shared.tf_luna.read_distance()
    if dist is not None and dist > 0:
        shared.last_distance_mm = dist
        status = shared.tf_luna.get_status()
        status["source"] = "tf_luna_uart"
        return jsonify(status), 200

    return jsonify(payload), status_code


@distance_bp.route('/distance/status', methods=['GET'])
def distance_status():
    """Get TF Luna status and last known reading"""
    payload, status_code = _read_arduino_i2c_distance()
    payload["last_distance_mm"] = shared.last_distance_mm
    if payload.get("ok"):
        return jsonify(payload), status_code

    payload["distance_motion_safe"] = False
    payload["safety_reason"] = "authoritative_i2c_distance_unavailable"
    return jsonify(payload), status_code


@distance_bp.route('/distance/calibrate', methods=['POST'])
def calibrate_distance():
    """
    Reset distance sensor (for future calibration)
    Note: TF Luna hardware calibration requires physical buttons on the device
    """
    if not shared.tf_luna:
        return jsonify({"status": "error", "message": "TF Luna not initialized"}), 503

    try:
        # Clear any pending data
        if shared.tf_luna.ser and shared.tf_luna.ser.is_open:
            shared.tf_luna.ser.reset_input_buffer()
            return jsonify({"status": "ok", "message": "Distance sensor cleared"}), 200
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@distance_bp.route('/distance/test', methods=['GET'])
def test_distance():
    """
    Test endpoint: Read and return 10 consecutive distance samples
    Useful for diagnostics and checking sensor responsiveness
    """
    samples = []
    try:
        for i in range(10):
            payload, _ = _read_arduino_i2c_distance()
            dist = payload.get("distance_mm")
            if isinstance(dist, int) and dist > 0:
                samples.append({
                    "sample": i + 1,
                    "distance_mm": dist,
                    "signal": payload.get("signal_strength"),
                    "temperature_raw": payload.get("temperature_raw"),
                    "source": payload.get("source"),
                })
            time.sleep(0.05)  # 50ms between reads

        return jsonify({
            "status": "ok",
            "samples_collected": len(samples),
            "samples": samples
        }), 200
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500
