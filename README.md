# Gensou
Implementation of the Touhou Unreal Mahjong 4N server.

### Why?
The game released in 2014 and it is not being sold anymore.
Even with a legitimate copy, it is not possible to play online.
The server rejects everything sent by the client.

### Rewrite notice
This is now the second iteration of the server, completely rewritten from python to elixir. You can find the previous implementation in the [python-archive branch](https://github.com/touhoumj/gensou/tree/python-archive).

Python implementation was meant to function with only minimal changes to the game client.
While this worked, it meant that we had to take on the baggage of questionable design choices, which negatively impacted reliability.

With the rewrite in elixir, we've dropped the constraint of not changing the client and modified all of the online functionality.
- The protocol has been changed from unencrypted HTTP to WebSockets.
- TLS encryption now works.
- Overly frequent polling requests got replaced by server sent messages, greatly reducing the amount of data transferred.
- Encoding of game events as Lua code has been replaced by CBOR, fixing the RCE (remote code execution) vulnerability from the original game.
- The implementation is no longer bound by a single thread.

### Server setup for development
Elixir 1.17 or higher should be the only pre-requisite. It is included in the nix flake present in this repo.

Clone the repo and run
```
mix setup
```

And start the server with
```
iex -S mix phx.server
```

### Server setup for production
TODO

### Client setup
See the [Gensou client repository](https://github.com/touhoumj/gensou-client).

### Missing features
- Serial key reset and registration

  This is handled by the client patches instead. Since we were going to accept any serial key anyway, this approach is less troublesome. We do not need server-side persistence to implement it. Users don't need to come up with unique keys, which are instead generated. This part is particularly important, since the keys are used to uniquely identify the players online. A collision will break the game.

- Player statistics storage and retrieval

  This refers to the first page of "view stats" in game. This data is only stored server-side and I did not want to add persistence for this one feature. Saving and loading has also been disabled by the client patches. Yaku and achievements still work.

- Automatic updates
- Quick play
- Twitter integration

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

Game events are Lua code which the game executes when "deserializing" it. In theory, it should be possible to achieve remote code execution, by sending game events with an additional payload. Our client patches fix this.
