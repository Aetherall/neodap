-- Quick debug script to check expansion
local prepare = require("spec.helpers.prepare").prepare
local SimpleVariableTree3 = require("neodap.plugins.SimpleVariableTree3")
local nio = require("nio")

-- Prepare API
local api, start = prepare()
api:getPluginInstance(SimpleVariableTree3)

-- Check the toggle_variable function
print("SimpleVariableTree3.toggle_variable exists:", SimpleVariableTree3.toggle_variable ~= nil)
print("SimpleVariableTree3.commands exists:", SimpleVariableTree3.commands ~= nil)
print("SimpleVariableTree3.commands.toggle_node exists:", SimpleVariableTree3.commands and SimpleVariableTree3.commands.toggle_node ~= nil)

-- Check what utils.wrap does
local utils = require("neo-tree.utils")
local wrapped = utils.wrap(SimpleVariableTree3.toggle_variable, {})
print("utils.wrap result type:", type(wrapped))

api:destroy()