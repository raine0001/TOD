# routes.py



# Main UI and control route module for the live Pi app.



# This file currently mixes page rendering, runtime state updates, persistence,



# and direct serial control paths.



from flask import Blueprint, request, jsonify, render_template, send_from_directory, Response



import serial



import glob



import time



import json
from datetime import datetime, timezone



from shared import movement_speed, load_safe_position, save_safe_position, load_routines, save_routines, load_servo_config
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
}


def utc_now_iso():

    return datetime.now(timezone.utc).isoformat()


def get_serial_connection():

    return shared.ser



def is_serial_ready():

    serial_connection = get_serial_connection()

    return bool(serial_connection and serial_connection.is_open)


def update_serial_runtime(event: str, command: str = None, ack: bool = False, error: str = None):

    now = time.time()

    serial_runtime["last_serial_event"] = event

    serial_runtime["last_serial_event_ts"] = now

    serial_runtime["last_serial_event_at"] = utc_now_iso()

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

    return Response(status=204)







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



            print("⚠️ /ping: serial not open")

            update_serial_runtime("ping_serial_not_open")



            return jsonify({"ok": False}), 200



    except Exception as e:



        print("❌ /ping error:", e)

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



        print(f"❌ Error reading last_position.json: {e}")



        return jsonify({"status": "default", "angles": [90, 90, 90, 90, 90, 50]})







@routes.route('/move', methods=['POST'])



def move_servo():



    try:



        data = request.get_json()



        print(f"📥 /move: {data}")







        if not data or 'servo' not in data or 'angle' not in data:



            print("❌ Invalid payload")



            return jsonify({"status": "error", "message": "Invalid request"}), 400







        servo = int(data['servo'])



        angle = int(data['angle'])







        serial_connection = get_serial_connection()



        if not serial_connection or not serial_connection.is_open:



            print("❌ Serial port not available")

            update_serial_runtime("move_serial_unavailable", error="Serial port unavailable")



            return jsonify({"status": "error", "message": "Serial port unavailable"}), 500







        command = f"MOVE {servo} {angle}\n"

        update_serial_runtime("move_command_sent", command=command.strip())



        print(f"➡️ Sending to Arduino: {command.strip()}")







        serial_connection.reset_input_buffer()  # 🔄 Clear old responses



        serial_connection.write(command.encode('utf-8'))



        serial_connection.flush()







        timeout = time.time() + 3



        response = ""



        while time.time() < timeout:



            if serial_connection.in_waiting > 0:



                try:



                    response = serial_connection.readline().decode('utf-8').strip()



                    print(f"⬅️ Arduino replied: {response}")



                    if response == "DONE":

                        update_serial_runtime("move_command_ack", ack=True)
                        return jsonify({"status": "ok", "sent": command.strip()}), 200
                    print(f"[WARN] Arduino response not DONE: {response}")



                except UnicodeDecodeError as ue:



                    print(f"⚠️ Decode error: {ue}")



                    continue



            time.sleep(0.01)  # 🧘‍♂️ Prevent CPU burn







        print(f"⚠️ Timeout: Arduino did not respond with DONE. Last response: '{response}'")
        update_serial_runtime("move_timeout", error=f"Arduino did not confirm movement. Last response: '{response}'")



        return jsonify({



            "status": "timeout",



            "message": f"Arduino did not confirm movement. Last response: '{response}'"



        }), 504







    except Exception as e:



        print(f"🔥 Exception during /move: {e}")
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



        print(f"✅ Saved routine '{routine_name}' with {len(data['keyframes'])} frames.")



        return jsonify({"status": "ok", "message": "Routine saved."}), 200



    except Exception as e:



        print(f"❌ Failed to save routine: {e}")



        return jsonify({"status": "error", "message": str(e)}), 500











@routes.route('/list_routines', methods=['GET'])



def list_routines():



    try:



        routines = load_routines()



        print(f"📄 Returning {len(routines)} routines.")



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



        print(f"❌ Error listing routines: {e}")



        return jsonify({"status": "error", "message": str(e)}), 500



















@routes.route('/go_safe', methods=['POST'])



