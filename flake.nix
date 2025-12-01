{
  description = "Neostate development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};

        neovim = pkgs.neovim.override {
          configure = {
            packages.neostate = {
              start = [pkgs.vimPlugins.plenary-nvim];
            };
          };
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            neovim
            pkgs.gnumake
            pkgs.python3
            pkgs.python3Packages.debugpy
            pkgs.vscode-js-debug
            pkgs.lldb
            pkgs.delve
            pkgs.netcoredbg
            pkgs.bashdb
            pkgs.vscode-extensions.vadimcn.vscode-lldb
          ];
          shellHook = ''
            export LUA_LIB_0="${pkgs.neovim}/lib/share/nvim/runtime/lua"
          '';
        };
      }
    );
}
