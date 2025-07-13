-- Public API for virtual buffer management
local VirtualBuffer = {}

VirtualBuffer.Registry = require('neodap.api.VirtualBuffer.Registry')
VirtualBuffer.Manager = require('neodap.api.VirtualBuffer.Manager')
VirtualBuffer.Metadata = require('neodap.api.VirtualBuffer.Metadata')

-- Factory functions
VirtualBuffer.createRegistry = VirtualBuffer.Registry.create
VirtualBuffer.createManager = VirtualBuffer.Manager.create

-- Static utility functions
VirtualBuffer.detectFiletype = VirtualBuffer.Manager.detectFiletype

return VirtualBuffer