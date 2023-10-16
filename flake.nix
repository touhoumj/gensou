{
  inputs = { nixpkgs.url = "nixpkgs/nixos-unstable"; };

  outputs = { self, nixpkgs }: {
    devShell.x86_64-linux = let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      python = pkgs.python311;
      pydantic-core = python.pkgs.callPackage ./nix/pkgs/pydantic-core { };
      pydantic =
        python.pkgs.callPackage ./nix/pkgs/pydantic { inherit pydantic-core; };
      # fixes flask debug mode
      werkzeug = python.pkgs.werkzeug.overrideAttrs (oldAttrs: rec {
        postPatch = ''
          substituteInPlace src/werkzeug/_reloader.py \
            --replace "rv = [sys.executable]" "return sys.argv"
        '';
      });
      flask = python.pkgs.flask.override { inherit werkzeug; };
      pyEnv = python.withPackages
        (ps: [ ps.black ps.pylint pydantic flask ps.gunicorn ]);
    in pkgs.mkShell { buildInputs = [ pyEnv ]; };
  };
}
