{
  description = "Neodap - Debug Adapter Protocol SDK for Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Lua development (LuaJIT for Neovim compatibility)
          luajit
          luarocks
          stylua # Lua formatter
          
          # Testing framework with LuaJIT compatibility
          luajitPackages.busted
          luajitPackages.luafilesystem
          luajitPackages.luasystem
          luaPackages.luacheck # Lua linter

          # Node.js for js-debug adapter
          nodejs_20

          # Debug adapters commonly used for testing
          # Note: js-debug needs to be installed separately via npm

          # Neovim for testing
          neovim

          # Git for development
          git

          # Optional: LSP for Lua development
          lua-language-server

          # Neovim plugins for development
          vimPlugins.nvim-nio
          vimPlugins.plenary-nvim

          # make for building/testing
          gnumake
        ];

        shellHook = ''
          # Set up Lua paths for testing
          export LUA_PATH="./lua/?.lua;./lua/?/init.lua;$LUA_PATH"
          export LUA_CPATH="$LUA_CPATH"

          # Set up LuaJIT C extension paths for Neovim compatibility
          export LUA_CPATH="${pkgs.luajitPackages.luafilesystem}/lib/lua/5.1/?.so;${pkgs.luajitPackages.luasystem}/lib/lua/5.1/?.so;$LUA_CPATH"

          # Provide nvim-nio as environment variable if needed
          export NVIM_NIO_PATH="${pkgs.vimPlugins.nvim-nio}"

          echo "🧪 Neodap development environment ready!"
          echo "📚 Library paths for .luarc.json:"
          echo "  Neovim runtime: ${pkgs.neovim}/share/nvim/runtime/lua"
          echo "  nvim-nio: ${pkgs.vimPlugins.nvim-nio}/lua"
          echo "  busted: ${pkgs.luajitPackages.busted}/share/lua/5.1"

          echo "Run 'nix run .#test-all' to run tests"
          echo "Run 'nix run .#test spec/$file' to run a specific test file"
          echo "Run 'nix run .#lint' to run linter"
        '';
      };

      # Package for the project itself
      packages.default = pkgs.stdenv.mkDerivation {
        pname = "neodap";
        version = "0.1.0";

        src = ./.;

        installPhase = ''
          mkdir -p $out/share/nvim/site/pack/neodap/start/neodap
          cp -r lua $out/share/nvim/site/pack/neodap/start/neodap/
        '';

        meta = with pkgs.lib; {
          description = "Debug Adapter Protocol SDK for Neovim";
          license = licenses.mit;
          platforms = platforms.all;
        };
      };

      # Test runner
      packages.test-all = pkgs.writeShellScriptBin "neodap-test" ''
        export LUA_PATH="./lua/?.lua;./lua/?/init.lua;$LUA_PATH"
        export LUA_CPATH="${pkgs.luajitPackages.luafilesystem}/lib/lua/5.1/?.so;${pkgs.luajitPackages.luasystem}/lib/lua/5.1/?.so;$LUA_CPATH"
        ${pkgs.luajitPackages.busted}/bin/busted spec/ --verbose
      '';

      # Test runner
      packages.test = pkgs.writeShellScriptBin "neodap-test" ''
        export LUA_PATH="./lua/?.lua;./lua/?/init.lua;$LUA_PATH"
        export LUA_CPATH="${pkgs.luajitPackages.luafilesystem}/lib/lua/5.1/?.so;${pkgs.luajitPackages.luasystem}/lib/lua/5.1/?.so;$LUA_CPATH"
        ${pkgs.luajitPackages.busted}/bin/busted $@
      '';

      # Run Neovim Init
      packages.test-nvim = pkgs.writeShellScriptBin "neodap-test-nvim" ''
        NEODAP_PLAYGROUND=1 nvim -u NONE -U NONE -N -i NONE -V1 -S ./lua/neodap/playground.lua
      '';

      # Linter runner
      packages.lint = pkgs.writeShellScriptBin "neodap-lint" ''
        ${pkgs.luaPackages.luacheck}/bin/luacheck lua/ --globals vim
      '';
    });
}
