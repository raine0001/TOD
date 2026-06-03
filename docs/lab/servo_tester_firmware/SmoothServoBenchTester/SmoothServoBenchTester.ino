#include <Wire.h>
#include <Adafruit_PWMServoDriver.h>

Adafruit_PWMServoDriver pwm = Adafruit_PWMServoDriver();

const int SERVO_MIN_COUNT = 100;
const int SERVO_MAX_COUNT = 650;
const int SERVO_MID_COUNT = 375;
const int SERVO_CHANNELS = 16;
const int DEFAULT_STEP_DELAY_MS = 12;
const byte PCA9685_ADDRESS = 0x40;

int currentPulse[SERVO_CHANNELS];

bool i2cAddressPresent(byte address) {
  Wire.beginTransmission(address);
  return Wire.endTransmission() == 0;
}

void printPcaStatus() {
  Serial.print("PCA9685 ");
  Serial.println(i2cAddressPresent(PCA9685_ADDRESS) ? "FOUND 0x40" : "NOT_FOUND 0x40");
}

void scanI2c() {
  Serial.print("I2C");
  bool found = false;
  for (byte address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0) {
      Serial.print(" 0x");
      if (address < 16) Serial.print("0");
      Serial.print(address, HEX);
      found = true;
    }
  }
  if (!found) Serial.print(" none");
  Serial.println();
}

int clampPulse(int value) {
  if (value < SERVO_MIN_COUNT) return SERVO_MIN_COUNT;
  if (value > SERVO_MAX_COUNT) return SERVO_MAX_COUNT;
  return value;
}

int angleToPulse(int angle) {
  if (angle < 0) angle = 0;
  if (angle > 180) angle = 180;
  return map(angle, 0, 180, SERVO_MIN_COUNT, SERVO_MAX_COUNT);
}

void applyPulseImmediate(int channel, int pulse) {
  if (channel < 0 || channel >= SERVO_CHANNELS) return;
  pulse = clampPulse(pulse);
  pwm.setPWM(channel, 0, pulse);
  currentPulse[channel] = pulse;
}

void rampChannel(int channel, int targetPulse, int durationMs) {
  if (channel < 0 || channel >= SERVO_CHANNELS) {
    Serial.print("ERR channel ");
    Serial.println(channel);
    return;
  }

  targetPulse = clampPulse(targetPulse);
  int startPulse = currentPulse[channel];
  int diff = targetPulse - startPulse;
  int distance = abs(diff);

  if (distance == 0) {
    Serial.print("OK channel ");
    Serial.print(channel);
    Serial.print(" pulse ");
    Serial.println(targetPulse);
    return;
  }

  int stepDirection = diff > 0 ? 1 : -1;
  int stepCount = distance;
  int stepDelay = DEFAULT_STEP_DELAY_MS;
  if (durationMs > 0 && stepCount > 0) {
    stepDelay = max(2, durationMs / stepCount);
  }

  for (int pulse = startPulse; pulse != targetPulse; pulse += stepDirection) {
    pwm.setPWM(channel, 0, pulse);
    currentPulse[channel] = pulse;
    delay(stepDelay);
  }

  pwm.setPWM(channel, 0, targetPulse);
  currentPulse[channel] = targetPulse;
  Serial.print("OK channel ");
  Serial.print(channel);
  Serial.print(" pulse ");
  Serial.println(targetPulse);
}

void rampBothBenchChannels(int targetPulse, int durationMs) {
  targetPulse = clampPulse(targetPulse);
  int start0 = currentPulse[0];
  int start1 = currentPulse[1];
  int distance = max(abs(targetPulse - start0), abs(targetPulse - start1));

  if (distance == 0) {
    Serial.print("OK both pulse ");
    Serial.println(targetPulse);
    return;
  }

  int stepDelay = DEFAULT_STEP_DELAY_MS;
  if (durationMs > 0) {
    stepDelay = max(2, durationMs / distance);
  }

  for (int i = 1; i <= distance; i++) {
    int pulse0 = start0 + ((targetPulse - start0) * i) / distance;
    int pulse1 = start1 + ((targetPulse - start1) * i) / distance;
    pwm.setPWM(0, 0, pulse0);
    pwm.setPWM(1, 0, pulse1);
    currentPulse[0] = pulse0;
    currentPulse[1] = pulse1;
    delay(stepDelay);
  }

  Serial.print("OK both pulse ");
  Serial.println(targetPulse);
}

