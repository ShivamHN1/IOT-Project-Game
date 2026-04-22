/**
 * ============================================================================
 * SPACE DEFENDER - IOT PROJECT GAME ENGINE
 * ============================================================================
 * An arcade-style top-down space shooter built in Processing.
 * 
 * ARCHITECTURE OVERVIEW:
 * - State Machine: Controlled via `gameState` (0=Menu, 1=Playing, 2=GameOver).
 * - Entity Component: Game objects handled via ArrayLists (enemies, bullets, particles).
 * - Hardware Integration: Receives real-world joystick input via Serial (Arduino).
 * - Active Input Switching: Seamlessly hot-swaps between keyboard and joystick at runtime.
 * 
 * HOW TO USE HARDWARE:
 * 1. Set `useSerial = true`
 * 2. Ensure Arduino is printing string payloads: "X_VAL,Y_VAL,BUTTON_STATE\n"
 * 3. Match the Serial baud rate (9600 default).
 * 4. Both keyboard and joystick work simultaneously - last used input takes control.
 * ============================================================================
 */
import processing.serial.*;  // Handles Arduino/Joystick communication
import processing.sound.*;   // Handles procedural audio generation
boolean useSerial = true; // Enabled for IoT hardware presentation

Serial myPort;  // Serial port for joystick
float playerX, playerY;  // Player position
float playerSize = 40;   // Size of the player's aircraft
int gameState = 0;       // 0 = Main Menu, 1 = Playing, 2 = Game Over
int stateTransitionCooldown = 0; // Prevent instant restarts when spamming button

// --- Phase 1: Game State Variables ---
int score = 0;
int highScore = 0; // High score tracker
int lives = 3;
int level = 1;
int lastLevel = 1;      // To detect level up events
int levelUpTimer = 0;   // Frames to show level up overlay
boolean isPaused = false; // Pause state
int countdownTimer = 0;   // 3-2-1 counter for game starts

// --- Input control state ---
boolean keyLeft = false, keyRight = false, keyUp = false, keyDown = false;
boolean spaceHeld = false;
int shootCooldown = 0;  // Prevent bullet spam
boolean usingJoystick = false; // Active Input Switching: true = joystick controls ship, false = keyboard

// --- Sound Objects ---
SqrOsc playerLaser;
SqrOsc enemyLaser;
TriOsc explosionSound;
SqrOsc hurtSound; // Distinct sound for player taking damage
Env envPLaser, envELaser, envExplosion, envHurt;

// --- Polish / Feel Variables ---
int invincibilityTimer = 0; // i-frames after getting hit
float screenShake = 0;      // visual impact when getting hit
float playerBank = 0;       // ship tilting when moving horizontally
float playerVX = 0;         // player X velocity for smooth gliding
float playerVY = 0;         // player Y velocity for smooth gliding

Star[] stars;              // Starfield array
ArrayList<Enemy> enemies;  // List of enemies
ArrayList<Bullet> bullets; // List of enemy bullets
ArrayList<PlayerBullet> playerBullets; // List of player bullets
ArrayList<Particle> particles; // List of explosion particles
ArrayList<FloatingText> popups; // List of floating score popups
int spawnTimer = 0;        // Timer for spawning enemies
int playerMuzzleFlash = 0; // Frames to show bright gun flashes

/**
 * SETUP LOOP
 * Runs exactly once when the program starts. Initializes the window canvas,
 * establishes hardware connections, sets up the audio synthesizers, 
 * and builds the background starfield arrays.
 */
void setup() {
  size(600, 600);  // Defines the application window resolution

  if (useSerial) {
    // Safety: Check that a serial port actually exists before attempting connection
    printArray(Serial.list()); // List all ports to console to help identify Arduino
    if (Serial.list().length > 0) {
      try {
        myPort = new Serial(this, Serial.list()[0], 9600);
        myPort.bufferUntil('\n');
        println("Serial connected on: " + Serial.list()[0]);
      } catch (Exception e) {
        println("ERROR: Could not open serial port (may be in use). Falling back to keyboard.");
        useSerial = false;
      }
    } else {
      println("WARNING: No serial ports found. Falling back to keyboard mode.");
      useSerial = false;
    }
  }

  // Initialize Sounds
  playerLaser = new SqrOsc(this);
  enemyLaser = new SqrOsc(this);
  explosionSound = new TriOsc(this);
  hurtSound = new SqrOsc(this);
  envPLaser = new Env(this);
  envELaser = new Env(this);
  envExplosion = new Env(this);
  envHurt = new Env(this);

  // Initialize starfield
  stars = new Star[100];
  for (int i = 0; i < stars.length; i++) {
    stars[i] = new Star();
  }

  loadHighScore();   // Read from disk
  initializeGame();  // Initialize variables
  gameState = 0;     // Force start at the main menu
}

/**
 * MAIN ENGINE LOOP (draw)
 * Executes ~60 times per second. Acts as the primary orchestrator.
 * Designed to manage the State Machine, handle physics/movement updates, 
 * perform continuous collision detection, and render all graphics to the screen.
 */
