{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
  };

  outputs = { self, nixpkgs, flake-utils, nix-filter }:
    {
      nixosModules.default = self.nixosModules.gensou;
      nixosModules.gensou = { config, pkgs, lib, ... }:
        let
          releaseName = "gensou";
          cfg = config.services.gensou;
        in with lib; {
          options.services.gensou = {
            enable = mkEnableOption (lib.mdDoc "the Gensou server");

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.system}.gensou;
              defaultText = "pkgs.gensou";
              description = ''
                Package of the application to run, exposed for overriding purposes.
              '';
            };

            baseDirectory = mkOption {
              description = lib.mdDoc ''
                State directory (secrets, work directory, etc.)
              '';
              type = types.path;
              default = "/var/lib/gensou";
            };

            hostname = mkOption {
              type = types.str;
              default = "localhost";
              example = "example.com";
            };

            port = mkOption {
              type = types.port;
              default = 5000;
            };

            environmentFile = mkOption {
              type = types.path;
              description = ''
                Environment file as defined in {manpage}`systemd.exec(5)`.
                All of the listed variables are required:

                - GENSOU_SECRET_KEY_BASE
                  The secret key base is used to sign/encrypt cookies and other secrets.
                  A default value is used in config/dev.exs and config/test.exs but you
                  want to use a different value for prod and you most likely don't want
                  to check this value into version control, so we use an environment
                  variable instead.
                  Can be generated with `mix phx.gen.secret`.

                - RELEASE_COOKIE
                  Erlang cookie, which can be generated in an elixir console with
                  `Base.encode32(:crypto.strong_rand_bytes(32))`
              '';
            };
          };

          config = mkIf cfg.enable {
            systemd.services.${releaseName} = {
              wantedBy = [ "multi-user.target" ];
              description = "Gensou server";
              environment = {
                RELEASE_TMP = cfg.baseDirectory;
                GENSOU_HOST = cfg.hostname;
                GENSOU_PORT = toString cfg.port;
              };
              serviceConfig = {
                Type = "exec";
                User = "gensou";
                Group = "gensou";
                WorkingDirectory = cfg.baseDirectory;
                StateDirectory = baseNameOf cfg.baseDirectory;
                StateDirectoryMode = "700";
                # Implied by DynamicUser, but just to emphasize due to RELEASE_TMP
                PrivateTmp = true;
                EnvironmentFile = cfg.environmentFile;
                ExecStart = ''
                  ${cfg.package}/bin/${releaseName} start
                '';
                ExecStop = ''
                  ${cfg.package}/bin/${releaseName} stop
                '';
                ExecReload = ''
                  ${cfg.package}/bin/${releaseName} restart
                '';
                Restart = "on-failure";
                RestartSec = 5;
              };
              startLimitBurst = 3;
              startLimitIntervalSec = 10;
              # disksup requires bash
              path = [ pkgs.bash ];
            };

            users.groups.gensou = { };
            users.users.gensou = {
              description = "Service user for Gensou";
              group = "gensou";
              isSystemUser = true;
            };

            # in case you have migration scripts or you want to use a remote shell
            environment.systemPackages = [ cfg.package ];
          };
        };

      nixosConfigurations.test-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          self.nixosModules.default
          ({ config, pkgs, lib, ... }: {
            users.users.root.initialPassword = "";
            environment.systemPackages = [ pkgs.tmux pkgs.htop ];
            networking.firewall.enable = false;

            services.openssh = {
              enable = true;
              # FIXME this still doesn't let me login over ssh without a password
              # it used to work in the past...
              settings = {
                PermitRootLogin = "yes";
                PermitEmptyPasswords = "yes";
                StrictModes = true;
              };
            };

            services.gensou = {
              enable = true;
              hostname = "localhost";
              port = 5000;
              environmentFile = pkgs.writeText "nix-secrets" ''
                RELEASE_COOKIE=aGkgYmluIGhpIGJpbiBoaSBiaW4gaGkgYmluIGhpIGJpbg==
                GENSOU_SECRET_KEY_BASE=at_least_sixtyfour_bytes_of_pure_entropy_please_dont_use_this_in_deployments
              '';
            };
          })
        ];
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        beam = pkgs.beam.packages.erlang_27;
        erlang = beam.erlang;
        elixir = beam.elixir_1_17;
        elixir-ls = (beam.elixir-ls.override { inherit elixir; });
        tailwind = self.packages.${system}.tailwind;

        pname = "gensou";
        version = "0.1.0";
        name = "${pname}-${version}";
        src = nix-filter {
          root = self;
          include = [ "mix.exs" "mix.lock" "assets" "config" "lib" "priv" ];
        };
      in {
        apps.gensou =
          flake-utils.lib.mkApp { drv = self.packages.${system}.gensou; };
        apps.default = self.apps.${system}.gensou;

        packages.default = self.packages.${system}.gensou;

        packages.gensou = beam.mixRelease rec {
          inherit pname version src elixir erlang;

          mixFodDeps = self.packages.${system}.gensou-deps;

          preInstall = ''
            export TAILWIND_BIN=${tailwind}/bin/tailwind
            export ESBUILD_BIN=${pkgs.esbuild}/bin/esbuild
            export NODE_PATH=${mixFodDeps}
            mix do deps.loadpaths --no-deps-check, assets.deploy, phx.digest
          '';
        };

        packages.gensou-deps = beam.fetchMixDeps {
          inherit src version elixir erlang;
          pname = "${pname}-deps";
          sha256 = "sha256-PjHKDjsF9FDC8LVYczECt/Je2xUHJwr54BQqzjWfm+E=";
        };

        packages.tailwind = pkgs.nodePackages.tailwindcss.overrideAttrs
          (oldAttrs: {
            plugins = [
              pkgs.nodePackages."@tailwindcss/forms"
              pkgs.nodePackages."@tailwindcss/typography"
            ];
          });

        devShells.default = pkgs.mkShell {
          buildInputs = [
            elixir-ls
            elixir
            # phoenix deps
            tailwind
            pkgs.esbuild
            # burrito deps
            pkgs.xz
            pkgs.p7zip
            pkgs.zig
          ];

          shellHook = ''
            # this allows mix to work on the local directory
            mkdir -p .state/mix .state/hex
            export MIX_HOME=$PWD/.state/mix
            export HEX_HOME=$PWD/.state/hex
            export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
            export ESBUILD_BIN=${pkgs.esbuild}/bin/esbuild
            export TAILWIND_BIN=${tailwind}/bin/tailwind
            mix local.hex --if-missing --force
            export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_path '\"$PWD/.state\"' -kernel shell_history_file_bytes 1024000"
            export QEMU_NET_OPTS="hostfwd=tcp::2222-:22,hostfwd=tcp::5000-:5000"
          '';
        };

        hydraJobs = { inherit (self.packages.${system}) gensou; };
        checks = { inherit (self.packages.${system}) gensou; };
        formatter = pkgs.nixpkgs-fmt;
      });
}
