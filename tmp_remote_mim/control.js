//control.js

/********************************************
 * Global Variables and Helpers
 ********************************************/
// Servo angle tracking: [Base, Shoulder, Elbow, Wrist, Hand, Claw]
const currentServoAngles = { 0:90, 1:90, 2:90, 3:90, 4:90, 5:90 };

let currentRoutine = [];              // Array of keyframes
let currentRoutineName = null;        // Optional: name of currently loaded routine
let editingKeyframeIndex = null;      // Used for editing a specific keyframe
let isPaused = false;                 // Pause flag for routine playback
let stopPlayback = false;             // Stop flag for routine playback
let currentStepDisplay = null;        // DOM reference for showing current playback step
let routineDelay = 1000;              // Default movement delay (ms)

const debounceTimers = {};            // Debounce timers for each slider input
let serialReady = false;              // 🔌 Serial port ready flag
let pingAttempts = 0;
const maxPingAttempts = 10;

let easingEnabled = true;             // 🔄 Easing toggle
let hasInitializedMainUI = false;     // Prevent duplicate DOM bootstrap paths


/********************************************
 * Servo Setup: Config, UI Rendering, & Management
 ********************************************/

const maxServos = 16;
let activeServos = 0;
let servoConfigs = []; // Fetched from backend or fallback
const defaultConfigs = [
  { id: 0, label: "Base", left: "right", right: "left", min: 0, max: 180 },
  { id: 1, label: "Shoulder", left: "back", right: "forward", min: 0, max: 180 },
  { id: 2, label: "Elbow", left: "down", right: "up", min: 0, max: 180 },
  { id: 3, label: "Wrist", left: "turn left", right: "turn right", min: 0, max: 180 },
  { id: 4, label: "Hand", left: "left", right: "right", min: 0, max: 180 },
  { id: 5, label: "Claw", left: "close", right: "open", min: 0, max: 180 }
];

// 🧱 Create one servo control group
function addNewServo(config) {
  const { id, label, min, max } = config;

  const container = document.getElementById('servoContainer');
  const group = document.createElement('div');
  group.className = 'servo-group';
  group.innerHTML = `
    <label for="servo${id}">${label}
      <span class="angle-display" id="value${id}">90</span>°
    </label>
    <div class="nudge-controls">
      <button onclick="nudgeServo(${id}, -1)">◀</button>
      <input type="range" id="servo${id}" class="servo-slider" data-servo="${id}" min="${min}" max="${max}" value="90">
      <button onclick="nudgeServo(${id}, 1)">▶</button>
    </div>
    <div class="direction-labels">
      <span class="servo-dir-left">${config.left || min}</span>
      <span class="servo-dir-right" style="float:right;">${config.right || max}</span>
    </div>

  `;

  container.appendChild(group);
  currentServoAngles[id] = 90;
  setupSliderDebounce(id);
  activeServos++;
}

// ➕ Called when user clicks "Add New Servo"
function handleAddNewServo() {
  const id = servoConfigs.length;
  if (id >= maxServos) {
    alert("Maximum number of servos reached.");
    return;
  }

  const defaultConfig = {
    id,
    label: `Servo ${id}`,
    min: 0,
    max: 180
  };

  servoConfigs.push(defaultConfig);
  addNewServo(defaultConfig);
}

// 🚀 Setup servo UI from config JSON or fallback
function renderServosFromConfig(configs) {
  console.log("🔧 Rendering servos:", configs);
  const container = document.getElementById('servoContainer');
  console.log("📦 Servo container:", container);
  console.log("🔧 Rendering servos:", configs);
  document.getElementById('servoContainer').innerHTML = ''; // Clear first
  activeServos = 0;
  configs.forEach(cfg => addNewServo(cfg));
}

function renderServoConfigEditor(servos) {
  const tbody = document.getElementById('servoConfigEditorBody');
  if (!tbody) {
    console.warn("⚠️ servoConfigEditorBody not found in DOM.");
    return;
  }

  tbody.innerHTML = ''; // Clear existing rows

  if (!Array.isArray(servos)) {
    console.error("❌ Invalid servo config format:", servos);
    return;
  }

  servos.forEach((servo, i) => {
    const row = document.createElement('tr');
    row.innerHTML = `
      <td>${servo.id}</td>
      <td><input type="text" name="label-${i}" value="${servo.label || ''}"></td>
      <td><input type="text" name="left-${i}" value="${servo.left || ''}"></td>
      <td><input type="text" name="right-${i}" value="${servo.right || ''}"></td>
      <td><input type="number" name="min-${i}" value="${servo.min}" min="0" max="180"></td>
      <td><input type="number" name="max-${i}" value="${servo.max}" min="0" max="180"></td>
    `;
    tbody.appendChild(row);
  });
}


/********************************************
 * DOM Ready Bootstrap
 ********************************************/
