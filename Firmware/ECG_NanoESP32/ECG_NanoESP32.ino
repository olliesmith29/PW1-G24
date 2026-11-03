/*
  ECG_NanoESP32.ino - AD8232 ECG acquisition firmware for the Arduino Nano ESP32
  EE22005 Project Week 1 - Group 24 (afb48, fjc48, owas20, aedg20, lhs53, ke417)

  Streams the SparkFun AD8232 heart-monitor output over USB serial as CSV:

      time_us,ecg_V
      0,1.6512
      2000,1.6538
      ...
      !            <- printed instead of a sample while a lead is off

  The format is read directly by ECG_Analyser (MATLAB), with no settings
  changes needed:
    - the time column is in microseconds, so the sampling rate is calculated
      automatically
    - samples are volts at the AD8232 output (calibrated by the ESP32's
      factory ADC calibration), which the analyser auto-detects and divides
      by the AD8232 gain (1100) to give millivolts at the electrodes
    - "!" lines are counted as leads-off events and skipped

  WIRING (AD8232 board -> Nano ESP32)
    GND    -> GND
    3.3V   -> 3V3          (NOT 5 V: the ESP32 ADC input max is ~3.3 V)
    OUTPUT -> A0
    LO-    -> D11
    LO+    -> D10
    SDN    -> not connected
  Electrodes: RA = right arm, LA = left arm, RL = right leg (reference).

  USE
    1. Board: "Arduino Nano ESP32" (Arduino ESP32 Boards package). Upload.
    2. Close the Arduino Serial Monitor (only one program can use the port).
    3. In ECG_Analyser.m set  source = 'capture';  and press Run. MATLAB
       records (default 30 s, with a live trace), saves
       recordings/ECG_yyyymmdd_HHMMSS.csv and analyses it.
       Sit still and breathe normally while recording.
    (Logging the Serial Monitor/PuTTY output to a .csv also works:
     then set  source = 'path\to\file.csv'.)

  Commands (type into the Serial Monitor and press Enter):
    p  pause / resume streaming
    h  print the header line again (useful after re-opening a logger)

  Educational use only - not a medical device. Do not connect electrodes
  while the laptop is plugged into mains power (use battery).
*/

// ------------------------------- settings ----------------------------------
const uint8_t  PIN_ECG       = A0;    // AD8232 OUTPUT
const uint8_t  PIN_LO_PLUS   = D10;   // AD8232 LO+
const uint8_t  PIN_LO_MINUS  = D11;   // AD8232 LO-
const bool     USE_LEADS_OFF = true;  // set false if LO+/LO- are not wired

const uint32_t SAMPLE_RATE_HZ = 500;  // 250-1000 Hz is sensible for ECG
const uint8_t  OVERSAMPLE     = 4;    // ADC readings averaged per sample (reduces noise)
const uint32_t SERIAL_BAUD    = 115200;
const uint32_t HOST_WAIT_MS   = 5000; // wait this long for the PC to open the port
// ---------------------------------------------------------------------------

const uint32_t PERIOD_US = 1000000UL / SAMPLE_RATE_HZ;

uint32_t nextSampleUs = 0;
uint32_t startUs      = 0;
bool     streaming    = true;
bool     leadsWereOff = false;

void printHeader() {
  Serial.println("time_us,ecg_V");
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  uint32_t t0 = millis();
  while (!Serial && (millis() - t0) < HOST_WAIT_MS) {
    delay(10);                          // wait for USB serial so the header is not lost
  }

  analogReadResolution(12);             // 0-4095
  analogSetAttenuation(ADC_11db);       // full 0-~3.1 V input range
  pinMode(PIN_ECG, INPUT);
  if (USE_LEADS_OFF) {
    pinMode(PIN_LO_PLUS, INPUT);
    pinMode(PIN_LO_MINUS, INPUT);
  }
  pinMode(LED_BUILTIN, OUTPUT);

  printHeader();
  startUs      = micros();
  nextSampleUs = startUs;
}

void handleCommands() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == 'p' || c == 'P') {
      streaming = !streaming;
      digitalWrite(LED_BUILTIN, LOW);
    } else if (c == 'h' || c == 'H') {
      printHeader();
    }
  }
}

void loop() {
  handleCommands();

  // fixed-rate timing: schedule against an absolute clock so errors do not accumulate
  uint32_t now = micros();
  if ((int32_t)(now - nextSampleUs) < 0) {
    return;                              // not time yet
  }
  nextSampleUs += PERIOD_US;
  if ((int32_t)(now - nextSampleUs) > (int32_t)(10 * PERIOD_US)) {
    nextSampleUs = now + PERIOD_US;      // fell far behind (e.g. USB stall): resync
  }
  if (!streaming) return;

  // leads-off check (AD8232 drives LO+/LO- high when an electrode is detached)
  if (USE_LEADS_OFF && (digitalRead(PIN_LO_PLUS) == HIGH || digitalRead(PIN_LO_MINUS) == HIGH)) {
    Serial.println('!');                 // one marker per missed sample
    leadsWereOff = true;
    digitalWrite(LED_BUILTIN, HIGH);     // LED on = check electrodes
    return;
  }
  leadsWereOff = false;
  digitalWrite(LED_BUILTIN, LOW);

  // read ECG: average a few calibrated readings (millivolts at the ADC pin)
  uint32_t sumMv = 0;
  for (uint8_t i = 0; i < OVERSAMPLE; i++) {
    sumMv += analogReadMilliVolts(PIN_ECG);
  }
  float volts = (sumMv / (float)OVERSAMPLE) / 1000.0f;

  Serial.print(now - startUs);           // microseconds since start
  Serial.print(',');
  Serial.println(volts, 4);
}
