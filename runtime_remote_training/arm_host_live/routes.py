# routes.py



# Main UI and control route module for the live Pi app.



# This file currently mixes page rendering, runtime state updates, persistence,



# and direct serial control paths.



from flask import Blueprint, request, jsonify, render_template, send_from_directory



import serial
import threading



import glob



import time



import uuid


import json
from collections import deque
from datetime import datetime, timezone



from shared import load_safe_position, save_safe_position, load_routines, save_routines, load_servo_config
import shared
import servo_driver
from config_paths import app_path, load_json_file, save_json_file



import os







routes = Blueprint('routes', __name__)



config_bp = Blueprint('config_bp', __name__)



CONFIG_FILE = app_path("mim_config.json")

serial_runtime = {
    "last_serial_event": "startup",
    "last_serial_event_at": None,
    "last_serial_event_ts": None,
    "last_command_sent": None,
    "last_command_sent_at": None,
    "last_command_ack_at": None,
    "controller_error": None,
    "serial_command_count": 0,
    "serial_ack_count": 0,
    "last_serial_event_details": None,
}
SERIAL_MOVE_LOCK = threading.Lock()
MOVE_TRACE_LIMIT = 300
move_trace_buffer = deque(maxlen=MOVE_TRACE_LIMIT)


def utc_now_iso():

    return datetime.now(timezone.utc).isoformat()


def get_serial_connection():

    return shared.ser



def is_serial_ready():

    serial_connection = get_serial_connection()

    return bool(serial_connection and serial_connection.is_open)


def update_serial_runtime(event: str, command: str = None, ack: bool = False, error: str = None, **details):

    now = time.time()

    serial_runtime["last_serial_event"] = event

    serial_runtime["last_serial_event_ts"] = now

    serial_runtime["last_serial_event_at"] = utc_now_iso()
    serial_runtime["last_serial_event_details"] = details or None

    if command is not None:

        serial_runtime["last_command_sent"] = command

        serial_runtime["last_command_sent_at"] = serial_runtime["last_serial_event_at"]

        serial_runtime["serial_command_count"] += 1

    if ack:

        serial_runtime["last_command_ack_at"] = serial_runtime["last_serial_event_at"]

        serial_runtime["serial_ack_count"] += 1

    if error is not None:

        serial_runtime["controller_error"] = error

    elif ack or event in ("serial_ready", "reconnect_success"):

        serial_runtime["controller_error"] = None


def append_move_trace(event_type: str, payload: dict):
    try:
        move_trace_buffer.append({
            "event": event_type,
            "timestamp": utc_now_iso(),
            **(payload if isinstance(payload, dict) else {}),
        })
    except Exception:
        pass


@routes.route('/move_trace', methods=['GET'])
def move_trace():
    try:
        limit = int(request.args.get('limit', 50))
    except Exception:
        limit = 50
    limit = max(1, min(500, limit))
    rows = list(move_trace_buffer)[-limit:]
    return jsonify({"status": "ok", "count": len(rows), "items": rows}), 200


def serial_health_payload():

    serial_connection = get_serial_connection()

    serial_bound = bool(serial_connection)

    serial_ready = bool(serial_connection and serial_connection.is_open)

    controller_port = getattr(serial_connection, "port", None) if serial_connection else None

    last_age = None

    if serial_runtime["last_serial_event_ts"]:

        last_age = round(time.time() - serial_runtime["last_serial_event_ts"], 3)

    return {

        "status": "ok",

        "serial_bound": serial_bound,

        "serial_ready": serial_ready,

        "last_serial_event": serial_runtime["last_serial_event"],

        "last_serial_event_at": serial_runtime["last_serial_event_at"],

        "last_serial_age_seconds": last_age,

        "controller_port": controller_port,

        "controller_error": serial_runtime["controller_error"],

        "last_command_sent": serial_runtime["last_command_sent"],

        "last_command_sent_at": serial_runtime["last_command_sent_at"],

        "last_command_ack_at": serial_runtime["last_command_ack_at"],

        "serial_command_count": serial_runtime["serial_command_count"],

        "serial_ack_count": serial_runtime["serial_ack_count"],

    }


def load_last_position_snapshot():

    try:

        with open('last_position.json', 'r') as f:

            return json.load(f)

    except Exception:

        return None


def save_last_position_snapshot(angles):
    try:
        normalized = [int(a) for a in list(angles or [])]
        if len(normalized) < 6:
            normalized.extend([90] * (6 - len(normalized)))
        normalized = normalized[:6]
        with open('last_position.json', 'w') as f:
            json.dump(normalized, f)
        return True
    except Exception:
        return False





def render_known_template(template_name):



    template_path = os.path.join("templates", template_name)



    if not os.path.exists(template_path):



        return jsonify({



            "status": "unavailable",



            "message": f"Missing template: {template_name}"



        }), 503



    return render_template(template_name)