// Legacy bootstrap is disabled by default; main bootstrap lives below.
if (window.__enableLegacyBootstrap === true) {
  console.log("✅ DOM loaded");

  // ▶ Pause Button
  const pauseBtn = document.createElement('button');
  pauseBtn.id = 'pauseBtn';
  pauseBtn.textContent = '⏸ Pause';
  pauseBtn.style.margin = '1rem auto';
  pauseBtn.style.display = 'block';
  pauseBtn.onclick = togglePlayPause;
  document.body.appendChild(pauseBtn);

  // ⏹ Stop Button
  const stopBtn = document.createElement('button');
  stopBtn.id = 'stopBtn';
  stopBtn.textContent = '⏹ Stop';
  stopBtn.style.margin = '0 auto';
  stopBtn.style.display = 'block';
  stopBtn.onclick = () => {
    isPaused = false;
    stopPlayback = true;
    const pauseBtn = document.getElementById('pauseBtn');
    if (pauseBtn) pauseBtn.textContent = '⏸ Pause';
  };
  document.body.appendChild(stopBtn);

  // 🌀 Easing Toggle
  const easingToggle = document.createElement('label');
  easingToggle.style.display = 'block';
  easingToggle.style.textAlign = 'center';
  easingToggle.style.margin = '1rem auto';
  easingToggle.innerHTML = `
    <input type="checkbox" id="easingToggle" style="margin-right: 6px;">
    Enable Acceleration Easing
  `;
  document.body.appendChild(easingToggle);

  // 🛠 Toggle Servo Config Editor Visibility
  const toggleConfigEditor = document.getElementById('toggleConfigEditor');
  if (toggleConfigEditor) {
    toggleConfigEditor.addEventListener('click', function () {
      const wrapper = document.getElementById('servoEditorWrapper');
      if (!wrapper) return;

      const visible = wrapper.style.display !== 'none';
      wrapper.style.display = visible ? 'none' : 'block';
      this.textContent = visible ? 'Show' : 'Hide';
    });
  }

  console.log("🔁 About to fetch servo_config");
  // 🔁 Fetch config and render sliders/editor
  fetch('/servo_config')
    .then(r => r.json())
    .then(data => {
      const config = data.servos || data;
      servoConfigs = config;
      renderServosFromConfig(config);
      renderServoConfigEditor(config);
    })
    .catch(err => {
      console.error("❌ Servo config fetch failed:", err);
      const fallback = [
        { id: 0, label: "Base", min: 0, max: 180 },
        { id: 1, label: "Shoulder", min: 0, max: 180 },
        { id: 2, label: "Elbow", min: 0, max: 180 },
        { id: 3, label: "Wrist", min: 0, max: 180 },
        { id: 4, label: "Hand", min: 0, max: 180 },
        { id: 5, label: "Claw", min: 0, max: 180 }
      ];
      servoConfigs = fallback;
      renderServosFromConfig(fallback);
      renderServoConfigEditor(fallback);
    });

  // 🔌 System checks
  checkArduinoStatus();
  loadSavedRoutines();

  // ⏳ Retry reconnect if needed
  setTimeout(() => {
    if (!serialReady) reconnectArm();
  }, 2000);
}




/********************************************
 * Serial Status Check
 ********************************************/
function checkArduinoStatus() {
  const statusEl = document.getElementById('connectionStatus');

  fetch('/ping')
    .then(res => res.json())
    .then(data => {
      if (data.ok) {
        console.log("✅ Arduino responsive");
        serialReady = true;
        enableSliderListeners();

        if (statusEl) {
          statusEl.innerHTML = "🟢 Arduino Connected";
          statusEl.style.color = "green";
        }
      } else {
        pingAttempts++;
        console.warn(`⚠️ Arduino not ready (attempt ${pingAttempts}/${maxPingAttempts})`);

        if (statusEl) {
          statusEl.innerHTML = `🟡 Connecting to Arduino... (attempt ${pingAttempts})`;
          statusEl.style.color = "goldenrod";
        }

        if (pingAttempts < maxPingAttempts) {
          setTimeout(checkArduinoStatus, 1000);
        } else {
          if (statusEl) {
            statusEl.innerHTML = "🔴 Arduino Unresponsive";
            statusEl.style.color = "red";
          }
          alert("❌ Arduino is not responding. Please check your connection.");
        }
      }
    })
    .catch(err => {
      pingAttempts++;
      console.error(`❌ Ping request failed (attempt ${pingAttempts}):`, err);

      if (statusEl) {
        statusEl.innerHTML = "🔴 Arduino Disconnected";
        statusEl.style.color = "red";
      }

      if (pingAttempts < maxPingAttempts) {
        setTimeout(checkArduinoStatus, 1000);
      } else {
        alert("❌ Unable to reach MIM. Is the app running?");
      }
    });
}




/********************************************
 * Utility Functions
 ********************************************/
function togglePlayPause() {
  const btn = document.getElementById('playPauseBtn');
  if (!btn) return;
  isPaused = !isPaused;
  btn.textContent = isPaused ? '▶' : '⏸';
}

function getSliderValues() {
  return [...document.querySelectorAll('.servo-slider')].map(s => parseInt(s.value));
}

function loadSlidersFromKeyframe(keyframe) {
  keyframe.forEach((angle, servo) => {
    const slider = document.getElementById('servo' + servo);
    const display = document.getElementById('value' + servo);
    if (slider && display) {
      slider.value = angle;
      display.textContent = angle;
      currentServoAngles[servo] = angle;
    }
  });
}

function updateProgressDisplay(step, total) {
  if (!currentStepDisplay) {
    currentStepDisplay = document.createElement('div');
    currentStepDisplay.id = 'routineProgress';
    currentStepDisplay.style.textAlign = 'center';
    currentStepDisplay.style.margin = '1rem 0';
    currentStepDisplay.setAttribute('aria-live', 'polite');
    currentStepDisplay.setAttribute('role', 'status');
    document.body.insertBefore(currentStepDisplay, document.querySelector('.section'));
  }

  currentStepDisplay.innerHTML = `<strong>Playing routine:</strong> Step ${step} of ${total}`;

  const timelineSlider = document.getElementById('routineTimeline');
  if (timelineSlider) {
    timelineSlider.max = total;
    timelineSlider.value = step;
  }

  const tbody = document.getElementById('savedPositionsTbody');
  if (tbody) {
    [...tbody.children].forEach((row, idx) => {
      row.style.backgroundColor = idx === step - 1 ? '#d2f4ff' : '';
    });
  }
}

/********************************************
 * Slider Debounce Hook for New Servos
 ********************************************/
function setupSliderDebounce(id) {
  const slider = document.getElementById('servo' + id);
  const display = document.getElementById('value' + id);
  if (!slider || !display) return;

  slider.disabled = false;
  slider.removeEventListener('input', slider._debouncedInput); // cleanup if exists

  const handler = () => {
    if (!serialReady) {
      console.warn("⛔ Servo ignored: serial not ready");
      return;
    }

    let targetAngle = parseFloat(slider.value);
    targetAngle = Math.max(0, Math.min(180, targetAngle));
    display.textContent = targetAngle;

    if (debounceTimers[id]) clearTimeout(debounceTimers[id]);

    const duration = parseInt(document.getElementById('moveSpeed').value || '500');
    debounceTimers[id] = setTimeout(() => {
      sendServoDirectly(id, targetAngle, duration);
    }, 200);
  };

  slider.addEventListener('input', handler);
  slider._debouncedInput = handler;
}