void draw() {
  background(8, 12, 24);  // Deep navy blue space instead of flat black

  // Update and draw starfield behind everything
  for (Star s : stars) {
    s.update();
    s.show();
  }

  // Decrement cooldowns BEFORE any early returns so they work on all screens
  if (stateTransitionCooldown > 0) stateTransitionCooldown--;

  // Handle Pause UI - Render early to skip gameplay logic
  if (gameState == 1 && isPaused) {
    drawPausedOverlay();
    return;
  }

  if (gameState == 0) {
    // --- MAIN MENU SCREEN ---
    
    // Dramatic glow behind title
    noStroke();
    fill(0, 255, 255, 20 + sin(frameCount * 0.05) * 15);
    ellipse(width / 2, height / 2 - 80, 500, 120);
    
    // Title with shadow for depth
    textAlign(CENTER, CENTER);
    textSize(52);
    fill(0, 80, 80);
    text("SPACE DEFENDER", width / 2 + 3, height / 2 - 77); // Shadow
    fill(0, 255, 255);
    text("SPACE DEFENDER", width / 2, height / 2 - 80);
    
    // Subtitle
    fill(100, 200, 255, 180);
    textSize(14);
    text("IOT ARCADE EXPERIENCE", width / 2, height / 2 - 52);
    
    // High Score Display
    fill(255, 200, 0);
    textSize(18);
    if (highScore > 0) text("HIGH SCORE: " + nf(highScore, 6), width / 2, height / 2 - 30);
    
    // Divider line
    stroke(0, 255, 255, 60);
    strokeWeight(1);
    line(width / 2 - 150, height / 2 - 15, width / 2 + 150, height / 2 - 15);
    noStroke();
    
    // Controls - show both input methods
    fill(200);
    textSize(15);
    text("KEYBOARD: WASD / Arrows + SPACE to Shoot", width / 2, height / 2 + 5);
    fill(150, 255, 150);
    text("JOYSTICK: Analog Stick + Button to Shoot", width / 2, height / 2 + 28);
    
    // Add pulsing effect for start text
    float pulse = map(sin(frameCount * 0.08), -1, 1, 80, 255);
    fill(255, 255, 100, pulse);
    textSize(26);
    text("PRESS SPACE / JOYSTICK BUTTON", width / 2, height / 2 + 80);
    
    // Animated arrow indicators pointing at the start text
    float arrowBounce = sin(frameCount * 0.1) * 5;
    fill(255, 255, 100, pulse * 0.6);
    triangle(width / 2 - 200, height / 2 + 80 + arrowBounce, width / 2 - 190, height / 2 + 74 + arrowBounce, width / 2 - 190, height / 2 + 86 + arrowBounce);
    triangle(width / 2 + 200, height / 2 + 80 + arrowBounce, width / 2 + 190, height / 2 + 74 + arrowBounce, width / 2 + 190, height / 2 + 86 + arrowBounce);
    
    // Aesthetic decorative ship at bottom with enhanced presentation
    pushMatrix();
    translate(width / 2, height - 100 + sin(frameCount * 0.05) * 10); // Hover effect
    noStroke();
    
    // Engine glow underneath
    fill(255, 100, 0, 40);
    ellipse(0, 50, 60, 40);
    
    fill(255, random(150, 255), 0); triangle(-8, 35, 8, 35, 0, 55 + random(-10, 10)); // Flame
    fill(150); triangle(0, 0, -25, 35, 25, 35); // Wings
    fill(100); rectMode(CENTER); rect(-25, 35, 6, 20); rect(25, 35, 6, 20); // Guns
    fill(220); ellipse(0, 15, 18, 50); // Body
    fill(0, 200, 255); ellipse(0, 10, 10, 20); // Cockpit
    popMatrix();

    return; // Stop here, don't run game logic
  }

  // Apply screen shake if active
  if (screenShake > 0) {
    translate(random(-screenShake, screenShake), random(-screenShake, screenShake));
    screenShake *= 0.9; // Decay the shake rapidly
    if (screenShake < 0.5) screenShake = 0;
  }

  // Update and draw explosion particles (so they run even during game over)
  for (int i = particles.size() - 1; i >= 0; i--) {
    Particle p = particles.get(i);
    p.update();
    p.show();
    if (p.isDead()) {
      particles.remove(i);
    }
  }

  if (gameState == 2) {
    // Show "Game Over" screen - Cinematic dark overlay
    fill(0, 0, 0, 180);
    rectMode(CORNER);
    noStroke();
    rect(0, 0, width, height);

    // Red vignette effect
    for (int i = 0; i < 5; i++) {
      fill(255, 0, 0, 8 - i * 1.5);
      rect(i * 20, i * 20, width - i * 40, height - i * 40);
    }

    // Title shadow + text
    textAlign(CENTER, CENTER);
    textSize(64);
    fill(80, 0, 0);
    text("GAME OVER", width / 2 + 3, height / 2 - 77);
    fill(255, 50, 50);
    text("GAME OVER", width / 2, height / 2 - 80);
    
    // Divider
    stroke(255, 50, 50, 80);
    strokeWeight(1);
    line(width / 2 - 120, height / 2 - 45, width / 2 + 120, height / 2 - 45);
    noStroke();
    
    fill(255);
    textSize(28);
    text("FINAL SCORE: " + nf(score, 6), width / 2, height / 2 - 20);
    
    // NEW HIGH SCORE callout - only if score actually beat the record
    if (score > 0 && score > highScore) {
      float glow = map(sin(frameCount * 0.15), -1, 1, 150, 255);
      fill(255, 200, 0, glow);
      textSize(22);
      text("\u2605 NEW HIGH SCORE! \u2605", width / 2, height / 2 + 15);
    } else {
      fill(255, 200, 0, 180);
      textSize(18);
      text("High Score: " + nf(highScore, 6), width / 2, height / 2 + 15);
    }
    
    fill(0, 255, 255);
    textSize(16);
    text("Level Reached: " + level, width / 2, height / 2 + 45);
    
    // Pulsing restart prompt
    float restartPulse = map(sin(frameCount * 0.08), -1, 1, 100, 255);
    fill(200, 200, 200, restartPulse);
    textSize(18);
    text("Press R / Joystick Button to Restart", width / 2, height / 2 + 90);
    return;
  }
  
  if (gameState == 1 && countdownTimer > 0) {
    countdownTimer--;
    drawCountdownOverlay();
    // Do NOT return here — we want stars and particles to keep moving
  }

  // Update level based on score (Difficulty scaling) - Capped to level 10
  level = min(10, 1 + (score / 100));

  // Detect Level Up for visual feedback
  if (level > lastLevel) {
    levelUpTimer = 120; // Show for 2 seconds
    lastLevel = level;
  }

  if (gameState == 1 && countdownTimer <= 0 && !usingJoystick) {
    // --- KEYBOARD MODE: Smooth velocity-based movement ---
    float accel = 0.8;
    float maxSpeed = 6.0;
    float friction = 0.85; // Sliding friction
    
    if (keyLeft)  playerVX -= accel;
    if (keyRight) playerVX += accel;
    if (keyUp)    playerVY -= accel;
    if (keyDown)  playerVY += accel;
    
    // Apply friction when no keys pressed
    if (!keyLeft && !keyRight) playerVX *= friction;
    if (!keyUp && !keyDown) playerVY *= friction;
    
    // Clamp speed to maximums
    playerVX = constrain(playerVX, -maxSpeed, maxSpeed);
    playerVY = constrain(playerVY, -maxSpeed, maxSpeed);
    
    playerX += playerVX;
    playerY += playerVY;

    // Constrain player to screen bounds (Y is restricted to bottom half to prevent unfair instant spawn-deaths)
    playerX = constrain(playerX, 20, width - 20);
    playerY = constrain(playerY, height / 2, height - 20);
  }
  // NOTE: Joystick mode movement is handled directly in serialEvent() via absolute positioning

  // Unified shooting for BOTH input modes (spaceHeld is set by keyboard OR joystick button)
  if (spaceHeld && shootCooldown <= 0 && countdownTimer <= 0) {
    playerBullets.add(new PlayerBullet(playerX, playerY));
    playerMuzzleFlash = 5; // Set flash duration
    
    // Play procedural high-pitch laser sound
    playerLaser.freq(random(800, 1000));
    playerLaser.play();
    envPLaser.play(playerLaser, 0.01, 0.05, 0.1, 0.1);
    
    shootCooldown = 12;
  }
  // Decrement shoot cooldown OUTSIDE input-mode block so it works for BOTH keyboard and joystick
  if (shootCooldown > 0) shootCooldown--;

  // Smooth banking for player ship
  // Calculate horizontal tilt depending on velocity (works for both Keyboard and Joystick via playerVX)
  float targetBank = map(playerVX, -6, 6, -0.4, 0.4);
  playerBank = lerp(playerBank, targetBank, 0.2);

  // Draw Player Aircraft
  noStroke();
  
  pushMatrix();
  translate(playerX, playerY);
  rotate(playerBank); // Tilt the ship based on movement
  
  // Make ship flash during invincibility frames
  boolean isVisible = true;
  if (invincibilityTimer > 0) {
    invincibilityTimer--;
    if (frameCount % 10 < 5) isVisible = false; // Blink effect
    
    // Draw energy shield glow around ship (visible even during blink-off frames)
    float shieldPulse = map(sin(frameCount * 0.3), -1, 1, 80, 180);
    fill(0, 200, 255, shieldPulse * 0.3);
    ellipse(0, 15, 70, 75);
    stroke(0, 200, 255, shieldPulse);
    strokeWeight(1.5);
    noFill();
    ellipse(0, 15, 65, 70);
    noStroke();
  }

  if (isVisible) {
    // Engine thruster flame (flickering effect)
    fill(255, 50, 0, 150); // Thruster outer glow
    ellipse(0, 45, 20, 30 + random(10));
    fill(255, random(150, 255), 0); // Inner hot flame
    triangle(-8, 35, 8, 35, 0, 55 + random(-10, 10));

    // Main wings structure
    fill(150);
    triangle(0, 0, -25, 35, 25, 35);
    
    // Wing details/guns
    fill(100);
    rectMode(CENTER);
    rect(-25, 35, 6, 20);
    rect(25, 35, 6, 20);

    // Dynamic Muzzle Flash on firing
    if (playerMuzzleFlash > 0) {
      fill(255, 255, random(150, 255), 200); // Bright glowing yellow/white
      ellipse(-25, 20, 15, 25);
      ellipse(25, 20, 15, 25);
      playerMuzzleFlash--;
    }

    // Main fuselage (body)
    fill(220);
    ellipse(0, 15, 18, 50);

    // Cockpit window
    fill(0, 200, 255);
    ellipse(0, 10, 10, 20);
  }
  popMatrix();

  // Logic updates should only happen if not in countdown
  if (gameState == 1 && countdownTimer <= 0) {
    // Update and draw enemies
    for (int i = enemies.size() - 1; i >= 0; i--) {
      Enemy e = enemies.get(i);
      e.update();
      e.show();
      if (e.isOffScreen()) {
        enemies.remove(i);
      }
    }

    // Update and draw enemy bullets
    for (int i = bullets.size() - 1; i >= 0; i--) {
      Bullet b = bullets.get(i);
      b.update();
      b.show();
      if (b.isOffScreen()) {
        bullets.remove(i);
      } else if (invincibilityTimer <= 0 && b.hitsPlayer(playerX, playerY, playerSize)) {
        lives--;
        bullets.remove(i);
        hurtSound.freq(random(150, 200));
        hurtSound.play();
        envHurt.play(hurtSound, 0.01, 0.1, 0.5, 0.2);
        createExplosion(playerX, playerY);
        screenShake = 15;
        invincibilityTimer = 90;
        if (lives <= 0) {
          if (score > 0 && score > highScore) { highScore = score; saveHighScore(); }
          gameState = 2; stateTransitionCooldown = 60;
        }
      }
    }

    // Check if enemy crashes directly into player
    for (int i = enemies.size() - 1; i >= 0; i--) {
      Enemy e = enemies.get(i);
      if (invincibilityTimer <= 0 && dist(playerX, playerY, e.x, e.y) < (playerSize + e.size) / 2) {
        lives--;
        hurtSound.freq(random(100, 150));
        hurtSound.play();
        envHurt.play(hurtSound, 0.01, 0.1, 0.6, 0.3);
        createExplosion(e.x, e.y);
        enemies.remove(i);
        screenShake = 20;
        invincibilityTimer = 90;
        if (lives <= 0) {
          if (score > 0 && score > highScore) { highScore = score; saveHighScore(); }
          gameState = 2; stateTransitionCooldown = 60;
        }
      }
    }

    // Spawn Logic
    spawnTimer++;
    int spawnRate = max(20, 60 - (level * 5)); 
    if (spawnTimer > spawnRate) {  
      enemies.add(new Enemy());
      spawnTimer = 0;
    }
  } else if (gameState == 1) {
    // During countdown, just show existing entities (static)
    for (Enemy e : enemies) e.show();
    for (Bullet b : bullets) b.show();
  }

  // Update and draw player bullets
  for (int i = playerBullets.size() - 1; i >= 0; i--) {
    PlayerBullet pb = playerBullets.get(i);
    pb.update();
    pb.show();

    boolean removed = false;

    // Check if the bullet hits any enemy
    for (int j = enemies.size() - 1; j >= 0; j--) {
      if (pb.hitsEnemy(enemies.get(j))) {
        Enemy hitEnemy = enemies.get(j);
        createExplosion(hitEnemy.x, hitEnemy.y); // Create explosion visually
        // Note: flashTimer is NOT set here because the enemy is destroyed immediately.
        
        // Floating score popup!
        popups.add(new FloatingText(hitEnemy.x, hitEnemy.y - 15, "+10"));
        
        enemies.remove(j);        // Remove the enemy
        playerBullets.remove(i);  // Remove the player bullet
        removed = true;
        score += 10;              // Increase score!
        break;
      }
    }

    // Only check off-screen if not already removed
    if (!removed && pb.isOffScreen()) {
      playerBullets.remove(i);
    }
  }

  // Particles handled at top of draw loop

  // Update and draw floating text popups
  for (int i = popups.size() - 1; i >= 0; i--) {
    FloatingText ft = popups.get(i);
    ft.update();
    ft.show();
    if (ft.isDead()) popups.remove(i);
  }

  // Spawn Logic moved into non-countdown block above
  
  // HUD gradient: fade from opaque at top to transparent — only 6 bands for performance
  for (int i = 0; i < 6; i++) {
    fill(0, 0, 0, map(i, 0, 5, 190, 0));
    rectMode(CORNER);
    rect(0, i * 9, width, 10); // 10px tall bands covering the ~55px HUD zone
  }

  fill(0, 255, 255); // Cyan text for futuristic vibe
  textAlign(LEFT, TOP);
  textSize(20);
  text("SCORE: " + nf(score, 6), 15, 15); // Format score with leading zeros
  
  // Draw little ship icons for lives instead of text
  for (int i = 0; i < lives; i++) {
    fill(0, 255, 0);
    triangle(180 + (i * 25), 30, 170 + (i * 25), 45, 190 + (i * 25), 45);
  }

  fill(255, 200, 0); // Gold text for level
  textAlign(RIGHT, TOP);
  text("LEVEL " + level, width - 15, 15);
  
  // Input mode indicator
  textSize(10);
  fill(100, 100, 100);
  textAlign(RIGHT, TOP);
  text(usingJoystick ? "[JOYSTICK]" : "[KEYBOARD]", width - 15, 38);

  // --- LEVEL UP OVERLAY ---
  if (levelUpTimer > 0) {
    levelUpTimer--;
    float progress = levelUpTimer / 120.0;
    float alpha = progress * 255;
    
    // Screen flash on level up (only first few frames)
    if (levelUpTimer > 110) {
      fill(255, 255, 100, (levelUpTimer - 110) * 25);
      rectMode(CORNER);
      rect(0, 0, width, height);
    }
    
    // Scaling text effect: text starts big and eases to resting size
    // Clamp scaleEffect to max 1.8 so text never becomes enormous
    float scaleEffect = constrain(1.0 + (progress > 0.8 ? (progress - 0.8) * 5.0 : 0), 1.0, 1.8);
    
    textAlign(CENTER, CENTER);
    
    // Glow behind text
    fill(255, 200, 0, alpha * 0.2);
    ellipse(width / 2, height / 2 - 30, 350 * scaleEffect, 100 * scaleEffect);
    
    textSize(55 * scaleEffect);
    fill(255, 255, 100, alpha);
    text("LEVEL " + level, width / 2, height / 2 - 40);
    
    textSize(18);
    fill(255, 200, 100, alpha * 0.8);
    text("DIFFICULTY INCREASED", width / 2, height / 2 + 10);
  }
  
  // Final safeguard: ensure pause indicator is visible on HUD
  if (isPaused) {
    drawPausedOverlay();
  }
}

