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

### Client setup
See the [Gensou client repository](https://github.com/touhoumj/gensou-client).

### Server setup for development
This repository contains a Nix devshell with necessary dependencies. With [Nix installed](https://nixos.org/download/#download-nix), it can be built and entered with:

```sh
nix develop
```

Otherwise, you'll need [Elixir 1.17](https://elixir-lang.org/install.html) or newer.

To run the development build, install the dependencies and start the program:

```sh
mix deps.get
iex -S mix phx.server
```

### Server builds for production
This repository contains a Nix package recipe for production builds, which can be created with:

```sh
nix build .#
```

Another way is to use pre-built binaries from [the release page](https://github.com/touhoumj/gensou/releases).

To build such binaries, these additional dependencies are required:
- xz
- 7z
- zig

Then it can be built like so:

```sh
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release gensou_wrapped
```

Regardless of the build, it must be lauched with an environment variable `GENSOU_SECRET_KEY_BASE`.

Environment variables you can configure are:
- `GENSOU_SECRET_KEY_BASE` 64 byte or larger secret key used throughout the web server. Can be generated with `mix phx.gen.secret`
- `GENSOU_HOST` (default: localhost) hostname which must match the publicly accessible name
- `GENSOU_PORT` (default: 5000) port under which the server will be listening
- `RELEASE_COOKIE` Erlang cookie used for connecting nodes in the cluster

### Deployment
This repository contains a Nixos module to ease deployment. It can be used like so:

```nix
{
  # add Gensou flake to your inputs
  inputs.gensou.url = "github:touhoumj/gensou";

  # ensure that gensou is an allowed argument to the outputs function
  outputs = { self, nixpkgs, gensou }: {
    nixosConfigurations.yourHostName = let system = "x86_64-linux";
    in nixpkgs.lib.nixosSystem {
      modules = [
        # load the Gensou NixOS module
        gensou.nixosModules.${system}.default
        ({ pkgs, ... }: {
          # configure the gensou module
          services.gensou = {
            enable = true;
            port = 5000;
            # take extra care to not include this file in the globally readable /nix/store
            # check the flake.nix file for expected environment variables
            environmentFile = "/run/keys/gensou_environment";
          };
        })
      ];
    };
  };
}
```

If you can't or don't want to use NixOS, check out the [Elixir release guide](https://hexdocs.pm/mix/Mix.Tasks.Release.html).

### Missing features
- Serial key reset and registration

  This is handled by the client patches instead. Since we were going to accept any serial key anyway, this approach is less troublesome. We do not need server-side persistence to implement it. Users don't need to come up with unique keys, which are instead generated. This part is particularly important, since the keys are used to uniquely identify the players online. A collision will break the game.

- Player statistics storage and retrieval

  This refers to the first page of "view stats" in game. This data is only stored server-side and I did not want to add persistence for this one feature. Saving and loading has also been disabled by the client patches. Yaku and achievements still work.

- Automatic updates
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
