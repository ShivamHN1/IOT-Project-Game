# ShooterGame.pde Reference Documentation

## Purpose
This document explains the current behavior of `ShooterGame.pde` in detail so the codebase can be used as a reference during later team collaboration. It is written to help you understand what is already implemented, how the game flows, and where individual behaviors live before you replace or append features.

## Quick Reference
- Technology: Processing on the JVM
- Game type: top-down space shooter
- Hardware input: Arduino joystick over Serial
- Control modes: keyboard and joystick, with runtime switching
- Main states: menu, gameplay, game over
- Persistent data: high score in `data/highscore.txt`
- Main loop: `setup()` runs once, `draw()` runs continuously

## High-Level Architecture
The sketch is built around a state-driven game loop. The top-level control variable is `gameState`:
- `0` = main menu
- `1` = active gameplay
- `2` = game over

Most of the game logic is executed inside `draw()`, which acts as the real-time orchestrator for rendering, movement, collisions, entity updates, HUD drawing, and overlays.

The project also uses several supporting systems:
- Serial input parsing for joystick data
- Keyboard event handling for fallback and alternate control
- Procedural sound via Processing's sound library
- ArrayList-based entity storage for dynamic game objects
- File I/O for high score persistence
- Visual polish systems such as starfield, screen shake, invincibility flash, explosion particles, and floating score text

## Startup Flow
When the sketch starts:
1. `setup()` creates the window at 600x600.
2. If `useSerial` is enabled, it tries to connect to the first available serial port at 9600 baud.
3. If serial is unavailable or fails, the game falls back to keyboard mode.
4. Audio oscillators and envelopes are created.
5. A background starfield of 100 stars is created.
6. The high score is loaded from disk.
7. `initializeGame()` resets gameplay variables and creates fresh entity lists.
8. `gameState` is forced to the menu.

This means the sketch always starts in a ready-but-not-playing state.

## Main Runtime Loop
`draw()` runs continuously, usually around 60 FPS. Its order matters:
1. Draw the background.
2. Update and draw the starfield.
3. Reduce cooldown timers.
4. If paused during gameplay, draw the pause overlay and stop.
5. If on the menu, draw the menu and stop.
6. Apply screen shake if active.
7. Update explosion particles.
8. If in game over, draw the game-over screen and stop.
9. Process countdown behavior if a new game has just started.
10. Update difficulty and level-up state.
11. Handle movement.
12. Handle shooting.
13. Draw the player ship.
14. Update enemies, enemy bullets, player bullets, popups, and collisions.
15. Draw the HUD and overlays.

This structure ensures that background visuals and effects continue even when gameplay logic is partially paused or waiting.

## Game States in Detail

### Intro State (`gameState == -1`)
Before the main menu appears, the sketch now shows a timed intro screen.

This intro:
- displays the game title
- animates the team member names
- shows a "press any key to skip" prompt
- auto-skips to the main menu after 5 seconds
- can also be skipped immediately with any keyboard key or joystick button press

This state is only a presentation layer; it does not start gameplay until it transitions into the menu.

### Menu State (`gameState == 0`)
The menu is more than a static title screen. It shows:
- the title with glow and shadow styling
- the subtitle `IOT ARCADE EXPERIENCE`
- the high score, if it exists
- keyboard instructions
- joystick instructions
- a pulsing prompt to start
- a decorative ship animation at the bottom

Input on the menu:
- Space starts the game from keyboard
- Joystick button starts the game when serial input is active

The menu returns early from `draw()`, so gameplay logic does not run while on the title screen.

### Gameplay State (`gameState == 1`)
This is the active play loop.

During gameplay, the code manages:
- player movement
- bullet firing
- enemy spawning
- enemy shooting
- collision detection
- score updates
- life loss
- invincibility frames
- level scaling
- visual effects
- HUD rendering

A countdown can temporarily block movement and shooting at the start of the run. The game still animates the background and some passive visuals during this time.

### Game Over State (`gameState == 2`)
When lives reach zero:
- the game over overlay appears
- the final score is shown
- the saved high score is compared and possibly updated
- the level reached is shown
- the restart prompt appears

Input on the game over screen:
- `R` restarts from keyboard
- Joystick button restarts when serial input is active

## Input System

### Keyboard Input
Keyboard input is managed using `keyPressed()` and `keyReleased()`.

Supported controls:
- `WASD` or arrow keys for movement
- Space to shoot
- `P` to pause or resume
- `R` to restart from game over