/**
 * UI: PAUSE OVERLAY
 */
void drawPausedOverlay() {
  fill(0, 0, 0, 150);
  rectMode(CORNER);
  rect(0, 0, width, height);
  
  textAlign(CENTER, CENTER);
  textSize(60);
  fill(0, 255, 255);
  text("PAUSED", width / 2, height / 2 - 20);
  
  textSize(20);
  fill(200);
  text("PRESS 'P' TO RESUME", width / 2, height / 2 + 30);
}

/**
 * UI: COUNTDOWN OVERLAY
 */
void drawCountdownOverlay() {
  int seconds = (countdownTimer / 60) + 1;
  String display = str(seconds);
  if (countdownTimer < 40) display = "GO!";
  
  // Pulsing scale for numbers
  float s = 1.0 + (countdownTimer % 60) / 40.0;
  if (countdownTimer < 40) s = 1.0 + (40 - countdownTimer) / 20.0;
  
  textAlign(CENTER, CENTER);
  textSize(80 * s);
  fill(255, 255, 100, map(s, 1, 2, 255, 0));
  text(display, width / 2, height / 2);
}

// --- Keyboard input handlers ---
void keyPressed() {
  if (gameState == 0 && key == ' ' && stateTransitionCooldown <= 0) {
    initializeGame();
    return;
  }

  if (gameState == 2 && (key == 'r' || key == 'R') && stateTransitionCooldown <= 0) {
    initializeGame();
    return;
  }

  if (gameState != 1) return;

  // Handle Pause Toggle
  if (key == 'p' || key == 'P') {
    isPaused = !isPaused;
    return;
  }

  // Any gameplay key press instantly switches to keyboard mode
  usingJoystick = false;

  if (key == CODED) {
    if (keyCode == LEFT)  keyLeft  = true;
    if (keyCode == RIGHT) keyRight = true;
    if (keyCode == UP)    keyUp    = true;
    if (keyCode == DOWN)  keyDown  = true;
  }

  if (key == 'a' || key == 'A') keyLeft  = true;
  if (key == 'd' || key == 'D') keyRight = true;
  if (key == 'w' || key == 'W') keyUp    = true;
  if (key == 's' || key == 'S') keyDown  = true;

  if (key == ' ') spaceHeld = true;
}