void testAllChannels(int lowPulse, int highPulse, int durationMs) {
  lowPulse = clampPulse(lowPulse);
  highPulse = clampPulse(highPulse);
  int dwellMs = durationMs > 0 ? durationMs : 450;
  for (int channel = 0; channel < SERVO_CHANNELS; channel++) {
    applyPulseImmediate(channel, lowPulse);
  }
  delay(dwellMs);
  for (int channel = 0; channel < SERVO_CHANNELS; channel++) {
    applyPulseImmediate(channel, highPulse);
  }
  delay(dwellMs);
  for (int channel = 0; channel < SERVO_CHANNELS; channel++) {
    applyPulseImmediate(channel, SERVO_MID_COUNT);
  }
  Serial.print("OK testall ");
  Serial.print(lowPulse);
  Serial.print(" ");
  Serial.println(highPulse);
}

String nextToken(String &line) {
  line.trim();
  if (!line.length()) return "";
  int splitAt = line.indexOf(' ');
  if (splitAt < 0) {
    String token = line;
    line = "";
    return token;
  }
  String token = line.substring(0, splitAt);
  line = line.substring(splitAt + 1);
  return token;
}

void handleCommand(String line) {
  line.trim();
  if (!line.length()) return;

  String work = line;
  String command = nextToken(work);
  command.toUpperCase();

  if (command == "PING") {
    Serial.println("PONG SmoothServoBenchTester");
    return;
  }

  if (command == "STATUS") {
    printPcaStatus();
    return;
  }

  if (command == "SCAN") {
    scanI2c();
    return;
  }

  if (command == "S") {
    int channel = nextToken(work).toInt();
    int pulse = nextToken(work).toInt();
    int durationMs = nextToken(work).toInt();
    rampChannel(channel, pulse, durationMs);
    return;
  }

  if (command == "MOVE") {
    int channel = nextToken(work).toInt();
    int angle = nextToken(work).toInt();
    int durationMs = nextToken(work).toInt();
    rampChannel(channel, angleToPulse(angle), durationMs);
    return;
  }

  if (command == "ALL") {
    int pulse = nextToken(work).toInt();
    int durationMs = nextToken(work).toInt();
    rampBothBenchChannels(pulse, durationMs);
    return;
  }

  if (command == "TESTALL") {
    int lowPulse = nextToken(work).toInt();
    int highPulse = nextToken(work).toInt();
    int durationMs = nextToken(work).toInt();
    testAllChannels(lowPulse > 0 ? lowPulse : 300, highPulse > 0 ? highPulse : 650, durationMs);
    return;
  }

  bool numericOnly = true;
  for (unsigned int i = 0; i < line.length(); i++) {
    if (!isDigit(line.charAt(i)) && !isWhitespace(line.charAt(i))) {
      numericOnly = false;
      break;
    }
  }

  if (numericOnly) {
    rampBothBenchChannels(line.toInt(), 650);
    return;
  }

  Serial.print("ERR unknown command ");
  Serial.println(line);
}

void setup() {
  Serial.begin(9600);
  while (!Serial) {
    delay(10);
  }

  pwm.begin();
  pwm.setOscillatorFrequency(27000000);
  pwm.setPWMFreq(50);

  for (int channel = 0; channel < SERVO_CHANNELS; channel++) {
    currentPulse[channel] = SERVO_MID_COUNT;
  }
  applyPulseImmediate(0, SERVO_MID_COUNT);
  applyPulseImmediate(1, SERVO_MID_COUNT);

  Serial.println("=== Smooth PCA9685 Servo Bench Tester ===");
  Serial.println("Raw input: 100-650 moves channels 0 and 1 smoothly.");
  Serial.println("Commands: PING | STATUS | SCAN | S channel pulse durationMs | MOVE channel angle durationMs | ALL pulse durationMs | TESTALL low high durationMs");
  Serial.print("Starting at midpoint pulse: ");
  Serial.println(SERVO_MID_COUNT);
  printPcaStatus();
}

void loop() {
  if (Serial.available() > 0) {
    String line = Serial.readStringUntil('\n');
    handleCommand(line);
  }
}