Keyboard movement is velocity-based:
- pressing movement keys changes velocity
- friction slows movement when keys are released
- position is then updated using velocity

This gives the keyboard ship a gliding feel rather than instant movement.

### Joystick Input
Joystick input is read from Serial in `serialEvent(Serial myPort)`.

The Arduino is expected to send:
- X value from 0 to 1023
- Y value from 0 to 1023
- button state as `0` or `1`

The joystick logic does several things:
- parses the serial line
- ignores malformed data
- clamps values to the ADC range
- checks whether the stick is moved away from center
- switches to joystick mode when movement is detected
- maps joystick position directly to screen coordinates
- uses the button for start, fire, and restart actions depending on state

### Active Input Switching
The game does not permanently lock to one input source.

Instead:
- any gameplay key press forces keyboard mode
- moving the joystick outside a deadzone forces joystick mode
- the HUD shows the currently active mode

This means the control source changes based on which input was used most recently for meaningful movement.

## Serial Protocol
The Processing sketch expects serial lines in this exact format:
```text
X_VALUE,Y_VALUE,BUTTON_STATE
```

Where:
- `X_VALUE` is the raw joystick X reading
- `Y_VALUE` is the raw joystick Y reading
- `BUTTON_STATE` is `0` when pressed and `1` when not pressed

This matches the Arduino sketch behavior with `INPUT_PULLUP` on the button pin.

## Countdown Behavior
When a game starts, `countdownTimer` is set to 180 frames, which is about 3 seconds at 60 FPS.

While the countdown is active:
- the overlay shows `3`, `2`, `1`, then `GO!`
- the player cannot fire yet
- the active play loop is partially delayed
- stars and particles continue to animate

This gives the player a short reset window before the action begins.

## Player Logic
The player ship has several moving parts:
- visual position (`playerX`, `playerY`)
- movement velocity (`playerVX`, `playerVY`)
- tilt/banking (`playerBank`)
- muzzle flash state (`playerMuzzleFlash`)
- invincibility state (`invincibilityTimer`)
- visible damage feedback via blinking and shield effects

The player is constrained to the bottom half of the screen so enemies do not spawn directly on top of the ship in an unfair way.

### Shooting
The player fires when `spaceHeld` is true and `shootCooldown` is zero or less.

Shooting behavior:
- creates a `PlayerBullet`
- triggers muzzle flash graphics
- plays a laser sound
- starts a cooldown of 12 frames

This same firing path works for both keyboard and joystick.

### Hit Reactions
When the player is hit:
- lives are reduced by 1
- hurt sound plays
- explosion is created
- screen shake starts
- invincibility frames begin
- game ends if lives drop to 0

## Enemy Logic
Enemies are stored in `ArrayList<Enemy>`.

Each enemy:
- spawns above the top of the screen
- moves downward
- may also weave side to side depending on type
- shoots bullets at intervals
- flashes white when destroyed or damaged visually
- is removed when off-screen

### Enemy Types
There are two enemy behaviors:
- type 0: straight-falling enemy
- type 1: weaving enemy with sinusoidal horizontal movement

The likelihood of spawning a weaving enemy increases as level rises.

### Enemy Shooting
Enemies can fire bullets downward while on-screen.

Enemy fire behavior:
- bullet speed scales with level
- shooting intervals are randomized per enemy using `shootOffset`
- enemy sound is played when firing

## Bullet Logic
There are two bullet systems.

### Enemy Bullets
Stored in `ArrayList<Bullet>`.

They:
- move downward
- become faster at higher levels
- damage the player on collision
- are removed off-screen

### Player Bullets
Stored in `ArrayList<PlayerBullet>`.

They:
- move upward
- destroy enemies on impact
- create explosions and score popups
- are removed off-screen

## Collision Rules
The sketch uses distance-based collision checks rather than pixel-perfect hitboxes.

Collision cases:
- enemy bullet hits player
- enemy body collides with player
- player bullet hits enemy

The hitboxes are tuned to be slightly forgiving in some cases and tighter in others so the game feels playable rather than too strict.

## Scoring and Difficulty
Scoring is simple and direct:
- each enemy destroyed by the player gives `+10`

Difficulty scales from score:
- level is computed as `1 + score / 100`
- level is capped at 10
- enemy spawn rate increases with level
- enemy speed increases with level
- enemy bullet speed increases with level
- stronger enemy variety becomes more common with level

A level-up overlay appears when the level changes.

## Lives System
The game starts with 3 lives.

Lives are represented in the HUD as small ship icons instead of text.