@routes.route('/favicon.ico')



def favicon():



    static_dir = os.path.join(os.getcwd(), "static")

    icon_path = os.path.join(static_dir, "favicon.ico")

    if os.path.exists(icon_path):

        return send_from_directory(static_dir, "favicon.ico")

    return ("", 204)







#comm ports



@routes.route('/list_ports', methods=['GET'])



def list_ports():



    ports = glob.glob('/dev/ttyACM*') + glob.glob('/dev/ttyUSB*')



    return jsonify({



        "ports": ports,



        "preferred": ports[0] if ports else None



    })







#check serial readiness



@routes.route('/status', methods=['GET'])



def status():



    is_connected = is_serial_ready()

    update_serial_runtime("serial_ready" if is_connected else "serial_not_ready")

    payload = serial_health_payload()

    payload["serial_ready"] = is_connected

    return jsonify(payload), 200





@routes.route('/serial_health', methods=['GET'])



def serial_health():



    return jsonify(serial_health_payload()), 200







@routes.route('/sensor/i2c_scan', methods=['GET'])
def sensor_i2c_scan():
    """Read-only Arduino I2C scan for sensor discovery."""
    serial_connection = get_serial_connection()
    if not serial_connection or not serial_connection.is_open:
        update_serial_runtime("i2c_scan_serial_unavailable", error="Serial port unavailable")
        return jsonify({"status": "error", "message": "Serial port unavailable"}), 500

    acquired = SERIAL_MOVE_LOCK.acquire(timeout=5)
    if not acquired:
        update_serial_runtime("i2c_scan_serial_busy", error="Serial command lane busy")
        return jsonify({"status": "busy", "message": "Serial command lane busy; retry the scan."}), 429

    try:
        command = "I2C_SCAN\n"
        update_serial_runtime("i2c_scan_command_sent", command=command.strip())
        serial_connection.reset_input_buffer()
        serial_connection.write(command.encode("utf-8"))
        serial_connection.flush()

        timeout = time.time() + 4
        lines = []
        while time.time() < timeout:
            if serial_connection.in_waiting > 0:
                line = serial_connection.readline().decode("utf-8", errors="replace").strip()
                if line:
                    lines.append(line)
                    if line == "I2C_SCAN_END":
                        break
            time.sleep(0.01)

        addresses = []
        for line in lines:
            if line.startswith("I2C:0x"):
                addresses.append(line.split("I2C:", 1)[1].strip())
            elif line.startswith("Found I2C device at 0x"):
                addresses.append("0x" + line.rsplit("0x", 1)[1].strip())

        normalized = sorted({addr.upper().replace("0X", "0x") for addr in addresses})
        update_serial_runtime("i2c_scan_complete", ack=True)
        return jsonify({
            "status": "ok",
            "sent": command.strip(),
            "addresses": normalized,
            "likely_tf_luna_present": "0x10" in normalized,
            "pca9685_present": "0x40" in normalized,
            "raw_lines": lines,
        }), 200
    except Exception as e:
        update_serial_runtime("i2c_scan_exception", error=str(e))
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        SERIAL_MOVE_LOCK.release()


def parse_tfmini_line(line):
    if not line.startswith("TFMINI:"):
        return None
    if line == "TFMINI:NO_FRAME":
        return {"ok": False, "raw_line": line, "reason": "no_frame"}
    payload = {"ok": True, "raw_line": line}
    for part in line.split(":", 1)[1].split(","):
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        key = key.strip().lower()
        value = value.strip()
        if key in {"cm", "mm", "strength", "temp_raw"}:
            try:
                payload[key] = int(value)
            except ValueError:
                payload[key] = value
        elif key == "frame":
            payload[key] = value
    return payload


def parse_i2c_distance_line(line):
    if not line.startswith("DIST:"):
        return None
    if line == "DIST:NO_READ":
        return {"ok": False, "raw_line": line, "reason": "no_read"}
    payload = {"ok": True, "raw_line": line}
    for part in line.split(":", 1)[1].split(","):
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        key = key.strip().lower()
        value = value.strip()
        if key in {"cm", "mm", "strength", "temp_raw"}:
            try:
                payload[key] = int(value)
            except ValueError:
                payload[key] = value
        elif key in {"addr", "reg0_7"}:
            payload[key] = value
    return payload


