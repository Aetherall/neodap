-- NewBreakpoint module exports
-- This module implements the lazy binding architecture with hierarchical events

return {
  -- Core classes
  BreakpointManager = require('neodap.plugins.BreakpointApi.BreakpointManager'),
  FileSourceBreakpoint = require('neodap.plugins.BreakpointApi.FileSourceBreakpoint'),
  FileSourceBinding = require('neodap.plugins.BreakpointApi.FileSourceBinding'),
  
  -- Collections
  BreakpointCollection = require('neodap.plugins.BreakpointApi.BreakpointCollection'),
  BindingCollection = require('neodap.plugins.BreakpointApi.BindingCollection'),
  
  -- Utilities
  Location = require('neodap.plugins.BreakpointApi.Location'),
  
  -- Example usage
  example = require('neodap.plugins.BreakpointApi.example'),
}