/********************************************
 * Enable all slider listeners
 ********************************************/
function enableSliderListeners() {
  document.querySelectorAll('.servo-slider').forEach(slider => {
    const id = parseInt(slider.getAttribute('data-servo'));
    setupSliderDebounce(id);
  });

  console.log("🎚️ Slider listeners (re)attached");
}



/********************************************
 * Servo Communication
 ********************************************/

// Clamp angle to safe range
function constrain(val, min, max) {
  return Math.max(min, Math.min(max, val));
}

// Update slider + label UI
function updateServoDisplay(servo, angle) {
  const slider = document.getElementById('servo' + servo);
  const display = document.getElementById('value' + servo);
  if (slider && display) {
    slider.value = angle;
    display.textContent = angle;
  }
  currentServoAngles[servo] = angle;
}

// Send move command to backend
function sendMove(servo, angle) {
  angle = constrain(angle, 0, 180);
  return fetch('/move', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ servo, angle })
  })
  .then(response => response.json())
  .then(data => {
    console.log(`Servo ${servo} updated:`, data);
    return data;
  })
  .catch(error => {
    console.error(`❌ Error sending command to servo ${servo}:`, error);
    return { status: "error", message: error.message };
  });
}


/********************************************
 * Send Command Logic
 ********************************************/
function sendServoDirectly(servo, angle, duration = 0) {
  angle = constrain(angle, 0, 180);
  if (duration > 0) {
    // Do not pre-update currentServoAngles before animation; animateServo uses
    // currentServoAngles as the start angle.
    animateServo(servo, angle, duration);
  } else {
    updateServoDisplay(servo, angle);
    sendMove(servo, angle);
  }
}

function nudgeServo(servo, delta) {
  const slider = document.getElementById('servo' + servo);
  const current = parseInt(slider.value, 10);
  const updated = constrain(current + delta, 0, 180);

  slider.value = updated;
  const duration = parseInt(document.getElementById('moveSpeed').value || '500');
  if (duration > 0) {
    animateServo(servo, updated, duration);
  } else {
    updateServoDisplay(servo, updated);
    sendMove(servo, updated);
  }
}


/********************************************
 * Servo Animation with Optional Easing
 ********************************************/
// Animate servo over time
function easeInOut(t) {
  return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
}

async function animateServo(servo, targetAngle, duration) {
  const startAngle = currentServoAngles[servo];
  const diff = targetAngle - startAngle;
  const absDiff = Math.abs(diff);

  if (absDiff === 0) return;

  // For tiny manual changes, send once to avoid visible repeated micro-motions.
  if (absDiff <= 2) {
    updateServoDisplay(servo, targetAngle);
    try {
      await sendMove(servo, targetAngle);
    } catch (err) {
      console.error(`Servo ${servo} failed during animation`, err);
    }
    return;
  }

  // Keep smoothing, but never exceed the number of distinct degree positions.
  const desiredSteps = Math.max(8, Math.ceil(duration / 40));
  const steps = Math.min(desiredSteps, absDiff);
  const stepDuration = Math.max(duration / steps, 10);
  let lastSent = startAngle;

  for (let i = 1; i <= steps; i++) {
    let progress = i / steps;
    if (easingEnabled) progress = easeInOut(progress);
    const intermediate = Math.round(startAngle + diff * progress);

    if (intermediate === lastSent) {
      continue;
    }
    lastSent = intermediate;

    updateServoDisplay(servo, intermediate);
    try {
      await sendMove(servo, intermediate);
    } catch (err) {
      console.error(`Servo ${servo} failed during animation`, err);
    }
    await new Promise(resolve => setTimeout(resolve, stepDuration));
  }
}


/********************************************
 * Playback Logic
 ********************************************/

function playRoutine(name) {
  if (name === "__shutdown__") return shutdownArm();

  if (!confirm(`Play routine "${name}" now?`)) return;

  fetch('/load_routine', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name })
  })
  .then(res => res.json())
  .then(data => {
    if (!data.routine || !Array.isArray(data.routine.keyframes) || data.routine.keyframes.length === 0) {
      alert("⚠️ Routine has no keyframes to play.");
      return;
    }

    const keyframes = data.routine.keyframes;
    const delay = parseFloat(data.routine.delay || 1);

    loadSlidersFromKeyframe(keyframes[0]); // Show starting pose
    isPaused = false;
    stopPlayback = false;

    playRoutineLocally(keyframes, delay);
  })
  .catch(err => {
    console.error('❌ Error loading or playing routine:', err.message || err);
    alert(`❌ Failed to play routine: ${err.message || err}`);
  });
  
}