@routes.route('/sensor/i2c_distance_read', methods=['GET'])
def sensor_i2c_distance_read():
    """Read one distance sample from the Arduino-side I2C sensor at 0x10."""
    serial_connection = get_serial_connection()
    if not serial_connection or not serial_connection.is_open:
        update_serial_runtime("i2c_distance_serial_unavailable", error="Serial port unavailable")
        return jsonify({"status": "error", "message": "Serial port unavailable"}), 500

    acquired = SERIAL_MOVE_LOCK.acquire(timeout=5)
    if not acquired:
        update_serial_runtime("i2c_distance_serial_busy", error="Serial command lane busy")
        return jsonify({"status": "busy", "message": "Serial command lane busy; retry the read."}), 429

    try:
        command = "I2C_DIST_READ\n"
        update_serial_runtime("i2c_distance_command_sent", command=command.strip())
        serial_connection.reset_input_buffer()
        serial_connection.write(command.encode("utf-8"))
        serial_connection.flush()

        timeout = time.time() + 2.0
        lines = []
        reading = None
        while time.time() < timeout:
            if serial_connection.in_waiting > 0:
                line = serial_connection.readline().decode("utf-8", errors="replace").strip()
                if line:
                    lines.append(line)
                    reading = parse_i2c_distance_line(line)
                    if reading is not None:
                        break
            time.sleep(0.01)

        if not reading:
            update_serial_runtime("i2c_distance_no_response", error="No I2C distance response from Arduino")
            return jsonify({
                "status": "error",
                "sent": command.strip(),
                "message": "No I2C distance response from Arduino",
                "raw_lines": lines,
            }), 504

        if not reading.get("ok"):
            update_serial_runtime("i2c_distance_no_read", ack=True)
            return jsonify({
                "status": "no_read",
                "sent": command.strip(),
                "raw_lines": lines,
                "reading": reading,
            }), 200

        update_serial_runtime("i2c_distance_read_complete", ack=True)
        return jsonify({
            "status": "ok",
            "sent": command.strip(),
            "address": reading.get("addr", "0x10"),
            "distance_cm": reading.get("cm"),
            "distance_mm": reading.get("mm"),
            "strength": reading.get("strength"),
            "temperature_raw": reading.get("temp_raw"),
            "registers_0_7": reading.get("reg0_7"),
            "raw_lines": lines,
        }), 200
    except Exception as e:
        update_serial_runtime("i2c_distance_exception", error=str(e))
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        SERIAL_MOVE_LOCK.release()


@routes.route('/sensor/tfmini_read', methods=['GET'])
def sensor_tfmini_read():
    """Read one TFMini-S frame through the Arduino controller serial lane."""
    serial_connection = get_serial_connection()
    if not serial_connection or not serial_connection.is_open:
        update_serial_runtime("tfmini_serial_unavailable", error="Serial port unavailable")
        return jsonify({"status": "error", "message": "Serial port unavailable"}), 500

    acquired = SERIAL_MOVE_LOCK.acquire(timeout=5)
    if not acquired:
        update_serial_runtime("tfmini_serial_busy", error="Serial command lane busy")
        return jsonify({"status": "busy", "message": "Serial command lane busy; retry the read."}), 429

    try:
        command = "TFMINI_READ\n"
        update_serial_runtime("tfmini_command_sent", command=command.strip())
        serial_connection.reset_input_buffer()
        serial_connection.write(command.encode("utf-8"))
        serial_connection.flush()

        timeout = time.time() + 2.0
        lines = []
        reading = None
        while time.time() < timeout:
            if serial_connection.in_waiting > 0:
                line = serial_connection.readline().decode("utf-8", errors="replace").strip()
                if line:
                    lines.append(line)
                    reading = parse_tfmini_line(line)
                    if reading is not None:
                        break
            time.sleep(0.01)

        if not reading:
            update_serial_runtime("tfmini_no_response", error="No TFMini response from Arduino")
            return jsonify({
                "status": "error",
                "sent": command.strip(),
                "message": "No TFMini response from Arduino",
                "raw_lines": lines,
            }), 504

        if not reading.get("ok"):
            update_serial_runtime("tfmini_no_frame", ack=True)
            return jsonify({
                "status": "no_frame",
                "sent": command.strip(),
                "raw_lines": lines,
                "reading": reading,
            }), 200

        update_serial_runtime("tfmini_read_complete", ack=True)
        return jsonify({
            "status": "ok",
            "sent": command.strip(),
            "distance_cm": reading.get("cm"),
            "distance_mm": reading.get("mm"),
            "strength": reading.get("strength"),
            "temperature_raw": reading.get("temp_raw"),
            "frame": reading.get("frame"),
            "raw_lines": lines,
        }), 200
    except Exception as e:
        update_serial_runtime("tfmini_exception", error=str(e))
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        SERIAL_MOVE_LOCK.release()


#site pages



@routes.route('/settings')



def settings():



    return render_template('settings.html')







#site pages



@routes.route('/diagnostics')



def diagnostics():



    return render_template('diagnostics.html')







#site pages



@routes.route('/routines')



def routines():



    return render_template('routines.html')







#site pages



