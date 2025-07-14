-- local Class = require('neodap.tools.class')
-- local Base = require('neodap.api.Location.Base')
-- local nio = require("nio")

-- ---@class api.SourceFileProps: api.BaseLocationProps
-- ---@field path string

-- ---@class api.SourceFile: api.SourceFileProps, api.BaseLocationProps
-- ---@field new Constructor<api.SourceFileProps>
-- local SourceFile = Class(Base)

-- ---@param opts { path: string }
-- function SourceFile.create(opts)
--   return SourceFile:new({
--     type = 'source_file',
--     key = opts.path,
--     path = opts.path,
--   })
-- end

-- ---NEW: Create with source identifier
-- ---@param opts { source_identifier: SourceIdentifier }
-- function SourceFile.createWithIdentifier(opts)
--   local key
--   if opts.source_identifier.type == 'file' then
--     key = opts.source_identifier.path
--   else
--     key = opts.source_identifier:toString()
--   end
  
--   return SourceFile:new({
--     type = 'source_file',
--     key = key,
--     source_identifier = opts.source_identifier,
--     -- Backward compatibility
--     path = opts.source_identifier.type == 'file' and opts.source_identifier.path or nil
--   })
-- end

-- ---@param source api.FileSource
-- ---@return api.SourceFile
-- function SourceFile.fromSource(source)
--   local path = source:absolutePath()
--   return SourceFile:new({
--     type = 'source_file',
--     key = path,
--     path = path,
--   })
-- end

-- ---@return api.SourceFile
-- function SourceFile.fromCursor()
--   local path = vim.api.nvim_buf_get_name(0)

--   return SourceFile:new({
--     type = 'source_file',
--     key = path,
--     path = path,
--   })
-- end

-- ---@param other api.Location
-- ---@return_cast other api.SourceFile
-- function SourceFile:equals(other)
--   return self.key == other.key
-- end

-- ---@return integer?
-- function SourceFile:bufnr()
--   local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(self.path))
--   if bufnr == -1 then
--     return nil
--   end
--   return bufnr
-- end

-- function SourceFile:deferUntilLoaded()
--   local bufnr = self:bufnr()

--   if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
--     return self
--   end
  
--   local future = nio.control.future()
  
--   if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
--     return future.wait() -- This buffer will never load, block indefinitely
--   end

--   vim.api.nvim_create_autocmd({ "BufReadPost" }, {
--     buffer = bufnr,
--     once = true,
--     callback = function()
--       if not vim.api.nvim_buf_is_loaded(bufnr) then
--         future.set(nil)
--         return
--       end
--       future.set(self)
--     end
--   })

--   return future.wait()
-- end

-- function SourceFile:SourceFile()
--   return self
-- end


-- return SourceFile