async function playRoutineLocally(keyframes, delay) {
  // Use the speed slider value for playback speed, overriding the saved delay
  delay = parseInt(document.getElementById('moveSpeed').value || '500') / 1000;
  stopPlayback = false;
  console.log(`▶️ Playing routine with ${keyframes.length} steps`);
  const tbody = document.getElementById('savedPositionsTbody');
  if (tbody) [...tbody.children].forEach(row => row.style.backgroundColor = '');

  for (let i = 0; i < keyframes.length; i++) {
    if (stopPlayback) {
      console.log("🛑 Routine stopped");
      updateProgressDisplay(i, keyframes.length);
      return;
    }

    updateProgressDisplay(i + 1, keyframes.length);
    console.log(`➡️ Executing step ${i + 1}:`, keyframes[i]);

    for (let servo = 0; servo < keyframes[i].length; servo++) {
      await animateServo(servo, keyframes[i][servo], delay * 1000);
    }  

    loadSlidersFromKeyframe(keyframes[i]); // Reflect current step in UI

    // Wait for full delay if not paused
    let elapsed = 0;
    const fullDelay = delay * 1000;

    while (elapsed < fullDelay) {
      if (stopPlayback) return;
      if (!isPaused) {
        await new Promise(resolve => setTimeout(resolve, 100));
        elapsed += 100;
      } else {
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }
  }

  updateProgressDisplay(keyframes.length, keyframes.length);
  console.log("✅ Routine complete");
}

function togglePause() {
  isPaused = !isPaused;
  const btn = document.getElementById('pauseBtn');
  if (btn) btn.textContent = isPaused ? '▶ Resume' : '⏸ Pause';
}

function resumePlayback() {
  isPaused = false;
  const btn = document.getElementById('pauseBtn');
  if (btn) btn.textContent = '⏸ Pause';
}

function shutdownArm() {
  fetch('/shutdown_sequence', { method: 'POST' })
    .then(res => res.json())
    .then(data => {
      alert(data.message || 'Shutdown complete.');
    })
    .catch(err => {
      console.error('Shutdown error:', err);
      alert('Error during shutdown.');
    });
}


/********************************************
 * Routine Management (Save / Load / Reverse / Delete)
 ********************************************/

function saveRoutine(event) {
  event.preventDefault();  // Prevent page reload

  const routineName = document.getElementById('routineName').value.trim();
  const routineDesc = document.getElementById('routineDesc').value.trim();
  const delayVal = document.getElementById('groupDelay').value || 1;

  // Check: Keyframes must exist
  if (currentRoutine.length === 0) {
    alert("⚠️ No keyframes to save. Please record at least one.");
    return;
  }

  // Check: Name must be provided
  if (!routineName) {
    alert("⚠️ Please enter a routine name.");
    return;
  }

  const routine = {
    name: routineName,
    description: routineDesc,
    keyframes: currentRoutine,
    delay: delayVal
  };

  console.log("📝 Saving routine:", routine);

  fetch('/save_routine', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(routine)
  })
  .then(response => response.json())
  .then(data => {
    if (data.status === 'ok') {
      console.log(`✅ Routine "${routine.name}" saved.`);
      alert(`✅ Routine "${routine.name}" has been saved.`);
      currentRoutine = [];
      updateKeyframeTable();
      document.getElementById('routineForm').reset();
      loadSavedRoutines();
    } else {
      alert(`❌ Failed to save routine: ${data.message}`);
      console.error('Server error response:', data);
    }
  })
  .catch(error => {
    alert("❌ Error saving routine.");
    console.error('Error saving routine:', error);
  });
}


function loadSavedRoutines() {
  fetch('/list_routines')
    .then(r => r.json())
    .then(data => {
      const routineTable = document.getElementById('routineGroupTbody');
      if (!routineTable) {
        console.warn('routineGroupTbody not found; skipping routine table render');
        return;
      }
      routineTable.innerHTML = '';
      if (!data.routines) return;
      console.log("🧾 Loaded routines:", data.routines);


      data.routines
        // .filter(rt => !rt.name.startsWith('autosave_'))
        .forEach(rt => routineTable.innerHTML += generateRoutineRow(rt));
    })
    .catch(err => console.error('Failed to load routines:', err));
}

function generateRoutineRow(rt) {
  const routineName = rt.name;
  const safeName = routineName.replace(/'/g, "\\'");
  const keyframeCount = rt.keyframe_count || (Array.isArray(rt.keyframes) ? rt.keyframes.length : 0);  // ✅ FIXED
  const delay = rt.delay || 1;


  return `
    <tr>
      <td>${routineName}</td>
      <td>${rt.description || ''}</td>
      <td>${keyframeCount} positions</td>
      <td>${delay}</td>
      <td>
        <button class="action-btn" onclick="playRoutine('${safeName}')">Play</button>
        <button class="action-btn" onclick="loadRoutine('${safeName}')">Edit</button>
        <button class="action-btn" onclick="deleteRoutine('${safeName}')">Delete</button>
        <button class="action-btn" onclick="reorderRoutine('${safeName}', 'up')">⬆️</button>
        <button class="action-btn" onclick="reorderRoutine('${safeName}', 'down')">⬇️</button>
      </td>
    </tr>
  `;
}


function saveAutosaveRoutine() {
  if (currentRoutine.length === 0) {
    alert("⚠️ No keyframes to save. Please record at least one position.");
    return;
  }

  const rawName = document.getElementById('routineName').value.trim();
  const routineName = rawName !== '' ? rawName : `autosave_${Date.now()}`;
  const routineDesc = document.getElementById('routineDesc').value.trim();
  const delayVal = document.getElementById('groupDelay').value || 1;

  const routine = {
    name: routineName,
    description: routineDesc || "Auto-saved routine",
    keyframes: currentRoutine,
    delay: delayVal
  };

  fetch('/save_routine', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(routine)
  })
  .then(response => response.json())
  .then(data => {
    if (data.status === 'ok') {
      console.log(`✅ Routine "${routineName}" saved.`);
      alert(`Routine "${routineName}" has been saved.`);
      loadSavedRoutines();
    } else {
      alert(`❌ Failed to save routine: ${data.message}`);
    }
  })
  .catch(err => {
    console.error('Failed to update routine after keyframe edit:', err);
    alert('Error saving routine.');
  });
}

function reverseRoutine(name) {
  fetch('/load_routine', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name })
  })
  .then(res => res.json())
  .then(data => {
    if (!data.routine) {
      alert(`Routine "${name}" not found.`);
      return;
    }

    const original = data.routine;
    const reversedKeyframes = [...(original.keyframes || [])].map(frame => [...frame]).reverse();

    const reversedRoutine = {
      name: `reverse-${original.name}`,
      description: `Reversed version of "${original.name}"`,
      keyframes: reversedKeyframes,
      delay: original.delay || 1
    };

    fetch('/save_routine', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(reversedRoutine)
    })
    .then(r => r.json())
    .then(saveResult => {
      if (saveResult.status === "ok") {
        alert(`✅ Reverse routine saved as "${reversedRoutine.name}"`);
        loadSavedRoutines();
      } else {
        alert(`❌ Failed to save reverse routine: ${saveResult.message}`);
      }
    })
    .catch(err => {
      console.error("Error saving reversed routine:", err);
      alert("Error saving reversed routine.");
    });
  });
}

