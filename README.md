# Game2d

A 2D sandbox game, using Gosu and REnet.

## Overview

Built on top of Gosu, an engine for making 2-D games.  Gosu provides the means
to handle the graphics, sound, and keyboard/mouse events.  It doesn't provide
any sort of client/server network architecture for multiplayer games, nor a
system for tracking objects in game-space.  This gem aims to fill that gap.

Originally I tried using Chipmunk as the physics engine, but its outcomes were
too unpredictable for the client to anticipate the server.  It was also hard to
constrain in the ways I wanted.  So I elected to build something integer-based.

In the short term, I'm throwing anything into this gem that interests me.  There
are reusable elements (GameSpace, Entity, ServerPort), and game-specific
elements (particular Entity subclasses with custom behaviors).  Longer term, I
could see splitting it into two gems.  This gem, game_2d, would retain the
reusable platform classes.  The other classes would move into a new gem specific
to the game I'm developing, as a sort of reference implementation.

## Design

### GameSpace

* A GameSpace holds a copy of the game's state.  This is primarily a grid populated by Entities.
* The dimensions of the GameSpace (in cells) are specified on server startup.
* Each cell in the grid is 40x40 pixels, but is represented as 400x400 internally.  This allows for motion at slow speeds (1 pixel every 10 ticks == 6 pixels per second).
* Entity positions and velocities are integers.  Apart from player input, all entities' behaviors are predictable.  This allows the client to make accurate predictions of the server state.
* New Entities are assigned IDs in order, again, to allow the client to predict which ID will be assigned to each new entity.

### Client/Server

* The server runs at 60 frames a second, to match Gosu.
* Clients connect using REnet.  The handshaking process creates a Player object to represent the client.
* Client and server use Diffie-Hellman key exchange to establish a shared secret.  This is used to encrypt sensitive information, rather like SSH (but over REnet).
  * Right now, the only sensitive information is the user's password.  This allows the server to remember who's who.
* On startup, the client prompts the user to enter the password, which is encrypted and then sent to the server along with the player-name.
* Server keeps a record of each player and their password.
  * Nothing else interesting here yet, but I fully expect to put an inventory here, once there is anything useful to carry around.
  * This is also where I plan to put authorization data - who's a god player (level editor) and who isn't.
  * Player data is persisted in ~/.game_2d/players/players as JSON text.
* The client and server communicate using JSON text.  This is undoubtedly inefficient, but aids in debugging at this early stage.  I fully intend to replace this, eventually.
* Every frame is numbered by the server, and is referred to as a 'tick'.
* Player actions are both executed locally, and sent to the server.
* If other players are connected, the server sends everyone's actions to everyone else.
  * This is obviously insecure.  Validating user data is on my to-do list.
* Player actions are dated six ticks in the future, to give everyone a chance to get the message early.  That way everyone can execute the action at the same time.
* The server broadcasts the complete GameSpace four times a second, just in case a client gets out of sync.
* The client predicts the server state, but treats its own copy as advisory only -- the server's is definitive.
  * If the server sends something conflicting, the client discards its wrong prediction.
  * This is intended to compensate for dropped packets or lag, but much more testing is needed.

### Player Interface

* Keyboard commands control the player object, which is called a Gecko:
  * A and D, or LeftArrow and RightArrow: Slide sideways.  Hold down to accelerate.
  * LeftControl or RightControl: Hold down to brake (slow down).
  * S, or DownArrow: Hold down to build (the longer you hold, the stronger the block).
  * W, or UpArrow:
    * When not building: Flip (turn 180 degrees).
    * When building: Rise up (ascend to the top of the built block).
* The mouse is also used.
  * Left button: Fire a pellet.  Mouse click determines the direction and speed.
    * When firing up, the pellet's trajectory will peak where you clicked.
    * When firing down, the pellet will be fired horizontally such that it falls through the place where you clicked.
* A simple menu system is available.  Left-click to select.  Esc returns to the top-level.

### Level-Editing Features

This will eventually become a separate game mode, accessible only to certain authorized players.

* Menu options let you select the type of entity to build, and turn "snap to grid" on or off.
  * Snap-to-grid aims to put entities exactly in particular cells, with X and Y coordinates both multiples of 400.
* Right button: Grab an entity and drag it around.  Right-click again to release.  Grab is affected by snap-to-grid.
* Shifted right button, or B: Build a block where the mouse points, of the type selected in the menu.
* Shortcut keys for particular object types:
  * 1: Dirt
  * 2: Brick
  * 3: Cement
  * 4: Steel
  * 5: Unlikelium
  * 6: Titanium
  * 7: Teleporter
  * 8: Hole
  * 9: Base
  * 0: Slime
* Mousing over an entity displays some basic information about it.
* The menus include a Save feature, which tells the server to save the level's state.
  * Levels are persisted in ~/.game_2d/levels/<level name> as JSON text.
  * On subsequent startup with the same name, the level is loaded.

## Gameplay

### Block physics

The physics is (intentionally) pretty simple.  Unsupported blocks fall, accelerating downward at a rate of 1/10 pixel per tick per tick.  Blocks assume one of the following forms depending on how many hit points they possess:

* Dirt blocks (1-5 HP) fall unless something is underneath.
* Brick blocks (6-10 HP) can stay up if supported from both left and right.
* Cement blocks (11-15 HP) can stay up if supported from *either* left *or* right.
* Steel blocks (16-20 HP) can stay up if touching anything else, even above.
* Unlikelium blocks (21-25 HP) never fall.

Brick and Cement blocks are considered supported from the sides only if the entities present there are at exactly the same height.  Steel blocks are less picky; they only fall if nothing is touching them.

When building a block, the longer you hold the S or DownArrow key, the more HP will be awarded to the block.  Hitting a block with a pellet reduces its HP, until it degrades to a lower form.  Dirt blocks with 1 HP will be entirely destroyed when hit.

Whether a block is supported depends exclusively on its immediate surroundings.  That means two blocks can support each other, and hang suspended.  For example, a dirt block sitting on a steel block will support each other.  A horizontal row of brick, capped at either end with cement, will also be free-standing.

There are also Titanium entities.  They take up space and can be used for support, but they are not truly blocks.  They never fall, and are indestructible.  These are intended for use in designing levels with specific shapes.  They can only be created, destroyed, or moved by using the level-editing features.

The GameSpace is bounded by invisible, indestructible Wall entities.  These are like Titanium, except that they are off-screen, and cannot be altered even with the level-editing features.

### Geckos

A player object is called a Gecko, because of how it moves.  A Gecko is considered to be supported if its "feet" are touching a block.  Unsupported Geckos will turn feet-downward and fall, until they land on something.  Supported Geckos may slide left or right, and will follow any edges they reach -- going up and down walls, or hanging under ceilings.  The "flip" maneuver swaps head and feet; this becomes useful if the Gecko's head is exactly touching another block.  At all other times, a flip leads to a fall (which can be useful too).

When building a block, the player and the new block occupy the same space.  This is allowed until the player moves off of the block.  After that, the block is considered opaque as usual.  While the block is still "inside" the player, the Rise Up maneuver may be used.  This moves the player headward (which may not be "up"--it depends which way the player is turned) to sit "on top" of the block.  It's possible to use this maneuver to construct a horizontal row of bricks, carefully.

### Bases

A base is a spawn point for players, and is also an object that can be moved.  When a game server is started with a new level name, a single starter base will be created in the center (and then promptly fall to the bottom).  New bases can be created using the level-editing features, as many as desired, and placed wherever it makes sense for players to enter the level.  Bases are indestructible (currently).

Like Geckos, Bases can perch on walls or ceilings, as long as their "feet" are pointed the right way.  Unlike Geckos, when a Base gets thrown sideways or upwards, it will turn its "feet" in the direction it's going.  So it will tend to stick to the first thing it hits.

Bases are physical objects, and most other objects (like blocks) can't move through them; but they're transparent to players.  Players who join the game will start out at a randomly selected unoccupied base, in the same orientation as the base.

## Ghosts

When a Gecko is destroyed, the player turns into a Ghost.  This means you're dead.  A Ghost can't touch anything or affect anything, and isn't affected by anything, even gravity.  Ghosts can only float around, and look at things.

One other thing a Ghost can do is turn back into a Gecko, i.e. respawn.  The player gets some choice as to which base to respawn at, if more than one exist and are unoccupied.  The Ghost will move quickly to the unoccupied base nearest to the click position (even if that's really far away).  If the player's not choosy, they may click anywhere.  If all bases are occupied, nothing happens; the Ghost player must wait for those other Geckos to get out of the way.

This is also the solution for allowing new players to enter the game when all bases are occupied: The new player is created as a Ghost.

### Pellets

Pellets are fired from the player's center, and are affected by gravity.  They damage whatever they hit first, and disappear.  Pellets won't hit the player who fired them.  Blocks, slime, and players can take damage and be destroyed.

### Teleporters

Teleporters never fall, and they are "transparent" to most entities; they act as if part of the background.  Their only action is to transfer their contents (anything close enough to intersect with their center) to their single destination-point.  This transfer affects location but not velocity.  Transfer doesn't happen if there is something blocking the exit point.

### Holes

They're black.  Really black.  Against the starry background, they're impossible to see... except that they occlude the stars.

Mostly, holes are detectable just like real black holes: by virtue of the effect they have on everything around them.  Normal gravity makes loose objects fall downward, but in the vicinity of a hole, gravity sucks all objects toward the hole.  If the falling object gets too close to the hole, it will begin taking damage.  Blocks will rapidly be destroyed as they approach.  Pellets can't take damage in this way, but their path will bend around the hole.  Pellets can even be captured in orbit around the hole, though they always escape eventually.


## Installation

Install it with:

    $ gem install game_2d

## Usage

This needs streamlining.

Start a server in one window:

    $ game_2d_server.rb -w 50 -h 50 --level example

And a client in another window:

    $ game_2d_client.rb --name Bender --hostname 127.0.0.1

The client can use the menu to select "Save", telling the server to save a copy of the level.  Subsequent runs of the server can leave off the dimensions:

    $ game_2d_server.rb --level example

Run these commands with --help to see more options.

## Contributing

1. Fork it ( https://github.com/sereneiconoclast/game_2d/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
