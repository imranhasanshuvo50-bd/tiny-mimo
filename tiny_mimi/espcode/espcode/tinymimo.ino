#include <Wire.h>
#include <U8g2lib.h>
#include <Preferences.h>
#include <time.h>
#include <sys/time.h>
#include "esp_sleep.h"
#include "driver/gpio.h"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 2
#include <esp_mac.h>
#else
#include <esp_system.h>
#endif

struct NextPrayerInfo {
  const char* name;
  int hoursRemaining;
  int minutesRemaining;
  int secondsRemaining;
};

void setCustomMacAddress() {
  uint8_t mac[6];
  if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK) {
    // Toggle the last bit of the MAC address to bypass stale phone pairings
    mac[5] ^= 0x01; 
    esp_base_mac_addr_set(mac);
  }
}

// ---------------- PINS ----------------

#define OLED_SDA 8
#define OLED_SCL 9

#define BUTTON_PIN 4
#define BUZZER_PIN 5

#define BUTTON_PRESSED LOW

// ---------------- REAL BATTERY VOLTAGE DETECTION ----------------

#define ENABLE_BATTERY_MONITOR 1
#define BATTERY_ADC_PIN 0

// 100k + 100k voltage divider = x2
#define VOLTAGE_DIVIDER_RATIO 2.0

// Adjust this if multimeter value is different
#define BATTERY_CALIBRATION 0.903153

float lastBatteryVoltage = 0.0;

// ---------------- BLE ----------------

#define BLE_DEVICE_NAME "TinyMimiRobot"

#define BLE_SERVICE_UUID "b0b00001-1234-5678-9999-abcdef000001"
#define BLE_RX_UUID      "b0b00002-1234-5678-9999-abcdef000002"
#define BLE_TX_UUID      "b0b00003-1234-5678-9999-abcdef000003"

BLECharacteristic* bleTxChar = nullptr;
bool bleConnected = false;

volatile bool restartAdvertisingFlag = false;
volatile bool bleRxAvailable = false;
String bleRxQueue = "";

// ---------------- OLED ----------------

U8G2_SH1106_128X64_NONAME_F_HW_I2C u8g2(
  U8G2_R0,
  U8X8_PIN_NONE
);

int eyeW = 36;
int eyeR = 8;
int leftBaseX  = 10;
int rightBaseX = 82;

// ---------------- SETTINGS ----------------

Preferences prefs;

// ---------------- POWER ----------------

const unsigned long POWER_OFF_HOLD_MS = 2500;
const unsigned long POWER_ON_HOLD_MS  = 1200;

bool buttonIsDown = false;
bool longPressDone = false;
unsigned long buttonPressStart = 0;

// ---------------- BATTERY / CHARGING ----------------

int batteryPercentRaw = 85;
float batteryFiltered = 85.0;
int lastSentBatteryPercent = -1;

const bool chargingConnected = false;

unsigned long lastBatteryUpdate = 0;

// ---------------- TIMING ----------------

unsigned long lastBlinkTime = 0;
unsigned long blinkInterval = 4000;

unsigned long lastLookTime = 0;
unsigned long lookInterval = 8000;

unsigned long lastScreenRefresh = 0;
unsigned long lastActivityTime = 0;

const unsigned long LOW_POWER_TIMEOUT = 10000;
const unsigned long VERY_LOW_POWER_TIMEOUT = 12000;

// ---------------- MODES ----------------

enum RobotMode {
  MODE_IDLE,
  MODE_LOW_POWER,
  MODE_VERY_LOW_POWER
};

RobotMode currentMode = MODE_IDLE;

enum DisplayState {
  STATE_FACE,
  STATE_ONLY_TIME,
  STATE_TIME_AND_PRAYER
};

DisplayState currentDisplayState = STATE_FACE;

// ---------------- PRAYER ----------------

struct PrayerTime {
  const char* name;
  int hour;
  int minute;
  bool reminded;
};

PrayerTime prayers[5] = {
  {"Fajr",     4, 20, false},
  {"Dhuhr",   12, 10, false},
  {"Asr",     15, 45, false},
  {"Maghrib", 18, 35, false},
  {"Isha",    20, 00, false}
};

int lastPrayerDay = -1;

// Different click animation
int clickAnimationIndex = 0;
const int CLICK_ANIMATION_COUNT = 8;

// ---------------- FUNCTION DECLARATIONS ----------------

void handleCommand(String line, const char* source);
void drawEyes(int h, int xOffset = 0, int yOffset = 0);
void slideEyes(int startX, int startY, int endX, int endY, int durationMs);
void drawIdleFace();
void showTextScreen(const char* l1, const char* l2, const char* l3);
void startupAnimation();
void buttonAnimation();
void enterPowerOffSleep();
void enterLowBatteryShutdown();
void saveDisplayState();
void printHelp();
void printStatus();

// ---------------- BLE HELPERS ----------------

void bleSend(String msg) {
  Serial.print("BLE TX: ");
  Serial.println(msg);

  if (bleConnected && bleTxChar != nullptr) {
    bleTxChar->setValue(msg.c_str());
    bleTxChar->notify();
    delay(20);
  }
}

class RobotServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) {
    bleConnected = true;
    Serial.println("BLE: Phone connected");
    bleSend("CONNECTED");
  }

  void onDisconnect(BLEServer* server) {
    bleConnected = false;
    Serial.println("BLE: Phone disconnected");
    restartAdvertisingFlag = true;
  }
};

class RobotRxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) {
    String line = String(characteristic->getValue().c_str());
    line.trim();

    if (line.length() > 0) {
      bleRxQueue = line;
      bleRxAvailable = true;
    }
  }
};

void startBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEDevice::setMTU(128);

  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new RobotServerCallbacks());

  BLEService* service = server->createService(BLE_SERVICE_UUID);

  bleTxChar = service->createCharacteristic(
    BLE_TX_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );

  bleTxChar->addDescriptor(new BLE2902());

  BLECharacteristic* rxChar = service->createCharacteristic(
    BLE_RX_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );

  rxChar->setCallbacks(new RobotRxCallbacks());

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(BLE_SERVICE_UUID);

  // Set name explicitly in the Scan Response data so scanning phones receive it instantly
  BLEAdvertisementData scanResponseData;
  scanResponseData.setName(BLE_DEVICE_NAME);
  advertising->setScanResponseData(scanResponseData);

  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);

  advertising->setMinInterval(0x40);
  advertising->setMaxInterval(0x80);

  BLEDevice::startAdvertising();

  Serial.println("BLE: Started");
  Serial.print("BLE NAME: ");
  Serial.println(BLE_DEVICE_NAME);
}

void stopBLEForSleep() {
  if (bleTxChar != nullptr) {
    bleSend("POWER SLEEP");
    delay(100);
  }

  BLEDevice::deinit(true);
  bleTxChar = nullptr;
  bleConnected = false;
}

// ---------------- BUZZER ----------------

void buzzerOn() {
  digitalWrite(BUZZER_PIN, HIGH);
}

void buzzerOff() {
  digitalWrite(BUZZER_PIN, LOW);
}

void beep(int onTime, int offTime) {
  digitalWrite(BUZZER_PIN, HIGH);
  delay(onTime);
  digitalWrite(BUZZER_PIN, LOW);
  delay(offTime);
}

void startupSound() {
  beep(80, 60);
  beep(80, 60);
  beep(180, 100);
}

void petSound() {
  beep(60, 50);
  beep(80, 60);
  beep(50, 40);
  beep(120, 80);
  beep(60, 40);
}

void prayerSound() {
  beep(180, 120);
  beep(180, 120);
  beep(300, 150);
}

void chargingSound() {
  beep(60, 50);
  beep(60, 50);
  beep(180, 80);
}

// ---------------- TIME ----------------

void setupTimeZone() {
  setenv("TZ", "BDT-6", 1);
  tzset();
}

bool getLocalTimeNow(struct tm &timeinfo) {
  time_t now;
  time(&now);
  localtime_r(&now, &timeinfo);

  return timeinfo.tm_year > 120;
}

String getTimeString() {
  struct tm timeinfo;

  if (!getLocalTimeNow(timeinfo)) {
    return "--:--";
  }

  int hour12 = timeinfo.tm_hour % 12;
  if (hour12 == 0) hour12 = 12;

  const char* ampm = (timeinfo.tm_hour >= 12) ? "PM" : "AM";

  char buf[16];
  sprintf(buf, "%02d:%02d %s", hour12, timeinfo.tm_min, ampm);

  return String(buf);
}

String getDateTimeString() {
  struct tm timeinfo;

  if (!getLocalTimeNow(timeinfo)) {
    return "--";
  }

  int hour12 = timeinfo.tm_hour % 12;
  if (hour12 == 0) hour12 = 12;

  const char* ampm = (timeinfo.tm_hour >= 12) ? "PM" : "AM";

  char buf[32];

  sprintf(
    buf,
    "%04d-%02d-%02d %02d:%02d:%02d %s",
    timeinfo.tm_year + 1900,
    timeinfo.tm_mon + 1,
    timeinfo.tm_mday,
    hour12,
    timeinfo.tm_min,
    timeinfo.tm_sec,
    ampm
  );

  return String(buf);
}

void setClockManual(int year, int month, int day, int hour, int minute, int second) {
  setupTimeZone();

  struct tm t;
  memset(&t, 0, sizeof(t));

  t.tm_year = year - 1900;
  t.tm_mon  = month - 1;
  t.tm_mday = day;
  t.tm_hour = hour;
  t.tm_min  = minute;
  t.tm_sec  = second;

  time_t epoch = mktime(&t);

  struct timeval tv;
  tv.tv_sec = epoch;
  tv.tv_usec = 0;

  settimeofday(&tv, NULL);

  Serial.print("TIME: Updated: ");
  Serial.println(getDateTimeString());

  bleSend("TIME OK " + getTimeString());
}

void setClockFromCompileTimeIfNeeded() {
  struct tm checkTime;

  if (getLocalTimeNow(checkTime)) {
    return;
  }

  setupTimeZone();

  char monthStr[4];
  int day, year;
  int hour, minute, second;

  sscanf(__DATE__, "%3s %d %d", monthStr, &day, &year);
  sscanf(__TIME__, "%d:%d:%d", &hour, &minute, &second);

  const char* months = "JanFebMarAprMayJunJulAugSepOctNovDec";
  const char* pos = strstr(months, monthStr);

  int month = 0;

  if (pos != NULL) {
    month = (pos - months) / 3;
  }

  struct tm t;
  memset(&t, 0, sizeof(t));

  t.tm_year = year - 1900;
  t.tm_mon  = month;
  t.tm_mday = day;
  t.tm_hour = hour;
  t.tm_min  = minute;
  t.tm_sec  = second;

  time_t epoch = mktime(&t);

  struct timeval tv;
  tv.tv_sec = epoch;
  tv.tv_usec = 0;

  settimeofday(&tv, NULL);

  Serial.println("TIME: Set from compile time");
}

// ---------------- SAVE / LOAD ----------------

void savePrayerTimes() {
  prefs.begin("robot", false);

  for (int i = 0; i < 5; i++) {
    char keyH[8];
    char keyM[8];

    sprintf(keyH, "p%dh", i);
    sprintf(keyM, "p%dm", i);

    prefs.putInt(keyH, prayers[i].hour);
    prefs.putInt(keyM, prayers[i].minute);
  }

  prefs.end();

  Serial.println("PRAYER: Saved");
  bleSend("PRAYER SAVED");
}