@routes.route('/workspace')



def workspace():



    return render_template('workspace.html')







#site pages



@routes.route('/')



def index():



    return render_template('index.html')







#site pages



@routes.route('/old')



def old():



    return render_template('index_old.html')







@routes.route('/help')



def help():



    return render_template('help.html')







@routes.route('/test')



def test():



    return render_known_template('test.html')







@routes.route('/get_mode')



def get_mode():



    from mim_state_manager import load_context



    context = load_context()



    return jsonify({"mode": context.get("mode", "unknown")})







@routes.route('/set_mode/<new_mode>', methods=['POST'])



def set_mode(new_mode):



    from mim_state_manager import update_context



    update_context(mode=new_mode)



    return jsonify({"status": "ok", "mode": new_mode})







@routes.route('/next_action')



def next_action():



    from mim_state_manager import get_next_action



    return jsonify({"next": get_next_action()})







@routes.route('/get_state')



def get_state():



    from mim_state_manager import load_context



    ctx = load_context()



    return jsonify({"state": ctx.get("state", "Manual")})











# keep app live



@routes.route('/ping')



def ping():



    try:



        if is_serial_ready():

            update_serial_runtime("ping_ok")



            return jsonify({"ok": True}), 200



        else:



            print("?? /ping: serial not open")

            update_serial_runtime("ping_serial_not_open")



            return jsonify({"ok": False}), 200



    except Exception as e:



        print("? /ping error:", e)

        update_serial_runtime("ping_exception", error=str(e))



        return jsonify({"ok": False}), 200







@routes.route('/save_current_position', methods=['POST'])



def save_current_position():



    data = request.get_json()



    if not data or 'angles' not in data:



        return jsonify({"status": "error", "message": "Missing angles"}), 400



    try:



        with open('last_position.json', 'w') as f:



            json.dump(data['angles'], f)



        return jsonify({"status": "ok", "message": "Position saved"})



    except Exception as e:



        return jsonify({"status": "error", "message": str(e)}), 500











@routes.route('/get_current_position')



def get_current_position():



    try:



        with open('last_position.json', 'r') as f:



            angles = json.load(f)



        return jsonify({"status": "ok", "angles": angles})



    except Exception as e:



        print(f"? Error reading last_position.json: {e}")



        return jsonify({"status": "default", "angles": [90, 90, 90, 90, 90, 50]})







def _workspace_servo_limit_for(servo_index):
    try:
        servos = load_servo_config() or []
        if not isinstance(servos, list):
            raise ValueError("servo config is not a list")
        servo_index = int(servo_index)
        if servo_index < 0 or servo_index >= len(servos):
            raise IndexError("servo index out of range")

        cfg = servos[servo_index] or {}
        min_angle = int(cfg.get("min", 0))
        max_angle = int(cfg.get("max", 180))
        if min_angle > max_angle:
            min_angle, max_angle = max_angle, min_angle
        return {
            "configured": True,
            "min": min_angle,
            "max": max_angle,
            "source": "servo_config",
        }
    except Exception:
        return {
            "configured": False,
            "min": 0,
            "max": 180,
            "source": "default",
        }


def _workspace_clamp_servo_angle(servo_index, requested_angle):
    limit = _workspace_servo_limit_for(servo_index)
    clamped_angle = max(int(limit["min"]), min(int(limit["max"]), int(requested_angle)))
    return clamped_angle, {
        "servo": int(servo_index),
        "requested_angle": int(requested_angle),
        "clamped_angle": int(clamped_angle),
        "clamped": int(clamped_angle) != int(requested_angle),
        "limit_min": int(limit["min"]),
        "limit_max": int(limit["max"]),
        "limit_source": limit["source"],
        "limit_configured": bool(limit["configured"]),
        "table_edge_guard": "servo_limit_clamp",
    }