void keyReleased() {
  // Only process key releases during gameplay to prevent stale key states
  if (gameState != 1) return;

  if (key == CODED) {
    if (keyCode == LEFT)  keyLeft  = false;
    if (keyCode == RIGHT) keyRight = false;
    if (keyCode == UP)    keyUp    = false;
    if (keyCode == DOWN)  keyDown  = false;
  }

  if (key == 'a' || key == 'A') keyLeft  = false;
  if (key == 'd' || key == 'D') keyRight = false;
  if (key == 'w' || key == 'W') keyUp    = false;
  if (key == 's' || key == 'S') keyDown  = false;

  if (key == ' ') spaceHeld = false;
}

/**
 * HARDWARE INTERRUPT HANDLER
 * Automatically triggered by Processing whenever new data arrives on the Serial port.
 * Parses the incoming string chunk ("X,Y,BTN\n") into usable data,
 * maps raw potentiometer values (0-1023) to screen coordinates, and triggers analog actions.
 * 
 * INPUT SWITCHING LOGIC:
 * - If the joystick analog stick is moved outside a center deadzone, `usingJoystick` is set to true
 *   and the ship locks onto the joystick's absolute position.
 * - If a keyboard key is pressed (handled in keyPressed()), `usingJoystick` is set to false
 *   and the ship returns to velocity-based keyboard physics.
 * 
 * BUTTON MAPPING (single joystick button handles all actions):
 * - Menu Screen (gameState 0): Button press = Start Game
 * - Playing    (gameState 1): Button held  = Fire bullets
 * - Game Over  (gameState 2): Button press = Restart Game
 */
