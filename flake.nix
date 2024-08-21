{
  inputs = { nixpkgs.url = "nixpkgs/nixos-unstable"; };

  outputs = { self, nixpkgs }: {
    devShell.x86_64-linux = let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      beam = pkgs.beam.packages.erlang_27;
      elixir = beam.elixir_1_17;
      elixir-ls = (beam.elixir-ls.override { inherit elixir; });
    in pkgs.mkShell {
      buildInputs = [ elixir elixir-ls ] ++ (with pkgs; [ xz p7zip zig ]);
      shellHook = ''
        # this allows mix to work on the local directory
        mkdir -p .state/mix .state/hex
        export MIX_HOME=$PWD/.state/mix
        export HEX_HOME=$PWD/.state/hex
        export PATH=$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH
        # TODO: not sure how to make hex available without installing it afterwards.
        mix local.hex --if-missing --force
        export LANG=en_US.UTF-8
        export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_path '\"$PWD/.state\"' -kernel shell_history_file_bytes 1024000"

        export MIX_ENV=dev
      '';
    };
  };
}