void loadSettings() {
  prefs.begin("robot", true);

  for (int i = 0; i < 5; i++) {
    char keyH[8];
    char keyM[8];

    sprintf(keyH, "p%dh", i);
    sprintf(keyM, "p%dm", i);

    prayers[i].hour = prefs.getInt(keyH, prayers[i].hour);
    prayers[i].minute = prefs.getInt(keyM, prayers[i].minute);
  }

  currentDisplayState = (DisplayState)prefs.getInt("disp_state", (int)STATE_FACE);

  prefs.end();

  Serial.println("SETTINGS: Loaded");
}

void saveDisplayState() {
  prefs.begin("robot", false);
  prefs.putInt("disp_state", (int)currentDisplayState);
  prefs.end();
}

// ---------------- DISPLAY ----------------

void showTextScreen(const char* l1, const char* l2, const char* l3) {
  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_6x10_tf);

  if (l1 != nullptr) u8g2.drawStr(0, 14, l1);
  if (l2 != nullptr) u8g2.drawStr(0, 32, l2);
  if (l3 != nullptr) u8g2.drawStr(0, 50, l3);

  u8g2.sendBuffer();
}

void drawBatteryIcon(int x, int y) {
  int percent = constrain((int)batteryFiltered, 0, 100);

  u8g2.drawFrame(x, y, 16, 8);
  u8g2.drawBox(x + 16, y + 2, 2, 4);

  int fillW = map(percent, 0, 100, 0, 14);

  if (fillW > 0) {
    u8g2.drawBox(x + 1, y + 1, fillW, 6);
  }
}

void drawStatusBar() {
  u8g2.setFont(u8g2_font_5x7_tr);

  u8g2.drawStr(0, 7, "Mimo");

  if (bleConnected) {
    u8g2.drawStr(28, 7, "BLE");
  }

  // Draw battery percentage text
  int percent = constrain((int)batteryFiltered, 0, 100);
  char pctBuf[8];
  sprintf(pctBuf, "%d%%", percent);
  int textWidth = u8g2.getStrWidth(pctBuf);
  
  int textX = 108 - textWidth;
  u8g2.drawStr(textX, 7, pctBuf);

  drawBatteryIcon(110, 0);
}

NextPrayerInfo getNextPrayerInfo() {
  NextPrayerInfo info = {"None", 0, 0, 0};

  struct tm timeinfo;

  if (!getLocalTimeNow(timeinfo)) {
    return info;
  }

  int currentSecs = timeinfo.tm_hour * 3600 + timeinfo.tm_min * 60 + timeinfo.tm_sec;

  int nextIdx = -1;

  for (int i = 0; i < 5; i++) {
    int prayerSecs = prayers[i].hour * 3600 + prayers[i].minute * 60;

    if (prayerSecs > currentSecs) {
      nextIdx = i;
      break;
    }
  }

  int diffSecs = 0;

  if (nextIdx != -1) {
    info.name = prayers[nextIdx].name;
    int prayerSecs = prayers[nextIdx].hour * 3600 + prayers[nextIdx].minute * 60;
    diffSecs = prayerSecs - currentSecs;
  } else {
    info.name = prayers[0].name;
    int prayerSecs = prayers[0].hour * 3600 + prayers[0].minute * 60;
    diffSecs = (24 * 3600 - currentSecs) + prayerSecs;
  }

  info.hoursRemaining = diffSecs / 3600;
  info.minutesRemaining = (diffSecs % 3600) / 60;
  info.secondsRemaining = diffSecs % 60;

  return info;
}

void drawIdleFace() {
  updatePowerMode();

  if (currentMode == MODE_VERY_LOW_POWER) {
    showVeryLowPowerClock();
    return;
  }

  if (currentMode == MODE_LOW_POWER) {
    showLowPowerScreen();
    return;
  }

  u8g2.clearBuffer();
  drawStatusBar(); // Draw battery and BLE status bar on all states

  if (currentDisplayState == STATE_ONLY_TIME) {
    // STATE 1: Only Time + Remaining Prayer Time
    String timeText = getTimeString();
    u8g2.setFont(u8g2_font_ncenB18_tr);
    int w = u8g2.getStrWidth(timeText.c_str());
    u8g2.drawStr((128 - w) / 2, 40, timeText.c_str());

    NextPrayerInfo nextPrayer = getNextPrayerInfo();
    if (strcmp(nextPrayer.name, "None") != 0) {
      u8g2.setFont(u8g2_font_6x10_tf);
      char timeBuf[32];
      sprintf(timeBuf, "%s in %dh %dm", nextPrayer.name, nextPrayer.hoursRemaining, nextPrayer.minutesRemaining);
      int w3 = u8g2.getStrWidth(timeBuf);
      u8g2.drawStr((128 - w3) / 2, 56, timeBuf);
    }
  } 
  else if (currentDisplayState == STATE_TIME_AND_PRAYER) {
    // STATE 2: Time and Next Prayer Time
    String timeText = getTimeString();
    u8g2.setFont(u8g2_font_ncenB14_tr);
    int w = u8g2.getStrWidth(timeText.c_str());
    u8g2.drawStr((128 - w) / 2, 32, timeText.c_str());

    NextPrayerInfo nextPrayer = getNextPrayerInfo();
    if (strcmp(nextPrayer.name, "None") != 0) {
      u8g2.setFont(u8g2_font_6x10_tf);
      char prayerBuf[32];
      sprintf(prayerBuf, "Next: %s", nextPrayer.name);
      int w2 = u8g2.getStrWidth(prayerBuf);
      u8g2.drawStr((128 - w2) / 2, 48, prayerBuf);

      char timeBuf[32];
      sprintf(timeBuf, "in %dh %dm", nextPrayer.hoursRemaining, nextPrayer.minutesRemaining);
      int w3 = u8g2.getStrWidth(timeBuf);
      u8g2.drawStr((128 - w3) / 2, 60, timeBuf);
    }
  } 
  else {
    // STATE 0: Active eyes face
    int y = (64 - 36) / 2; // y = 14
    u8g2.drawRBox(leftBaseX, y, eyeW, 36, eyeR);
    u8g2.drawRBox(rightBaseX, y, eyeW, 36, eyeR);
  }

  u8g2.sendBuffer();
}

