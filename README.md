# Gensou
Rudimentary implementation of the Touhou Gensou Mahjong 4N server.

### Why?
The game released in 2014 and it is not being sold anymore.
Even with a legitimate copy, it is not possible to play online.
The server rejects everything sent by the client.

### Server setup
Install the dependencies. I'm not going to explain here how to use virtualenv, but you probably should do it.
```
pip install -r requirements.txt
```

Alternatively, use the provided Nix flake, which will set up the dev environment with all necessary dependencies.
```
nix develop
```

Run the production server.
```
gunicorn -b 0.0.0.0:5000 'gensou:app'
```
Important note: this implementation makes no attempt to sync state between workers and will only function correctly when spawned with a single worker.

### Client setup
See the [client documentation](./client/README.md).

### Missing features
- Serial key reset and registration

  This is handled by the client patches instead. Since we were going to accept any serial key anyway, this approach is less troublesome. We do not need server-side persistence to implement it. Users don't need to come up with unique keys, which are instead generated. This part is particularly important, since the keys are used to uniquely identify the players online. A collision will break the game.

- Player statistics storage and retrieval

  This refers to the first page of "view stats" in game. This data is only stored server-side and I did not want to add persistence for this one feature. Saving and loading has also been disabled by the client patches. Yaku and achievements still work.

- Twitter integration
- Quick play

### Features not supported by the game to begin with
- Spectating
- Reconnecting

  Game will replace disconnected players with AI instead.

### Fun facts
The reason why players with a legitimate copy of the game can't play online is a broken custom HTTP client the game uses.
It sends HTTP terms separated by `\n` instead of `\r\n`, like the RFC specified.
Perhaps this worked at one point, but then the developers updated the server and it started rejecting invalid HTTP requests.
This is fixed by one of our client patches.
The client also appears to be subtly broken in other ways that I could not figure out. More modern and stricter HTTP server implementations seem not work with game requests with Keep-Alive enabled.
It is the main reason why the server is written in Python - their servers worked fine.

Game also contains a websocket client, which attempts to connect to a non-existent server. It doesn't appear to have any handlers and shouldn't do anything. Providing the game a real, working websocket server only makes the game run at 2FPS.

All game logic is executed on the clients. The server merely acts as a lobby manager, serial key validator and a way to distribute game events submitted by the clients. This includes the AI players, for which the events are submitted by the room host.

Game events are Lua code which the game executes when "deserializing" it. In theory, it should be possible to achieve remote code execution, by sending game events with an additional payload. Trust whoever you play with.