void serialEvent(Serial myPort) {
  if (!useSerial) return;

  String data = myPort.readStringUntil('\n');
  if (data == null) return;

  data = trim(data);
  String[] values = split(data, ',');

  if (values.length == 3) {
    try {
      float parsedX = float(values[0]);
      float parsedY = float(values[1]);
      int buttonState = int(values[2]);

      // SAFETY CHECK: If string failed to parse into a float due to serial noise, ignore this frame
      if (Float.isNaN(parsedX) || Float.isNaN(parsedY)) return;

      // Clamp raw input to valid ADC range before mapping to prevent out-of-bounds coordinates
      parsedX = constrain(parsedX, 0, 1023);
      parsedY = constrain(parsedY, 0, 1023);

      // --- BUTTON MAPPING: Single button handles Start, Fire, and Restart ---
      // Menu: Button press starts the game
      if (gameState == 0 && buttonState == 0 && stateTransitionCooldown <= 0) {
        initializeGame();
        return;
      }
      // Game Over: Button press restarts the game
      if (gameState == 2 && buttonState == 0 && stateTransitionCooldown <= 0) {
        initializeGame();
        return;
      }

      if (gameState == 1) {
        // --- JOYSTICK DEADZONE DETECTION for Active Input Switching ---
        // If the stick is pushed away from center (512), switch to joystick mode.
        // Deadzone prevents tiny analog drift from stealing control from keyboard.
        float joystickDeadzone = 30; // Adjust if your stick is loose/tight
        boolean stickMoved = (abs(parsedX - 512) > joystickDeadzone) || (abs(parsedY - 512) > joystickDeadzone);
        
        if (stickMoved) {
          usingJoystick = true; // Joystick takes control
          
          // Map joystick to absolute screen position (your deliberate game mechanic)
          float xValue = map(parsedX, 0, 1023, 0, width);
          float yValue = map(parsedY, 0, 1023, height / 2, height);
          
          float oldX = playerX; // Track old X for banking math
          playerX = constrain(xValue, 20, width - 20);
          playerY = constrain(yValue, height / 2, height - 20);
          
          // Update playerVX so the ship automatically banks (tilts) while using the joystick
          playerVX = playerX - oldX;
        }

        // --- PAUSE TOGGLE via Joystick? (Optional: if the user holds stick still and presses button? No, let's stick to 'P') ---
        // spaceHeld handles shooting but only if not paused
        if (!isPaused) spaceHeld = (buttonState == 0);
      }
    } catch (Exception e) {
      // Catch any unexpected parseInt/parseFloat failures from corrupted serial data
      println("Hardware Communication Error: " + e.getMessage());
    }
  }
}

