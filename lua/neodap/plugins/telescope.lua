-- Plugin: Telescope pickers for DAP entities
--
-- Requires telescope.nvim as an external dependency.
-- NOT included in boost.lua — user registers explicitly:
--
--   local telescope = require("neodap").use(require("neodap.plugins.telescope"))
--   vim.keymap.set("n", "<leader>ds", telescope.sessions)
--
-- Commands (routed through :Dap pick):
--   :DapPick sessions           - Pick and focus a debug session
--   :DapPick frames             - Pick and focus a stack frame
--   :DapPick exception_filters  - Toggle exception filter breakpoints

local navigate = require("neodap.plugins.utils.navigate")
local log = require("neodap.logger")

---@class neodap.plugins.TelescopeConfig
---@field frames? { skip_hints?: table<string,boolean>, dim_hints?: table<string,boolean> }

local default_config = {
  frames = {
    skip_hints = { label = true },
    dim_hints = { subtle = true },
  },
}

---@param debugger neodap.entities.Debugger
---@param config? neodap.plugins.TelescopeConfig
---@return table api Plugin API
return function(debugger, config)
  local has_telescope, _ = pcall(require, "telescope")
  if not has_telescope then
    error("neodap.plugins.telescope requires telescope.nvim")
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  local entry_display = require("telescope.pickers.entry_display")

  config = vim.tbl_deep_extend("force", default_config, config or {})

  local api = {}

  -- ========================================================================
  -- Sessions
  -- ========================================================================

  function api.sessions(opts)
    opts = opts or {}
    local show_terminated = false

    local function get_sessions()
      local all = debugger:queryAll("/sessions(leaf=true)")
      if show_terminated then return all end
      return vim.tbl_filter(function(s)
        return s.state:get() ~= "terminated"
      end, all)
    end

    local function make_entry(session)
      return {
        value = session,
        display = debugger:render_text(session, { { "state", prefix = "[", suffix = "] " }, "title" }),
        ordinal = debugger:render_text(session, { "title" }),
      }
    end

    pickers.new(opts, {
      prompt_title = "Debug Sessions",
      finder = finders.new_table({
        results = get_sessions(),
        entry_maker = make_entry,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Session Info",
        define_preview = function(self, entry)
          local session = entry.value
          local bufnr = self.state.bufnr
          local ns = vim.api.nvim_create_namespace("neodap_telescope_preview")

          -- Collect lines and their highlight segments
          -- Each entry: { text = string, highlights = { { col_start, col_end, hl_group } } }
          local rendered = {}

          ---Add a line with highlight segments from debugger:render()
          ---@param label string|nil Label prefix (e.g. "Session: ")
          ---@param entity table Entity to render
          ---@param layout table Layout slots for render()
          local function add_rendered_line(label, entity, layout)
            local segments = debugger:render(entity, layout)
            local text_parts = {}
            local highlights = {}
            if label then
              text_parts[#text_parts + 1] = label
            end
            for _, seg in ipairs(segments) do
              local start = #table.concat(text_parts)
              text_parts[#text_parts + 1] = seg.text
              if seg.hl then
                highlights[#highlights + 1] = { start, start + #seg.text, seg.hl }
              end
            end
            rendered[#rendered + 1] = { text = table.concat(text_parts), highlights = highlights }
          end

          ---Add a plain text line with optional highlight
          ---@param text string
          ---@param hl? string
          local function add_line(text, hl)
            local highlights = {}
            if hl then
              highlights[#highlights + 1] = { 0, #text, hl }
            end
            rendered[#rendered + 1] = { text = text, highlights = highlights }
          end

          -- === Metadata section ===

          add_rendered_line("Session: ", session, { "session_name" })
          add_rendered_line("State:   ", session, { "state" })

          -- Show config name if part of a compound
          local cfg = session.config:get()
          if cfg and cfg.isCompound:get() then
            add_rendered_line("Config:  ", cfg, { "title" })
          end

          -- Show chain (root > ... > leaf) if session has a parent
          local parent = session.parent:get()
          if parent then
            add_rendered_line("Chain:   ", session, { "title" })
          end

          add_line("")

          -- Threads
          local threads = debugger:queryAll(session.uri:get() .. "/threads")
          if #threads > 0 then
            add_line("Threads:", "DapTreeGroup")
            for _, thread in ipairs(threads) do
              add_rendered_line("  ", thread, { { "state", prefix = "[", suffix = "] " }, "title" })
            end
          end

          -- === Separator ===

          -- Calculate preview window width for the separator line
          local win_width = 40
          if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
            win_width = vim.api.nvim_win_get_width(self.state.winid)
          end
          add_line("")
          add_line(string.rep("─", win_width), "Comment")
          add_line("")

          -- === Console output section ===

          -- Query recent outputs (newest first via allOutputs sorted by globalSeq desc)
          local separator_line = #rendered
          local max_outputs = 50
          local count = 0
          for output in session.allOutputs:iter("by_visible_matched_globalSeq_desc") do
            if count >= max_outputs then break end
            local visible = output.visible:get()
            local matched = output.matched:get()
            if visible ~= false and matched ~= false then
              add_rendered_line(nil, output, { { "category", suffix = " " }, "title" })
              count = count + 1
            end
          end

          if count == 0 then
            add_line("  No console output", "Comment")
          end

          -- === Apply to buffer ===

          local lines = {}
          for _, r in ipairs(rendered) do
            lines[#lines + 1] = r.text
          end
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

          -- Apply highlights via extmarks
          vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
          for i, r in ipairs(rendered) do
            for _, hl in ipairs(r.highlights) do
              pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, i - 1, hl[1], {
                end_col = hl[2],
                hl_group = hl[3],
              })
            end
          end
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          if not entry then return end

          debugger:action("focus_and_jump", entry.value)
        end)

        map({ "i", "n" }, "<C-a>", function()
          show_terminated = not show_terminated
          local picker = action_state.get_current_picker(prompt_bufnr)
          picker:refresh(finders.new_table({
            results = get_sessions(),
            entry_maker = make_entry,
          }))
        end)

        return true
      end,
    }):find()
  end

  -- ========================================================================
  -- Frames
  -- ========================================================================

  function api.frames(opts)
    opts = opts or {}
    local skip_hints = config.frames.skip_hints
    local dim_hints = config.frames.dim_hints

    local frames = debugger:queryAll("@thread/stack/frames")
    if #frames == 0 then
      log:warn("No frames in current stack")
      return
    end

    table.sort(frames, function(a, b) return a.index:get() < b.index:get() end)

    if skip_hints and next(skip_hints) then
      frames = vim.tbl_filter(function(f)
        return not f:isSkippable(skip_hints)
      end, frames)
    end

    local displayer = entry_display.create({
      separator = " ",
      items = {
        { width = 4 },
        { remaining = true },
      },
    })

    pickers.new(opts, {
      prompt_title = "Stack Frames",
      finder = finders.new_table({
        results = frames,
        entry_maker = function(frame)
          local idx_text = debugger:render_text(frame, { "index" })
          local right = debugger:render_text(frame, { "title", { "location", prefix = " (", suffix = ")" } })

          local hl = frame:isSubtle(dim_hints) and "Comment" or nil

          local path, line = navigate.frame_location(frame)

          return {
            value = frame,
            display = function()
              return displayer({
                { idx_text, hl },
                { right, hl },
              })
            end,
            ordinal = debugger:render_text(frame, { "index", { "title", prefix = " " }, { "location", prefix = " " } }),
            filename = path and not path:match("^dap://") and path or nil,
            lnum = line or 1,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Source",
        define_preview = function(self, entry)
          local frame = entry.value
          local path, line = navigate.frame_location(frame)
          if not path then return end

          local real_path = path:match("^dap://source/source:(.+)$")
          if real_path and vim.fn.filereadable(real_path) == 1 then
            path = real_path
          end

          if not path:match("^dap://") and vim.fn.filereadable(path) == 1 then
            local content = vim.fn.readfile(path)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)

            local ft = vim.filetype.match({ filename = path })
            if ft then
              vim.bo[self.state.bufnr].filetype = ft
            end

            if line and line > 0 and line <= #content then
              pcall(vim.api.nvim_buf_add_highlight,
                self.state.bufnr, 0, "CursorLine", line - 1, 0, -1)
              pcall(vim.api.nvim_win_set_cursor, self.state.winid, { line, 0 })
            end
          end
        end,
      }),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          if not entry then return end

          debugger:action("focus_and_jump", entry.value)
        end)
        return true
      end,
    }):find()
  end

  -- ========================================================================
  -- Exception Filters
  -- ========================================================================

  function api.exception_filters(opts)
    opts = opts or {}

    local function get_bindings()
      return debugger:queryAll("@session/exceptionFilterBindings")
    end

    local function make_entry(binding)
      local ef = binding.exceptionFilter:get()
      if not ef then return nil end
      return {
        value = binding,
        display = debugger:render_text(binding, { "icon", { "title", prefix = " " }, { "condition", prefix = " " } }),
        ordinal = debugger:render_text(binding, { "title" }),
      }
    end

    pickers.new(opts, {
      prompt_title = "Exception Filters",
      finder = finders.new_table({
        results = get_bindings(),
        entry_maker = make_entry,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          if not entry then return end

          debugger:action("toggle", entry.value)

          local picker = action_state.get_current_picker(prompt_bufnr)
          picker:refresh(finders.new_table({
            results = get_bindings(),
            entry_maker = make_entry,
          }))
        end)

        map("n", "c", function()
          local entry = action_state.get_selected_entry()
          if not entry then return end

          actions.close(prompt_bufnr)
          debugger:action("edit_condition", entry.value)
        end)

        return true
      end,
    }):find()
  end

  -- ========================================================================
  -- DapPick Command
  -- ========================================================================

  local picker_names = { "sessions", "frames", "exception_filters" }

  vim.api.nvim_create_user_command("DapPick", function(opts)
    local name = opts.args
    if api[name] then
      api[name]()
    else
      log:error("DapPick: unknown picker", { picker = name })
    end
  end, {
    nargs = 1,
    desc = "Open telescope picker for DAP entities",
    complete = function(arglead)
      return vim.tbl_filter(function(name)
        return name:match("^" .. vim.pesc(arglead))
      end, picker_names)
    end,
  })

  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "DapPick")
  end

  return api
end