def _execute_servo_move(
    servo,
    requested_angle,
    *,
    source="unknown",
    request_id=None,
    page=None,
    client_timestamp=None,
    dry_run=False,
):
    request_id = request_id or uuid.uuid4().hex
    angle, safety = _workspace_clamp_servo_angle(servo, requested_angle)
    audit = {
        "request_id": str(request_id),
        "source": str(source or "unknown"),
        "page": page,
        "client_timestamp": client_timestamp,
        "server_timestamp": utc_now_iso(),
        "servo": int(servo),
        "requested_angle": int(requested_angle),
        "angle": int(angle),
        "safety": safety,
    }

    if dry_run:
        update_serial_runtime(
            "move_dry_run_validated",
            source=audit["source"],
            request_id=audit["request_id"],
            page=page,
            servo=servo,
            requested_angle=requested_angle,
            clamped_angle=angle,
            clamped=safety["clamped"],
        )
        return jsonify({
            "status": "ok",
            "dry_run": True,
            "no_motion": True,
            "sent": f"MOVE {servo} {angle}",
            "audit": audit,
            "safety": safety,
        }), 200

    serial_connection = get_serial_connection()
    if not serial_connection or not serial_connection.is_open:
        print("? Serial port not available")
        update_serial_runtime(
            "move_serial_unavailable",
            source=audit["source"],
            request_id=audit["request_id"],
            page=page,
            error="Serial port unavailable",
        )
        return jsonify({"status": "error", "message": "Serial port unavailable"}), 500

    command = f"MOVE {servo} {angle}\n"
    with SERIAL_MOVE_LOCK:
        discarded = ""
        if getattr(serial_connection, "in_waiting", 0) > 0:
            try:
                discard_bytes = serial_connection.read(min(int(serial_connection.in_waiting), 256))
                discarded = discard_bytes.decode("utf-8", errors="replace").strip()
            except Exception as e:
                discarded = f"<discard read failed: {e}>"
            update_serial_runtime(
                "move_input_buffer_discarded",
                source=audit["source"],
                request_id=audit["request_id"],
                page=page,
                discarded=discarded,
            )

        update_serial_runtime(
            "move_command_sent",
            source=audit["source"],
            request_id=audit["request_id"],
            page=page,
            command=command.strip(),
        )
        append_move_trace("move_sent", {
            "source": audit["source"],
            "request_id": audit["request_id"],
            "page": page,
            "servo": int(servo),
            "requested_angle": int(requested_angle),
            "angle": int(angle),
            "command": command.strip(),
        })
        print(f"?? Sending to Arduino: {command.strip()} | source={audit['source']} request_id={audit['request_id']}")

        serial_connection.write(command.encode('utf-8'))
        serial_connection.flush()

        timeout = time.time() + 3
        response = ""
        while time.time() < timeout:
            if serial_connection.in_waiting > 0:
                try:
                    response = serial_connection.readline().decode('utf-8').strip()
                    print(f"?? Arduino replied: {response}")
                    if response == "DONE":
                        snapshot = load_last_position_snapshot()
                        if not isinstance(snapshot, list):
                            snapshot = [90, 90, 90, 90, 90, 50]
                        if len(snapshot) < 6:
                            snapshot = list(snapshot) + [90] * (6 - len(snapshot))
                        snapshot[int(servo)] = int(angle)
                        save_last_position_snapshot(snapshot)
                        update_serial_runtime(
                            "move_command_ack",
                            ack=True,
                            source=audit["source"],
                            request_id=audit["request_id"],
                            page=page,
                        )
                        append_move_trace("move_ack", {
                            "source": audit["source"],
                            "request_id": audit["request_id"],
                            "page": page,
                            "servo": int(servo),
                            "angle": int(angle),
                            "ack": response,
                        })
                        return jsonify({
                            "status": "ok",
                            "sent": command.strip(),
                            "safety": safety,
                            "audit": audit,
                        }), 200
                    print(f"[WARN] Arduino response not DONE: {response}")
                except UnicodeDecodeError as ue:
                    print(f"?? Decode error: {ue}")
                    continue
            time.sleep(0.01)

    print(f"?? Timeout: Arduino did not respond with DONE. Last response: '{response}'")
    update_serial_runtime(
        "move_timeout",
        source=audit["source"],
        request_id=audit["request_id"],
        page=page,
        error=f"Arduino did not confirm movement. Last response: '{response}'",
    )
    append_move_trace("move_timeout", {
        "source": audit["source"],
        "request_id": audit["request_id"],
        "page": page,
        "servo": int(servo),
        "angle": int(angle),
        "last_response": response,
    })
    return jsonify({
        "status": "timeout",
        "message": f"Arduino did not confirm movement. Last response: '{response}'",
        "audit": audit,
    }), 504


@routes.route('/move', methods=['POST'])
def move_servo():
    try:
        data = request.get_json()
        print(f"?? /move: {data}")

        if not data or 'servo' not in data or 'angle' not in data:
            print("? Invalid payload")
            return jsonify({"status": "error", "message": "Invalid request"}), 400

        servo = int(data['servo'])
        requested_angle = int(data['angle'])
        source = data.get('source', 'unknown')
        request_id = data.get('request_id') or request.headers.get('X-MIM-Request-Id')
        page = data.get('page') or request.headers.get('X-MIM-Page')
        client_timestamp = data.get('timestamp')
        dry_run = bool(data.get("dry_run") or data.get("no_motion") or data.get("validate_only"))
        return _execute_servo_move(
            servo,
            requested_angle,
            source=source,
            request_id=request_id,
            page=page,
            client_timestamp=client_timestamp,
            dry_run=dry_run,
        )

    except Exception as e:
        print(f"?? Exception during /move: {e}")
        update_serial_runtime("move_exception", error=str(e))
        return jsonify({"status": "error", "message": f"Exception: {str(e)}"}), 500

