# camera_routes.py
# Camera, perception, and object-memory routes for the live Pi app.
# This module also performs import-time DepthAI setup, so its startup behavior
# is coupled to module import order.
from flask import Blueprint, Response, jsonify, redirect, url_for, request
import depthai as dai
import time
import numpy as np
import cv2
from vision.object_tracker import ObjectTracker
from vision.workspace_calibrator import WorkspaceCalibrator
from model_manager import ModelManager
from object_memory_manager import load_memory, save_memory, add_to_memory
from arm_controller import move_to_angles, get_safe_positions
import os
from datetime import datetime, timezone
import json
from face_memory_manager import match_face, add_face
import face_recognition
import speech_recognition as sr
from model_loader import get_model_path, get_input_size
from mim_state_manager import load_context

camera_bp = Blueprint('camera_bp', __name__)
camera_serial = None  # placeholder
mm = ModelManager()

LIVE_CAMERA_ACTIVE = True
last_frame_ts = None
frame_counter = 0
CAPTURE_FRAME_OUTPUT_DIR = os.getenv("MIM_CAPTURE_FRAME_OUTPUT_DIR", "static/captures")

# Thermal/throughput guardrails for sustained runtime on Pi-class hardware.
# Default to camera streaming without continuous detections; enable the detection
# pipeline explicitly only when MIM actively needs object perception.
CAMERA_MAX_FPS = float(os.getenv("MIM_CAMERA_MAX_FPS", "4"))
CAMERA_PROCESS_MAX_FPS = float(os.getenv("MIM_CAMERA_PROCESS_MAX_FPS", str(CAMERA_MAX_FPS)))
CAMERA_IDLE_SLEEP_SECONDS = float(os.getenv("MIM_CAMERA_IDLE_SLEEP_SECONDS", "0.08"))
CAMERA_DETECTIONS_EVERY_N = max(1, int(os.getenv("MIM_CAMERA_DETECTIONS_EVERY_N", "4")))
CAMERA_JPEG_QUALITY = max(40, min(95, int(os.getenv("MIM_CAMERA_JPEG_QUALITY", "55"))))
CAMERA_QUEUE_MAX_SIZE = max(1, int(os.getenv("MIM_CAMERA_QUEUE_MAX_SIZE", "1")))
CAMERA_SENSOR_RESOLUTION = os.getenv("MIM_CAMERA_SENSOR_RESOLUTION", "1080p").strip().lower()
CAMERA_DISPLAY_SOURCE = os.getenv("MIM_CAMERA_DISPLAY_SOURCE", "video").strip().lower()
CAMERA_DISPLAY_ROTATION = os.getenv("MIM_CAMERA_DISPLAY_ROTATION", "none").strip().lower()
CAMERA_VIDEO_SIZE = (
    max(160, int(os.getenv("MIM_CAMERA_VIDEO_WIDTH", "1280"))),
    max(120, int(os.getenv("MIM_CAMERA_VIDEO_HEIGHT", "960"))),
)
UNKNOWN_CAPTURE_COOLDOWN_SECONDS = float(os.getenv("MIM_UNKNOWN_CAPTURE_COOLDOWN_SECONDS", "8"))
unknown_capture_cooldowns = {}
DEPTHAI_RECONNECT_COOLDOWN_SECONDS = float(os.getenv("MIM_DEPTHAI_RECONNECT_COOLDOWN_SECONDS", "5"))
depthai_last_connect_attempt_ts = 0.0
depthai_connect_error = None

object_model = mm.get_model("object_detection")
model_path = object_model["path"]
input_size = object_model["input_size"]
labels = object_model["labels"]

DETECTIONS_ENABLED = os.getenv("MIM_ENABLE_DETECTIONS_PIPELINE", "off").strip().lower() in ("1", "true", "on", "yes")
detections_stream_available = False
detections_pipeline_error = None

print(f"ðŸ” Loading model at {model_path} with input {input_size}")

