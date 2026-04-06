# mim_arm/app.py
# Live Flask entrypoint for the Pi-hosted MIM ARM application.
# This file still coordinates boot phases, hardware probing, route registration,
# and background worker startup in one place.

# source mimenv/bin/activate

# python3 app.py



import os

import json

import time

import glob

import serial

import atexit

import threading

from flask import Flask, redirect

from startup_routine_routes import startup_bp

from routes import routes

from camera_routes import camera_bp

from chat_routes import chat_bp

from shared import load_routines, save_routines, load_safe_position

import shared

from config_paths import app_path

from dotenv import load_dotenv

from settings_routes import settings_bp

from diagnostics_routes import diagnostics_bp

import camera_routes

import servo_driver

from voice_routes import voice_bp

from routes import config_bp



load_dotenv(str(app_path(".env")))



os.environ["MIM_MODE"] = "production"  # or "development"





def register_blueprints(flask_app):

    flask_app.register_blueprint(routes)

    flask_app.register_blueprint(camera_bp)

    flask_app.register_blueprint(chat_bp)

    flask_app.register_blueprint(startup_bp)

    flask_app.register_blueprint(settings_bp)

    flask_app.register_blueprint(diagnostics_bp)

    flask_app.register_blueprint(voice_bp)

    flask_app.register_blueprint(config_bp)





def print_routes(flask_app, heading="📋 Active Routes:"):

    print(heading)

    for rule in flask_app.url_map.iter_rules():

        print(f"{rule.endpoint:25s} -> {rule.rule}")



# ----------------------------------------

# Flask App Initialization

# ----------------------------------------

app = Flask(__name__, template_folder="templates")

register_blueprints(app)



print_routes(app)





# ----------------------------------------

# Serial Port Detection & Setup

# ----------------------------------------

camera_serial = None

latest_camera_detection = {}



def detect_arduino():

    ports = glob.glob('/dev/ttyACM*') + glob.glob('/dev/ttyUSB*')

    for port in ports:

        try:

            ser = serial.Serial(port, 9600, timeout=1)

            time.sleep(1)

            ser.write(b"MOVE 0 90\n")

            time.sleep(0.5)

            if ser.in_waiting:

                resp = ser.readline().decode().strip()

                if "DONE" in resp:

                    print(f"✅ Arduino detected on {port}")

                    return ser

            ser.close()

        except Exception as e:

            print(f"⚠️ Error probing {port}: {e}")

            continue

    print("❌ Arduino not found.")

    return None



def detect_camera(exclude_port=None):

    ports = glob.glob('/dev/ttyACM*') + glob.glob('/dev/ttyUSB*')

    for port in ports:

        if port == exclude_port:

            continue

        try:

            cam = serial.Serial(port, 115200, timeout=1)

            time.sleep(2)

            cam.flushInput()

            cam.write(b"ping\n")

            time.sleep(0.5)

            line = cam.readline().decode(errors='ignore').strip()

            if line.startswith("{") or "CANMV" in line or "freq:" in line:

                print(f"✅ Vision camera detected on {port}")

                return cam

            cam.close()

        except Exception as e:

            print(f"⚠️ Error probing camera on {port}: {e}")

            continue

    print("⚠️ Vision camera not found.")

    return None





def initialize_controller_connection():

    shared.ser = detect_arduino()

    servo_driver.set_serial_connection(shared.ser)

    print(f"🔗 shared.ser = {shared.ser}")

    print(f"🔗 shared.ser.is_open = {shared.ser.is_open if shared.ser else 'None'}")





def initialize_camera_connection():

    global camera_serial

    camera_serial = detect_camera(shared.ser.port if shared.ser else None)

    camera_routes.camera_serial = camera_serial



initialize_controller_connection()

initialize_camera_connection()



# ----------------------------------------

# Camera Serial Reader Thread

# ----------------------------------------

def listen_to_camera():

    global latest_camera_detection

    if not camera_serial:

        return

    print("📡 Listening to camera serial...")

    while True:

        try:

            line = camera_serial.readline().decode(errors='ignore').strip()

            if line.startswith("{"):

                try:

                    latest_camera_detection = json.loads(line)

                    print("📥 Vision:", latest_camera_detection)

                except json.JSONDecodeError:

                    pass

        except Exception as e:

            print(f"❌ Camera read error: {e}")

            time.sleep(0.5)





def start_camera_listener():

    if camera_serial:

        cam_thread = threading.Thread(target=listen_to_camera, daemon=True)

        cam_thread.start()





start_camera_listener()



# ----------------------------------------

# Cleanup

# ----------------------------------------

@atexit.register

def cleanup():

    if shared.ser and shared.ser.is_open:

        print("🔌 Closing Arduino serial connection...")

        shared.ser.close()

    else:

        print("⚠️ No Arduino serial connection to close.")

    if camera_serial and camera_serial.is_open:

        print("🔌 Closing camera serial connection...")

        camera_serial.close()

    else:

        print("⚠️ No camera serial connection to close.")





def preload_saved_data():

    print("📦 Preloading saved data...")



    try:

        routines = load_routines()

        save_routines(routines)  # Write back dict-format if needed

        print(f"✅ Loaded {len(routines)} routines.")

    except Exception as e:

        print(f"❌ Error loading routines: {e}")



    try:

        safe_pos = load_safe_position()

        print(f"✅ Safe position loaded: {safe_pos}")

    except Exception as e:

        print(f"❌ Error loading safe position: {e}")



# ----------------------------------------

# Data Preloading

# ----------------------------------------

preload_saved_data()







# ----------------------------------------

# Launch App

# ----------------------------------------

@app.route('/')

def home_redirect():

    return redirect('/settings')









if __name__ == '__main__':

    print("🚀 Starting MIM app...")

    print("🌐 Access at: http://localhost:5000 or http://<your-pi-ip>:5000")

    print_routes(app, heading="\n📋 Registered routes:")



    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)



