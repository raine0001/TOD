#include <Wire.h>

static const unsigned long SCAN_INTERVAL_MS = 2500;
static const uint8_t DISTANCE_SENSOR_ADDR = 0x10;
static unsigned long lastScanAt = 0;
static unsigned long lastDistanceAt = 0;

void scanI2C() {
  uint8_t found = 0;
  Serial.println("I2C_SCAN_BEGIN");
  for (uint8_t address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    uint8_t error = Wire.endTransmission();
    if (error == 0) {
      found++;
      Serial.print("I2C:0x");
      if (address < 16) {
        Serial.print('0');
      }
      Serial.println(address, HEX);
    }
  }
  if (found == 0) {
    Serial.println("I2C:NONE");
  }
  Serial.print("I2C_COUNT:");
  Serial.println(found);
  Serial.println("I2C_SCAN_END");
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

void printHexByte(uint8_t value) {
  if (value < 16) {
    Serial.print('0');
  }
  Serial.print(value, HEX);
}

void readDistanceSensor() {
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

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(10);
  }
  Wire.begin();
  Wire.setClock(100000);
  Serial.println("PC_UNO_R4_I2C_DIAGNOSTIC_READY");
  scanI2C();
  readDistanceSensor();
  lastScanAt = millis();
  lastDistanceAt = millis();
}

void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line == "PING") {
      Serial.println("PONG");
    } else if (line == "I2C_SCAN" || line == "SCAN") {
      scanI2C();
      lastScanAt = millis();
    } else if (line == "DIST_READ" || line == "DISTANCE" || line == "READ_DISTANCE") {
      readDistanceSensor();
      lastDistanceAt = millis();
    } else if (line.length() > 0) {
      Serial.println("ERR");
    }
  }

  if (millis() - lastScanAt >= SCAN_INTERVAL_MS) {
    scanI2C();
    lastScanAt = millis();
  }

  if (millis() - lastDistanceAt >= 500) {
    readDistanceSensor();
    lastDistanceAt = millis();
  }
}
