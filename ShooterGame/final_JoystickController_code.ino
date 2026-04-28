/**
 * ============================================================================
 * SPACE DEFENDER - ARDUINO JOYSTICK CONTROLLER
 * ============================================================================
 * Reads analog joystick position (X, Y) and a fire button, then transmits
 * the data to the Processing game engine over Serial USB.
 *
 * OUTPUT FORMAT (sent every loop iteration):
 *   "X_VALUE,Y_VALUE,BUTTON_STATE\n"
 *   - X_VALUE:      0-1023 (raw analog, left-right)
 *   - Y_VALUE:      0-1023 (raw analog, up-down)
 *   - BUTTON_STATE:  0 = pressed (fire), 1 = not pressed
 *
 * HARDWARE REQUIRED:
 *   - Arduino Uno / Nano / Mega (any board with analog pins)
 *   - KY-023 Joystick Module (or equivalent with VRx, VRy, SW)
 *   - (Optional) External push button for dedicated fire control
 *
 * WIRING GUIDE:
 *   Joystick Module       Arduino
 *   ──────────────────────────────
 *   GND          ──────>  GND
 *   +5V          ──────>  5V
 *   VRx          ──────>  A0  (Analog Pin 0)
 *   VRy          ──────>  A1  (Analog Pin 1)
 *   SW           ──────>  D2  (Digital Pin 2, uses internal pull-up)
 *
 *   External Button (Optional)
 *   ──────────────────────────────
 *   One leg      ──────>  D3  (Digital Pin 3, uses internal pull-up)
 *   Other leg    ──────>  GND
 *
 * NOTE: The game expects the joystick center idle position to be ~512, ~512.
 *       Most KY-023 modules are factory-calibrated to this.
 * ============================================================================
 */

// --- Pin Definitions ---
// --- Pin Definitions ---
//🎮 Joystick Pins
const int JOY_X_PIN = A0;
const int JOY_Y_PIN = A1;
const int BTN_PIN   = 2;

// 🔥 Deadzone (increase for stability)
const int DEADZONE = 100;

// 🎯 Center (auto calibrated)
int centerX = 512;
int centerY = 512;

// 🔥 Smoothing
float smoothX = 512;
float smoothY = 512;
float alpha = 0.1;   // lower = smoother

void setup() {
  Serial.begin(9600);
  pinMode(BTN_PIN, INPUT_PULLUP);

  delay(2000); // ⚠️ Don't touch joystick

  // 🔥 Auto calibration
  centerX = analogRead(JOY_X_PIN);
  centerY = analogRead(JOY_Y_PIN);
}

void loop() {
  int rawX = analogRead(JOY_X_PIN);
  int rawY = analogRead(JOY_Y_PIN);

  // 🔥 Apply smoothing (low-pass filter)
  smoothX = alpha * rawX + (1 - alpha) * smoothX;
  smoothY = alpha * rawY + (1 - alpha) * smoothY;

  int x = (int)smoothX;
  int y = (int)smoothY;

  // 🔥 Apply deadzone
  if (abs(x - centerX) < DEADZONE) x = centerX;
  if (abs(y - centerY) < DEADZONE) y = centerY;

  // 🔘 Button (0 = pressed)
  int button = digitalRead(BTN_PIN);

  // 📡 Send data to Processing
  Serial.print(x);
  Serial.print(",");
  Serial.print(y);
  Serial.print(",");
  Serial.println(button);

  delay(20); // stable rate
}