// ---------------- EYES ----------------

void drawEyes(int h, int xOffset, int yOffset) {
  u8g2.clearBuffer();

  int y = (64 - h) / 2 + yOffset;
  int r = eyeR;

  if (h < 16) r = h / 2;
  if (r < 1) r = 1;

  u8g2.drawRBox(leftBaseX + xOffset, y, eyeW, h, r);
  u8g2.drawRBox(rightBaseX + xOffset, y, eyeW, h, r);

  u8g2.sendBuffer();
}

void blinkEyes() {
  Serial.println("ANIMATION: Blink");

  for (int h = 36; h >= 2; h -= 4) {
    drawEyes(h);
    delay(25);
  }

  delay(70);

  for (int h = 2; h <= 36; h += 4) {
    drawEyes(h);
    delay(25);
  }

  drawIdleFace();
}

void happyEyes() {
  Serial.println("ANIMATION: Happy");

  u8g2.clearBuffer();

  u8g2.drawTriangle(10, 38, 46, 24, 46, 38);
  u8g2.drawTriangle(10, 38, 10, 28, 46, 24);

  u8g2.drawTriangle(82, 24, 118, 38, 82, 38);
  u8g2.drawTriangle(118, 38, 118, 28, 82, 24);

  u8g2.sendBuffer();
}

void surpriseEyes() {
  Serial.println("ANIMATION: Surprise");

  u8g2.clearBuffer();

  u8g2.drawRBox(8, 12, 40, 40, 12);
  u8g2.drawRBox(80, 12, 40, 40, 12);

  u8g2.sendBuffer();
}

void lookLeft() {
  Serial.println("ANIMATION: Look left");

  for (int x = 0; x >= -8; x -= 2) {
    drawEyes(36, x);
    delay(40);
  }

  delay(250);

  for (int x = -8; x <= 0; x += 2) {
    drawEyes(36, x);
    delay(40);
  }

  drawIdleFace();
}

void lookRight() {
  Serial.println("ANIMATION: Look right");

  for (int x = 0; x <= 8; x += 2) {
    drawEyes(36, x);
    delay(40);
  }

  delay(250);

  for (int x = 8; x >= 0; x -= 2) {
    drawEyes(36, x);
    delay(40);
  }

  drawIdleFace();
}

void bounceEyes() {
  Serial.println("ANIMATION: Bounce");

  drawEyes(36, 0, 0);
  delay(80);

  drawEyes(38, 0, -3);
  delay(80);

  drawEyes(34, 0, 3);
  delay(80);

  drawEyes(36, 0, 0);
  delay(80);
}

// ---------------- LOW POWER ----------------

void showLowPowerScreen() {
  u8g2.clearBuffer();

  drawStatusBar();

  u8g2.drawRBox(14, 30, 34, 4, 2);
  u8g2.drawRBox(82, 30, 34, 4, 2);

  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.drawStr(43, 55, "Low Power");

  u8g2.sendBuffer();
}

void showVeryLowPowerClock() {
  u8g2.clearBuffer();

  String timeText = getTimeString();

  u8g2.setFont(u8g2_font_ncenB14_tr);

  int w = u8g2.getStrWidth(timeText.c_str());
  u8g2.drawStr((128 - w) / 2, 32, timeText.c_str());

  u8g2.setFont(u8g2_font_6x10_tf);



  // Draw battery percentage text next to battery icon at bottom right
  int percent = constrain((int)batteryFiltered, 0, 100);
  char pctBuf[8];
  sprintf(pctBuf, "%d%%", percent);
  int textWidth = u8g2.getStrWidth(pctBuf);
  
  int textX = chargingConnected ? (102 - textWidth) : (108 - textWidth);
  u8g2.drawStr(textX, 61, pctBuf);

  drawBatteryIcon(110, 54);

  u8g2.sendBuffer();
}

// ---------------- BATTERY ----------------

float readBatteryVoltage() {
#if ENABLE_BATTERY_MONITOR
  long total = 0;

  for (int i = 0; i < 20; i++) {
    total += analogRead(BATTERY_ADC_PIN);
    delay(2);
  }

  float raw = total / 20.0;

  float adcVoltage = (raw / 4095.0) * 3.3;
  float batteryVoltage = adcVoltage * VOLTAGE_DIVIDER_RATIO * BATTERY_CALIBRATION;

  return batteryVoltage;
#else
  return 0.0;
#endif
}

int voltageToPercent(float v) {
  if (v >= 4.20) return 100;
  if (v >= 4.00) return 80;
  if (v >= 3.80) return 60;
  if (v >= 3.60) return 50;
  if (v >= 3.40) return 40;
  if (v >= 3.30) return 35; // 3.3V -> 35%
  if (v >= 3.20) return 20;
  if (v >= 3.10) return 10; // 3.1V -> 10% (shutdown)

  return 0;
}

int readBatteryPercentReal() {
#if ENABLE_BATTERY_MONITOR
  lastBatteryVoltage = readBatteryVoltage();

  Serial.print("BATTERY VOLTAGE: ");
  Serial.print(lastBatteryVoltage, 2);
  Serial.println("V");

  return voltageToPercent(lastBatteryVoltage);
#else
  return batteryPercentRaw;
#endif
}

