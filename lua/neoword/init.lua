local Generator = {}

-- Configuration: The "Phonetic" Alphabet
-- We use tables for faster lookup than string.sub
local consonants = {
    'b', 'c', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'm',
    'n', 'p', 'r', 's', 't', 'v', 'w', 'x', 'y', 'z'
}                                          -- 20 chars
local vowels = { 'a', 'e', 'i', 'o', 'u' } -- 5 chars

-- 1. Internal Hashing Function (DJB2 variant)
-- This converts a string into a large integer deterministically.
local function string_to_int(str)
    local hash = 5381
    for i = 1, #str do
        local byte = string.byte(str, i)
        -- hash * 33 + byte
        hash = (hash * 33) + byte
        -- Keep it within positive Lua integer range
        hash = hash % 2147483647
    end
    return hash
end

-- 2. The Generator Function
function Generator.generate(input_str)
    -- If no input provided, use random time seed
    local seed = input_str and string_to_int(input_str) or math.random(1, 2147483647)

    local result = {}
    local temp_val = seed

    -- We need 5 characters: C - V - C - V - C
    -- We use modulus (%) to pick the index, and floor division to move to the next "slot"

    -- Char 1: Consonant
    table.insert(result, consonants[(temp_val % 20) + 1])
    temp_val = math.floor(temp_val / 20)

    -- Char 2: Vowel
    table.insert(result, vowels[(temp_val % 5) + 1])
    temp_val = math.floor(temp_val / 5)

    -- Char 3: Consonant
    table.insert(result, consonants[(temp_val % 20) + 1])
    temp_val = math.floor(temp_val / 20)

    -- Char 4: Vowel
    table.insert(result, vowels[(temp_val % 5) + 1])
    temp_val = math.floor(temp_val / 5)

    -- Char 5: Consonant
    table.insert(result, consonants[(temp_val % 20) + 1])

    return table.concat(result)
end

return Generator