function reorderRoutine(name, direction) {
  fetch('/reorder_routines', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, direction })
  })
  .then(res => res.json())
  .then(data => {
    if (data.status === "ok") {
      loadSavedRoutines();
    } else {
      alert(data.message);
    }
  })
  .catch(err => console.error('Error reordering routine:', err));
}

function loadRoutine(name) {
  fetch('/load_routine', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name })
  })
  .then(r => r.json())
  .then(data => {
    if (data.routine) {
      currentRoutine = data.routine.keyframes || [];
      updateKeyframeTable();
      document.getElementById('routineName').value = data.routine.name;
      document.getElementById('routineDesc').value = data.routine.description || '';
      document.getElementById('groupDelay').value = data.routine.delay || 1;
      loadSlidersFromKeyframe(currentRoutine[0]);
      alert(`Routine "${name}" loaded for editing.`);
    }
  })
  .catch(err => {
    console.error('Failed to load routine:', err);
    alert('Error loading routine');
  });
}

function deleteRoutine(name) {
  if (!confirm(`Delete routine "${name}"?`)) return;

  fetch('/delete_routine', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name })
  })
  .then(() => loadSavedRoutines())
  .catch(err => console.error('Failed to delete:', err));
}

/********************************************
 * view page helpers. index.html
 ********************************************/
function loadServoControls() {
  fetch('/load_config')
    .then(res => res.json())
    .then(config => {
      const container = document.getElementById('servo-controls');
      container.innerHTML = '';

      for (const [id, servo] of Object.entries(config)) {
        const block = document.createElement('div');
        block.innerHTML = `
          <label><strong>${servo.label}</strong> &nbsp;
            <small>(${servo.direction})</small>
          </label><br>
          <input type="range" id="slider-${id}" min="${servo.min}" max="${servo.max}" value="${servo.value}">
          <span id="value-${id}">${servo.value}</span>
          <br><br>
        `;
        container.appendChild(block);

        const slider = block.querySelector(`#slider-${id}`);
        const valueLabel = block.querySelector(`#value-${id}`);

        slider.addEventListener('input', () => {
          valueLabel.textContent = slider.value;
          sendServoCommand(id, slider.value);
        });
      }
    })
    .catch(err => {
      document.getElementById('servo-controls').innerHTML = '<p style="color:red;">⚠️ Failed to load servo config</p>';
    });
}

function sendServoCommand(servoId, angle) {
  fetch(`/move_servo/${servoId}/${angle}`)
    .catch(() => console.warn(`Failed to move ${servoId} to ${angle}`));
}

function loadActionButtons() {
  const container = document.getElementById('action-buttons');
  container.innerHTML = '';

  const buttons = [
    { label: 'Record Current Position', action: '/record_position' },
    { label: 'Save Safe Position', action: '/save_safe_position' },
    { label: 'Run Subroutine Routine', action: '/run_subroutine' },
    { label: 'Rearm/Reset', action: '/reset_arm' }
  ];

  buttons.forEach(btn => {
    const el = document.createElement('button');
    el.className = 'btn';
    el.textContent = btn.label;
    el.style.display = 'block';
    el.style.margin = '0.5rem 0';

    el.addEventListener('click', () => {
      fetch(btn.action, { method: 'POST' })
        .then(res => res.json())
        .then(resp => console.log(`${btn.label} ->`, resp))
        .catch(err => console.error(`${btn.label} failed`, err));
    });

    container.appendChild(el);
  });

  // NOTE: Speed control is now in main routines.html UI (moveSpeed element)
  // Servo config editor previously had its own speed-slider, but consolidated
  // to avoid confusion. Main moveSpeed slider in routines.html (min 100ms, max 3000ms)
  // controls all servo animation timing.
}


/********************************************
 * Event Listeners
 ********************************************/
window.addEventListener('DOMContentLoaded', () => {
  if (hasInitializedMainUI) return;
  hasInitializedMainUI = true;

  // Load and render servo controls
  fetch('/load_config')
    .then(res => res.json())
    .then(data => {
      servoConfigs = data.servos || data;
      if (!servoConfigs || servoConfigs.length === 0) servoConfigs = defaultConfigs;
      renderServosFromConfig(servoConfigs);
    })
    .catch(err => {
      console.error('Failed to load servo config:', err);
      servoConfigs = defaultConfigs;
      renderServosFromConfig(servoConfigs);
    });
  console.log("✅ DOM loaded");

  // 🔄 Update movement speed label
  const moveSpeedEl = document.getElementById('moveSpeed');
  if (moveSpeedEl) {
    moveSpeedEl.addEventListener('input', function () {
      document.getElementById('moveSpeedVal').textContent = this.value;
      // Send speed to backend
      fetch('/set_speed', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ speed: parseInt(this.value) })
      }).catch(err => console.error('Failed to set speed:', err));
    });
  }

  // ▶️ Play routine button
  const playBtn = document.getElementById('playBtn');
  if (playBtn) {
    playBtn.addEventListener('click', () => {
      isPaused = false;
      stopPlayback = false;

      const delayVal = parseFloat(document.getElementById('groupDelay').value || 1);
      if (currentRoutine.length > 0) {
        playRoutineLocally(currentRoutine, delayVal);
      } else {
        alert("⚠️ No loaded positions to play.");
      }
    });
  }

  // ⏸ Pause button
  const pauseBtnEl = document.getElementById('pauseBtn');
  if (pauseBtnEl) {
    pauseBtnEl.addEventListener('click', togglePause);
  }

  // ⏹ Stop button
  const stopBtnEl = document.getElementById('stopBtn');
  if (stopBtnEl) {
    stopBtnEl.addEventListener('click', () => {
      stopPlayback = true;
      isPaused = false;
      const btn = document.getElementById('pauseBtn');
      if (btn) btn.textContent = '⏸ Pause';
    });
  }

  // 💾 Bind Save Routine form submission
  const routineFormEl = document.getElementById('routineForm');
  if (routineFormEl) {
    routineFormEl.addEventListener('submit', saveRoutine);
  }


  // 💾 Save/Load Safe Position buttons
  const saveSafeBtn = document.getElementById('saveSafeBtn');
  if (saveSafeBtn) {
    saveSafeBtn.addEventListener('click', saveSafePosition);
  }
  const goSafeBtn = document.getElementById('goSafeBtn');
  if (goSafeBtn) {
    goSafeBtn.addEventListener('click', goSafePosition);
  }

  // Initialize serial readiness for active UI path.
  checkArduinoStatus();
  setTimeout(() => {
    if (!serialReady) reconnectArm();
  }, 2000);
});