@routes.route('/set_speed', methods=['POST'])



def set_speed():



    data = request.get_json()



    if not data or 'speed' not in data:



        return jsonify({"status": "error", "message": "Missing speed"}), 400



    global movement_speed



    movement_speed = int(data['speed'])



    print(f"Speed set to: {movement_speed}ms")



    return jsonify({"status": "ok", "speed": movement_speed})







@routes.route('/load_config')



def load_config():



    import json



    try:



        with open('servo_config.json', 'r') as f:



            config = json.load(f)



        return jsonify(config)



    except Exception as e:



        return jsonify({'error': str(e)}), 500







@routes.route('/latest_detections')



def latest_detections():



    import json



    try:



        with open('object_memory.json', 'r') as f:



            memory = json.load(f)



        return jsonify(memory)



    except Exception as e:



        return jsonify({'error': str(e)}), 500















@routes.route('/set_safe', methods=['POST'])



def set_safe():



    """Accepts a JSON payload with safe positions and saves them."""



    data = request.get_json()



    if not data or 'safe' not in data:



        return jsonify({"status": "error", "message": "Invalid safe position data"}), 400



    safe_pos = data['safe']



    if not isinstance(safe_pos, list) or len(safe_pos) != 6:



        return jsonify({"status": "error", "message": "Safe position must be a list of 6 values"}), 400



    try:



        save_safe_position(safe_pos)



        print(f"Safe position set to: {safe_pos}")



        return jsonify({"status": "ok", "message": "Safe position saved", "safe": safe_pos}), 200



    except Exception as e:



        return jsonify({"status": "error", "message": f"Failed to save safe position: {e}"}), 500


@routes.route('/get_safe_position', methods=['GET'])
def get_safe_position():
    """Returns the currently saved canonical safe position without moving hardware."""
    try:
        safe_pos = load_safe_position()
        if not isinstance(safe_pos, list) or len(safe_pos) != 6:
            return jsonify({"status": "error", "message": "No valid safe position saved."}), 404
        return jsonify({"status": "ok", "safe": safe_pos}), 200
    except Exception as e:
        return jsonify({"status": "error", "message": f"Failed to load safe position: {e}"}), 500







@routes.route('/save_routine', methods=['POST'])



def save_routine():



    data = request.get_json()



    if not data or 'name' not in data or 'keyframes' not in data:



        return jsonify({"status": "error", "message": "Invalid routine format"}), 400







    try:



        routines = load_routines()



        routine_name = data['name']







        # Optional fields



        data.setdefault('description', "")



        data.setdefault('delay', 0.5)







        # Save/update



        routines[routine_name] = {



            "name": routine_name,



            "description": data["description"],



            "keyframes": data["keyframes"],



            "delay": data["delay"]



        }







        save_routines(routines)



        print(f"? Saved routine '{routine_name}' with {len(data['keyframes'])} frames.")



        return jsonify({"status": "ok", "message": "Routine saved."}), 200



    except Exception as e:



        print(f"? Failed to save routine: {e}")



        return jsonify({"status": "error", "message": str(e)}), 500











@routes.route('/list_routines', methods=['GET'])



def list_routines():



    try:



        routines = load_routines()



        print(f"?? Returning {len(routines)} routines.")



        summary = [



            {



                "name": r["name"],



                "description": r.get("description", ""),



                "keyframe_count": len(r.get("keyframes", [])),



                "delay": r.get("delay", 0.5)



            }



            for r in routines.values()



        ]



        return jsonify({"status": "ok", "routines": summary}), 200



    except Exception as e:



        print(f"? Error listing routines: {e}")



        return jsonify({"status": "error", "message": str(e)}), 500



















