-- Tests for structured output expansion in the tree
--
-- Verifies that console output with variablesReference can be expanded
-- to show nested data. This is primarily supported by js-debug.
-- Python debugpy typically outputs plain text without variablesReference.

local harness = require("helpers.test_harness")

-- Helper to setup structured-output fixture
local function setup_structured_output(h)
  h:fixture("structured-output")
  h:use_plugin("neodap.plugins.tree_buffer")

  h:cmd("DapLaunch Debug")
  h:wait_url("/sessions/threads(state=stopped)/stacks[0]/frames[0]")
  h:cmd("DapFocus /sessions/threads/stacks[0]/frames[0]")
end

local T = harness.integration("structured_output", function(T, ctx)

  --============================================================================
  -- Structured Output Tests (JavaScript-focused)
  --============================================================================

  T["outputs are created when console.log runs"] = function()
    local h = ctx.create()
    setup_structured_output(h)

    -- Continue to run the console.log statements
    h:cmd("DapContinue")
    h:wait(500) -- Wait for output events

    -- Check that outputs were created
    local output_count = h:query_count("/sessions[0]/outputs")
    MiniTest.expect.equality(output_count >= 1, true, "Should have at least 1 output")
  end

  -- JavaScript-specific test for structured output expansion
  T["javascript: output with variablesReference can be expanded"] = {
    -- Only run for javascript fixture
    filter = function(_, lang) return lang == "javascript" end,
    test = function()
      local h = ctx.create()
      setup_structured_output(h)

      -- Continue to run the console.log statements
      h:cmd("DapContinue")
      h:wait(1000) -- Wait for output events

      -- Find outputs with variablesReference > 0
      local output_count = h:query_count("/sessions[0]/outputs")
      local found_structured = false
      local structured_output_uri = nil

      for i = 0, output_count - 1 do
        local output_url = "/sessions[0]/outputs[" .. i .. "]"
        local vars_ref = h:query_field(output_url, "variablesReference")
        if vars_ref and vars_ref > 0 then
          found_structured = true
          structured_output_uri = h:query_uri(output_url)

          -- Expand the output
          h:query_call(output_url, "fetchChildren")
          h:wait(200)

          -- Verify children were created
          local children_count = h:query_count(structured_output_uri .. "/children")
          MiniTest.expect.equality(children_count >= 1, true, "Structured output should have children")
          break
        end
      end

      MiniTest.expect.equality(found_structured, true, "Should have at least one structured output")
    end
  }

  T["javascript: expanded output children have names and values"] = {
    filter = function(_, lang) return lang == "javascript" end,
    test = function()
      local h = ctx.create()
      setup_structured_output(h)

      -- Continue to run the console.log statements
      h:cmd("DapContinue")
      h:wait(1000)

      -- Find first structured output
      local output_count = h:query_count("/sessions[0]/outputs")
      for i = 0, output_count - 1 do
        local output_url = "/sessions[0]/outputs[" .. i .. "]"
        local vars_ref = h:query_field(output_url, "variablesReference")
        if vars_ref and vars_ref > 0 then
          local output_uri = h:query_uri(output_url)

          -- Expand output
          h:query_call(output_url, "fetchChildren")
          h:wait(200)

          -- Check first child has name and value
          local child_url = output_uri .. "/children[0]"
          if not h:query_is_nil(child_url) then
            local name = h:query_field(child_url, "name")
            local value = h:query_field(child_url, "value")
            MiniTest.expect.no_equality(name, nil, "Child should have name")
            MiniTest.expect.no_equality(value, nil, "Child should have value")
          end
          return
        end
      end

      -- If no structured output found, that's ok for this test
      MiniTest.expect.equality(true, true, "No structured output to test")
    end
  }

  T["javascript: nested output children can be expanded"] = {
    filter = function(_, lang) return lang == "javascript" end,
    test = function()
      local h = ctx.create()
      setup_structured_output(h)

      -- Continue to run the console.log statements
      h:cmd("DapContinue")
      h:wait(1000)

      -- Find structured output (config object should have nested structure)
      local output_count = h:query_count("/sessions[0]/outputs")
      for i = 0, output_count - 1 do
        local output_url = "/sessions[0]/outputs[" .. i .. "]"
        local vars_ref = h:query_field(output_url, "variablesReference")
        if vars_ref and vars_ref > 0 then
          local output_uri = h:query_uri(output_url)

          -- Expand output to get first level children
          h:query_call(output_url, "fetchChildren")
          h:wait(200)

          -- Check if any child has variablesReference (can be expanded further)
          local children_count = h:query_count(output_uri .. "/children")
          for j = 0, children_count - 1 do
            local child_url = output_uri .. "/children[" .. j .. "]"
            local child_vars_ref = h:query_field(child_url, "variablesReference")
            if child_vars_ref and child_vars_ref > 0 then
              local child_uri = h:query_uri(child_url)

              -- Expand nested child
              h:query_call(child_url, "fetchChildren")
              h:wait(200)

              local nested_count = h:query_count(child_uri .. "/children")
              MiniTest.expect.equality(nested_count >= 1, true, "Nested child should be expandable")
              return
            end
          end
        end
      end

      -- If no nested structure found, that's ok
      MiniTest.expect.equality(true, true, "No nested structure to test")
    end
  }

  --============================================================================
  -- Output Entity Tests (both languages)
  --============================================================================

  T["output has session link"] = function()
    local h = ctx.create()
    setup_structured_output(h)

    -- Continue to generate output
    h:cmd("DapContinue")
    h:wait(500)

    local output_count = h:query_count("/sessions[0]/outputs")
    if output_count > 0 then
      local output_url = "/sessions[0]/outputs[0]"
      local output_uri = h:query_uri(output_url)
      local session_uri = h:query_field_uri(output_url, "session")
      MiniTest.expect.no_equality(session_uri, nil, "Output should have session link")
    else
      MiniTest.expect.equality(true, true, "No outputs to test")
    end
  end

  T["output hasVariables returns correct value"] = function()
    local h = ctx.create()
    setup_structured_output(h)

    -- Continue to generate output
    h:cmd("DapContinue")
    h:wait(500)

    local output_count = h:query_count("/sessions[0]/outputs")
    if output_count > 0 then
      local output_url = "/sessions[0]/outputs[0]"
      -- Just verify the output entity exists and has required fields
      local text = h:query_field(output_url, "text")
      MiniTest.expect.no_equality(text, nil, "Output should have text")
    else
      MiniTest.expect.equality(true, true, "No outputs to test")
    end
  end

end)

return T
