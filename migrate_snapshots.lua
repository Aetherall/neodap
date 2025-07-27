#!/usr/bin/env lua

-- Migration script to extract embedded terminal snapshots from test files
-- and save them as external .snapshot files

local function parse_embedded_snapshots(file_path)
    local file = io.open(file_path, "r")
    if not file then
        error("Could not open file: " .. file_path)
    end
    
    local content = file:read("*all")
    file:close()
    
    local snapshots = {}
    
    -- Pattern to match embedded snapshots
    -- Captures: snapshot_name, size, cursor_info, mode, content_lines
    local pattern = "%-%-%[%[ TERMINAL SNAPSHOT: ([^%s]+)\nSize: ([^\n]+)\nCursor: ([^\n]+)\nMode: ([^\n]+)\n\n(.-)\n%]%]"
    
    for snapshot_name, size, cursor_info, mode, content_lines in content:gmatch(pattern) do
        -- Parse the content lines to remove line number prefixes
        local clean_lines = {}
        for line in content_lines:gmatch("([^\n]*)\n?") do
            if line ~= "" then
                -- Remove line number prefix like " 1| " or "10| "
                local clean_line = line:gsub("^%s*%d+%|", "")
                table.insert(clean_lines, clean_line)
            end
        end
        
        -- Join lines back together
        local clean_content = table.concat(clean_lines, "\n")
        
        table.insert(snapshots, {
            name = snapshot_name,
            size = size,
            cursor = cursor_info,
            mode = mode,
            content = clean_content
        })
    end
    
    return snapshots
end

local function create_snapshot_file(snapshot, output_dir)
    -- Create directory if it doesn't exist
    os.execute("mkdir -p " .. output_dir)
    
    -- Create the .snapshot file
    local snapshot_path = output_dir .. "/" .. snapshot.name .. ".snapshot"
    local file = io.open(snapshot_path, "w")
    if not file then
        error("Could not create snapshot file: " .. snapshot_path)
    end
    
    -- Write snapshot in the external format
    file:write("Size: " .. snapshot.size .. "\n")
    file:write("Cursor: " .. snapshot.cursor .. "\n") 
    file:write("Mode: " .. snapshot.mode .. "\n")
    file:write("\n")
    file:write(snapshot.content)
    
    file:close()
    return snapshot_path
end

local function get_snapshot_dir_for_spec(spec_file_path)
    -- Convert spec file path to snapshot directory
    -- e.g., lua/neodap/plugins/Variables4/specs/focus_mode.spec.lua
    -- becomes lua/neodap/plugins/Variables4/specs/snapshots/focus_mode/
    
    local dir = spec_file_path:match("(.+)/[^/]+%.spec%.lua$")
    if not dir then
        error("Could not determine directory for spec file: " .. spec_file_path)
    end
    
    local spec_filename = spec_file_path:match("/([^/]+)%.spec%.lua$")
    if not spec_filename then
        error("Could not determine spec filename: " .. spec_file_path)
    end
    
    return dir .. "/snapshots/" .. spec_filename
end

-- Main migration function
local function migrate_file(spec_file_path)
    print("Processing: " .. spec_file_path)
    
    local snapshots = parse_embedded_snapshots(spec_file_path)
    print("Found " .. #snapshots .. " embedded snapshots")
    
    local output_dir = get_snapshot_dir_for_spec(spec_file_path)
    print("Output directory: " .. output_dir)
    
    local created_files = {}
    for _, snapshot in ipairs(snapshots) do
        local snapshot_path = create_snapshot_file(snapshot, output_dir)
        table.insert(created_files, snapshot_path)
        print("  Created: " .. snapshot_path)
    end
    
    return {
        snapshots_found = #snapshots,
        output_dir = output_dir,
        created_files = created_files
    }
end

-- Command line interface
if arg and arg[1] then
    local spec_file = arg[1]
    local result = migrate_file(spec_file)
    
    print("\nMigration Summary:")
    print("- Snapshots found: " .. result.snapshots_found)
    print("- Output directory: " .. result.output_dir)
    print("- Files created: " .. #result.created_files)
    
    print("\nCreated files:")
    for _, file_path in ipairs(result.created_files) do
        print("  " .. file_path)
    end
else
    print("Usage: lua migrate_snapshots.lua <spec_file_path>")
    print("Example: lua migrate_snapshots.lua lua/neodap/plugins/Variables4/specs/focus_mode.spec.lua")
end

-- Export functions for use as a module
return {
    parse_embedded_snapshots = parse_embedded_snapshots,
    create_snapshot_file = create_snapshot_file,
    get_snapshot_dir_for_spec = get_snapshot_dir_for_spec,
    migrate_file = migrate_file
}