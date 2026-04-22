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
const int JOY_X_PIN   = A0;    // Joystick horizontal axis (analog)
const int JOY_Y_PIN   = A1;    // Joystick vertical axis (analog)
const int JOY_BTN_PIN = 2;     // Joystick built-in push button (digital)
const int FIRE_BTN_PIN = 3;    // Optional external fire button (digital)

// --- Timing ---
const unsigned long SEND_INTERVAL = 20; // Send data every 20ms (~50Hz, fast enough for smooth gameplay)
unsigned long lastSendTime = 0;

// --- Deadzone Filtering ---
// Prevents the ship from drifting when the joystick is at rest but not perfectly centered
const int DEADZONE = 30;      // Raw ADC units around center (512 ± 30)
const int CENTER_X = 512;
const int CENTER_Y = 512;

void setup() {
  Serial.begin(9600);          // Must match Processing's baud rate

  // Configure button pins with internal pull-up resistors
  // (No external resistors needed — press connects to GND, reads LOW)
  pinMode(JOY_BTN_PIN, INPUT_PULLUP);
  pinMode(FIRE_BTN_PIN, INPUT_PULLUP);
}

void loop() {
  // Throttle output rate to prevent flooding the serial buffer
  unsigned long currentTime = millis();
  if (currentTime - lastSendTime < SEND_INTERVAL) return;
  lastSendTime = currentTime;

  // --- Read Joystick Axes ---
  int rawX = analogRead(JOY_X_PIN);
  int rawY = analogRead(JOY_Y_PIN);

  // Apply deadzone: if joystick is near center, snap to exact center
  // This prevents the ship from slowly drifting when the stick is released
  if (abs(rawX - CENTER_X) < DEADZONE) rawX = CENTER_X;
  if (abs(rawY - CENTER_Y) < DEADZONE) rawY = CENTER_Y;

  // --- Read Buttons ---
  // Both buttons use INPUT_PULLUP: pressed = LOW (0), released = HIGH (1)
  int joyButton  = digitalRead(JOY_BTN_PIN);
  int fireButton = digitalRead(FIRE_BTN_PIN);

  // Combine both buttons: if EITHER is pressed, fire
  // This allows the player to use the joystick click OR the external button
  int buttonState = (joyButton == LOW || fireButton == LOW) ? 0 : 1;

  // --- Transmit Data ---
  // Format: "X,Y,BTN\n" — exactly what the Processing serialEvent() expects
  Serial.print(rawX);
  Serial.print(",");
  Serial.print(rawY);
  Serial.print(",");
  Serial.println(buttonState);  // println adds the '\n' terminator
}
