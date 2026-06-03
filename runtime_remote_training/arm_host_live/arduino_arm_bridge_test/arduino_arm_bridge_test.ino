#include <Wire.h>
#include <Adafruit_PWMServoDriver.h>

Adafruit_PWMServoDriver pwm(0x40);

static const int SERVO_MIN = 110;  // default pulse for ~0 deg
static const int SERVO_MAX = 510;  // default pulse for ~180 deg
static const int SHOULDER_CHANNEL = 1;
static const int SHOULDER_MIN = 55;
static const int SHOULDER_MAX = 500;
static const int SHOULDER_MAX_SAFE_ANGLE = 135;
static const int CLAW_CHANNEL = 5;
static const int CLAW_MIN = 45;  // extends close travel for the gripper at angle 0
static const int CLAW_MAX = SERVO_MAX;
static const uint8_t DISTANCE_SENSOR_ADDR = 0x10;
static const unsigned long TFMINI_BAUD = 115200;
static const unsigned long TFMINI_READ_TIMEOUT_MS = 350;

struct TFMiniReading {
  bool ok;
  uint16_t distance_cm;
  uint16_t strength;
  int16_t temperature_raw;
  uint8_t frame[9];
};

int angleToPulse(int channel, int angle) {
  if (angle < 0) angle = 0;
  if (channel == SHOULDER_CHANNEL) {
    if (angle > SHOULDER_MAX_SAFE_ANGLE) {
      angle = SHOULDER_MAX_SAFE_ANGLE;
    }
  } else if (angle > 180) {
    angle = 180;
  }
  int minPulse = SERVO_MIN;
  int maxPulse = SERVO_MAX;
  if (channel == SHOULDER_CHANNEL) {
    minPulse = SHOULDER_MIN;
    maxPulse = SHOULDER_MAX;
  } else if (channel == CLAW_CHANNEL) {
    minPulse = CLAW_MIN;
    maxPulse = CLAW_MAX;
  }
  return map(angle, 0, 180, minPulse, maxPulse);
}

bool i2cDevicePresent(uint8_t address) {
  Wire.beginTransmission(address);
  return Wire.endTransmission() == 0;
}

bool readRegisterBlock(uint8_t address, uint8_t reg, uint8_t *buffer, uint8_t len) {
  Wire.beginTransmission(address);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) {
    return false;
  }

  uint8_t received = Wire.requestFrom(address, len);
  if (received != len) {
    while (Wire.available()) {
      Wire.read();
    }
    return false;
  }

  for (uint8_t i = 0; i < len; i++) {
    buffer[i] = Wire.read();
  }
  return true;
}

void logI2CBus() {
  bool any = false;
  Serial.println("I2C_SCAN_BEGIN");
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      any = true;
      Serial.print("I2C:0x");
      if (addr < 16) {
        Serial.print('0');
      }
      Serial.println(addr, HEX);
    }
  }
  if (!any) {
    Serial.println("I2C:NONE");
  }
  Serial.println("I2C_SCAN_END");
}

void moveServo(int channel, int angle) {
  if (channel < 0 || channel > 15) return;
  pwm.setPWM(channel, 0, angleToPulse(channel, angle));
}

void printHexByte(uint8_t value) {
  if (value < 16) {
    Serial.print('0');
  }
  Serial.print(value, HEX);
}