// 📍 Go to Safe Position
function goSafePosition() {
  console.log("📍 goSafePosition triggered");

  fetch('/go_safe', { method: 'POST' })
    .then(r => r.json())
    .then(data => {
      if (!data.safe) return;

      data.safe.forEach((angle, servo) => {
        const slider = document.getElementById('servo' + servo);
        const display = document.getElementById('value' + servo);

        if (slider && display) {
          slider.value = angle;
          display.textContent = angle;
          currentServoAngles[servo] = angle;
        }
      });

      console.log('✅ Went to safe position:', data.safe);
    })
    .catch(err => console.error('Error going to safe position:', err));
}

// 💾 Save Safe Position & last position
function saveSafePosition() {
  const safePos = getSliderValues();

  fetch('/set_safe', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ safe: safePos })
  })
  .then(r => r.json())
  .then(data => {
    console.log('✅ Safe position saved:', data);
    alert('✅ Safe position saved!');
  })
  .catch(err => console.error('Error saving safe position:', err));
}

// save postion, keyframe
const recordBtn = document.getElementById('recordBtn');
if (recordBtn) {
  recordBtn.addEventListener('click', recordKeyframe);
}

// clear keyframes
const clearAllBtn = document.getElementById('clearAllBtn');
if (clearAllBtn) {
  clearAllBtn.addEventListener('click', clearAllKeyframes);
}


function loadLastPosition() {
  fetch('/get_current_position')
    .then(res => res.json())
    .then(data => {
      const angles = data.angles || [90, 90, 90, 90, 90, 50];
      document.querySelectorAll('.servo-slider').forEach((slider, i) => {
        const angle = angles[i];
        slider.value = angle;

        // Boot-time hydration should not emit movement events before serial is ready.
        const servoId = slider.getAttribute('data-servo');
        const display = document.getElementById('value' + servoId);
        if (display) display.textContent = angle;

        if (typeof updateServoDisplay === 'function' && servoId !== null) {
          const parsedServoId = parseInt(servoId, 10);
          if (!Number.isNaN(parsedServoId)) {
            updateServoDisplay(parsedServoId, angle);
          }
        }
      });
    });
}




/********************************************
 * Connectivity Monitor & Shutdown
 ********************************************/
const pingIntervalMs = 5000;

setInterval(() => {
  fetch('/ping')
    .then(response => response.json())
    .then(data => {
      if (!data.ok) {
        serialReady = false;
        console.warn('⚠️ Arduino unresponsive');
        // You could trigger UI feedback or attempt reconnect here
        // reconnectArm(); // Optional: implement if needed
      } else {
        if (!serialReady) {
          serialReady = true;
          enableSliderListeners();
        }
        console.log('✅ Arduino responsive');
      }
    })
    .catch(err => {
      serialReady = false;
      console.error('❌ Ping request failed:', err);
    });
}, pingIntervalMs);

function reconnectArm() {
  fetch('/reconnect', { method: 'POST' })
    .then(res => res.json())
    .then(data => {
      if (data.status === "ok") {
        console.log("🔄 Reconnected:", data.message);
        serialReady = true;

        document.querySelectorAll('.servo-slider').forEach(slider => slider.disabled = false);
        const statusEl = document.getElementById('arduinoStatus');
        if (statusEl) statusEl.textContent = "✅ Arduino connected";

        // Rebind slider input listeners if needed
        enableSliderListeners();

        if (Array.isArray(data.safe) && data.safe.length === Object.keys(currentServoAngles).length) {
          loadSlidersFromKeyframe(data.safe);
        }
      } else {
        console.warn("⚠️ Reconnect failed:", data.message);
      }
    })
    .catch(err => {
      console.error("❌ Error reconnecting:", err);
    });
}





function saveShutdownRoutine() {
  fetch('/save_shutdown_routine', {
    method: 'POST'
  })
  .then(res => res.json())
  .then(data => {
    if (data.status === 'ok') {
      alert('✅ Shutdown routine saved.');
      loadSavedRoutines(); // Refresh list
    } else {
      alert(`⚠️ Could not save shutdown routine: ${data.message}`);
    }
  })
  .catch(err => {
    console.error('❌ Error saving shutdown routine:', err);
    alert('Error saving shutdown routine.');
  });
}


function recordKeyframe() {
  console.log("🟢 recordKeyframe triggered");

  const keyframe = getSliderValues();
  currentRoutine.push(keyframe);
  updateKeyframeTable();

  const autosave = {
    name: "autosave_draft",
    description: "Temporary routine draft",
    keyframes: currentRoutine,
    delay: 1
  };

  fetch('/autosave_routine', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(autosave)
  })
  .then(res => res.json())
  .then(() => console.log('💾 Draft autosave updated'))
  .catch(err => console.error('❌ Draft autosave failed:', err));
}



function recordKeyframe() {
  console.log("🟢 recordKeyframe triggered");

  const keyframe = getSliderValues();
  currentRoutine.push(keyframe);
  updateKeyframeTable();
  console.log(`✅ Recorded keyframe #${currentRoutine.length}:`, keyframe);

  // ❌ No autosave here
}


