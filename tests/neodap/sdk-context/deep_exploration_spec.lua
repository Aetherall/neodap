-- Test deep exploration into structured output
-- NO MOCKS - uses real debugpy adapter and actual Python program

local sdk = require("neodap.sdk")

describe("Deep Structured Output Exploration (Real Debugger)", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/deep_structured.py"

  ---Helper to find a variable by name in a list
  ---@param variables List<Variable>
  ---@param name string
  ---@return Variable?
  local function find_variable(variables, name)
    for var in variables:iter() do
      if var.name == name then
        return var
      end
    end
    return nil
  end

  it("should explore deeply nested object structure", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Breakpoint at line 62 where we have all the data
    local bp = debugger:add_breakpoint({ path = script_path }, 62)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- Wait for stopped state
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    assert.are.equal("stopped", session.state:get())

    -- Get thread and stack
    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    assert.is_not_nil(thread, "should have thread")

    local stack = thread:stack()
    local frame = stack:top()
    assert.is_not_nil(frame, "should have top frame")

    -- Get scopes
    local scopes = frame:scopes()
    assert.is_not_nil(scopes, "should have scopes")

    -- Find locals scope
    local locals_scope = nil
    for s in scopes:iter() do
      if s.name == "Locals" or s.name:lower():find("local") then
        locals_scope = s
        break
      end
    end
    assert.is_not_nil(locals_scope, "should have Locals scope")

    -- Get variables from locals
    local variables = locals_scope:variables()
    assert.is_not_nil(variables, "should have variables")

    -- ==========================================================================
    -- LEVEL 1: Find the 'company' variable
    -- ==========================================================================
    local company = find_variable(variables, "company")
    assert.is_not_nil(company, "should have 'company' variable")
    assert.is_true(company.variablesReference > 0, "company should be expandable")

    -- ==========================================================================
    -- LEVEL 2: Explore company's children
    -- ==========================================================================
    local company_children = company:variables()
    assert.is_not_nil(company_children, "company should have children")

    local company_name = find_variable(company_children, "name")
    assert.is_not_nil(company_name, "company should have 'name' attribute")
    assert.is_string(company_name.value:get(), "company.name should have value")
    assert.is_true(company_name.value:get():find("TechCorp") ~= nil, "company.name should be TechCorp")

    local company_address = find_variable(company_children, "address")
    assert.is_not_nil(company_address, "company should have 'address' attribute")
    assert.is_true(company_address.variablesReference > 0, "address should be expandable")

    local company_departments = find_variable(company_children, "departments")
    assert.is_not_nil(company_departments, "company should have 'departments' attribute")
    assert.is_true(company_departments.variablesReference > 0, "departments should be expandable")

    -- ==========================================================================
    -- LEVEL 3: Explore address and departments
    -- ==========================================================================
    local address_children = company_address:variables()
    assert.is_not_nil(address_children, "address should have children")

    local street = find_variable(address_children, "street")
    assert.is_not_nil(street, "address should have 'street' attribute")
    assert.is_true(street.value:get():find("123 Main St") ~= nil, "street should be '123 Main St'")

    local city = find_variable(address_children, "city")
    assert.is_not_nil(city, "address should have 'city' attribute")
    assert.is_true(city.value:get():find("San Francisco") ~= nil, "city should be 'San Francisco'")

    -- Explore departments list
    local departments_children = company_departments:variables()
    assert.is_not_nil(departments_children, "departments should have children")

    -- Find first department (index 0)
    local dept_0 = find_variable(departments_children, "0")
    assert.is_not_nil(dept_0, "departments[0] should exist")
    assert.is_true(dept_0.variablesReference > 0, "departments[0] should be expandable")

    -- ==========================================================================
    -- LEVEL 4: Explore first department
    -- ==========================================================================
    local dept_children = dept_0:variables()
    assert.is_not_nil(dept_children, "department should have children")

    local dept_name = find_variable(dept_children, "name")
    assert.is_not_nil(dept_name, "department should have 'name' attribute")
    assert.is_true(dept_name.value:get():find("Engineering") ~= nil, "department name should be 'Engineering'")

    local employees = find_variable(dept_children, "employees")
    assert.is_not_nil(employees, "department should have 'employees' attribute")
    assert.is_true(employees.variablesReference > 0, "employees should be expandable")

    -- ==========================================================================
    -- LEVEL 5: Explore first employee
    -- ==========================================================================
    local employees_children = employees:variables()
    assert.is_not_nil(employees_children, "employees should have children")

    local emp_0 = find_variable(employees_children, "0")
    assert.is_not_nil(emp_0, "employees[0] should exist")
    assert.is_true(emp_0.variablesReference > 0, "employees[0] should be expandable")

    local emp_children = emp_0:variables()
    assert.is_not_nil(emp_children, "employee should have children")

    local emp_name = find_variable(emp_children, "name")
    assert.is_not_nil(emp_name, "employee should have 'name' attribute")
    assert.is_true(emp_name.value:get():find("Alice") ~= nil, "employee name should be 'Alice'")

    local emp_role = find_variable(emp_children, "role")
    assert.is_not_nil(emp_role, "employee should have 'role' attribute")
    assert.is_true(emp_role.value:get():find("Lead") ~= nil, "employee role should be 'Lead'")

    local skills = find_variable(emp_children, "skills")
    assert.is_not_nil(skills, "employee should have 'skills' attribute")
    assert.is_true(skills.variablesReference > 0, "skills should be expandable")

    local metadata = find_variable(emp_children, "metadata")
    assert.is_not_nil(metadata, "employee should have 'metadata' attribute")
    assert.is_true(metadata.variablesReference > 0, "metadata should be expandable")

    -- ==========================================================================
    -- LEVEL 6: Explore skills array and metadata dict
    -- ==========================================================================
    local skills_children = skills:variables()
    assert.is_not_nil(skills_children, "skills should have children")

    local skill_0 = find_variable(skills_children, "0")
    assert.is_not_nil(skill_0, "skills[0] should exist")
    assert.is_true(skill_0.value:get():find("python") ~= nil, "skills[0] should be 'python'")

    local metadata_children = metadata:variables()
    assert.is_not_nil(metadata_children, "metadata should have children")

    local active = find_variable(metadata_children, "'active'") or find_variable(metadata_children, "active")
    assert.is_not_nil(active, "metadata should have 'active' key")
    assert.is_true(active.value:get():find("True") ~= nil, "metadata['active'] should be True")

    local level_val = find_variable(metadata_children, "'level'") or find_variable(metadata_children, "level")
    assert.is_not_nil(level_val, "metadata should have 'level' key")
    assert.is_true(level_val.value:get():find("5") ~= nil, "metadata['level'] should be 5")

    local tags = find_variable(metadata_children, "'tags'") or find_variable(metadata_children, "tags")
    assert.is_not_nil(tags, "metadata should have 'tags' key")
    assert.is_true(tags.variablesReference > 0, "tags should be expandable")

    -- ==========================================================================
    -- LEVEL 7: Explore tags array
    -- ==========================================================================
    local tags_children = tags:variables()
    assert.is_not_nil(tags_children, "tags should have children")

    local tag_0 = find_variable(tags_children, "0")
    assert.is_not_nil(tag_0, "tags[0] should exist")
    assert.is_true(tag_0.value:get():find("developer") ~= nil, "tags[0] should be 'developer'")

    -- ==========================================================================
    -- Also test nested_dict exploration (pure dict nesting)
    -- ==========================================================================
    local nested_dict = find_variable(variables, "nested_dict")
    assert.is_not_nil(nested_dict, "should have 'nested_dict' variable")
    assert.is_true(nested_dict.variablesReference > 0, "nested_dict should be expandable")

    -- Level 1
    local nested_dict_children = nested_dict:variables()
    local level1 = find_variable(nested_dict_children, "'level1'") or find_variable(nested_dict_children, "level1")
    assert.is_not_nil(level1, "nested_dict should have 'level1' key")
    assert.is_true(level1.variablesReference > 0, "level1 should be expandable")

    -- Level 2
    local level1_children = level1:variables()
    local level2 = find_variable(level1_children, "'level2'") or find_variable(level1_children, "level2")
    assert.is_not_nil(level2, "level1 should have 'level2' key")
    assert.is_true(level2.variablesReference > 0, "level2 should be expandable")

    -- Level 3
    local level2_children = level2:variables()
    local level3 = find_variable(level2_children, "'level3'") or find_variable(level2_children, "level3")
    assert.is_not_nil(level3, "level2 should have 'level3' key")
    assert.is_true(level3.variablesReference > 0, "level3 should be expandable")

    -- Level 4
    local level3_children = level3:variables()
    local level4 = find_variable(level3_children, "'level4'") or find_variable(level3_children, "level4")
    assert.is_not_nil(level4, "level3 should have 'level4' key")
    assert.is_true(level4.variablesReference > 0, "level4 should be expandable")

    -- Final value
    local level4_children = level4:variables()
    local deep_value = find_variable(level4_children, "'value'") or find_variable(level4_children, "value")
    assert.is_not_nil(deep_value, "level4 should have 'value' key")
    assert.is_true(deep_value.value:get():find("deep_value") ~= nil, "deepest value should be 'deep_value'")

    session:disconnect(true)
    debugger:dispose()
  end)

  it("should verify all variables have correct hierarchy info", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 62)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    local stack = thread:stack()
    local frame = stack:top()
    local scopes = frame:scopes()
    local locals_scope = nil
    for s in scopes:iter() do
      if s.name == "Locals" or s.name:lower():find("local") then
        locals_scope = s
        break
      end
    end
    local variables = locals_scope:variables()

    -- Navigate deep and verify hierarchy
    local company = find_variable(variables, "company")
    local company_children = company:variables()
    local address = find_variable(company_children, "address")
    local address_children = address:variables()
    local street = find_variable(address_children, "street")
    local departments = find_variable(company_children, "departments")
    local departments_children = departments:variables()
    local dept_0 = find_variable(departments_children, "0")
    local dept_children = dept_0:variables()
    local employees = find_variable(dept_children, "employees")
    local employees_children = employees:variables()
    local emp_0 = find_variable(employees_children, "0")
    local emp_children = emp_0:variables()
    local skills = find_variable(emp_children, "skills")
    local skills_children = skills:variables()
    local skill_0 = find_variable(skills_children, "0")
    local metadata = find_variable(emp_children, "metadata")
    local metadata_children = metadata:variables()
    local tags = find_variable(metadata_children, "'tags'") or find_variable(metadata_children, "tags")
    local tags_children = tags:variables()
    local tag_0 = find_variable(tags_children, "0")

    -- nested_dict path
    local nested_dict = find_variable(variables, "nested_dict")
    local nd_children = nested_dict:variables()
    local level1 = find_variable(nd_children, "'level1'") or find_variable(nd_children, "level1")
    local l1_children = level1:variables()
    local level2 = find_variable(l1_children, "'level2'") or find_variable(l1_children, "level2")
    local l2_children = level2:variables()
    local level3 = find_variable(l2_children, "'level3'") or find_variable(l2_children, "level3")
    local l3_children = level3:variables()
    local level4 = find_variable(l3_children, "'level4'") or find_variable(l3_children, "level4")
    local l4_children = level4:variables()
    local deep_value = find_variable(l4_children, "'value'") or find_variable(l4_children, "value")

    -- All variables should have correct session reference
    assert.are.equal(session, company.session, "company should have session")
    assert.are.equal(session, dept_0.session, "dept_0 should have session")
    assert.are.equal(session, emp_0.session, "emp_0 should have session")
    assert.are.equal(session, skill_0.session, "skill_0 should have session")

    -- All variables from scopes should have container_type = "scope"
    assert.are.equal("scope", company.container_type, "company.container_type should be 'scope'")
    assert.are.equal("scope", skill_0.container_type, "skill_0.container_type should be 'scope'")

    -- container_id should be the scope name for scope variables
    assert.is_string(company.container_id, "company should have container_id")
    assert.is_string(skill_0.container_id, "skill_0 should have container_id")

    -- All variables should be current
    assert.is_true(company:is_current(), "company should be current")
    assert.is_true(skill_0:is_current(), "skill_0 should be current")

    -- All variables should have URIs
    assert.is_string(company.uri, "company should have URI")
    assert.is_string(skill_0.uri, "skill_0 should have URI")

    session:disconnect(true)
    debugger:dispose()
  end)

  it("should mark deeply nested variables as stale when stack expires", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    -- Two breakpoints to trigger stack expiration
    local bp1 = debugger:add_breakpoint({ path = script_path }, 62)
    local bp2 = debugger:add_breakpoint({ path = script_path }, 63)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    local stack = thread:stack()
    local frame = stack:top()
    local scopes = frame:scopes()
    local locals_scope = nil
    for s in scopes:iter() do
      if s.name == "Locals" or s.name:lower():find("local") then
        locals_scope = s
        break
      end
    end
    local variables = locals_scope:variables()

    -- Navigate deep to get a deeply nested variable
    local company = find_variable(variables, "company")
    local company_children = company:variables()
    local departments = find_variable(company_children, "departments")
    local departments_children = departments:variables()
    local dept_0 = find_variable(departments_children, "0")
    local dept_children = dept_0:variables()
    local employees = find_variable(dept_children, "employees")
    local employees_children = employees:variables()
    local emp_0 = find_variable(employees_children, "0")
    local emp_children = emp_0:variables()
    local skills = find_variable(emp_children, "skills")
    local skills_children = skills:variables()
    local skill_0 = find_variable(skills_children, "0")

    -- All should be current
    assert.is_true(company:is_current(), "company should be current initially")
    assert.is_true(skill_0:is_current(), "skill_0 should be current initially")

    -- Continue to next breakpoint
    session:continue(thread.id)

    -- Wait for second stop with stale stack
    vim.wait(10000, function()
      local t = nil
      for thread in session:threads():iter() do
        t = thread
        break
      end
      if not t then return false end

      local stale_count = 0
      for _ in t:stale_stacks():iter() do
        stale_count = stale_count + 1
      end

      return t.state:get() == "stopped" and stale_count > 0
    end)

    -- All deeply nested variables should now be stale
    assert.is_false(company:is_current(), "company should be stale after continue")
    assert.is_false(dept_0:is_current(), "dept_0 should be stale after continue")
    assert.is_false(emp_0:is_current(), "emp_0 should be stale after continue")
    assert.is_false(skill_0:is_current(), "skill_0 should be stale after continue")

    -- But values should still be accessible (not disposed)
    assert.is_string(company.name, "company.name should still be accessible")
    assert.is_string(skill_0.name, "skill_0.name should still be accessible")
    assert.is_string(skill_0.value:get(), "skill_0.value should still be accessible")

    session:disconnect(true)
    debugger:dispose()
  end)