/**
 * GAME STATE RESET ROUTINE
 * Cleans the board by purging all active entity memory lists, resets the player's 
 * position, and restores score/lives/levels to their default starting values.
 * Called when transitioning from Main Menu to Playing, or when triggering a Restart.
 */
void initializeGame() {
  playerX = width / 2;
  playerY = height - 60;

  enemies     = new ArrayList<Enemy>();
  bullets     = new ArrayList<Bullet>();
  playerBullets = new ArrayList<PlayerBullet>();
  particles   = new ArrayList<Particle>();
  popups      = new ArrayList<FloatingText>();

  spawnTimer    = 0;
  gameState     = 1;  // Set state to Playing
  shootCooldown = 0;
  // Reset input and momentum vectors to prevent ghost-drifting if you restart while holding keys
  spaceHeld = false;
  keyLeft = false; keyRight = false; keyUp = false; keyDown = false;
  playerVX = 0; playerVY = 0;
  usingJoystick = false; // Default to keyboard on fresh game start
  
  // Reset all visual effect states to prevent carry-over between games
  invincibilityTimer = 0;
  screenShake = 0;
  playerBank = 0;
  playerMuzzleFlash = 0;
  
  // Phase 1 Resets
  score = 0;
  lives = 3;
  level = 1;
  lastLevel = 1;
  levelUpTimer = 0;
  
  isPaused = false;
  countdownTimer = 180; // 3 second countdown
}

/**
 * FILE I/O: HIGH SCORE PERSISTENCE
 */
void loadHighScore() {
  try {
    String[] lines = loadStrings("data/highscore.txt");
    if (lines != null && lines.length > 0) {
      highScore = int(lines[0]);
    }
  } catch (Exception e) {
    println("No highscore file found - starting fresh.");
    highScore = 0;
  }
}

void saveHighScore() {
  String[] lines = { str(highScore) };
  saveStrings("data/highscore.txt", lines);
}

/**
 * FX FACTORY: EXPLOSION
 * Instantiates the necessary audio and visual components to simulate a dynamic space crash.
 * Uses a Triangle wave envelope for low audio rumble and spawns a burst array of Particles.
 * @param ex The X coordinate of the explosion epicenter.
 * @param ey The Y coordinate of the explosion epicenter.
 */
void createExplosion(float ex, float ey) {
  // Explosion sound
  explosionSound.freq(random(80, 120));
  explosionSound.play();
  envExplosion.play(explosionSound, 0.01, 0.1, 0.3, 0.2);

  // Initial flash particle (big and white)
  particles.add(new Particle(ex, ey, true));

  for (int i = 0; i < 30; i++) {
    particles.add(new Particle(ex, ey, false));
  }
}

/**
 * ENEMY ENTITY CLASS
 * Represents hostile ships. Spawns at the top of the screen and travels
 * downwards. Fires projectiles rhythmically based on a randomized offset
 * to ensure organic, unpredictable bullet patterns across multiple entities.
 */