@routes.route('/go_safe', methods=['POST'])
def go_safe():
    """Commands the arm to move all servos to the safe position."""
    data = request.get_json(silent=True) or {}
    try:
        requested_duration_ms = int(data.get('move_duration_ms', 1540))
    except Exception:
        requested_duration_ms = 1540
    requested_duration_ms = max(40, min(5000, requested_duration_ms))

    safe_pos = load_safe_position()
    current_pos = load_last_position_snapshot()
    if not isinstance(current_pos, list) or len(current_pos) < 6:
        current_pos = [90, 90, 90, 90, 90, 50]
    current_pos = [int(v) for v in current_pos[:6]]

    for servo, target in enumerate(safe_pos):
        start = int(current_pos[servo])
        end = int(target)
        diff = end - start
        distance = abs(diff)
        if distance <= 2:
            segments = 1
        elif distance <= 20:
            segments = 2
        elif distance <= 45:
            segments = 3
        elif distance <= 75:
            segments = 4
        else:
            segments = 5

        # Respect requested Move Duration by pacing the staged safe-position segments.
        step_duration_ms = max(70, round(requested_duration_ms / max(1, segments)))
        for segment in range(1, segments + 1):
            step_started = time.time()
            step_target = round(start + (diff * (segment / segments)))
            try:
                result, status = _execute_servo_move(
                    servo,
                    step_target,
                    source="safe_position",
                    request_id=uuid.uuid4().hex,
                    page="/go_safe",
                )
                if status != 200:
                    print(f"[WARN] Safe move failed for servo {servo}: {result.get_json(silent=True) if hasattr(result, 'get_json') else result}")
            except Exception as e:
                print(f"Error moving servo {servo}: {e}")
            if segment < segments:
                elapsed_ms = (time.time() - step_started) * 1000.0
                wait_ms = step_duration_ms - elapsed_ms
                if wait_ms > 0:
                    time.sleep(wait_ms / 1000.0)
        current_pos[servo] = end

    save_last_position_snapshot(safe_pos)
    return jsonify({"status": "ok", "safe": safe_pos}), 200

@routes.route('/play_routine', methods=['POST'])
def play_routine():
    data = request.get_json()
    name = data.get('name')

    routines = load_routines()

    if isinstance(routines, dict):
        routine = routines.get(name)
        if isinstance(routine, dict) and 'name' not in routine:
            routine = {**routine, 'name': name}
    else:
        routine = next((r for r in routines if isinstance(r, dict) and r.get('name') == name), None)

    if not routine:
        return jsonify({"status": "error", "message": "Routine not found"}), 404

    delay = float(routine.get('delay', 1))

    for frame in routine.get('keyframes', []):
        for servo, angle in enumerate(frame):
            try:
                result, status = _execute_servo_move(
                    servo,
                    angle,
                    source="routine_playback",
                    request_id=uuid.uuid4().hex,
                    page=f"/play_routine:{name}",
                )
                if status != 200:
                    snapshot = load_last_position_snapshot()
                    if not isinstance(snapshot, list) or len(snapshot) < 6:
                        snapshot = [90, 90, 90, 90, 90, 50]
                    snapshot = [int(v) for v in snapshot[:6]]
                    snapshot[servo] = int(angle)
                    save_last_position_snapshot(snapshot)
                    print(f"[WARN] Arduino response not DONE: {result.get_json(silent=True) if hasattr(result, 'get_json') else result}")
            except Exception as e:
                print(f"[ERROR] during routine: {e}")

        time.sleep(delay)

    return jsonify({"status": "ok", "message": f"Routine '{name}' executed."}), 200

@routes.route('/reconnect', methods=['POST'])



def reconnect():



    serial_connection = get_serial_connection()







    # Try to close and re-open serial



    if serial_connection and serial_connection.is_open:



        try:



            serial_connection.close()

            update_serial_runtime("serial_closed_for_reconnect")



            time.sleep(1)



        except Exception:



            pass







    # Re-detect ports



    port_candidates = glob.glob('/dev/ttyACM*') + glob.glob('/dev/ttyUSB*')



    if not port_candidates:

        update_serial_runtime("reconnect_no_ports", error="No Arduino found")



        return jsonify({"status": "error", "message": "No Arduino found."}), 500







    try:



        shared.ser = serial.Serial(port_candidates[0], 9600, timeout=1)



        servo_driver.set_serial_connection(shared.ser)

        update_serial_runtime("reconnect_success", command=f"open:{port_candidates[0]}")



        time.sleep(2)
        # Reconnect should only restore the serial link.

        # Movement must remain explicit and operator-initiated.

        return jsonify({"status": "ok", "message": "Reconnected serial link.", "serial_ready": is_serial_ready()}), 200



    except Exception as e:

        update_serial_runtime("reconnect_exception", error=str(e))



        return jsonify({"status": "error", "message": str(e)}), 500











@routes.route('/arm_state', methods=['GET'])



def arm_state():



    settings = {

        "MIM_MODE": "unknown",

        "MIM_SIM": "off",

    }

    camera_payload = {
        "status": "ok",
        "depthai_device_bound": False,
        "video_queue_ready": False,
        "detection_pipeline_enabled": False,
        "detection_stream_configured": False,
        "detections_queue_ready": False,
        "frame_counter": 0,
        "last_frame_age_seconds": None,
        "detection_pipeline_error": None,
    }

    serial_payload = serial_health_payload()

    sim_enabled = str(settings.get("MIM_SIM", "off")).lower() == "on"

    mode_name = settings.get("MIM_MODE", "unknown")

    runtime_mode = "sim" if sim_enabled else "live"

    pose = load_last_position_snapshot()

    last_error = serial_payload.get("controller_error") or camera_payload.get("detection_pipeline_error")

    last_command_result = {

        "last_command_sent": serial_payload.get("last_command_sent"),

        "last_command_sent_at": serial_payload.get("last_command_sent_at"),

        "last_command_ack_at": serial_payload.get("last_command_ack_at"),

        "acks_total": serial_payload.get("serial_ack_count"),

        "commands_total": serial_payload.get("serial_command_count"),

    }

    return jsonify({

        "status": "ok",

        "app_alive": True,

        "mode": mode_name,

        "runtime": runtime_mode,

        "sim_enabled": sim_enabled,

        "camera": camera_payload,

        "serial": serial_payload,

        "estop": {

            "supported": False,

            "active": None,

        },

        "current_pose": pose,

        "last_error": last_error,

        "last_command_result": last_command_result,

    }), 200