void updateBatteryAndCharging() {
  if (millis() - lastBatteryUpdate > 2000) {
#if ENABLE_BATTERY_MONITOR
    int targetPercent = readBatteryPercentReal();
#else
    int targetPercent = batteryPercentRaw;
#endif

    float alpha = 0.15;
    batteryFiltered = (batteryFiltered * (1.0 - alpha)) + (targetPercent * alpha);

    Serial.print("BATTERY: ");
    Serial.print((int)batteryFiltered);
    Serial.println("%");

    int currentPercent = constrain((int)batteryFiltered, 0, 100);
    if (currentPercent != lastSentBatteryPercent) {
      lastSentBatteryPercent = currentPercent;
      if (bleConnected) {
        bleSend("BAT " + String(currentPercent));
      }
    }

    lastBatteryUpdate = millis();

    // Check for low battery auto-shutdown (10% or below)
    if (currentPercent <= 10) {
      enterLowBatteryShutdown();
    }
  }
}

// ---------------- PRAYER ----------------

void resetPrayerRemindersIfNewDay() {
  struct tm timeinfo;

  if (!getLocalTimeNow(timeinfo)) {
    return;
  }

  if (timeinfo.tm_mday != lastPrayerDay) {
    lastPrayerDay = timeinfo.tm_mday;

    for (int i = 0; i < 5; i++) {
      prayers[i].reminded = false;
    }

    Serial.println("PRAYER: New day reset");
  }
}

void prayerAnimation(const char* prayerName) {
  Serial.print("PRAYER: ");
  Serial.println(prayerName);

  bleSend(String("PRAYER ") + prayerName);

  u8g2.clearBuffer();

  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.drawStr(30, 10, "Prayer Time");

  u8g2.setFont(u8g2_font_ncenB14_tr);

  int w = u8g2.getStrWidth(prayerName);
  u8g2.drawStr((128 - w) / 2, 36, prayerName);

  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.drawStr(34, 58, "Time to pray");

  u8g2.sendBuffer();

  prayerSound();

  delay(2500);
  drawIdleFace();
}

void checkPrayerReminder() {
  resetPrayerRemindersIfNewDay();

  struct tm timeinfo;

  if (!getLocalTimeNow(timeinfo)) {
    return;
  }

  for (int i = 0; i < 5; i++) {
    if (
      timeinfo.tm_hour == prayers[i].hour &&
      timeinfo.tm_min == prayers[i].minute &&
      prayers[i].reminded == false
    ) {
      prayers[i].reminded = true;
      lastActivityTime = millis();
      currentMode = MODE_IDLE;
      prayerAnimation(prayers[i].name);
    }
  }
}

// ---------------- ROBOT ANIMATION ----------------

void startupAnimation() {
  Serial.println("SYSTEM: Startup animation");

  drawEyes(2);
  delay(300);

  for (int h = 2; h <= 36; h += 3) {
    drawEyes(h);
    delay(35);
  }

  bounceEyes();
  startupSound();

  drawIdleFace();
}

void drawSmallHeart(int x, int y) {
  u8g2.drawDisc(x - 3, y, 4);
  u8g2.drawDisc(x + 3, y, 4);
  u8g2.drawTriangle(x - 7, y + 2, x + 7, y + 2, x, y + 12);
}

void winkClickAnimation() {
  Serial.println("CLICK ANIMATION: Wink");

  u8g2.clearBuffer();

  u8g2.drawRBox(10, 18, 36, 34, 8);
  u8g2.drawRBox(82, 32, 36, 4, 2);

  u8g2.sendBuffer();

  beep(60, 60);
  delay(500);
}

void sleepyClickAnimation() {
  Serial.println("CLICK ANIMATION: Sleepy");

  u8g2.clearBuffer();

  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.drawStr(54, 18, "Zz");

  u8g2.drawRBox(14, 34, 34, 4, 2);
  u8g2.drawRBox(82, 34, 34, 4, 2);

  u8g2.sendBuffer();

  beep(80, 80);
  delay(700);
}

void loveClickAnimation() {
  Serial.println("CLICK ANIMATION: Love");

  for (int i = 0; i < 2; i++) {
    u8g2.clearBuffer();

    drawSmallHeart(30, 20);
    drawSmallHeart(98, 20);

    u8g2.drawRBox(18, 44, 24, 5, 3);
    u8g2.drawRBox(86, 44, 24, 5, 3);

    u8g2.sendBuffer();

    beep(60, 50);
    delay(230);

    u8g2.clearBuffer();

    drawSmallHeart(30, 16);
    drawSmallHeart(98, 16);

    u8g2.drawRBox(18, 42, 24, 5, 3);
    u8g2.drawRBox(86, 42, 24, 5, 3);

    u8g2.sendBuffer();

    delay(230);
  }
}

void dizzyClickAnimation() {
  Serial.println("CLICK ANIMATION: Dizzy");

  for (int i = 0; i < 3; i++) {
    u8g2.clearBuffer();

    u8g2.drawCircle(28, 32, 15);
    u8g2.drawCircle(28, 32, 8);
    u8g2.drawCircle(28, 32, 3);

    u8g2.drawCircle(100, 32, 15);
    u8g2.drawCircle(100, 32, 8);
    u8g2.drawCircle(100, 32, 3);

    u8g2.sendBuffer();

    beep(40, 40);
    delay(220);
  }
}

void danceClickAnimation() {
  Serial.println("CLICK ANIMATION: Dance");

  for (int i = 0; i < 3; i++) {
    drawEyes(34, -8, -2);
    beep(35, 20);
    delay(90);

    drawEyes(38, 8, 2);
    beep(35, 20);
    delay(90);
  }
}

void tinyEyesClickAnimation() {
  Serial.println("CLICK ANIMATION: Tiny eyes");

  drawEyes(24, 0, 0);
  beep(50, 40);
  delay(250);

  drawEyes(12, 0, 0);
  beep(50, 40);
  delay(250);

  drawEyes(36, 0, 0);
  beep(80, 60);
  delay(250);
}

