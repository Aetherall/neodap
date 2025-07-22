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
          luajitPackages.penlight
          luajitPackages.lua-term
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
          vimPlugins.nui-nvim
          vimPlugins.telescope-nvim

          # make for building/testing
          gnumake
        ];

        shellHook = ''
          # Set up Lua paths for testing
          export LUA_PATH="./lua/?.lua;./lua/?/init.lua;$LUA_PATH"
          export LUA_CPATH="$LUA_CPATH"

          # Add busted to the Lua path & C path
          export LUA_PATH="${pkgs.luajitPackages.busted}/share/lua/5.1/?.lua;${pkgs.luajitPackages.busted}/share/lua/5.1/?/init.lua;$LUA_PATH"
          export LUA_CPATH="${pkgs.luajitPackages.busted}/lib/lua/5.1/?.so;$LUA_CPATH"

          # Add plenary.nvim to the Lua path and C path
          export LUA_PATH="${pkgs.vimPlugins.plenary-nvim}/lua/?.lua;${pkgs.vimPlugins.plenary-nvim}/lua/?/init.lua;$LUA_PATH"
          export LUA_CPATH="${pkgs.vimPlugins.plenary-nvim}/lib/lua/5.1/?.so;$LUA_CPATH"

          # Set up LuaJIT C extension paths for Neovim compatibility
          export LUA_PATH="${pkgs.luajitPackages.luafilesystem}/share/lua/5.1/?.lua;${pkgs.luajitPackages.luasystem}/share/lua/5.1/?.lua;$LUA_PATH"
          export LUA_CPATH="${pkgs.luajitPackages.luafilesystem}/lib/lua/5.1/?.so;${pkgs.luajitPackages.luasystem}/lib/lua/5.1/?.so;$LUA_CPATH"

          # Set up Penlight library paths
          export LUA_PATH="${pkgs.luajitPackages.penlight}/share/lua/5.1/?.lua;${pkgs.luajitPackages.penlight}/share/lua/5.1/?/init.lua;$LUA_PATH"
          export LUA_CPATH="${pkgs.luajitPackages.penlight}/lib/lua/5.1/?.so;$LUA_CPATH"

          # Set up Lua term library paths
          export LUA_PATH="${pkgs.luajitPackages.lua-term}/share/lua/5.1/?.lua;${pkgs.luajitPackages.lua-term}/share/lua/5.1/?/init.lua;$LUA_PATH"
          export LUA_CPATH="${pkgs.luajitPackages.lua-term}/lib/lua/5.1/?.so;$LUA_CPATH"

          # Provide nvim-nio as environment variable if needed
          export NVIM_NIO_PATH="${pkgs.vimPlugins.nvim-nio}"
          export PLENARY_NVIM_PATH="${pkgs.vimPlugins.plenary-nvim}"
          export NUI_NVIM_PATH="${pkgs.vimPlugins.nui-nvim}"
          export TELESCOPE_NVIM_PATH="${pkgs.vimPlugins.telescope-nvim}"


          echo "🧪 Neodap development environment ready!"
          echo "📚 Library paths for .luarc.json:"
          echo "  Neovim runtime: ${pkgs.neovim}/share/nvim/runtime/lua"
          echo "  nvim-nio: ${pkgs.vimPlugins.nvim-nio}/lua"
          echo "  plenary-nvim: ${pkgs.vimPlugins.plenary-nvim}/lua"
          echo "  nui-nvim: ${pkgs.vimPlugins.nui-nvim}/lua"
          echo "  telescope-nvim: ${pkgs.vimPlugins.telescope-nvim}/lua"
          echo "  busted: ${pkgs.luajitPackages.busted}/share/lua/5.1"
          echo "  penlight: ${pkgs.luajitPackages.penlight}/share/lua/5.1"

          echo "Run 'make test' to run tests"
          echo "Run 'make test spec/$file' to run a specific test file"
          echo "Run 'NEODAP_LOG_LEVEL=TRACE make test' to run tests with verbose logging"
          # echo "Run 'make play-all' to run the playground with all plugins"
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
    });
}
