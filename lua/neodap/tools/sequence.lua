local Class = require("neodap.tools.class")


---@class SequenceProps
---@field seq integer

---@class Sequence: SequenceProps
---@field new fun(self: Sequence, props: SequenceProps): Sequence
local Sequence = Class()

function Sequence.zero()
  return Sequence:new({
    seq = 0,
  })
end

---@return integer
function Sequence:next()
  self.seq = self.seq + 1
  return self.seq
end

function Sequence:set(seq)
  self.seq = seq
end

return Sequence