pipeline = dai.Pipeline()
cam_rgb = pipeline.create(dai.node.ColorCamera)
cam_rgb.setPreviewSize(*input_size)  # e.g., (640, 352)
try:
    cam_rgb.setVideoSize(*CAMERA_VIDEO_SIZE)
except Exception as e:
    print(f"Unable to apply camera video size {CAMERA_VIDEO_SIZE}: {e}")
cam_rgb.setInterleaved(False)
if CAMERA_SENSOR_RESOLUTION in ("1080p", "the_1080_p"):
    cam_rgb.setResolution(dai.ColorCameraProperties.SensorResolution.THE_1080_P)
else:
    cam_rgb.setResolution(dai.ColorCameraProperties.SensorResolution.THE_720_P)

try:
    cam_rgb.setIspScale(1, 1)
except Exception as e:
    print(f"Unable to apply camera ISP scale 1:1: {e}")
try:
    cam_rgb.setFps(CAMERA_MAX_FPS)
except Exception as e:
    print(f"âš ï¸ Unable to apply camera FPS throttle ({CAMERA_MAX_FPS}): {e}")

if DETECTIONS_ENABLED:
    try:
        detection_nn = pipeline.create(dai.node.YoloDetectionNetwork)
        detection_nn.setBlobPath(model_path)
        detection_nn.setConfidenceThreshold(object_model.get("confidence_threshold", 0.25))
        detection_nn.setIouThreshold(object_model.get("iou_threshold", 0.5))
        detection_nn.setNumClasses(int(object_model.get("num_classes", max(1, len(labels)))))
        detection_nn.setCoordinateSize(4)

        anchors = object_model.get("anchors")
        if anchors:
            detection_nn.setAnchors(anchors)
        else:
            detection_nn.setAnchors([
                10,13, 16,30, 33,23,
                30,61, 62,45, 59,119,
                116,90, 156,198, 373,326
            ])

        anchor_masks = object_model.get("anchor_masks")
        if anchor_masks:
            detection_nn.setAnchorMasks(anchor_masks)
        else:
            detection_nn.setAnchorMasks({
                "side52": [0,1,2],
                "side26": [3,4,5],
                "side13": [6,7,8]
            })

        cam_rgb.preview.link(detection_nn.input)

        xout_nn = pipeline.create(dai.node.XLinkOut)
        xout_nn.setStreamName("detections")
        detection_nn.out.link(xout_nn.input)
        detections_stream_available = True
    except Exception as e:
        detections_pipeline_error = str(e)
        print(f"âš ï¸ Detection pipeline disabled due to setup error: {e}")

# xout_video = pipeline.create(dai.node.XLinkOut)
# xout_video.setStreamName("video")
# cam_rgb.preview.link(xout_video.input)

# xout_nn = pipeline.create(dai.node.XLinkOut)
# xout_nn.setStreamName("detections")
# try:
#     device = dai.Device(pipeline)
#     video_q = device.getOutputQueue(name="video", maxSize=4, blocking=False)
#     detections_q = device.getOutputQueue(name="detections", maxSize=4, blocking=False)
# except RuntimeError as e:
#     print(f"âŒ Camera device not found: {e}")
#     device = None
#     video_q = None
#     detections_q = None

xout_video = pipeline.create(dai.node.XLinkOut)
xout_video.setStreamName("video")
if CAMERA_DISPLAY_SOURCE == "preview":
    cam_rgb.preview.link(xout_video.input)
else:
    cam_rgb.video.link(xout_video.input)

device = None
video_q = None
detections_q = None


def prepare_display_frame(frame):
    if CAMERA_DISPLAY_ROTATION in ("left90", "90ccw", "counterclockwise"):
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    if CAMERA_DISPLAY_ROTATION in ("right90", "90cw", "clockwise"):
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if CAMERA_DISPLAY_ROTATION in ("180", "flip"):
        return cv2.rotate(frame, cv2.ROTATE_180)
    return frame