def go_safe():



    """Commands the arm to move all servos to the safe position."""



    safe_pos = load_safe_position()



    serial_connection = get_serial_connection()



    for servo, angle in enumerate(safe_pos):



        command = f"MOVE {servo} {angle}\n"



        if serial_connection and serial_connection.is_open:



            try:



                serial_connection.write(command.encode('utf-8'))



                serial_connection.flush()



                print(f"Sent: {command.strip()}")







                # Wait for Arduino ACK



                try:



                    ack = serial_connection.readline().decode().strip()



                    if ack != "DONE":



                        print(f"[WARN] Unexpected response. Expected 'DONE', got: {ack}")



                except Exception as e:



                    print(f"[ERROR] Failed waiting for ACK: {e}")







            except Exception as e:



                print(f"Error moving servo {servo}: {e}")



    return jsonify({"status": "ok", "safe": safe_pos}), 200







@routes.route('/save_shutdown_routine', methods=['POST'])



def save_shutdown_routine():



    try:



        safe = load_safe_position()



        shutdown_steps = [



            [90, 90, 90, 90, 90, 125],  # Open claw



            [90, 80, 90, 90, 90, 125],  # Raise shoulder



            safe                        # Safe pos



        ]







        shutdown_routine = {



            "name": "__shutdown__",



            "description": "Auto shutdown sequence: claw open, shoulder raise, return to safe.",



            "keyframes": shutdown_steps,



            "delay": 0.6



        }







        routines = load_routines()



        # Replace old __shutdown__ if exists



        routines = [r for r in routines if r["name"] != "__shutdown__"]



        routines.append(shutdown_routine)



        save_routines(routines)







        return jsonify({"status": "ok", "message": "Shutdown routine saved."}), 200



    except Exception as e:



        return jsonify({"status": "error", "message": str(e)}), 500











# run shutdown



@routes.route('/shutdown_sequence', methods=['POST'])



def shutdown_sequence():



    try:



        # Load safe position



        safe = load_safe_position()



        steps = [



            [90, 90, 90, 90, 90, 125],  # 1. Open claw slightly



            [90, 80, 90, 90, 90, 125],  # 2. Raise shoulder slightly



            safe                        # 3. Safe position



        ]







        # Run each step with 600ms delay between



        serial_connection = get_serial_connection()



        for step in steps:



            for servo, angle in enumerate(step):



                command = f"MOVE {servo} {angle}\n"



                if serial_connection and serial_connection.is_open:



                    serial_connection.write(command.encode('utf-8'))



                    serial_connection.flush()



                    time.sleep(0.06)  # ~60ms per servo, total 600ms/step



            time.sleep(0.6)







        return jsonify({"status": "ok", "message": "Shutdown routine completed"}), 200



    except Exception as e:



        return jsonify({"status": "error", "message": str(e)}), 500











# delete a saved routine



@routes.route('/delete_routine', methods=['POST'])



def delete_routine():



    data = request.get_json()



    name = data.get('name')



    routines = load_routines()



    routines = [r for r in routines if r['name'] != name]



    save_routines(routines)



    return jsonify({"status": "ok", "message": "Deleted routine."}), 200







@routes.route('/load_routine', methods=['POST'])



def load_routine():



    data = request.get_json()

    name = data.get('name')



    routines = load_routines()







    routine = routines.get(name)



    if not routine:



        return jsonify({"status": "error", "message": "Routine not found."}), 404







    return jsonify({"status": "ok", "routine": routine}), 200







# Save draft routines during keyframe creation



@routes.route('/autosave_routine', methods=['POST'])



def autosave_routine():



    data = request.get_json()



    if not data or 'keyframes' not in data:



        return jsonify({"status": "error", "message": "Missing keyframes"}), 400



    try:



        from shared import save_autosave



        save_autosave(data)



        return jsonify({"status": "ok", "message": "Autosave stored."}), 200



    except Exception as e:



        return jsonify({"status": "error", "message": str(e)}), 500











#reorder routines



@routes.route('/reorder_routines', methods=['POST'])



def reorder_routines():



    data = request.get_json()



    name = data.get('name')



    direction = data.get('direction')  # 'up' or 'down'







    routines = load_routines()



    index = next((i for i, r in enumerate(routines) if r['name'] == name), -1)







    if index == -1:



        return jsonify({"status": "error", "message": "Routine not found"}), 404







    if direction == 'up' and index > 0:



        routines[index], routines[index - 1] = routines[index - 1], routines[index]



    elif direction == 'down' and index < len(routines) - 1:



        routines[index], routines[index + 1] = routines[index + 1], routines[index]



    else:



        return jsonify({"status": "error", "message": "Cannot move in that direction"}), 400







    save_routines(routines)



    return jsonify({"status": "ok", "message": "Routine reordered"}), 200











