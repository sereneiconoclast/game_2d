# Game2d

A 2D sandbox game, using Gosu and REnet.

There's not much here yet, in terms of actual gameplay.  At this point I'm laying the foundation.  What I have so far:

* The server runs at 60 frames a second, to match Gosu.
* A GameSpace holds a copy of the game's state.  This is primarily a grid populated by Entities.
* The dimensions of the GameSpace (in cells) are specified on server startup.
* Each cell in the grid is 40x40 pixels, but is represented as 400x400 internally.  This allows for motion at slow speeds (1 pixel every 10 ticks == 6 pixels per second).
* Entity positions and velocities are integers.  Apart from player input, all entities' behaviors are predictable.  This allows the client to make accurate predictions of the server state.
* New Entities are assigned IDs in order, again, to allow the client to predict which ID will be assigned to each new entity.
* Clients connect using REnet.  The handshaking process creates a Player object to represent the client.
* Keyboard commands control the player:
  * A and D, or LeftArrow and RightArrow: Hold down to accelerate.
  * LeftControl or RightControl: Hold down to brake (slow down).
  * S, or DownArrow: Hold down to build (the longer you hold, the stronger the block).
  * W, or UpArrow:
    * When not building: Flip (turn 180 degrees).
    * When building: Rise up (ascend to the top of the built block).
  * Left button: Fire a pellet.  Mouse click determines the direction and speed -- closer to the player means slower speed.
  * Right button: Build a block where you click.  *(This will eventually become part of a level-editing mode.)*
* A simple menu system is also available.  Left-click to select.  Esc returns to the top-level.
* The menus include a Save feature, which tells the server to save the level's state.
  * Levels are persisted in ~/.game_2d/<level name> as JSON text.
  * On subsequent startup with the same name, the level is loaded.
* The client and server communicate using JSON text.  This is undoubtedly inefficient, but aids in debugging at this early stage.
* Every frame is numbered by the server, and is referred to as a 'tick'.
* Player actions are both executed locally, and sent to the server.
* If other players are connected, the server sends everyone's actions to everyone else.
* Player actions are dated six ticks in the future, to give everyone a chance to get the message early.  That way everyone can execute the action at the same time.
* The server broadcasts the complete GameSpace four times a second, just in case a client gets out of sync.
* The client predicts the server state, but treats its own copy as advisory only -- the server's is definitive.
  * If the server sends something conflicting, the client discards its wrong prediction.
  * This is intended to compensate for dropped packets or lag, but much more testing is needed.

The physics is (intentionally) pretty simple.  Unsupported objects fall, accelerating downward at a rate of 1/10 pixel per tick per tick.  Blocks assume one of the following forms depending on how many hit points they possess:

* Dirt blocks (1-5 HP) fall unless something is underneath.
* Brick blocks (6-10 HP) can stay up if supported from both left and right.
* Cement blocks (11-15 HP) can stay up if supported from *either* left *or* right.
* Steel blocks (16-20 HP) can stay up if touching anything else, even above.
* Unlikelium blocks (21-25 HP) never fall.

When building a block, the longer you hold the S or DownArrow key, the more HP will be awarded to the block.  Hitting a block with a pellet reduces its HP, until it degrades to a lower form.  Dirt blocks with 1 HP will be entirely destroyed when hit.

Whether an object is supported depends exclusively on its immediate surroundings.  That means two objects can support each other, and hang suspended.  For example, a dirt block sitting on a steel block will support each other.  A horizontal row of brick, capped at either end with cement, will also be free-standing.

Pellets are fired from the player's center, and are affected by gravity.  They damage whatever they hit first, and disappear.  Pellets won't hit the player who fired them.

There are also Titanium entities, which never fall, and are indestructible.  These are intended for use in designing levels with specific shapes.  They can only be created by using the menu to select Titanium, and then right-clicking.

A player is considered to be supported if their "feet" are touching a block.  Unsupported players will turn feet-downward and fall, until they land on something.  Supported players may slide left or right, and will follow any edges they reach -- going up and down walls, or hanging under ceilings.  The "flip" maneuver swaps head and feet; this becomes useful if the player's head is exactly touching another block.  At all other times, a flip leads to a fall (which can be useful too).

When building a block, the player and the new block occupy the same space.  This is allowed until the player moves off of the block.  After that, the block is considered opaque as usual.  While the block is still "inside" the player, the Rise Up maneuver may be used.  This moves the player headward (which may not be "up"--it depends which way the player is turned) to sit "on top" of the block.  It's possible to use this maneuver to construct a horizontal row of bricks, carefully.

The GameSpace is bounded by invisible, indestructible Wall entities.  These can also support blocks, or the player.


## Installation

Install it with:

    $ gem install game_2d

## Usage

This needs streamlining.

Start a server in one window:

    $ game_2d_server.rb -w 50 -h 50 --level example

And a client in another window:

    $ game_2d_client.rb --name Bender --hostname 127.0.0.1

## Contributing

1. Fork it ( https://github.com/sereneiconoclast/game_2d/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