def connect_depthai(force=False):
    global device, video_q, detections_q, depthai_last_connect_attempt_ts, depthai_connect_error, detections_pipeline_error
    now_ts = time.time()
    if (not force) and (now_ts - depthai_last_connect_attempt_ts < DEPTHAI_RECONNECT_COOLDOWN_SECONDS):
        return False

    depthai_last_connect_attempt_ts = now_ts

    if device is not None:
        try:
            device.close()
        except Exception:
            pass

    device = None
    video_q = None
    detections_q = None

    try:
        device = dai.Device(pipeline)
        video_q = device.getOutputQueue(name="video", maxSize=CAMERA_QUEUE_MAX_SIZE, blocking=False)
        if detections_stream_available:
            try:
                detections_q = device.getOutputQueue(name="detections", maxSize=CAMERA_QUEUE_MAX_SIZE, blocking=False)
            except Exception as e:
                detections_q = None
                detections_pipeline_error = str(e)
                print(f"âš ï¸ Detection queue unavailable: {e}")

        depthai_connect_error = None
        print("âœ… DepthAI camera connected")
        return True
    except Exception as e:
        depthai_connect_error = str(e)
        print(f"âš ï¸ DepthAI connect failed: {e}")
        return False


def capture_single_frame():
    global last_frame_ts, frame_counter, video_q, detections_q, device, depthai_connect_error

    if video_q is None:
        connect_depthai(force=True)

    if video_q is None:
        return {
            "status": "error",
            "message": "Camera is not connected.",
            "depthai_connect_error": depthai_connect_error,
        }

    deadline = time.time() + 4.0
    frame_packet = None
    while time.time() < deadline:
        try:
            frame_packet = video_q.tryGet()
        except Exception as e:
            depthai_connect_error = str(e)
            device = None
            video_q = None
            detections_q = None
            connect_depthai(force=True)
            time.sleep(CAMERA_IDLE_SLEEP_SECONDS)
            continue

        if frame_packet is not None:
            break

        time.sleep(CAMERA_IDLE_SLEEP_SECONDS)

    if frame_packet is None:
        return {
            "status": "error",
            "message": "Timed out waiting for a camera frame.",
            "depthai_connect_error": depthai_connect_error,
        }

    while True:
        newer_packet = video_q.tryGet()
        if newer_packet is None:
            break
        frame_packet = newer_packet

    frame = prepare_display_frame(frame_packet.getCvFrame())
    encode_ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), CAMERA_JPEG_QUALITY])
    if not encode_ok:
        return {
            "status": "error",
            "message": "Failed to encode captured frame.",
        }

    captured_at = datetime.now(timezone.utc)
    os.makedirs(CAPTURE_FRAME_OUTPUT_DIR, exist_ok=True)
    file_name = f"capture_{captured_at.strftime('%Y%m%dT%H%M%SZ')}.jpg"
    output_path = os.path.join(CAPTURE_FRAME_OUTPUT_DIR, file_name)
    encoded_bytes = encoded.tobytes()

    with open(output_path, "wb") as handle:
        handle.write(encoded_bytes)

    frame_counter += 1
    last_frame_ts = time.time()

    return {
        "status": "ok",
        "message": "Capture frame completed.",
        "captured_at": captured_at.isoformat(),
        "file_name": file_name,
        "output_path": output_path,
        "frame_counter": int(frame_counter),
        "jpeg_bytes": len(encoded_bytes),
        "frame_shape": list(frame.shape),
        "camera_display_source": CAMERA_DISPLAY_SOURCE,
        "camera_display_rotation": CAMERA_DISPLAY_ROTATION,
        "camera_video_size": list(CAMERA_VIDEO_SIZE),
        "camera_ready": bool(device and video_q),
        "detection_pipeline_enabled": bool(DETECTIONS_ENABLED),
    }


connect_depthai(force=True)

tracker = ObjectTracker()
calibrator = WorkspaceCalibrator()

UNKNOWN_DIR = "static/objects_unknown"
KNOWN_DIR = "static/objects_known"
os.makedirs(UNKNOWN_DIR, exist_ok=True)
os.makedirs(KNOWN_DIR, exist_ok=True)