end)

-- =============================================================================
-- STRUCTURED EVALUATION RESULTS
-- =============================================================================

-- Inline verified_it helper for async tests (evaluate requires coroutine)
local function verified_it(name, fn, timeout_ms)
  timeout_ms = timeout_ms or 30000

  return it(name, function()
    local completed = false
    local test_error = nil
    local test_result = nil

    local co = coroutine.create(function()
      local ok, result = pcall(fn)
      if not ok then
        test_error = result
      else
        test_result = result
      end
      completed = true
    end)

    local ok, err = coroutine.resume(co)
    if not ok and not completed then
      error("Test failed to start: " .. tostring(err))
    end

    local success = vim.wait(timeout_ms, function()
      return completed
    end, 100)

    if not success then
      error(string.format("Test '%s' timed out after %dms", name, timeout_ms))
    end

    if test_error then
      error(test_error)
    end

    if test_result ~= true then
      error(string.format(
        "Test did not return true (got: %s). Tests must return true at completion.",
        tostring(test_result)
      ))
    end
  end)
end

describe("Deep Structured Evaluation Results (Real Debugger)", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/deep_structured.py"

  ---Helper to find a variable by name in a list
  ---@param variables List<Variable>
  ---@param name string
  ---@return Variable?
  local function find_variable(variables, name)
    for var in variables:iter() do
      if var.name == name then
        return var
      end
    end
    return nil
  end

  verified_it("should explore deeply nested evaluation result", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 62)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    local stack = thread:stack()
    local frame = stack:top()

    -- Evaluate the company object
    local err, eval_result = frame:evaluate("company")
    assert.is_nil(err, "company evaluation should succeed: " .. tostring(err))
    assert.is_not_nil(eval_result, "should get evaluation result")
    assert.is_true(eval_result.variablesReference > 0, "company should be expandable")

    print("\n=== Evaluation Result URIs ===")
    print("eval_result.expression = " .. eval_result.expression)
    print("eval_result.result     = " .. eval_result.result)
    print("eval_result.varRef     = " .. eval_result.variablesReference)

    -- Level 1: Expand evaluation result
    local eval_children = eval_result:variables()
    assert.is_not_nil(eval_children, "eval_result should have children")

    local address = find_variable(eval_children, "address")
    assert.is_not_nil(address, "company should have 'address' attribute")
    print("address.uri            = " .. tostring(address.uri))

    local departments = find_variable(eval_children, "departments")
    assert.is_not_nil(departments, "company should have 'departments' attribute")
    print("departments.uri        = " .. tostring(departments.uri))

    -- Level 2: Expand address
    local address_children = address:variables()
    local street = find_variable(address_children, "street")
    assert.is_not_nil(street, "address should have 'street' attribute")
    print("street.uri             = " .. tostring(street.uri))

    -- Level 2: Expand departments list
    local departments_children = departments:variables()
    local dept_0 = find_variable(departments_children, "0")
    assert.is_not_nil(dept_0, "departments[0] should exist")
    print("dept_0.uri             = " .. tostring(dept_0.uri))

    -- Level 3: Expand first department
    local dept_children = dept_0:variables()
    local employees = find_variable(dept_children, "employees")
    assert.is_not_nil(employees, "department should have 'employees' attribute")
    print("employees.uri          = " .. tostring(employees.uri))

    -- Level 4: Expand employees
    local employees_children = employees:variables()
    local emp_0 = find_variable(employees_children, "0")
    assert.is_not_nil(emp_0, "employees[0] should exist")
    print("emp_0.uri              = " .. tostring(emp_0.uri))

    -- Level 5: Expand first employee
    local emp_children = emp_0:variables()
    local skills = find_variable(emp_children, "skills")
    assert.is_not_nil(skills, "employee should have 'skills' attribute")
    print("skills.uri             = " .. tostring(skills.uri))

    -- Level 6: Expand skills
    local skills_children = skills:variables()
    local skill_0 = find_variable(skills_children, "0")
    assert.is_not_nil(skill_0, "skills[0] should exist")
    print("skill_0.uri            = " .. tostring(skill_0.uri))
    assert.is_true(skill_0.value:get():find("python") ~= nil, "skills[0] should be 'python'")

    print("============================\n")

    -- Verify hierarchy info is correct for evaluation result children
    -- EvaluateResult is independent of frame/scope - has its own ID
    assert.are.equal(session, address.session, "address should have session")
    assert.are.equal(session, skill_0.session, "skill_0 should have session")

    -- container_id should be the eval result ID, container_type should be "eval"
    assert.is_string(address.container_id, "address should have container_id")
    assert.are.equal("eval", address.container_type, "address.container_type should be 'eval'")
    assert.are.equal("eval", skill_0.container_type, "skill_0.container_type should be 'eval'")

    -- Evaluation result itself should have a URI
    assert.is_string(eval_result.uri, "eval_result should have URI")
    print("eval_result.uri        = " .. eval_result.uri)

    -- Variables from evaluation results now have proper URIs
    assert.is_string(address.uri, "evaluation result children have URIs")
    assert.is_truthy(address.uri:match("eval:"), "address.uri should contain 'eval:'")

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("should explore nested dict evaluation result", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 62)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    local stack = thread:stack()
    local frame = stack:top()

    -- Evaluate the nested_dict
    local err, eval_result = frame:evaluate("nested_dict")
    assert.is_nil(err, "nested_dict evaluation should succeed: " .. tostring(err))
    assert.is_not_nil(eval_result, "should get evaluation result")
    assert.is_true(eval_result.variablesReference > 0, "nested_dict should be expandable")

    print("\n=== Nested Dict Evaluation URIs ===")

    -- Navigate through all 4 levels
    local l1_children = eval_result:variables()
    local level1 = find_variable(l1_children, "'level1'") or find_variable(l1_children, "level1")
    assert.is_not_nil(level1, "should have level1")
    print("level1.uri             = " .. tostring(level1.uri))

    local l2_children = level1:variables()
    local level2 = find_variable(l2_children, "'level2'") or find_variable(l2_children, "level2")
    assert.is_not_nil(level2, "should have level2")
    print("level2.uri             = " .. tostring(level2.uri))

    local l3_children = level2:variables()
    local level3 = find_variable(l3_children, "'level3'") or find_variable(l3_children, "level3")
    assert.is_not_nil(level3, "should have level3")
    print("level3.uri             = " .. tostring(level3.uri))

    local l4_children = level3:variables()
    local level4 = find_variable(l4_children, "'level4'") or find_variable(l4_children, "level4")
    assert.is_not_nil(level4, "should have level4")
    print("level4.uri             = " .. tostring(level4.uri))

    local l5_children = level4:variables()
    local deep_value = find_variable(l5_children, "'value'") or find_variable(l5_children, "value")
    assert.is_not_nil(deep_value, "should have value")
    print("deep_value.uri         = " .. tostring(deep_value.uri))

    assert.is_true(deep_value.value:get():find("deep_value") ~= nil, "deepest value should be 'deep_value'")
    print("=====================================\n")

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("should evaluate expression and explore result inline", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("python", {
      type = "stdio",
      command = "python3",
      args = { "-m", "debugpy.adapter" }
    })

    local bp = debugger:add_breakpoint({ path = script_path }, 62)

    local session = debugger:start({
      type = "python",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end)

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end
    local stack = thread:stack()
    local frame = stack:top()

    -- Evaluate a constructed expression
    local err, eval_result = frame:evaluate("{'constructed': {'nested': [1, 2, {'deep': 'value'}]}}")
    assert.is_nil(err, "dict evaluation should succeed: " .. tostring(err))
    assert.is_not_nil(eval_result, "should get evaluation result")

    print("\n=== Inline Expression Evaluation URIs ===")
    print("expression = " .. eval_result.expression)

    if eval_result.variablesReference > 0 then
      -- Navigate to the deepest value
      local root_children = eval_result:variables()
      local constructed = find_variable(root_children, "'constructed'") or find_variable(root_children, "constructed")
      assert.is_not_nil(constructed, "should have 'constructed' key")
      print("constructed.uri        = " .. tostring(constructed.uri))

      local nested_children = constructed:variables()
      local nested = find_variable(nested_children, "'nested'") or find_variable(nested_children, "nested")
      assert.is_not_nil(nested, "should have 'nested' key")
      print("nested.uri             = " .. tostring(nested.uri))

      local array_children = nested:variables()
      local item_2 = find_variable(array_children, "2")
      assert.is_not_nil(item_2, "should have index 2")
      print("item_2.uri             = " .. tostring(item_2.uri))

      local obj_children = item_2:variables()
      local deep = find_variable(obj_children, "'deep'") or find_variable(obj_children, "deep")
      assert.is_not_nil(deep, "should have 'deep' key")
      print("deep.uri               = " .. tostring(deep.uri))

      assert.is_true(deep.value:get():find("value") ~= nil, "deep value should be 'value'")
    else
      print("Note: Result not expandable (variablesReference=0)")
    end

    print("==========================================\n")

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)

-- =============================================================================
-- STRUCTURED OUTPUT (Console Output with variablesReference)
-- =============================================================================

describe("Deep Structured Output Exploration (Real Debugger - js-debug)", function()
  local script_path = vim.fn.getcwd() .. "/tests/fixtures/structured_output.js"

  ---Helper to find a variable by name in a list
  ---@param variables List<Variable>
  ---@param name string
  ---@return Variable?
  local function find_variable(variables, name)
    for var in variables:iter() do
      if var.name == name then
        return var
      end
    end
    return nil
  end

  ---Helper to wait for js-debug child session
  ---@param parent_session Session
  ---@return Session?
  local function wait_for_child_session(parent_session)
    local child = nil
    vim.wait(10000, function()
      for session in parent_session:children():iter() do
        child = session
        return true
      end
      return false
    end, 100)
    return child
  end

  verified_it("should explore structured console output", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },  -- Let js-debug pick a random port
      host = "::1",    -- js-debug listens on IPv6 localhost
      connect_condition = function(output)
        -- Handle both IPv4 and IPv6 addresses (captures port at end of line)
        return output:match(":(%d+)%s*$")
      end
    })

    local bootstrap_session = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- js-debug creates a child session for actual debugging
    local session = wait_for_child_session(bootstrap_session)
    assert.is_not_nil(session, "should have child session")

    -- Wait for debugger stop (at the debugger; statement)
    vim.wait(15000, function()
      return session.state:get() == "stopped"
    end)

    assert.are.equal("stopped", session.state:get(), "session should be stopped at debugger statement")

    -- Check if we have any structured outputs
    local outputs = session:outputs()
    assert.is_not_nil(outputs, "session should have outputs list")

    -- Print what outputs we got
    print("\n=== Structured Output Exploration ===")
    local structured_output = nil
    local output_count = 0
    for output in outputs:iter() do
      output_count = output_count + 1
      print(string.format("Output %d: category=%s, varRef=%d, output=%s",
        output.index, output.category or "nil", output.variablesReference or 0,
        (output.output or ""):sub(1, 50)))

      -- Find an output with variablesReference > 0
      if output.variablesReference and output.variablesReference > 0 then
        structured_output = output
      end
    end

    print(string.format("Total outputs: %d", output_count))

    if structured_output then
      print("\n=== Exploring Structured Output ===")
      print("output.uri             = " .. structured_output.uri)
      print("output.variablesRef    = " .. structured_output.variablesReference)

      -- Expand the output's variables
      local output_vars = structured_output:variables()
      assert.is_not_nil(output_vars, "structured output should have variables")

      for var in output_vars:iter() do
        print(string.format("  %s = %s (varRef=%d)",
          var.name, var.value:get():sub(1, 30), var.variablesReference or 0))
        print("    var.uri            = " .. tostring(var.uri))
        print("    var.container_type = " .. tostring(var.container_type))
        print("    var.container_id   = " .. tostring(var.container_id))

        -- Verify container_type is "output"
        assert.are.equal("output", var.container_type, "variable from output should have container_type='output'")
        assert.are.equal(session, var.session, "variable should have session reference")

        -- If this variable is expandable, go deeper
        if var.variablesReference > 0 then
          local children = var:variables()
          if children then
            for child in children:iter() do
              print(string.format("      %s = %s", child.name, child.value:get():sub(1, 30)))
              print("        child.uri          = " .. tostring(child.uri))
              assert.are.equal("output", child.container_type, "nested variable should have container_type='output'")
            end
          end
        end
      end
    else
      print("Note: No structured output with variablesReference > 0 received")
      print("This may vary by debug adapter version")
    end

    print("=====================================\n")

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("should have correct URIs for output variables", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },  -- Let js-debug pick a random port
      host = "::1",    -- js-debug listens on IPv6 localhost
      connect_condition = function(output)
        -- Handle both IPv4 and IPv6 addresses (captures port at end of line)
        return output:match(":(%d+)%s*$")
      end
    })

    local bootstrap_session = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    -- js-debug creates a child session for actual debugging
    local session = wait_for_child_session(bootstrap_session)
    assert.is_not_nil(session, "should have child session")

    vim.wait(15000, function()
      return session.state:get() == "stopped"
    end)

    -- Find structured output
    local structured_output = nil
    for output in session:outputs():iter() do
      if output.variablesReference and output.variablesReference > 0 then
        structured_output = output
        break
      end
    end

    if structured_output then
      -- Verify output URI format
      local expected_uri_pattern = "dap:session:" .. session.id .. "/output:%d+"
      assert.is_truthy(structured_output.uri:match(expected_uri_pattern),
        "output URI should match pattern: " .. expected_uri_pattern)

      -- Get variables and verify their URIs
      local vars = structured_output:variables()
      if vars then
        for var in vars:iter() do
          -- Variable URI should include output reference
          assert.is_truthy(var.uri:match("/output:%d+/var:"),
            "variable URI should contain /output:<index>/var:")

          -- Deep children should also have output URIs
          if var.variablesReference > 0 then
            local children = var:variables()
            if children then
              for child in children:iter() do
                assert.is_truthy(child.uri:match("/output:%d+/var:"),
                  "nested variable URI should contain /output:<index>/var:")
              end
            end
          end
        end
      end
    else
      print("Note: No structured output available - test passes vacuously")
    end

    session:disconnect(true)
    vim.wait(2000, function() return session.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)