void angryClickAnimation() {
  Serial.println("CLICK ANIMATION: Angry");

  for (int i = 0; i < 2; i++) {
    u8g2.clearBuffer();

    u8g2.drawTriangle(8, 24, 48, 18, 48, 42);
    u8g2.drawTriangle(8, 24, 8, 44, 48, 42);

    u8g2.drawTriangle(120, 24, 80, 18, 80, 42);
    u8g2.drawTriangle(120, 24, 120, 44, 80, 42);

    u8g2.sendBuffer();

    beep(70, 50);
    delay(260);
  }
}

void peekClickAnimation() {
  Serial.println("CLICK ANIMATION: Peek");

  for (int h = 2; h <= 36; h += 5) {
    drawEyes(h, 0, 0);
    delay(45);
  }

  delay(250);

  blinkEyes();
}

void slideEyes(int startX, int startY, int endX, int endY, int durationMs) {
  int steps = 25;
  int stepDelay = durationMs / steps;
  if (stepDelay < 1) stepDelay = 1;
  for (int i = 0; i <= steps; i++) {
    int cx = startX + ((endX - startX) * i) / steps;
    int cy = startY + ((endY - startY) * i) / steps;
    drawEyes(36, cx, cy);
    delay(stepDelay);
  }
}

void buttonAnimation() {
  Serial.println("BUTTON: Short press - playing long animation");
  bleSend("PET");

  // 1. Blink
  blinkEyes();
  delay(200);

  // 2. Slide eyes up-left (slowly, 400ms)
  slideEyes(0, 0, -6, -4, 400);
  delay(1200); // Hold for 1.2s

  // 3. Slide back to center (slowly, 400ms)
  slideEyes(-6, -4, 0, 0, 400);
  delay(200);

  // 4. Slide eyes up-right (slowly, 400ms)
  slideEyes(0, 0, 6, -4, 400);
  delay(1200); // Hold for 1.2s

  // 5. Slide back to center (slowly, 400ms)
  slideEyes(6, -4, 0, 0, 400);
  delay(200);

  // 6. Blink again
  blinkEyes();

  drawIdleFace();
}

// ---------------- POWER OFF / ON ----------------

void enableButtonWakeup() {
  Serial.println("POWER: Wake on GPIO4 LOW");

  pinMode(BUTTON_PIN, INPUT_PULLUP);

  gpio_num_t wakePin = (gpio_num_t)BUTTON_PIN;

  gpio_set_direction(wakePin, GPIO_MODE_INPUT);
  gpio_pullup_en(wakePin);
  gpio_pulldown_dis(wakePin);

  esp_deep_sleep_enable_gpio_wakeup(
    1ULL << BUTTON_PIN,
    ESP_GPIO_WAKEUP_GPIO_LOW
  );
}

bool waitButtonHold(unsigned long holdTime) {
  unsigned long startTime = millis();

  while (millis() - startTime < holdTime) {
    if (digitalRead(BUTTON_PIN) != BUTTON_PRESSED) {
      return false;
    }

    delay(20);
  }

  return true;
}

void powerOffAnimation() {
  Serial.println("POWER: Off animation");
  bleSend("POWER OFF");

  surpriseEyes();
  beep(80, 80);

  for (int h = 36; h >= 2; h -= 3) {
    drawEyes(h);
    delay(35);
  }

  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.drawStr(36, 30, "Power Off");
  u8g2.drawStr(24, 48, "Release button");
  u8g2.sendBuffer();

  beep(80, 60);
  beep(80, 60);
  beep(220, 100);
}

void enterPowerOffSleep() {
  Serial.println("POWER: Going to deep sleep");

  powerOffAnimation();

  while (digitalRead(BUTTON_PIN) == BUTTON_PRESSED) {
    delay(20);
  }

  delay(300);

  buzzerOff();
  stopBLEForSleep();

  u8g2.clearBuffer();
  u8g2.sendBuffer();
  u8g2.setPowerSave(1);

  enableButtonWakeup();

  Serial.println("POWER: Sleep now");
  Serial.flush();

  delay(100);
  esp_deep_sleep_start();
}

void enterLowBatteryShutdown() {
  Serial.println("POWER: Low battery shutdown (<=10%)");
  if (bleTxChar != nullptr) {
    bleSend("POWER OFF LOW_BAT");
    delay(100);
  }

  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.drawStr(32, 28, "Battery Low");
  u8g2.drawStr(30, 44, "Shutting Down");
  u8g2.sendBuffer();

  // Alert sound
  beep(100, 80);
  beep(100, 80);
  beep(200, 100);

  delay(2000);

  buzzerOff();
  stopBLEForSleep();

  u8g2.clearBuffer();
  u8g2.sendBuffer();
  u8g2.setPowerSave(1);

  enableButtonWakeup();

  Serial.println("POWER: Sleep now");
  Serial.flush();

  delay(100);
  esp_deep_sleep_start();
}

void enterSleepAgainWithoutAnimation() {
  Serial.println("POWER: Not held long enough. Sleeping again.");

  buzzerOff();
  stopBLEForSleep();

  u8g2.clearBuffer();
  u8g2.sendBuffer();
  u8g2.setPowerSave(1);

  enableButtonWakeup();

  Serial.flush();

  delay(100);
  esp_deep_sleep_start();
}

void powerOnAnimation() {
  Serial.println("POWER: Power on confirmed");

  u8g2.setPowerSave(0);

  drawEyes(2);
  delay(200);

  for (int h = 2; h <= 36; h += 3) {
    drawEyes(h);
    delay(35);
  }

  bounceEyes();
  startupSound();

  happyEyes();
  delay(600);

  drawIdleFace();

  while (digitalRead(BUTTON_PIN) == BUTTON_PRESSED) {
    delay(20);
  }

  delay(300);

  buttonIsDown = false;
  longPressDone = false;
}