# returns the current servo angles, placeholder for actual servo controller integration
def get_current_servo_angles():
    # TODO: integrate with actual servo controller
    return [90] * 6  # placeholder angles


def map_zone(cx, cy, bounds):
    if bounds is None:
        return "unknown"
    x1, y1, x2, y2 = bounds
    width_third = (x2 - x1) / 3
    height_third = (y2 - y1) / 3
    zone_y = int((cy - y1) / height_third)
    zone_x = int((cx - x1) / width_third)
    return f"zone-{zone_x}-{zone_y}"


def generate_frames():
    global last_frame_ts, frame_counter, video_q, detections_q, device
    last_detections = []
    last_yield_ts = 0.0
    min_frame_interval = 1.0 / max(0.5, CAMERA_PROCESS_MAX_FPS)
    while True:
        if video_q is None:
            connect_depthai()

            frame = np.zeros((480, 640, 3), dtype=np.uint8)
            cv2.putText(frame, "Camera not connected", (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 1, (255,255,255), 2)
            ret, buffer = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), CAMERA_JPEG_QUALITY])
            frame_bytes = buffer.tobytes()
            last_frame_ts = time.time()
            frame_counter += 1
            yield (b"--frame\r\n"
                   b"Content-Type: image/jpeg\r\n\r\n" + frame_bytes + b"\r\n")
            time.sleep(1)
            continue

        try:
            frame_packet = video_q.tryGet()
        except Exception as e:
            print(f"âš ï¸ Video queue read failed; forcing reconnect: {e}")
            device = None
            video_q = None
            detections_q = None
            depthai_connect_error = str(e)
            time.sleep(CAMERA_IDLE_SLEEP_SECONDS)
            continue

        if frame_packet is None:
            time.sleep(CAMERA_IDLE_SLEEP_SECONDS)
            continue

        while True:
            newer_packet = video_q.tryGet()
            if newer_packet is None:
                break
            frame_packet = newer_packet

        now_ts = time.time()
        since_last_yield = now_ts - last_yield_ts
        if since_last_yield < min_frame_interval:
            time.sleep(max(CAMERA_IDLE_SLEEP_SECONDS, min_frame_interval - since_last_yield))

        frame = frame_packet.getCvFrame()

        if detections_q and (frame_counter % CAMERA_DETECTIONS_EVERY_N == 0):
            det_packet = detections_q.tryGet()
            if det_packet is not None:
                last_detections = det_packet.detections
        detections = last_detections

        tracked = tracker.update(detections, frame.shape)
        frame = calibrator.detect_and_draw(frame)

        if calibrator.bounds and detections:
            x1_ws, y1_ws, x2_ws, y2_ws = calibrator.bounds
            memory = load_memory()
            updated = False

            for det in detections:
                class_id = det.label
                confidence = det.confidence
                x1 = int(det.xmin * frame.shape[1])
                y1 = int(det.ymin * frame.shape[0])
                x2 = int(det.xmax * frame.shape[1])
                y2 = int(det.ymax * frame.shape[0])
                cx = (x1 + x2) // 2
                cy = (y1 + y2) // 2

                if not (x1_ws <= cx <= x2_ws and y1_ws <= cy <= y2_ws):
                    continue

                label = labels[class_id] if class_id < len(labels) else "unknown"
                uncommon_labels = {"tie", "tv", "keyboard", "book", "cell phone"}
                is_unknown = label in uncommon_labels or confidence < 0.30

                if is_unknown:
                    capture_key = f"unknown:{cx}:{cy}"
                    now_ts = time.time()
                    last_saved_at = unknown_capture_cooldowns.get(capture_key, 0.0)
                    if (now_ts - last_saved_at) < UNKNOWN_CAPTURE_COOLDOWN_SECONDS:
                        continue

                    roi = frame[y1:y2, x1:x2]
                    filename = f"unknown_{cx}_{cy}.jpg"
                    filepath = os.path.join(UNKNOWN_DIR, filename)
                    if not os.path.exists(filepath):
                        cv2.imwrite(filepath, roi)

                        entry = {
                            "label": "unknown",
                            "image": f"static/objects_unknown/{filename}",
                            "position": [cx, cy],
                            "zone": map_zone(cx, cy, calibrator.bounds),
                            "confidence": confidence,
                            "origin": "unidentified",
                            "timestamp": datetime.now().isoformat(),
                            "center": {"x": cx, "y": cy},
                            "movable": None
                        }
                        memory.append(entry)
                        updated = True
                    unknown_capture_cooldowns[capture_key] = now_ts

                else:
                    # Only add if not already present in memory near that spot
                    exists = any(
                        obj["label"] == label and abs(obj["center"]["x"] - cx) < 20 and abs(obj["center"]["y"] - cy) < 20
                        for obj in memory
                    )

                    if not exists:
                        roi = frame[y1:y2, x1:x2]
                        filename = f"{label.replace(' ', '_')}_{cx}_{cy}.jpg"
                        filepath = os.path.join(KNOWN_DIR, filename)
                        if not os.path.exists(filepath):
                            cv2.imwrite(filepath, roi)

                        entry = {
                            "label": label,
                            "image": f"objects_known/{filename}",
                            "position": [cx, cy],
                            "zone": map_zone(cx, cy, calibrator.bounds),
                            "confidence": confidence,
                            "origin": "model",
                            "timestamp": datetime.now().isoformat(),
                            "center": {"x": cx, "y": cy},
                            "movable": None
                        }
                        memory.append(entry)
                        updated = True

            if updated:
                save_memory(memory)

        for obj in tracked:
            coords = obj.get('coords', {})
            bbox = coords.get('bbox')
            if not bbox:
                continue
            x1 = int(bbox[0] * frame.shape[1])
            y1 = int(bbox[1] * frame.shape[0])
            x2 = int(bbox[2] * frame.shape[1])
            y2 = int(bbox[3] * frame.shape[0])
            cx = (x1 + x2) // 2
            cy = (y1 + y2) // 2
            zone = map_zone(cx, cy, calibrator.bounds)

            obj['zone'] = zone
            label = f"{obj['label']} ({zone})"

            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.putText(frame, label, (x1 + 4, y1 - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)

        frame = prepare_display_frame(frame)
        ret, buffer = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), CAMERA_JPEG_QUALITY])
        if not ret:
            continue
        last_frame_ts = time.time()
        last_yield_ts = last_frame_ts
        frame_counter += 1
        yield (b'--frame\r\n'
               b'Content-Type: image/jpeg\r\n\r\n' + buffer.tobytes() + b'\r\n')
        time.sleep(CAMERA_IDLE_SLEEP_SECONDS)


