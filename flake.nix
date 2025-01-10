{
  description = "CMake module for Bluespec targets";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        bluespec-cmake = pkgs.callPackage ./default.nix { };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "bluespec-cmake-test";
          nativeBuildInputs = with pkgs; [
            cmake
            bluespec
            systemc
          ] ++ [
            bluespec-cmake
          ];
        };

        packages = {
          inherit bluespec-cmake;
          default = bluespec-cmake;
        };
      });
}
