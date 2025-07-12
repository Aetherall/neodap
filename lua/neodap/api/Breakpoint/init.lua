-- NewBreakpoint module exports
-- This module implements the lazy binding architecture with hierarchical events

return {
  -- Core classes
  BreakpointManager = require('neodap.api.NewBreakpoint.BreakpointManager'),
  FileSourceBreakpoint = require('neodap.api.NewBreakpoint.FileSourceBreakpoint'),
  FileSourceBinding = require('neodap.api.NewBreakpoint.FileSourceBinding'),
  
  -- Collections
  BreakpointCollection = require('neodap.api.NewBreakpoint.BreakpointCollection'),
  BindingCollection = require('neodap.api.NewBreakpoint.BindingCollection'),
  
  -- Utilities
  Location = require('neodap.api.NewBreakpoint.Location'),
  
  -- Example usage
  example = require('neodap.api.NewBreakpoint.example'),
}