#### recongnition ####
def build_pipeline(role):
    """
    Builds a DepthAI pipeline based on the role ('object_detection', 'face_detection', etc.).
    Requires role to exist in model_config.json.
    """
    model_path = get_model_path(role)
    input_size = get_input_size(role)  # (width, height)

    print(f"ðŸ“¦ Building pipeline for {role}")
    print(f"ðŸ”— Model path: {model_path}")
    print(f"ðŸ“ Input size: {input_size}")

    pipeline = dai.Pipeline()

    # Create camera
    cam_rgb = pipeline.create(dai.node.ColorCamera)
    cam_rgb.setPreviewSize(*input_size)
    if CAMERA_SENSOR_RESOLUTION in ("1080p", "the_1080_p"):
        cam_rgb.setResolution(dai.ColorCameraProperties.SensorResolution.THE_1080_P)
    else:
        cam_rgb.setResolution(dai.ColorCameraProperties.SensorResolution.THE_720_P)
    cam_rgb.setInterleaved(False)

    # Output for preview (used for motion detection)
    xout_preview = pipeline.create(dai.node.XLinkOut)
    xout_preview.setStreamName("preview")
    cam_rgb.preview.link(xout_preview.input)

    # Attach neural network (if specified)
    if model_path.endswith(".blob"):
        detection_nn = pipeline.create(dai.node.YoloDetectionNetwork)
        detection_nn.setBlobPath(model_path)
        detection_nn.setConfidenceThreshold(0.5)
        detection_nn.setNumClasses(80)  # Default YOLO, override if needed
        detection_nn.setCoordinateSize(4)
        detection_nn.setIouThreshold(0.5)
        detection_nn.setAnchorBoxes([], [], [])
        detection_nn.setAnchors([])

        cam_rgb.preview.link(detection_nn.input)

        xout_nn = pipeline.create(dai.node.XLinkOut)
        xout_nn.setStreamName("detections")
        detection_nn.out.link(xout_nn.input)

    return pipeline