class Enemy {
  float speed;
  int shootOffset; // For desynchronized shooting
  int flashTimer = 0; // Visual feedback when hit
  int type; // 0 = Straight, 1 = Weaver
  float waveOffset; // For movement math

  Enemy() {
    x = random(40, width - 40);
    y = -40;
    size = 40;
    
    // Type chance increases with level
    float weaverChance = map(level, 1, 10, 0.05, 0.6);
    type = (random(1) < weaverChance) ? 1 : 0;
    
    // Speed scales with level
    speed = 1.0 + (level * 0.2); 
    if (type == 1) speed *= 1.2; // Weavers are a bit faster downward
    
    waveOffset = random(TWO_PI);
    shootOffset = int(random(0, 60)); // Randomize shoot timing
  }

  void update() {
    y += speed; 
    
    if (type == 1) {
      // Weaver movement
      x += sin(frameCount * 0.08 + waveOffset) * 3;
      x = constrain(x, 20, width - 20);
    }
    
    if (flashTimer > 0) flashTimer--;

    // Shoot frequency scales with level as well
    int shootChance = max(30, 90 - (level * 5));
    if (y > 20 && (frameCount + shootOffset) % shootChance == 0) {  
      bullets.add(new Bullet(x, y + size / 2));
      
      // Enemy laser sound (lower pitch)
      enemyLaser.freq(random(250, 350));
      enemyLaser.play();
      envELaser.play(enemyLaser, 0.01, 0.05, 0.05, 0.1);
    }
  }

  void show() {
    noStroke();
    
    // Engine flame for enemy (pointing up since they move down)
    fill(255, 50, 0, 150); // Thruster glow
    ellipse(x, y - 15, 15, 20 + random(5));
    fill(255, 100, 0); // Inner flame
    triangle(x - 6, y - 10, x + 6, y - 10, x, y - 30 - random(5));

    // Enemy Core/Body
    if (flashTimer > 0) fill(255); // Flash bright white on impact
    else {
      if (type == 1) fill(150, 50, 250); // Purple for Weaver
      else fill(200, 50, 50); // Dark red for Normal
    }
    ellipse(x, y, size * 0.8, size);
    
    // Enemy wings
    if (flashTimer > 0) fill(255); 
    else {
      if (type == 1) fill(100, 30, 180);
      else fill(150, 30, 30);
    }
    triangle(x - size * 0.4, y, x - size * 0.8, y - size * 0.4, x - size * 0.4, y + size * 0.3);
    triangle(x + size * 0.4, y, x + size * 0.8, y - size * 0.4, x + size * 0.4, y + size * 0.3);

    // Enemy Cockpit
    if (flashTimer > 0) fill(255); else fill(50, 255, 50); // Greenish alien window
    ellipse(x, y + 5, size * 0.4, size * 0.2);
  }

  boolean isOffScreen() {
    return y > height + 60; // Allow it to fully leave the screen before popping out of physics calculations
  }
}

/**
 * ENEMY BULLET CLASS
 * Hostile projectiles fired by Enemy entities. These travel straight down
 * and deal 1 point of damage (lives) to the player upon successful hit detection.
 * Scales speed linearly according to the current game level.
 */
class Bullet {
  float x, y, size;
  float speed;

  Bullet(float startX, float startY) {
    x = startX;
    y = startY;
    size = 10;
    // Bullet speed scales with level too
    speed = 5.0 + (level * 0.3);
  }

  void update() {
    y += speed;  
  }

  void show() {
    rectMode(CENTER);
    noStroke();
    // Glowing laser body
    fill(255, 0, 0, 60);
    rect(x, y, size + 12, size * 3.5, 10); // Big faint aura
    fill(255, 50, 50, 150);
    rect(x, y, size + 4, size * 2.5, 5);   // Outer glow
    fill(255, 255, 150);
    rect(x, y, size - 2, size * 1.5, 5);   // Bright hot core
  }

  boolean isOffScreen() {
    return y > height + 40; // Ensure bullet visually clears the absolute bottom edge
  }

  boolean hitsPlayer(float px, float py, float pSize) {
    // Shrank the hitbox so players can barely dodge bullets
    return dist(x, y, px, py) < (size + pSize * 0.3) / 2;
  }
}

/**
 * PLAYER BULLET CLASS
 * Friendly projectiles fired by the player. Travels upwards and destroys
 * Enemy entities upon hit detection, rewarding the player with points.
 */
class PlayerBullet {
  float x, y, size;

  PlayerBullet(float startX, float startY) {
    x = startX;
    y = startY;
    size = 8;
  }

  void update() {
    y -= 7;  // Move upward
  }

  void show() {
    rectMode(CENTER);
    noStroke();
    // Glowing laser body for player
    fill(0, 100, 255, 60);
    rect(x, y, size + 10, size * 4, 10); // Big faint aura
    fill(50, 150, 255, 150);
    rect(x, y, size + 4, size * 3, 5);   // Outer glow
    fill(200, 255, 255);
    rect(x, y, size - 2, size * 2, 5);   // Bright hot core
  }

  boolean isOffScreen() {
    return y < -40; // Ensure bullet visually clears the absolute top edge
  }