void handlePowerOnBoot() {
  esp_sleep_wakeup_cause_t wakeReason = esp_sleep_get_wakeup_cause();

  if (wakeReason == ESP_SLEEP_WAKEUP_GPIO || wakeReason == ESP_SLEEP_WAKEUP_EXT0) {
    Serial.println("POWER: Woke by button");
    Serial.println("POWER: Keep holding to power on");

    if (digitalRead(BUTTON_PIN) == BUTTON_PRESSED) {
      bool confirmed = waitButtonHold(POWER_ON_HOLD_MS);

      if (confirmed) {
        if (batteryFiltered <= 10) {
          enterLowBatteryShutdown();
        } else {
          powerOnAnimation();
        }
      } else {
        enterSleepAgainWithoutAnimation();
      }
    } else {
      enterSleepAgainWithoutAnimation();
    }
  } else {
    Serial.println("POWER: Normal startup");
    if (batteryFiltered <= 10) {
      enterLowBatteryShutdown();
    } else {
      startupAnimation();
    }
  }
}

// ---------------- BUTTON ----------------

void checkButton() {
  bool currentState = digitalRead(BUTTON_PIN);
  bool pressed = currentState == BUTTON_PRESSED;

  if (pressed && !buttonIsDown) {
    buttonIsDown = true;
    longPressDone = false;
    buttonPressStart = millis();

    Serial.println("BUTTON GPIO4: PRESSED");
  }

  if (pressed && buttonIsDown && !longPressDone) {
    unsigned long pressDuration = millis() - buttonPressStart;

    if (pressDuration >= POWER_OFF_HOLD_MS) {
      longPressDone = true;

      Serial.println("BUTTON: LONG PRESS");
      enterPowerOffSleep();
    }
  }

  if (!pressed && buttonIsDown) {
    unsigned long pressDuration = millis() - buttonPressStart;

    buttonIsDown = false;

    Serial.println("BUTTON GPIO4: RELEASED");

    if (!longPressDone && pressDuration > 50) {
      lastActivityTime = millis();
      currentMode = MODE_IDLE;

      // Temporarily switch display state to STATE_FACE to show the click animation
      DisplayState previousState = currentDisplayState;
      currentDisplayState = STATE_FACE;
      buttonAnimation();
      
      // Restore user-selected screen state after the animation finishes
      currentDisplayState = previousState;
      drawIdleFace();

      lastBlinkTime = millis();
      lastLookTime = millis();
      lastScreenRefresh = millis();
    }
  }
}

// ---------------- POWER MODE ----------------

void updatePowerMode() {
  // Always stay in active mode (MODE_IDLE) to remove screen inactivity sleep modes
  currentMode = MODE_IDLE;
}

// ---------------- COMMANDS ----------------

String twoDigit(int v) {
  if (v < 10) return "0" + String(v);
  return String(v);
}

String prayerValue(int i) {
  return twoDigit(prayers[i].hour) + ":" + twoDigit(prayers[i].minute);
}

bool parseHHMM(String val, int &h, int &m) {
  int colon = val.indexOf(':');

  if (colon < 0) {
    return false;
  }

  h = val.substring(0, colon).toInt();
  m = val.substring(colon + 1).toInt();

  if (h < 0 || h > 23) return false;
  if (m < 0 || m > 59) return false;

  return true;
}

void printHelp() {
  Serial.println();
  Serial.println("BLE COMMANDS:");
  Serial.println("TIME 2026-06-10 22:30:00");
  Serial.println("TIME 22:30:00");
  Serial.println("PRAYER 04:20 12:10 15:45 18:35 20:00");
  Serial.println("STATUS");
  Serial.println("PET");
  Serial.println("BAT 85");
  Serial.println("HELP");
  Serial.println();

  bleSend("HELP READY");
}

void printStatus() {
  Serial.println("------ STATUS ------");

  Serial.print("TIME: ");
  Serial.println(getDateTimeString());

  Serial.print("BLE: ");
  Serial.println(bleConnected ? "CONNECTED" : "ADVERTISING");

  Serial.print("BATTERY: ");
  Serial.print((int)batteryFiltered);
  Serial.println("%");

#if ENABLE_BATTERY_MONITOR
  Serial.print("BATTERY VOLTAGE: ");
  Serial.print(lastBatteryVoltage, 2);
  Serial.println("V");
#endif

  Serial.println("PRAYER:");

  for (int i = 0; i < 5; i++) {
    Serial.print(prayers[i].name);
    Serial.print(" ");
    Serial.println(prayerValue(i));
  }

  Serial.println("--------------------");

  bleSend("TIME " + getDateTimeString());
  bleSend("BAT " + String((int)batteryFiltered));

#if ENABLE_BATTERY_MONITOR
  bleSend("BATV " + String(lastBatteryVoltage, 2));
#endif

  bleSend("FAJR " + prayerValue(0));
  bleSend("DHUHR " + prayerValue(1));
  bleSend("ASR " + prayerValue(2));
  bleSend("MAGHRIB " + prayerValue(3));
  bleSend("ISHA " + prayerValue(4));
  bleSend("DISP " + String((int)currentDisplayState));
}

void handleTimeCommand(String line) {
  int Y, M, D, h, m, s;

  if (sscanf(line.c_str(), "TIME %d-%d-%d %d:%d:%d", &Y, &M, &D, &h, &m, &s) == 6) {
    setClockManual(Y, M, D, h, m, s);
    drawIdleFace();
    return;
  }

  s = 0;

  if (sscanf(line.c_str(), "TIME %d:%d:%d", &h, &m, &s) >= 2) {
    struct tm timeinfo;

    if (!getLocalTimeNow(timeinfo)) {
      setClockManual(2026, 1, 1, h, m, s);
    } else {
      setClockManual(
        timeinfo.tm_year + 1900,
        timeinfo.tm_mon + 1,
        timeinfo.tm_mday,
        h,
        m,
        s
      );
    }

    drawIdleFace();
    return;
  }

  bleSend("TIME ERROR");
  Serial.println("TIME ERROR");
}