void printI2CDistanceReading() {
  uint8_t bytes[8] = {0};
  if (!readRegisterBlock(DISTANCE_SENSOR_ADDR, 0x00, bytes, 8)) {
    Serial.println("DIST:NO_READ");
    return;
  }

  uint16_t distance_cm = (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
  uint16_t strength = (uint16_t)bytes[2] | ((uint16_t)bytes[3] << 8);
  uint16_t temperature_raw = (uint16_t)bytes[4] | ((uint16_t)bytes[5] << 8);

  Serial.print("DIST:ADDR=0x10,CM=");
  Serial.print(distance_cm);
  Serial.print(",MM=");
  Serial.print((unsigned long)distance_cm * 10UL);
  Serial.print(",STRENGTH=");
  Serial.print(strength);
  Serial.print(",TEMP_RAW=");
  Serial.print(temperature_raw);
  Serial.print(",REG0_7=");
  for (uint8_t i = 0; i < 8; i++) {
    printHexByte(bytes[i]);
  }
  Serial.println();
}

bool readTFMiniFrame(TFMiniReading &reading) {
  unsigned long deadline = millis() + TFMINI_READ_TIMEOUT_MS;
  uint8_t frame[9];
  uint8_t index = 0;

  while (millis() < deadline) {
    while (Serial1.available() > 0) {
      uint8_t value = (uint8_t)Serial1.read();
      if (index == 0) {
        if (value != 0x59) {
          continue;
        }
        frame[index++] = value;
        continue;
      }
      if (index == 1) {
        if (value != 0x59) {
          index = 0;
          continue;
        }
        frame[index++] = value;
        continue;
      }
      frame[index++] = value;
      if (index < 9) {
        continue;
      }

      uint8_t checksum = 0;
      for (uint8_t i = 0; i < 8; i++) {
        checksum += frame[i];
      }
      if (checksum != frame[8]) {
        index = 0;
        continue;
      }

      reading.ok = true;
      reading.distance_cm = (uint16_t)frame[2] | ((uint16_t)frame[3] << 8);
      reading.strength = (uint16_t)frame[4] | ((uint16_t)frame[5] << 8);
      reading.temperature_raw = (int16_t)((uint16_t)frame[6] | ((uint16_t)frame[7] << 8));
      for (uint8_t i = 0; i < 9; i++) {
        reading.frame[i] = frame[i];
      }
      return true;
    }
  }
  reading.ok = false;
  return false;
}

void printTFMiniReading() {
  TFMiniReading reading;
  if (!readTFMiniFrame(reading)) {
    Serial.println("TFMINI:NO_FRAME");
    return;
  }

  Serial.print("TFMINI:CM=");
  Serial.print(reading.distance_cm);
  Serial.print(",MM=");
  Serial.print((unsigned long)reading.distance_cm * 10UL);
  Serial.print(",STRENGTH=");
  Serial.print(reading.strength);
  Serial.print(",TEMP_RAW=");
  Serial.print(reading.temperature_raw);
  Serial.print(",FRAME=");
  for (uint8_t i = 0; i < 9; i++) {
    printHexByte(reading.frame[i]);
  }
  Serial.println();
}

void setup() {
  Wire.begin();
  Wire.setClock(100000);
  Serial.begin(9600);
  Serial1.begin(TFMINI_BAUD);
  while (!Serial) {
    delay(10);
  }

  logI2CBus();
  if (i2cDevicePresent(0x40)) {
    Serial.println("PCA9685:FOUND");
  } else {
    Serial.println("PCA9685:MISSING");
  }

  pwm.begin();
  pwm.setPWMFreq(50);
  delay(200);

  // Startup twitch on CH0 to prove PWM is alive.
  moveServo(0, 90);
  delay(250);
  moveServo(0, 70);
  delay(250);
  moveServo(0, 90);

  Serial.println("READY");
}

void loop() {
  if (!Serial.available()) return;

  String line = Serial.readStringUntil('\n');
  line.trim();
  if (line.length() == 0) return;

  if (line == "PING") {
    Serial.println("PONG");
    return;
  }

  if (line == "TFMINI_READ" || line == "TFMINI" || line == "DIST" || line == "DISTANCE") {
    printTFMiniReading();
    return;
  }

  if (line == "I2C_DIST_READ" || line == "I2C_DISTANCE" || line == "READ_I2C_DISTANCE") {
    printI2CDistanceReading();
    return;
  }

  if (line == "I2C_SCAN") {
    logI2CBus();
    return;
  }

  if (line == "I2C_STATUS") {
    if (i2cDevicePresent(0x40)) {
      Serial.println("PCA9685:FOUND");
    } else {
      Serial.println("PCA9685:MISSING");
    }
    return;
  }

  int s = -1;
  int a = -1;
  if (sscanf(line.c_str(), "MOVE %d %d", &s, &a) == 2) {
    moveServo(s, a);
    Serial.println("DONE");
    return;
  }

  Serial.println("ERR");
}