  boolean hitsEnemy(Enemy e) {
    // Shrank hitbox slightly for tighter aiming requirement
    return dist(x, y, e.x, e.y) < (size + e.size * 0.7) / 2;
  }
}

/**
 * BACKGROUND STAR CLASS
 * Handles the generation and movement of a single background star element.
 * Implements a parallax scrolling effect where larger stars move faster
 * than smaller stars to create the optical illusion of 3D depth space travel.
 */
class Star {
  float x, y, size, speed;
  color starColor;

  Star() {
    x = random(width);
    y = random(height);       // Start randomly on screen
    size = random(1, 4);      // Add depth with size
    speed = size * 0.8;       // Parallax: bigger stars move faster
    
    // Give stars subtle color variation matching real space
    float r = random(1);
    if (r < 0.2) starColor = color(200, 220, 255);      // Hot blue
    else if (r < 0.3) starColor = color(255, 220, 200); // Red giant
    else if (r < 0.4) starColor = color(255, 255, 200); // Yellow
    else starColor = color(255);                        // White
  }

  void update() {
    // Speed increases slightly based on game level for dramatic effect
    y += speed + (level * 0.1); 
    
    if (y > height) {
      y = 0;                  // Reset to top
      x = random(width);      // New random X position
      size = random(1, 4);
      speed = size * 0.8;
      
      float r = random(1);
      if (r < 0.2) starColor = color(200, 220, 255);
      else if (r < 0.3) starColor = color(255, 220, 200);
      else if (r < 0.4) starColor = color(255, 255, 200);
      else starColor = color(255);
    }
  }

  void show() {
    // Render stars with colors and varying transparency based on depth
    fill(red(starColor), green(starColor), blue(starColor), map(size, 1, 4, 50, 255));
    noStroke();
    ellipse(x, y, size, size); // Core
    
    // Add subtle glow aura to larger/closer stars
    if (size > 2.5) {
      fill(red(starColor), green(starColor), blue(starColor), 40);
      ellipse(x, y, size * 3, size * 3);
    }
  }
}

/**
 * FX PARTICLE CLASS
 * Handles visual debris and impact flashes spawned during object destruction. 
 * Supports two independent rendering modes: 
 * 1. Flash mode (isFlash=true): A massive, stationary white core burst that shrinks instantly.
 * 2. Spark mode (isFlash=false): Small, hot colored debris that erupts outward with simulated atmospheric drag/friction.
 */
class Particle {
  float x, y, dx, dy, life, pSize;
  color c;
  boolean isFlash;

  Particle(float startX, float startY, boolean flash) {
    x = startX;
    y = startY;
    isFlash = flash;
    
    if (isFlash) {
      dx = 0; dy = 0;
      life = 255;
      pSize = random(40, 60);
      c = color(255); // White flash
    } else {
      float angle = random(TWO_PI);
      float speed = random(1, 6);
      dx = cos(angle) * speed;
      dy = sin(angle) * speed;
      life = 255;
      pSize = random(2, 8); // Varying sizes
      
      float r = random(1);
      if (r < 0.3)      c = color(255, 200, 0); // Yellow
      else if (r < 0.7) c = color(255, 100, 0); // Orange
      else              c = color(200, 50, 50); // Red
    }
  }

  void update() {
    x += dx;
    y += dy;
    // Friction: slow down over time
    dx *= 0.95; 
    dy *= 0.95;
    
    if (isFlash) {
      life -= 20; // Flash fades extremely fast
      pSize *= 0.9; // Flash shrinks
    } else {
      life -= 5;  // Sparkles fade slower
    }
  }

  void show() {
    noStroke();
    
    // Smooth bloom glow for explosions
    fill(red(c), green(c), blue(c), life * 0.3);
    ellipse(x, y, pSize * 2.5, pSize * 2.5);
    
    fill(red(c), green(c), blue(c), life);
    if (isFlash) {
      ellipse(x, y, pSize, pSize); // Core flash
    } else {
      ellipse(x, y, pSize, pSize); // Standard body
      fill(255, 255, 200, life); // White-hot inner center for debris
      ellipse(x, y, pSize * 0.5, pSize * 0.5);
    }
  }

  boolean isDead() {
    return life <= 0;
  }
}

/**
 * FLOATING TEXT CLASS
 * Classic arcade juice! Spawns ascending, fading numbers whenever the player
 * earns score, providing immediate localized visual feedback.
 */
class FloatingText {
  float x, y;
  float textLife;
  String message;
  float scale; // Scale animation

  FloatingText(float startX, float startY, String msg) {
    x = startX + random(-10, 10);
    y = startY;
    message = msg;
    textLife = 255.0;
    scale = 2.0; // Start big, shrink to 1.0
  }

  void update() {
    y -= 1.5; // Float upwards
    textLife -= 4.0; // Fade out gradually
    scale = lerp(scale, 1.0, 0.15); // Smooth scale down
  }

  void show() {
    // Glow effect behind text
    fill(0, 255, 255, textLife * 0.3);
    textAlign(CENTER, CENTER);
    textSize(18 * scale);
    text(message, x, y);
    
    // Crisp foreground text
    fill(255, 255, 255, textLife);
    textSize(16 * scale);
    text(message, x, y);
  }

  boolean isDead() {
    return textLife <= 0;
  }
}
