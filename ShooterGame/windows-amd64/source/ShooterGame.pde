/**
 * ============================================================================
 * SPACE DEFENDER - IOT PROJECT GAME ENGINE
 * ============================================================================
 * An arcade-style top-down space shooter built in Processing.
 * 
 * ARCHITECTURE OVERVIEW:
 * - State Machine: Controlled via `gameState` (0=Menu, 1=Playing, 2=GameOver).
 * - Entity Component: Game objects handled via ArrayLists (enemies, bullets, particles).
 * - Hardware Integration: Ready to receive real-world joystick input via Serial (Arduino).
 * 
 * HOW TO USE HARDWARE:
 * 1. Set `useSerial = true`
 * 2. Ensure Arduino is printing string payloads: "X_VAL,Y_VAL,BUTTON_STATE\n"
 * 3. Match the Serial baud rate (9600 default).
 * ============================================================================
 */
import processing.serial.*;  // Handles Arduino/Joystick communication
import processing.sound.*;   // Handles procedural audio generation
boolean useSerial = false;

Serial myPort;  // Serial port for joystick
float playerX, playerY;  // Player position
float playerSize = 40;   // Size of the player's aircraft
int gameState = 0;       // 0 = Main Menu, 1 = Playing, 2 = Game Over

// --- Phase 1: Game State Variables ---
int score = 0;
int highScore = 0; // High score tracker
int lives = 3;
int level = 1;