Losing all lives triggers the game over state.

## HUD
The HUD displays:
- score with leading zeros
- life icons
- current level
- current input mode (`[JOYSTICK]` or `[KEYBOARD]`)

The HUD also uses a translucent gradient at the top for a more polished presentation.

## Visual Effects
The sketch includes several layered effects that are part of the current design:
- animated starfield background
- title glow on menu
- ship engine flame animation
- muzzle flashes
- invincibility shield pulse
- screen shake on damage
- explosion particles
- floating score popups
- level-up flash and text effect
- red vignette on game over

These are not just decorative; they are part of the current feel of the game.

## Sound System
The game uses Processing sound oscillators and envelopes to synthesize effects in real time.

Sounds currently used:
- player laser
- enemy laser
- explosion sound
- hurt sound

This means the game does not depend on imported audio files for its core effects.

## File Persistence
High score persistence uses file I/O.

Behavior:
- `loadHighScore()` reads `data/highscore.txt`
- `saveHighScore()` writes the new record back to the same file
- if the file does not exist or fails to load, the game starts fresh with a high score of 0

## Game Reset Logic
`initializeGame()` performs a full run reset.

It resets:
- player position
- enemy list
- enemy bullet list
- player bullet list
- particle list
- popup list
- spawn timer
- game state to playing
- shoot cooldown
- movement states
- joystick mode flag
- invincibility and screen shake
- bank angle and muzzle flash
- score, lives, level, lastLevel, and level-up timer
- pause state
- countdown timer

This function is the clean restart entry point for new games.

## Helper Classes

### `Enemy`
Represents hostile ships.

Responsibilities:
- spawn configuration
- falling movement
- optional weaving movement
- enemy firing
- visual rendering
- off-screen cleanup

### `Bullet`
Represents enemy projectiles.

Responsibilities:
- downward movement
- rendering
- player hit detection
- off-screen cleanup

### `PlayerBullet`
Represents player projectiles.

Responsibilities:
- upward movement
- rendering
- enemy hit detection
- off-screen cleanup

### `Star`
Represents background stars.

Responsibilities:
- random initialization
- parallax scrolling
- star color variation
- respawn at the top when off-screen

### `Particle`
Represents explosion debris and flash effects.

Responsibilities:
- flash or spark mode
- motion with friction
- fading and shrinking
- removal when dead

### `FloatingText`
Represents score popups.

Responsibilities:
- upward drift
- fade-out
- scaling animation
- removal when expired

## Important Behavioral Notes
These are details that matter when you later modify or compare code:
- `serialEvent()` is where joystick movement and joystick-button actions are handled.
- Joystick movement uses absolute screen mapping, not velocity physics.
- Keyboard movement uses velocity and friction.
- `spaceHeld` is the shared fire signal across input methods.
- `countdownTimer` prevents immediate shooting and movement at the start of a run.
- The game keeps particles and some animations alive even when gameplay is blocked.
- `stateTransitionCooldown` prevents accidental repeated menu or restart triggers.
- `usingJoystick` is a mode flag, but the actual movement source is chosen by recent active input.
- High score is saved only when the current score beats the stored high score.

## What This Means for Future Work
When you later merge or replace parts of the project, this codebase already has clear separation points:
- menu and game over screens are isolated in `draw()` by state
- player movement logic can be changed separately for keyboard and joystick
- enemy spawning and enemy behavior are centralized in the `Enemy` class and spawn block
- effects such as particles, popups, and sound can be appended without rewriting the core loop
- high score, serial input, and reset logic are all self-contained enough to swap carefully

## Revision Summary
| Area | Current Behavior | Why It Matters |
|---|---|---|
| Game states | Menu, playing, game over | Controls the full flow of the program |
| Input | Keyboard and joystick both supported | Lets you compare alternate control implementations |
| Movement | Keyboard uses velocity, joystick uses absolute mapping | Important when changing control feel |
| Shooting | Shared `spaceHeld` firing path | Keeps both input methods consistent |
| Enemies | Randomized types, movement, and shooting | Main source of gameplay difficulty |
| Scoring | +10 per enemy | Defines progression and level scaling |
| Persistence | High score stored in text file | Preserves records between runs |
| Effects | Particles, shake, shield, flash, popups | Major part of the game's presentation |
| Reset | `initializeGame()` clears and rebuilds state | Safe starting point for new runs |

## Source File
Primary implementation: [ShooterGame.pde](/home/shivanshs/CSE/IOT-Project-Game/ShooterGame/ShooterGame.pde)