def listen_for_name():
    r = sr.Recognizer()
    with sr.Microphone() as source:
        print("Listening...")
        audio = r.listen(source)
    try:
        return r.recognize_google(audio)
    except Exception:
        return None


@camera_bp.route('/face_scan', methods=['POST'])
def face_scan():
    frame = video_q.get().getCvFrame()
    face_locations = face_recognition.face_locations(frame)
    encodings = face_recognition.face_encodings(frame, face_locations)

    results = []
    for loc, encoding in zip(face_locations, encodings):
        match = match_face(encoding)
        if match:
            results.append({"name": match['name'], "status": "known"})
        else:
            # Save unknown face as temp image
            top, right, bottom, left = loc
            face_img = frame[top:bottom, left:right]
            filename = f"faces/temp_{datetime.now().timestamp()}.jpg"
            cv2.imwrite(filename, face_img)
            results.append({
                "name": None,
                "status": "unknown",
                "embedding": encoding[:8].tolist(),  # pass short preview for debug
                "image": filename
            })

    return jsonify({"faces": results})







#### Object management ####

@camera_bp.route('/label_unknown', methods=['POST'])
def label_unknown():
    filename = request.form['filename']
    label = request.form['label']
    color = request.form.get('color')
    shape = request.form.get('shape')
    x = int(request.form.get('x', 0))
    y = int(request.form.get('y', 0))

    zone = map_zone(x, y, calibrator.bounds)
    add_to_memory(label, filename, [x, y], zone=zone, color=color, shape=shape)
    return redirect(url_for('camera_bp.camera_feed'))  # or object memory view

@camera_bp.route('/set_movable/<label>', methods=['POST'])
def set_movable(label):
    memory = load_memory()
    for obj in memory:
        if obj['label'] == label:
            obj['movable'] = True
            obj['servo_snapshot'] = get_current_servo_angles()
            obj['timestamp'] = datetime.now().isoformat()
            break
    save_memory(memory)
    return jsonify({"status": "movable set"})

@camera_bp.route('/set_unmovable/<label>', methods=['POST'])
def set_unmovable(label):
    memory = load_memory()
    for obj in memory:
        if obj['label'] == label:
            obj['movable'] = False
            obj['timestamp'] = datetime.now().isoformat()
            break
    save_memory(memory)
    return jsonify({"status": "unmovable set"})



@camera_bp.route('/camera_feed')
def camera_feed():
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')