void handlePrayerCommand(String line) {
  int h1, m1, h2, m2, h3, m3, h4, m4, h5, m5;

  int ok = sscanf(
    line.c_str(),
    "PRAYER %d:%d %d:%d %d:%d %d:%d %d:%d",
    &h1, &m1,
    &h2, &m2,
    &h3, &m3,
    &h4, &m4,
    &h5, &m5
  );

  if (ok == 10) {
    prayers[0].hour = h1; prayers[0].minute = m1;
    prayers[1].hour = h2; prayers[1].minute = m2;
    prayers[2].hour = h3; prayers[2].minute = m3;
    prayers[3].hour = h4; prayers[3].minute = m4;
    prayers[4].hour = h5; prayers[4].minute = m5;

    for (int i = 0; i < 5; i++) {
      prayers[i].reminded = false;
    }

    savePrayerTimes();

    showTextScreen("Prayer Times", "Updated", "from BLE");
    delay(900);
    drawIdleFace();

    printStatus();
  } else {
    bleSend("PRAYER ERROR");
    Serial.println("PRAYER ERROR");
  }
}

void handleCommand(String line, const char* source) {
  line.trim();

  if (line.length() == 0) {
    return;
  }

  lastActivityTime = millis();
  currentMode = MODE_IDLE;

  String upper = line;
  upper.toUpperCase();

  Serial.print(source);
  Serial.print(" RX: ");
  Serial.println(line);

  if (upper.startsWith("TIME ")) {
    handleTimeCommand(line);
  }

  else if (upper.startsWith("PRAYER ")) {
    handlePrayerCommand(line);
  }

  else if (upper == "STATUS") {
    printStatus();
  }

  else if (upper == "PET") {
    buttonAnimation();
    bleSend("PET OK");
  }

  else if (upper.startsWith("BAT ")) {
#if ENABLE_BATTERY_MONITOR
    bleSend("BAT ADC MODE");
    Serial.println("BAT command ignored because real ADC battery monitor is enabled");
#else
    int value = line.substring(4).toInt();
    batteryPercentRaw = constrain(value, 0, 100);

    bleSend("BAT OK " + String(batteryPercentRaw));
    drawIdleFace();
#endif
  }



  else if (upper.startsWith("DISP ")) {
    int value = line.substring(5).toInt();
    if (value >= 0 && value <= 2) {
      currentDisplayState = (DisplayState)value;
      saveDisplayState();
      drawIdleFace();
      bleSend("DISP OK " + String(value));
    } else {
      bleSend("DISP ERROR");
    }
  }

  else if (upper == "HELP") {
    printHelp();
  }

  else {
    bleSend("UNKNOWN CMD");
    Serial.println("UNKNOWN COMMAND");
  }
}

void handleSerial() {
  if (!Serial.available()) {
    return;
  }

  String line = Serial.readStringUntil('\n');
  handleCommand(line, "SERIAL");
}

// ---------------- SETUP ----------------

void setup() {
  Serial.begin(9600);
  setCustomMacAddress();

  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);

#if ENABLE_BATTERY_MONITOR
  pinMode(BATTERY_ADC_PIN, INPUT);
  analogReadResolution(12);
  analogSetPinAttenuation(BATTERY_ADC_PIN, ADC_11db);
#endif

  digitalWrite(BUZZER_PIN, LOW);

  randomSeed((uint32_t)micros());

  Serial.println();
  Serial.println("SYSTEM: Tiny robot BLE-only starting...");
  Serial.println("OLED: SH1106 128x64");
  Serial.println("OLED SDA: GPIO8");
  Serial.println("OLED SCL: GPIO9");
  Serial.println("BUTTON: GPIO4 INPUT_PULLUP, pressed LOW");
  Serial.println("BUZZER: GPIO5 active buzzer");
  Serial.println("BATTERY ADC: GPIO0");
  Serial.println("BLE NAME: TinyMimiRobot");
  Serial.println("SERIAL: 9600 baud");

  Wire.begin(OLED_SDA, OLED_SCL);

  u8g2.setI2CAddress(0x78);
  u8g2.begin();
  u8g2.setContrast(255);
  u8g2.setPowerSave(0);

  setupTimeZone();
  setClockFromCompileTimeIfNeeded();

  loadSettings();

#if ENABLE_BATTERY_MONITOR
  lastBatteryVoltage = readBatteryVoltage();
  batteryFiltered = voltageToPercent(lastBatteryVoltage);
#endif

  handlePowerOnBoot();

  startBLE();

  drawIdleFace();

  lastActivityTime = millis();
  lastBlinkTime = millis();
  lastLookTime = millis();
  lastScreenRefresh = millis();

  printHelp();
  printStatus();

  Serial.println("SYSTEM: Tiny robot ready");
}

// ---------------- LOOP ----------------

void loop() {
  handleSerial();

  if (bleRxAvailable) {
    bleRxAvailable = false;
    handleCommand(bleRxQueue, "BLE");
  }

  if (restartAdvertisingFlag) {
    restartAdvertisingFlag = false;
    delay(100);
    BLEDevice::startAdvertising();
    Serial.println("BLE: Advertising restarted");
  }

  updateBatteryAndCharging();

  checkButton();

  checkPrayerReminder();

  // Restore random blinking in idle mode (no multiple eye movements)
  if (currentMode == MODE_IDLE && currentDisplayState == STATE_FACE) {
    // Only blink if active interaction occurred in the last 30 seconds
    if (millis() - lastActivityTime < 30000) {
      if (millis() - lastBlinkTime > blinkInterval) {
        blinkEyes();
        lastBlinkTime = millis();
        blinkInterval = random(3000, 7000);
      }
    }
  }

  if (millis() - lastScreenRefresh > 1000) {
    drawIdleFace();
    lastScreenRefresh = millis();
  }

  delay(20);
}