function clearAllKeyframes() {
  if (confirm("Clear all recorded positions?")) {
    currentRoutine = [];
    updateKeyframeTable();
  }
}

function updateKeyframe() {
  if (editingKeyframeIndex === null) {
    alert("⚠️ No keyframe selected for editing.");
    return;
  }

  const updatedValues = getSliderValues();
  currentRoutine[editingKeyframeIndex] = updatedValues;
  updateKeyframeTable();

  alert(`✅ Updated keyframe #${editingKeyframeIndex + 1}`);
  editingKeyframeIndex = null;
  document.getElementById('updateKeyframeBtn').style.display = 'none';

  saveAutosaveRoutine();
}

function deleteKeyframe(index) {
  if (confirm(`Delete keyframe #${index + 1}?`)) {
    currentRoutine.splice(index, 1);
    updateKeyframeTable();
  }
}

function goToPosition(index) {
  const frame = currentRoutine[index];
  console.log(`📍 Moving to keyframe #${index + 1}:`, frame);
  frame.forEach((angle, servo) => animateServo(servo, parseFloat(angle), 500));
}

function editPosition(index) {
  const frame = currentRoutine[index];
  editingKeyframeIndex = index;

  frame.forEach((angle, servo) => {
    const slider = document.getElementById(`servo${servo}`);
    const display = document.getElementById(`value${servo}`);
    if (slider && display) {
      slider.value = angle;
      display.textContent = angle;
      currentServoAngles[servo] = angle;
    }
  });

  document.getElementById('updateKeyframeBtn').style.display = 'inline-block';
  alert(`📝 Keyframe #${index + 1} loaded. Adjust sliders and click "Update Keyframe".`);
}

function assignToGroup(index) {
  const groupName = prompt(`Assign position #${index + 1} to which group?`);
  if (groupName) {
    currentRoutine[index].group = groupName;
    updateKeyframeTable();
    console.log(`🏷 Assigned keyframe #${index + 1} to group "${groupName}"`);
  }
}

function updateKeyframeTable() {
  const tbody = document.getElementById('savedPositionsTbody');
  tbody.innerHTML = '';

  currentRoutine.forEach((frame, index) => {
    let row = `<tr><td>${index + 1}</td>`;
    frame.forEach(val => {
      row += `<td>${val}</td>`;
    });

    row += `
      <td>
        <button onclick="goToPosition(${index})">Go</button>
        <button onclick="editPosition(${index})">Edit</button>
        <button onclick="deleteKeyframe(${index})">Delete</button>
        <button onclick="insertKeyframeAt(${index})">Insert After</button>
        <button onclick="assignToGroup(${index})">Assign</button>
      </td>
    </tr>`;

    tbody.innerHTML += row;
  });
}

function insertKeyframeAt(index) {
  const newKeyframe = getSliderValues();

  // Insert the new keyframe after the specified index
  currentRoutine.splice(index + 1, 0, newKeyframe);
  updateKeyframeTable();

  alert(`📌 Inserted new keyframe after step #${index + 1}`);
}




/********************************************
 * Debounced Slider → Animate (with Validation)
 ********************************************/
window.addEventListener('DOMContentLoaded', () => {
  if (hasInitializedMainUI) return;
  hasInitializedMainUI = true;

  // Load and render servo controls
  fetch('/load_config')
    .then(res => res.json())
    .then(data => {
      servoConfigs = data.servos || data;
      if (!servoConfigs || servoConfigs.length === 0) servoConfigs = defaultConfigs;
      renderServosFromConfig(servoConfigs);
    })
    .catch(err => {
      console.error('Failed to load servo config:', err);
      servoConfigs = defaultConfigs;
      renderServosFromConfig(servoConfigs);
    });
  const sliders = document.querySelectorAll('.servo-slider');

  sliders.forEach(slider => {
    const servoNum = parseInt(slider.getAttribute('data-servo'));

    slider.addEventListener('input', () => {
      let targetAngle = parseFloat(slider.value);

      // 🛡️ Clamp angle between 0–180
      targetAngle = Math.max(0, Math.min(180, targetAngle));

      const display = document.getElementById('value' + servoNum);
      if (display) display.textContent = targetAngle;

      if (debounceTimers[servoNum]) clearTimeout(debounceTimers[servoNum]);

      const duration = parseInt(document.getElementById('moveSpeed').value || '500');

      debounceTimers[servoNum] = setTimeout(() => {
        sendServoDirectly(servoNum, targetAngle);
      }, 200);
    });
  });
});



/********************************************
 * Playback Logic – Progress Display
 ********************************************/
function updateProgressDisplay(step, total) {
  // Create the display if it doesn't exist
  if (!currentStepDisplay) {
    currentStepDisplay = document.createElement('div');
    currentStepDisplay.id = 'routineProgress';
    currentStepDisplay.style.textAlign = 'center';
    currentStepDisplay.style.margin = '1rem 0';
    currentStepDisplay.setAttribute('aria-live', 'polite'); // 🔊 Accessible announcement
    currentStepDisplay.setAttribute('role', 'status');
    document.body.insertBefore(currentStepDisplay, document.querySelector('.section'));
  }

  // Update screen-reader and visual progress
  currentStepDisplay.innerHTML = `<strong>Playing routine:</strong> Step ${step} of ${total}`;

  // Sync timeline slider, if present
  const timelineSlider = document.getElementById('routineTimeline');
  if (timelineSlider) {
    timelineSlider.max = total;
    timelineSlider.value = step;
  }

  // Highlight the current keyframe row
  const tbody = document.getElementById('savedPositionsTbody');
  if (tbody && tbody.children && tbody.children.length) {
    [...tbody.children].forEach((row, idx) => {
      row.style.backgroundColor = idx === (step - 1) ? '#d2f4ff' : '';
    });
  }
}

/********************************************
 * Servo Setup / Configuration
 ********************************************/