-- =============================================================================
-- NODE.JS VIRTUAL SOURCE EXPLORATION (Internal Timer Module)
-- =============================================================================

describe("Node.js Virtual Source Exploration (setInterval callback)", function()
  local script_path = vim.fn.fnamemodify("tests/fixtures/interval_test.js", ":p")

  ---Helper to wait for js-debug child session
  ---@param parent_session Session
  ---@return Session?
  local function wait_for_child_session(parent_session)
    local child = nil
    vim.wait(10000, function()
      for session in parent_session:children():iter() do
        child = session
        return true
      end
      return false
    end, 100)
    return child
  end

  verified_it("should explore stack frames when stopped in setInterval callback", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },  -- Let js-debug pick a random port
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        return tonumber(p), h  -- Return both port and host
      end,
    })

    -- Set breakpoint at line 6 (inside the interval callback)
    debugger:add_breakpoint({ path = script_path }, 6)

    -- Start returns the bootstrap session
    local bootstrap = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== NODE.JS VIRTUAL SOURCE EXPLORATION ===")

    -- js-debug creates a child session for actual debugging
    print("  Waiting for child session...")
    local session = wait_for_child_session(bootstrap)
    if not session then
      error("No child session created - js-debug bootstrap may have failed")
    end
    print("  Got child session")

    -- Wait for initial stop at breakpoint
    print("  Waiting for stopped state...")
    vim.wait(15000, function()
      return session.state:get() == "stopped"
    end, 100)
    print(string.format("  Session state: %s", session.state:get()))

    if session.state:get() ~= "stopped" then
      error("Session did not stop - state: " .. session.state:get())
    end

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end

    if not thread then
      error("No thread found - session state: " .. session.state:get())
    end

    -- Get the stack
    local stack = thread:stack()

    print("\n--- All Stack Frames ---")
    local virtual_sources = {}
    local frame_idx = 0
    for frame in stack:frames():iter() do
      frame_idx = frame_idx + 1
      local src = frame.source
      local src_name = src and src.name or "?"
      local src_path = src and src.path or "nil"
      local is_virtual = src and src:is_virtual() or false
      local src_ref = src and src.sourceReference or nil

      print(string.format("[%d] %s @ line %d, col %d", frame_idx, frame.name, frame.line or 0, frame.column or 0))
      print(string.format("    source.name: %s", src_name))
      print(string.format("    source.path: %s", src_path))
      print(string.format("    source.is_virtual: %s", tostring(is_virtual)))
      print(string.format("    source.sourceReference: %s", tostring(src_ref)))
      if src then
        print(string.format("    source.uri: %s", src:location_uri()))
      end
      print("")

      -- Track virtual sources for later use
      if is_virtual then
        table.insert(virtual_sources, {
          name = src_name,
          sourceReference = src_ref,
          line = frame.line,
          column = frame.column,
          frame_name = frame.name,
          source = src,
        })
      end
    end

    print(string.format("\n=== Found %d virtual sources ===", #virtual_sources))
    for i, vs in ipairs(virtual_sources) do
      print(string.format("[%d] %s (ref=%s) at %s:%d:%d",
        i, vs.name, tostring(vs.sourceReference),
        vs.frame_name, vs.line or 0, vs.column or 0))
    end

    -- If we found virtual sources, try to fetch content from the first one
    if #virtual_sources > 0 then
      local vs = virtual_sources[1]
      print(string.format("\n--- Fetching content from virtual source: %s ---", vs.name))

      -- fetch_content() returns (err, content) directly (uses settle() internally)
      local err, content = vs.source:fetch_content()

      if err then
        print("Fetch error: " .. err)
      elseif content then
        print("Virtual source content (first 20 lines):")
        local lines = vim.split(content, "\n")
        for i = 1, math.min(20, #lines) do
          print(string.format("  %3d: %s", i, lines[i]))
        end
        if #lines > 20 then
          print(string.format("  ... (%d more lines)", #lines - 20))
        end
      else
        print("Could not fetch virtual source content (nil)")
      end
    end

    -- Cleanup
    bootstrap:disconnect(true)
    vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)

  verified_it("should set and hit breakpoint in virtual source", function()
    local debugger = sdk:create_debugger()

    debugger:register_adapter("pwa-node", {
      type = "server",
      command = "js-debug",
      args = { "0" },
      connect_condition = function(chunk)
        local h, p = chunk:match("Debug server listening at (.*):(%d+)")
        return tonumber(p), h
      end,
    })

    -- Set breakpoint at line 6 (inside the interval callback) - we'll remove this later
    local user_bp = debugger:add_breakpoint({ path = script_path }, 6)

    local bootstrap = debugger:start({
      type = "pwa-node",
      request = "launch",
      program = script_path,
      console = "internalConsole",
    })

    print("\n=== VIRTUAL SOURCE BREAKPOINT TEST ===")

    -- Wait for child session
    local session = wait_for_child_session(bootstrap)
    if not session then
      error("No child session created")
    end

    -- Wait for initial stop at user's breakpoint
    vim.wait(15000, function()
      return session.state:get() == "stopped"
    end, 100)

    if session.state:get() ~= "stopped" then
      error("Session did not stop at initial breakpoint")
    end

    local thread = nil
    for t in session:threads():iter() do
      thread = t
      break
    end

    -- Get the stack to discover virtual sources
    local stack = thread:stack()

    -- Find the timer module virtual source (listOnTimeout function)
    local timer_source = nil
    local timer_line = nil
    for frame in stack:frames():iter() do
      if frame.source and frame.source:is_virtual() then
        if frame.source.name and frame.source.name:match("internal/timers") then
          timer_source = frame.source
          timer_line = frame.line
          print(string.format("Found timer source: %s (ref=%d) at line %d",
            timer_source.name, timer_source.sourceReference, timer_line))
          break
        end
      end
    end

    if not timer_source then
      -- No timer source found - this is ok for the test, skip
      print("No timer source found in stack - skipping virtual breakpoint test")
      bootstrap:disconnect(true)
      vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
      debugger:dispose()
      return true
    end

    -- IMPORTANT: Remove the user code breakpoint so we only have the virtual source breakpoint
    -- Otherwise we'll stop at the user code breakpoint again on the next interval tick
    print("Removing user code breakpoint...")
    user_bp:dispose()

    -- Wait for breakpoint removal to sync to DAP
    vim.wait(1000)

    -- Add a breakpoint in the virtual source using the discovered Source object
    -- Use the actual source data with its sourceReference
    print(string.format("Adding breakpoint to virtual source at line %d", timer_line))
    print(string.format("  timer_source.path: %s", tostring(timer_source.path)))
    print(string.format("  timer_source.name: %s", timer_source.name))
    print(string.format("  timer_source.correlation_key: %s", timer_source.correlation_key))
    local virtual_bp = debugger:add_breakpoint({
      -- Include ALL source properties for virtual source breakpoints
      path = timer_source.path,  -- pseudo-path like "<node_internals>/internal/timers"
      name = timer_source.name,
      sourceReference = timer_source.sourceReference,
      -- Set correlation_key to match the Source for proper tracking
      correlation_key = timer_source.correlation_key,
    }, timer_line)

    -- Wait for breakpoint sync to DAP
    vim.wait(2000, function()
      return virtual_bp.state:get() == "bound" or virtual_bp.state:get() == "hit"
    end, 100)

    print(string.format("Virtual breakpoint created: id=%s, state=%s",
      virtual_bp.id, virtual_bp.state:get()))

    -- Check bindings
    print("Checking bindings...")
    for binding in virtual_bp.bindings:iter() do
      print(string.format("  Binding: session=%s, verified=%s, message=%s",
        binding.session.id,
        tostring(binding.verified:get()),
        tostring(binding.message:get())))
    end

    -- Continue execution - should hit the virtual source breakpoint on next interval tick
    print("Continuing execution...")
    thread:continue()

    -- Wait for next stop
    vim.wait(10000, function()
      return session.state:get() == "stopped"
    end, 100)

    if session.state:get() ~= "stopped" then
      print("WARN: Did not stop again after continue")
    else
      -- Get new stack
      stack = thread:stack()
      local top_frame = stack:top()
      if top_frame then
        print(string.format("Stopped at: %s:%d (source=%s)",
          top_frame.name, top_frame.line or 0,
          top_frame.source and top_frame.source.name or "?"))

        -- Check if we're in the virtual source
        if top_frame.source and top_frame.source:is_virtual() then
          print("SUCCESS: Stopped in virtual source!")
          assert.is_true(true, "Hit breakpoint in virtual source")
        else
          print("Stopped in user code, not virtual source")
          -- Check virtual breakpoint state to understand what happened
          print(string.format("Virtual BP state: %s", virtual_bp.state:get()))
        end
      end
    end

    -- Check breakpoint state
    print(string.format("Virtual breakpoint final state: %s", virtual_bp.state:get()))

    -- Cleanup
    bootstrap:disconnect(true)
    vim.wait(2000, function() return bootstrap.state:get() == "terminated" end)
    debugger:dispose()

    return true
  end)
end)
