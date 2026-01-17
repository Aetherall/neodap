{
  description = "neodap - Neovim DAP plugin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forEachSystem = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forEachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.neovim
          pkgs.emmylua-ls
          pkgs.zig
          pkgs.vscode-js-debug
          (pkgs.python3.withPackages (ps: [ps.debugpy]))
          # Treesitter parsers for inline values plugin
          (pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
            p.javascript
            p.typescript
            p.python
            p.lua
          ]))
          pkgs.vimPlugins.luvit-meta
        ];

        shellHook = let
          treesitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
            p.javascript
            p.typescript
            p.python
            p.lua
          ]);
          # Individual grammar packages for manual registration
          grammars = pkgs.vimPlugins.nvim-treesitter.builtGrammars;
        in ''
          export VIMRUNTIME=$(nvim --headless -c "lua print(vim.env.VIMRUNTIME)" -c "q" 2>&1 | tail -1)
          export LUVIT_PATH="${pkgs.vimPlugins.luvit-meta}/library"

          export JS_DEBUG_PATH="${pkgs.vscode-js-debug}/bin/js-debug"
          export DEBUGPY_PATH="${pkgs.python3.withPackages (ps: [ps.debugpy])}/bin/python"
          export TREESITTER_PATH="${treesitter}"
          export TS_PARSER_JAVASCRIPT="${grammars.javascript}/parser"
          export TS_PARSER_TYPESCRIPT="${grammars.typescript}/parser"
          export TS_PARSER_PYTHON="${grammars.python}/parser"
          export TS_PARSER_LUA="${grammars.lua}/parser"
          echo "neodap dev environment"
          echo "  nvim: $(nvim --version | head -1)"
          echo "  zig:  $(zig version)"
          echo "  js-debug: $JS_DEBUG_PATH"
          echo "  debugpy: $DEBUGPY_PATH"
          echo "  treesitter: $TREESITTER_PATH"
        '';
      };
    });
  };
}
