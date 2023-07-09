{
  description = "Zig toolchain for development";

  inputs = 
    {
       nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
       zig-overlay.url = "github:mitchellh/zig-overlay";
       zig-overlay.inputs.nixpkgs.follows = "nixpkgs";

       flake-utils.url = "github:numtide/flake-utils";

        
    };

  outputs = { self, nixpkgs, zig-overlay, flake-utils, ... }: 
    flake-utils.lib.eachDefaultSystem (system: 
      let
        # overlays = [import zig-overlay ];
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      with pkgs;
      {
        devShells.default = mkShell {
          buildInputs = [
            zig-overlay.packages.${system}.master
          ];

          shellHook = ''
          '';
        };
      }
    );
}