// --- Keyboard control state ---
boolean keyLeft = false, keyRight = false, keyUp = false, keyDown = false;
boolean spaceHeld = false;
int shootCooldown = 0;  // Prevent bullet spam

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
    if (Serial.list().length > 0) {
      myPort = new Serial(this, Serial.list()[0], 9600);
      myPort.bufferUntil('\n');
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

  if (gameState == 0) {
    // --- MAIN MENU SCREEN ---
    fill(0, 255, 255);
    textAlign(CENTER, CENTER);
    textSize(50);
    text("SPACE DEFENDER", width / 2, height / 2 - 80);
    
    // High Score Display
    fill(255, 200, 0);
    textSize(18);
    if (highScore > 0) text("HIGH SCORE: " + nf(highScore, 6), width / 2, height / 2 - 45);
    
    // Controls
    fill(200);
    textSize(16);
    text("WASD / ARROWS to Move", width / 2, height / 2 - 10);
    text("SPACE to Shoot", width / 2, height / 2 + 15);
    
    // Add pulsing effect for start text
    fill(255, 255, 100, map(sin(frameCount * 0.1), -1, 1, 50, 255)); // Glowing yellow
    textSize(24);
    text("PRESS SPACE TO START", width / 2, height / 2 + 80);
    
    // Aesthetic decorative ship at bottom
    pushMatrix();
    translate(width / 2, height - 100 + sin(frameCount * 0.05) * 10); // Hover effect
    noStroke();
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
    // Show "Game Over" screen - Semi transparent overlay
    fill(0, 0, 0, 150);
    rectMode(CORNER);
    noStroke();
    rect(0, 0, width, height);

    fill(255, 50, 50);
    textAlign(CENTER, CENTER);
    textSize(60);
    text("GAME OVER", width / 2, height / 2 - 60);
    
    fill(255);
    textSize(30);
    text("Final Score: " + score, width / 2, height / 2);
    
    fill(255, 200, 0);
    textSize(20);
    text("High Score: " + highScore, width / 2, height / 2 + 40);
    
    fill(0, 255, 255);
    textSize(18);
    text("Level Reached: " + level, width / 2, height / 2 + 70);
    
    fill(200);
    textSize(18);
    text("Press R to Restart", width / 2, height / 2 + 110);
    return;
  }
  
  // Update level based on score (Difficulty scaling) - Capped to level 10 so it doesn't become impossible
  level = min(10, 1 + (score / 100));

  if (!useSerial) {
    // Smooth velocity-based movement 
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

    // Shoot with cooldown
    if (spaceHeld && shootCooldown <= 0) {
      playerBullets.add(new PlayerBullet(playerX, playerY));
      playerMuzzleFlash = 5; // Set flash duration
      
      // Play procedural high-pitch laser sound
      playerLaser.freq(random(800, 1000));
      playerLaser.play();
      envPLaser.play(playerLaser, 0.01, 0.05, 0.1, 0.1);
      
      shootCooldown = 12;
    }
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

  // Update and draw enemies
  for (int i = enemies.size() - 1; i >= 0; i--) {
    Enemy e = enemies.get(i);
    e.update();
    e.show();
    if (e.isOffScreen()) {
      enemies.remove(i);  // Remove enemies that leave the screen
      // Optional: penalty for letting enemies pass?
      // score = max(0, score - 5); 
    }
  }

  // Update and draw enemy bullets
  for (int i = bullets.size() - 1; i >= 0; i--) {
    Bullet b = bullets.get(i);
    b.update();
    b.show();
    if (b.isOffScreen()) {
      bullets.remove(i);  // Remove bullets that leave the screen
    } else if (invincibilityTimer <= 0 && b.hitsPlayer(playerX, playerY, playerSize)) {
      // Hit by bullet
      lives--;
      bullets.remove(i); // Destroy the bullet so it doesn't hit multiple times
      
      // Distinct harsh damage sound
      hurtSound.freq(random(150, 200));
      hurtSound.play();
      envHurt.play(hurtSound, 0.01, 0.1, 0.5, 0.2); // Louder and sharper than explosion
      
      // Also spawn visual explosion on the player
      createExplosion(playerX, playerY);
      
      screenShake = 15;  // Powerful screen shake
      invincibilityTimer = 90; // 1.5 seconds of i-frames (assuming 60 FPS)
      if (lives <= 0) {
        if (score > highScore) highScore = score;
        gameState = 2; // Game Over
      }
      break;  // Exit the loop for this frame to prevent multiple hits at once
    }
  }
  
  // Also check if enemy crashes directly into player
  for (int i = enemies.size() - 1; i >= 0; i--) {
    Enemy e = enemies.get(i);
    if (invincibilityTimer <= 0 && dist(playerX, playerY, e.x, e.y) < (playerSize + e.size) / 2) {
      lives--;
      
      // Harsh damage sound
      hurtSound.freq(random(100, 150));
      hurtSound.play();
      envHurt.play(hurtSound, 0.01, 0.1, 0.6, 0.3);
      
      createExplosion(e.x, e.y); // Explosion for enemy crashing
      enemies.remove(i);
      screenShake = 20; // Massive camera shake on crash
      invincibilityTimer = 90;
      if (lives <= 0) {
        if (score > highScore) highScore = score;
        gameState = 2; // Game Over
      }
      break;
    }
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
        createExplosion(enemies.get(j).x, enemies.get(j).y); // Create explosion visually
        // Floating score popup!
        popups.add(new FloatingText(enemies.get(j).x, enemies.get(j).y - 15, "+10"));
        
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

  // Spawn new enemies periodically
  spawnTimer++;
  // Spawn rate scales with level (harder = lower wait time)
  int spawnRate = max(20, 60 - (level * 5)); 
  if (spawnTimer > spawnRate) {  
    enemies.add(new Enemy());
    spawnTimer = 0;
  }
  
  // --- HUD (Heads Up Display) ---
  // Semi-transparent background panel for readability
  fill(0, 0, 0, 150);
  noStroke();
  rectMode(CORNER);
  rect(0, 0, width, 50);

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
}

// --- Keyboard input handlers ---
void keyPressed() {
  if (gameState == 0 && key == ' ') {
    initializeGame();
    return;
  }

  if (gameState == 2 && (key == 'r' || key == 'R')) {
    initializeGame();
    return;
  }

  // Only process gameplay keys when actually playing (prevents ghost inputs from menu/game-over)
  if (gameState != 1) return;

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
      float xValue = map(parsedX, 0, 1023, 0, width);
      float yValue = map(parsedY, 0, 1023, height / 2, height);

      if (gameState == 0 && buttonState == 0) {
        initializeGame();
        return;
      }
      if (gameState == 2 && buttonState == 0) {
        initializeGame();
        return;
      }

      if (gameState == 1) {
        float oldX = playerX; // Track old X for banking math
        playerX = constrain(xValue, 20, width - 20);
        playerY = constrain(yValue, height / 2, height - 20);
        
        // Update playerVX so the ship automatically banks (tilts) while using the joystick
        playerVX = playerX - oldX;

        // Shoot with cooldown to prevent serial-event flood from overflowing bullets
        if (buttonState == 0 && shootCooldown <= 0) {
          playerBullets.add(new PlayerBullet(playerX, playerY));
          playerMuzzleFlash = 5; // Set flash duration
          shootCooldown = 12; // Match keyboard cooldown
          // Joystick trigger sound
          playerLaser.freq(random(800, 1000));
          playerLaser.play();
          envPLaser.play(playerLaser, 0.01, 0.05, 0.1, 0.1);
        }
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
  
  // Reset all visual effect states to prevent carry-over between games
  invincibilityTimer = 0;
  screenShake = 0;
  playerBank = 0;
  playerMuzzleFlash = 0;
  
  // Phase 1 Resets
  score = 0;
  lives = 3;
  level = 1;
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
  float x, y, size;
  float speed;
  int shootOffset; // For desynchronized shooting

  Enemy() {
    x = random(20, width - 20);
    y = -40;
    size = 40;
    // Speed scales with level
    speed = 1.0 + (level * 0.2); 
    shootOffset = int(random(0, 60)); // Randomize shoot timing
  }

  void update() {
    y += speed; 
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
    fill(200, 50, 50); // Dark red
    ellipse(x, y, size * 0.8, size);
    
    // Enemy wings
    fill(150, 30, 30);
    triangle(x - size * 0.4, y, x - size * 0.8, y - size * 0.4, x - size * 0.4, y + size * 0.3);
    triangle(x + size * 0.4, y, x + size * 0.8, y - size * 0.4, x + size * 0.4, y + size * 0.3);

    // Enemy Cockpit
    fill(50, 255, 50); // Greenish alien window
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

  FloatingText(float startX, float startY, String msg) {
    x = startX + random(-10, 10);
    y = startY;
    message = msg;
    textLife = 255.0;
  }

  void update() {
    y -= 1.0; // Float upwards slowly
    textLife -= 5.0; // Fade out gradually
  }

  void show() {
    fill(0, 255, 255, textLife); // Cyan glow matching the HUD
    textAlign(CENTER, CENTER);
    textSize(16);
    text(message, x, y);
  }

  boolean isDead() {
    return textLife <= 0;
  }
}
