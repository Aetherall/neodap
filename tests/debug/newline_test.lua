local function test_jobstart()
  local job_id = vim.fn.jobstart({"printf", "A\\r\\n\\r\\nB"}, {
    on_stdout = function(_, data, _)
      if data then
        local joined = table.concat(data, "\n")
        local inspected = vim.inspect(data)
        print("Data: " .. inspected)
        print("Joined len: " .. #joined)
        for i = 1, #joined do
          print(string.format("Byte %d: %d", i, string.byte(joined, i)))
        end
      end
    end,
    stdout_buffered = true,
  })
  vim.fn.jobwait({job_id})
end

test_jobstart()