# play saved routine



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



    serial_connection = get_serial_connection()



    for frame in routine.get('keyframes', []):



        for servo, angle in enumerate(frame):



            command = f"MOVE {servo} {angle}\n"



            if serial_connection and serial_connection.is_open:



                try:



                    serial_connection.write(command.encode('utf-8'))



                    serial_connection.flush()



                    time.sleep(0.05)



                    response = serial_connection.readline().decode().strip()



                    print(f"[DEBUG] Arduino responded: '{response}'")



                    if response != "DONE":

                        print(f"[WARN] Arduino response not DONE: {response}")



                except Exception as e:



                    print(f"[ERROR] during routine: {e}")



        time.sleep(delay)







    return jsonify({"status": "ok", "message": f"Routine '{name}' executed."}), 200







#  route to manage reconnection upon lost communication



@routes.route('/reconnect', methods=['POST'])



def reconnect():



    serial_connection = get_serial_connection()







    # Try to close and re-open serial



    if serial_connection and serial_connection.is_open:



        try:



            serial_connection.close()

            update_serial_runtime("serial_closed_for_reconnect")



            time.sleep(1)



        except:



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



        safe_pos = load_safe_position()







        # Slowly move each servo to safe position



        for servo, angle in enumerate(safe_pos):



            command = f"MOVE {servo} {angle}\n"



            shared.ser.write(command.encode('utf-8'))



            shared.ser.flush()



            time.sleep(0.1)







        return jsonify({"status": "ok", "message": "Reconnected and reset arm.", "safe": safe_pos, "serial_ready": is_serial_ready()}), 200



    except Exception as e:

        update_serial_runtime("reconnect_exception", error=str(e))



        return jsonify({"status": "error", "message": str(e)}), 500











@routes.route('/arm_state', methods=['GET'])



def arm_state():



    settings = {

        "MIM_MODE": "unknown",

        "MIM_SIM": "off",

    }

    try:

        from settings_routes import load_env_settings

        settings = load_env_settings()

    except Exception as e:

        update_serial_runtime("arm_state_settings_error", error=str(e))

    camera_payload = {

        "status": "unknown",

        "depthai_device_bound": False,

        "video_queue_ready": False,

        "detection_pipeline_enabled": False,

        "detection_stream_configured": False,

        "detections_queue_ready": False,

        "frame_counter": 0,

        "last_frame_age_seconds": None,

        "detection_pipeline_error": None,

    }

    try:

        import camera_routes

        frame_age = None

        if getattr(camera_routes, "last_frame_ts", None):

            frame_age = round(time.time() - camera_routes.last_frame_ts, 3)

        camera_payload = {

            "status": "ok",

            "depthai_device_bound": bool(getattr(camera_routes, "device", None)),

            "video_queue_ready": bool(getattr(camera_routes, "video_q", None)),

            "detection_pipeline_enabled": bool(getattr(camera_routes, "DETECTIONS_ENABLED", False)),

            "detection_stream_configured": bool(getattr(camera_routes, "detections_stream_available", False)),

            "detections_queue_ready": bool(getattr(camera_routes, "detections_q", None)),

            "frame_counter": int(getattr(camera_routes, "frame_counter", 0)),

            "last_frame_age_seconds": frame_age,

            "detection_pipeline_error": getattr(camera_routes, "detections_pipeline_error", None),

        }

    except Exception as e:

        camera_payload["status"] = "error"

        camera_payload["detection_pipeline_error"] = str(e)

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



        return jsonify({ "servos": config })  # ✅ wrapped in "servos"



    except Exception as e:



        return jsonify({ "error": str(e) }), 500











@routes.route('/save_servo_config', methods=['POST'])



def save_servo_config():



    try:



        data = request.get_json()



        servos = data.get("servos")







        if not isinstance(servos, list):



            return jsonify({"status": "error", "message": "Invalid format"}), 400







        # ✅ Save the raw array directly



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



