@routes.route('/servo_config', methods=['GET'])



def get_servo_config():



    try:



        config = load_servo_config()



        return jsonify({ "servos": config })  # ? wrapped in "servos"



    except Exception as e:



        return jsonify({ "error": str(e) }), 500











@routes.route('/save_servo_config', methods=['POST'])



def save_servo_config():



    try:



        data = request.get_json()



        servos = data.get("servos")







        if not isinstance(servos, list):



            return jsonify({"status": "error", "message": "Invalid format"}), 400







        # ? Save the raw array directly



        with open("servo_config.json", "w") as f:



            json.dump(servos, f, indent=2)







        return jsonify({"status": "ok", "message": "Servo config saved."}), 200



    except Exception as e:



        return jsonify({"status": "error", "message": str(e)}), 500



    



@routes.route('/workspace_map.json')



def serve_workspace_map():



    try:



        with open("workspace_map.json", "r") as f:



            return jsonify(json.load(f))



    except Exception as e:



        return jsonify({"error": str(e)}), 404


def _default_workspace_setup_state():
    return {
        "version": 1,
        "units": "mm",
        "table": {
            "width": 508,
            "depth": 508,
            "height": 508,
            "thickness": 25.4,
            "origin": {"x": 0, "y": 0, "z": 0},
        },
        "mim_base": {
            "footprint_width": 210.06,
            "footprint_depth": 210.06,
            "height": 119.89,
            "position": {"x": 0, "y": 0, "z": 0},
            "locked": False,
        },
        "arm": {
            "links": {
                "base_to_shoulder": 119.89,
                "upper_arm": 180.09,
                "forearm": 169.93,
                "wrist": 89.92,
                "claw": 80.01,
            },
            "joint_map": {
                "base": 0,
                "shoulder": 1,
                "elbow": 2,
                "wrist": 3,
                "hand": 4,
                "claw": 5,
            },
            "visual_calibration": {
                "front_offset_deg": 0,
                "mesh_scale": 1,
                "shoulder_offset_deg": 0,
                "forearm_offset_deg": 0,
                "wrist_offset_deg": 0,
                "wrist_range_deg": 270,
                "base_range_deg": 270,
                "joint_offsets_deg": {},
            },
        },
        "obstacles": [],
        "walls": [],
        "markers": [],
    }


@routes.route('/workspace_setup_state', methods=['GET', 'POST'])
def workspace_setup_state():
    path = "workspace_setup.json"

    if request.method == 'POST':
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict):
            return jsonify({"status": "error", "message": "Invalid workspace setup payload."}), 400

        try:
            with open(path, 'w') as f:
                json.dump(payload, f, indent=2)
            return jsonify({"status": "ok", "message": "Workspace setup saved."}), 200
        except Exception as e:
            return jsonify({"status": "error", "message": f"Failed to save workspace setup: {e}"}), 500

    try:
        if os.path.exists(path):
            with open(path, 'r') as f:
                data = json.load(f)
        else:
            data = _default_workspace_setup_state()
            with open(path, 'w') as f:
                json.dump(data, f, indent=2)
        return jsonify(data), 200
    except Exception as e:
        return jsonify({"status": "error", "message": f"Failed to load workspace setup: {e}"}), 500



















@config_bp.route('/save_mim_config', methods=['POST'])



def save_mim_config():



    data = request.get_json()



    key = data.get("key")



    value = data.get("value") or data.get("angles")







    if not key or value is None:



        return jsonify({"status": "error", "message": "Missing key or value"}), 400







    config = load_json_file(CONFIG_FILE, {})







    config[key] = value







    save_json_file(CONFIG_FILE, config)







    return jsonify({"status": "ok", "message": f"Saved '{key}' to config."})





@config_bp.route('/get_mim_config', methods=['GET'])



def get_mim_config():



    config = load_json_file(CONFIG_FILE, {})

    if not isinstance(config, dict):

        config = {}

    if "mount_type" not in config:

        config["mount_type"] = "table"

    return jsonify(config), 200





