@camera_bp.route('/camera_health')
def camera_health():
    serial_open = bool(camera_serial and getattr(camera_serial, 'is_open', False))
    frame_age = None
    if last_frame_ts:
        frame_age = round(time.time() - last_frame_ts, 3)
    return jsonify({
        "status": "ok",
        "depthai_device_bound": bool(device),
        "video_queue_ready": bool(video_q),
        "detections_queue_ready": bool(detections_q),
        "camera_max_fps": CAMERA_MAX_FPS,
        "camera_process_max_fps": CAMERA_PROCESS_MAX_FPS,
        "camera_detections_every_n": CAMERA_DETECTIONS_EVERY_N,
        "camera_idle_sleep_seconds": CAMERA_IDLE_SLEEP_SECONDS,
        "camera_jpeg_quality": CAMERA_JPEG_QUALITY,
        "camera_queue_max_size": CAMERA_QUEUE_MAX_SIZE,
        "camera_sensor_resolution": CAMERA_SENSOR_RESOLUTION,
        "camera_display_source": CAMERA_DISPLAY_SOURCE,
        "camera_display_rotation": CAMERA_DISPLAY_ROTATION,
        "camera_video_size": list(CAMERA_VIDEO_SIZE),
        "detection_pipeline_enabled": bool(DETECTIONS_ENABLED),
        "detection_stream_configured": bool(detections_stream_available),
        "detection_pipeline_error": detections_pipeline_error,
        "depthai_connect_error": depthai_connect_error,
        "camera_serial_connected": serial_open,
        "live_camera_active": bool(LIVE_CAMERA_ACTIVE),
        "camera_max_fps": CAMERA_MAX_FPS,
        "camera_process_max_fps": CAMERA_PROCESS_MAX_FPS,
        "camera_idle_sleep_seconds": CAMERA_IDLE_SLEEP_SECONDS,
        "camera_detections_every_n": CAMERA_DETECTIONS_EVERY_N,
        "camera_queue_max_size": CAMERA_QUEUE_MAX_SIZE,
        "camera_sensor_resolution": CAMERA_SENSOR_RESOLUTION,
        "camera_display_source": CAMERA_DISPLAY_SOURCE,
        "camera_display_rotation": CAMERA_DISPLAY_ROTATION,
        "camera_video_size": list(CAMERA_VIDEO_SIZE),
        "frame_counter": int(frame_counter),
        "last_frame_age_seconds": frame_age
    })


@camera_bp.route('/capture_frame', methods=['POST'])
def capture_frame():
    payload = capture_single_frame()
    status_code = 200 if payload.get("status") == "ok" else 503
    return jsonify(payload), status_code

@camera_bp.route('/workspace_bounds')
def workspace_bounds():
    if calibrator.bounds is None:
        return jsonify({"status": "error", "message": "Not calibrated."})
    return jsonify({"status": "ok", "bounds": calibrator.bounds})

@camera_bp.route('/object_memory')
def object_memory():
    try:
        memory = load_memory() + tracker.get_tracked()
        # Pre-serialize to catch bad fields
        json.dumps(memory)  # will throw if unserializable
        return jsonify({"status": "ok", "objects": memory})
    except Exception as e:
        print("âŒ JSON serialization failed:", e)
        return jsonify({"status": "error", "message": str(e)}), 500


@camera_bp.route('/clear_object_memory', methods=['POST'])
def clear_object_memory():
    from object_memory_manager import save_memory
    save_memory([])  # Reset to empty list
    return jsonify({"status": "cleared"})

@camera_bp.route('/label_unknown', methods=['GET'])
def show_label_unknown():
    from flask import request, render_template
    image = request.args.get("image", "")
    return render_template("label_unknown.html", image=image)

@camera_bp.route('/update_object_entry', methods=['POST'])
def update_object_entry():
    from flask import request, jsonify
    data = request.get_json()
    memory = load_memory()
    found = False

    for obj in memory:
        if obj.get("image", "").endswith(data["image"]):
            obj["label"] = data["label"]
            obj["zone"] = data["zone"]
            obj["color"] = data.get("color")
            obj["shape"] = data.get("shape")
            obj["movable"] = data.get("movable")
            obj["origin"] = "user-labeled"
            found = True
            break

    if found:
        save_memory(memory)
        return jsonify({"status": "updated"})
    else:
        return jsonify({"status": "not found"}), 404


####  independant MIM actions ####

@camera_bp.route('/start_exploration', methods=['POST'])
def start_exploration():

    steps = get_safe_positions()  # e.g., [[90,90,90,90,90,90], [90,100,90,...]]
    for angles in steps:
        move_to_angles(angles)
        time.sleep(1.5)
        # capture frame automatically via generate_frames()

    return jsonify({"status": "exploration complete"})