function saveCurrentAs(key) {
  const angles = Array.from(document.querySelectorAll('.servo-slider')).map(s => parseInt(s.value));
  fetch('/save_mim_config', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      key: key,
      value: angles
    })
  })
  .then(res => res.json())
  .then(data => console.log(`✅ Saved ${key}:`, data))
  .catch(err => console.error(`❌ Failed to save ${key}`, err));
}

function saveMountType() {
  const type = document.getElementById('mountType').value;
  fetch('/save_mim_config', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ key: 'mount_type', value: type })
  })
  .then(res => res.json())
  .then(data => console.log("✅ Mount type saved:", data))
  .catch(err => console.error("❌ Failed to save mount type", err));
}




// Local fallback if fetch fails
const defaultServoConfigs = [
  { id: 0, label: "Base", min: 0, max: 180 },
  { id: 1, label: "Shoulder", min: 0, max: 180 },
  { id: 2, label: "Elbow", min: 0, max: 180 },
  { id: 3, label: "Wrist", min: 0, max: 180 },
  { id: 4, label: "Hand", min: 0, max: 180 },
  { id: 5, label: "Claw", min: 0, max: 180 }
];

function addNewServo(config) {
  const { id, label, min, max } = config;
  const container = document.getElementById('servoContainer');
  if (!container || id >= maxServos) return;

  const group = document.createElement('div');
  group.className = 'servo-group';
  group.innerHTML = `
    <label for="servo${id}">${label}
      <span class="angle-display" id="value${id}">90</span>°
    </label>
    <div class="nudge-controls">
      <button onclick="nudgeServo(${id}, -1)">◀</button>
      <input type="range" id="servo${id}" class="servo-slider" data-servo="${id}" min="${min}" max="${max}" value="90">
      <button onclick="nudgeServo(${id}, 1)">▶</button>
    </div>
    <div class="direction-labels">
      <span class="servo-dir-left">${config.left || config.min}</span>
      <span class="servo-dir-right" style="float:right;">${config.right || config.max}</span>
    </div>

  `;

  container.appendChild(group);
  currentServoAngles[id] = 90;
  setupSliderDebounce(id);
  activeServos++;
}

function renderServosFromConfig(configs) {
  console.log("🔧 Rendering servos:", configs);
  servoConfigs = configs; // store globally for other functions
  activeServos = 0;
  const container = document.getElementById('servoContainer');
  console.log("📦 Servo container:", container);
  if (container) container.innerHTML = ''; // Clear any previous entries
  configs.forEach(cfg => addNewServo(cfg));
}

function updateKeyframeTable() {
  const tbody = document.getElementById('savedPositionsTbody');
  if (!tbody) return;

  tbody.innerHTML = '';
  currentRoutine.forEach((frame, index) => {
    let row = `<tr><td>${index + 1}</td>`;
    frame.forEach((val, i) => {
      const label = (servoConfigs[i] && servoConfigs[i].label) || `Servo ${i}`;
      row += `<td>${val} <small>(${label})</small></td>`;
    });
    row += `
      <td>
        <button onclick="goToPosition(${index})">Go</button>
        <button onclick="editPosition(${index})">Edit</button>
        <button onclick="deleteKeyframe(${index})">Delete</button>
        <button onclick="insertKeyframeAt(${index})">Insert After</button>
        <button onclick="assignToGroup(${index})">Assign</button>
      </td>
    </tr>`;
    tbody.innerHTML += row;
  });
}

function fetchObjectMemory() {
  fetch('/latest_detections')
    .then(res => res.json())
    .then(data => {
      const statusEl = document.getElementById('objectMemoryStatus');
      const table = document.getElementById('objectMemoryTable');
      const tbody = table ? table.querySelector('tbody') : null;

      if (!tbody) {
        console.warn("⚠️ Missing <tbody> in objectMemoryTable");
        if (statusEl) statusEl.textContent = '⚠️ UI table element missing';
        return;
      }

      tbody.innerHTML = '';
      if (!Array.isArray(data) || data.length === 0) {
        if (statusEl) statusEl.textContent = 'No objects detected.';
        return;
      }

      if (statusEl) statusEl.textContent = `🧠 Tracking ${data.length} object(s)`;

      data.forEach((obj, index) => {
        const row = document.createElement('tr');
        const { label, confidence, coords, movable } = obj;
        const conf = (confidence * 100).toFixed(1) + "%";
        const cx = coords && coords.center && typeof coords.center.x !== 'undefined' ? coords.center.x : 0;
        const cy = coords && coords.center && typeof coords.center.y !== 'undefined' ? coords.center.y : 0;
        const center = `(${cx}, ${cy})`;

        row.innerHTML = `
          <td>${label}</td>
          <td>${conf}</td>
          <td>${center}</td>
          <td>${movable !== null ? (movable ? "✅ Yes" : "❌ No") : "Unknown"}</td>
          <td>
            <button onclick="setMovable(${index}, true)">Set Movable</button>
            <button onclick="setMovable(${index}, false)">Set Unmovable</button>
          </td>
        `;
        tbody.appendChild(row);
      });
    })
    .catch(err => {
      console.error("❌ Failed to load object memory:", err);
      const statusEl = document.getElementById('objectMemoryStatus');
      if (statusEl) statusEl.textContent = '❌ Error loading object memory';
    });
}


// Call it every 2 seconds
setInterval(fetchObjectMemory, 2000);
function setMovable(index, value) {
  fetch('/set_movable', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ index, movable: value })
  })
  .then(res => res.json())
  .then(data => {
    if (data.status === "ok") {
      console.log(`✅ Object ${index} set as ${value ? "movable" : "unmovable"}`);
      fetchObjectMemory(); // Refresh the list
    } else {
      console.error(`❌ Failed to update object ${index}:`, data.message);
      alert(`❌ Error: ${data.message}`);
    }
  })
  .catch(err => {
    console.error("❌ Error setting movable state:", err);
    alert("❌ Error updating object state.");
  });
}



