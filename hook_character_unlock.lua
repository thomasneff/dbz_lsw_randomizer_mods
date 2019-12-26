-- 0x0EA7 - 0x0EA9: dropped cards after battle, can probably intercept writes to this address to automatically patch randomized loot.
local max_character_id = 27
local character_start_address = 0x0C1D
local character_struct_size = 16

local UNLOCKED_AND_FORM_BYTE = 0x00
local GAME_UNLOCK_BYTE = 0x0E
local RANDOMIZER_UNLOCK_BYTE = 0x0F
local NUMBER_OF_LIMIT_CARDS_BYTE = 0x08
local EXP_BYTE_HIGH = 0x03
local LEVEL_BYTE = 0x01

-- This list of forms only counts the *additional* forms, not default forms.
local NUMBER_OF_FORMS = {
  [1] = 2, -- Gohan (Teen): SSJ, SSJ2
  [2] = 2, -- Piccolo: God, Evil King
  [3] = 0, -- Krillin
  [4] = 3, -- Goku: SSJ, SSJ2, SSJ3
  [5] = 2, -- Vegeta: SSJ, Prince (Majin)
  [6] = 2, -- Gohan (Adult): SSJ2, Strongest
  [7] = 1, -- Trunks (Adult): SSJ
  [8] = 1, -- Goten: SSJ
  [9] = 1, -- Trunks (Kid): SSJ
  [10] = 1, -- Gotenks: SSJ3
  [11] = 0, -- Vegeto
  [12] = 0, -- Nappa
  [13] = 0, -- Guldo
  [14] = 0, -- Recoome
  [15] = 0, -- Jeice
  [16] = 0, -- Burter
  [17] = 1, -- Ginyu: Goku
  [18] = 0, -- Frieza
  [19] = 0, -- No. 16
  [20] = 0, -- No. 17
  [21] = 0, -- No. 18
  [22] = 0, -- No. 19
  [23] = 0, -- No. 20
  [24] = 2, -- Cell: Second, Perfect
  [25] = 0, -- Cell Jr.
  [26] = 0, -- Buu
  [27] = 3  -- Buu: Gotenks, Gohan, Pure Evil
}

local CHARS_WITH_FORMS = {1, 2, 4, 5, 6, 7, 8, 9, 10, 17, 24, 27}

-- Character unlock checks the lowest 2 bits apparently
-- 0 -> locked
-- 1 -> unlocked
-- 2 -> nothing
-- 3 -> unlocked, but not available
-- so we can use FD for unlock, and check if the locked flag is different, but also store if anything has already been unlocked
-- we init. no character is unlocked.
-- char x unlocked. we store that char x has been unlocked both in lua structs and WRAM. remove unlocked (by setting to special value) in WRAM. unlock random char + set state to "lua unlocked" by writing special value
-- Forms:
-- goes from the msb to the lsb of the high nibble
-- those are additional forms:
-- 0x80 -> first form (if exists) unlocked, e.g. SS1
-- 0x40 -> second form (if exists) unlocked, e.g. SS2
-- 0x20 -> third form (if exists) unlocked, e.g. SS3
-- 0x10 -> fourth form (if exists) unlocked / I don't think there is any char with 4 forms tho (not counting normal)


-- TODO: forms (SSJ / buu forms / whatever): need to check if a form is unlocked for any character -> need to compare known high-nibble to changed high-nibble and unlock a form?
--       this seems annoying though, as we basically need to make a fixed table of forms to see which char even has a form, and then basically unlock it?
-- TODO: unlocked but "not available" -> count "not available" events I guess? which sucks... then I'll need to react to unlocks that already exist (not available--) and locks that already exist (not available++)
-- TODO: change it so that we don't actually use the unlock flags to store our state? coould use the last 2 bytes in the 16 byte struct, since it seems unused... we don't actually gain a benefit from that though

-- How to do forms:
-- track/detect form event (first nibble is overwritten)
-- check if we already have this "game unlocked" form -> we require more storage, will need to move to an unused byte for that. use the 16th byte as "game unlocked" and the 15th as "randomizer unlocked"
-- then we simply unlock a form of a char. preferably, we first try the chars we already have. otherwise we unlock a random form already (and store the data correctly in byte 15/16)

local game_unlocked_bit = 0x10 -- the 0x10 (fourth form) doesn't exist, so we can misuse it as a flag to keep state so we can check for form changes
local randomizer_unlocked_bit = 0x05 -- if we use 0x05 (101), the game will overwrite it with 0x01, which is good. then we can just check for differences to check for unlocks 
local game_unlock_changed_bit = 0x01
local form_changed_bits = 0xF0

local CHARACTER_UNLOCKED_MASK = 0x01
local FIRST_FORM_UNLOCKED_MASK = 0x80
local SECOND_FORM_UNLOCKED_MASK = 0x40
local THIRD_FORM_UNLOCKED_MASK = 0x20
local FORM_CHECK_BIT_MASK = 0x10
local UNLOCK_CHECK_BIT_MASK = 0x05

-- TODO: for battle mode, each char that is unlocked is already unlocked with all forms
-- TODO: rewrite such that we don't actually use a character array but only the 15/16 byte. we read memory into a temp object (including 15/16). 
-- then we simply compare if byte 0 is different than byte 15 (game unlock) at every frame. if it is, we do a rando unlock accordingly. 

-- NEW:
-- if the char is not random-unlocked yet (byte 16 == 0x00):
--   we simply check if byte 0 is different to byte 15 ( = game updated a value) and detect the differences, then unlocking forms or the character and updating byte 15. afterwards, we write byte 16 into byte 0.
  
-- if the char is random-unlocked (byte 16 != 0x00):
--   we simply check if byte 0 is different to byte 16 ( = game updated a value) and detect the differences *TO BYTE 15*, then unlocking forms or the character and updating byte 15. afterwards, we write byte 16 into byte 0.

-- we check for a change event by comparing byte 0 to byte 15/16 for each char 

-- if change and unlocked new char/form:
--   randomly unlock another char, form



-- 0x00: unlock bit and form bit 
-- 0x01 level
-- 0x02 exp low byte
-- 0x03 exp high byte
-- 0x04 num life upgrades
-- 0x05 num str upgrades
-- 0x06 num ki upgrades
-- 0x07 num speed upgrades
-- 0x08 number of limit cards (max 5 in UI)
-- 0x09 first limit cards
-- TODO: refactor this into a generic per-frame event system

local character_unlock_hooks = {}

function character_unlock_hooks.clear_chars()
  for i = 1, max_character_id do
    print("Clearing char " .. tostring(i))
    for byte_offset = 0, 15 do
      --print("writing " .. 0x00 .. " to addr " .. bizstring.hex(character_start_address + byte_offset + (i - 1) * character_struct_size))
      memory.writebyte(character_start_address + byte_offset + (i - 1) * character_struct_size, 0x00, "WRAM")
    end
  end
end

function character_unlock_hooks.unlock_random_chars(num_random_chars)
  -- Char indices for easier unlocking later
  local character_ids = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27}

  while #character_ids ~=0 and num_random_chars ~= 0 do

    local random_list_id = math.random(#character_ids)
    local char_index = character_ids[random_list_id]


    memory.writebyte(character_start_address + UNLOCKED_AND_FORM_BYTE + (char_index - 1) * character_struct_size, 0xE1, "WRAM")
    memory.writebyte(character_start_address + NUMBER_OF_LIMIT_CARDS_BYTE + (char_index - 1) * character_struct_size, 0x03, "WRAM")
    memory.writebyte(character_start_address + EXP_BYTE_HIGH + (char_index - 1) * character_struct_size, 0x02, "WRAM")
    memory.writebyte(character_start_address + LEVEL_BYTE + (char_index - 1) * character_struct_size, 0x05, "WRAM")
    table.remove(character_ids, random_list_id)
    num_random_chars = num_random_chars - 1
    print("Randomly unlocked char " .. char_index .. "!")
  end


end

function character_unlock_hooks.init()
    -- TODO: initialize character data by reading a specific byte and checking for a specific value
    --       we need a value that signifies that the story has unlocked this character, since we overwrite the values with 00 when unlocked

    for i = 1, max_character_id do
        print("Initializing character data for char " .. tostring(i))
        character_data = character_unlock_hooks.read_character_data(i)

        -- TODO: reconstruct correct game/rando unlock from what's in the savestate
        --       we simply take the current state and use it as rando unlock, game unlock stays the same (assumption: start from a coherent state)
        
        character_data.bytes[UNLOCKED_AND_FORM_BYTE] = character_data.bytes[RANDOMIZER_UNLOCK_BYTE]
      
        character_unlock_hooks.write_character_data(character_data, i)
   

    end

end


-- Indexed from 1 ... max_character_id
function character_unlock_hooks.read_character_data_2(char_index)
    local character_data = {}
    
    character_data.unlocked = memory.readbyte(character_start_address + (char_index - 1) * character_struct_size, "WRAM")
    
    return character_data
end

function character_unlock_hooks.read_character_data(char_index)
  local character_data = {}
  
  character_data.bytes = {}
  character_data.bytes[UNLOCKED_AND_FORM_BYTE] = memory.readbyte(character_start_address + UNLOCKED_AND_FORM_BYTE + (char_index - 1) * character_struct_size, "WRAM")
  character_data.bytes[GAME_UNLOCK_BYTE] = memory.readbyte(character_start_address + GAME_UNLOCK_BYTE + (char_index - 1) * character_struct_size, "WRAM")
  character_data.bytes[RANDOMIZER_UNLOCK_BYTE] = memory.readbyte(character_start_address + RANDOMIZER_UNLOCK_BYTE + (char_index - 1) * character_struct_size, "WRAM")
  character_data.bytes[NUMBER_OF_LIMIT_CARDS_BYTE] = memory.readbyte(character_start_address + NUMBER_OF_LIMIT_CARDS_BYTE + (char_index - 1) * character_struct_size, "WRAM")
  
  return character_data
end

function character_unlock_hooks.write_character_data(character_data, char_index)

  memory.writebyte(character_start_address + UNLOCKED_AND_FORM_BYTE + (char_index - 1) * character_struct_size, character_data.bytes[UNLOCKED_AND_FORM_BYTE], "WRAM")
  memory.writebyte(character_start_address + GAME_UNLOCK_BYTE + (char_index - 1) * character_struct_size, character_data.bytes[GAME_UNLOCK_BYTE], "WRAM")
  memory.writebyte(character_start_address + RANDOMIZER_UNLOCK_BYTE + (char_index - 1) * character_struct_size, character_data.bytes[RANDOMIZER_UNLOCK_BYTE], "WRAM")
  memory.writebyte(character_start_address + NUMBER_OF_LIMIT_CARDS_BYTE + (char_index - 1) * character_struct_size, character_data.bytes[NUMBER_OF_LIMIT_CARDS_BYTE], "WRAM")

end


function character_unlock_hooks.is_character_unlocked(previous_data, current_data)

  if bit.band(previous_data, CHARACTER_UNLOCKED_MASK) == 0 and bit.band(current_data, CHARACTER_UNLOCKED_MASK) ~= 0 then
    return true
  end

  return false

end

function character_unlock_hooks.number_of_forms_unlocked(previous_data, current_data)

  local number_of_new_forms = 0

  if bit.band(previous_data, FIRST_FORM_UNLOCKED_MASK) == 0 and bit.band(current_data, FIRST_FORM_UNLOCKED_MASK) ~= 0 then
    number_of_new_forms = number_of_new_forms + 1
  end

  if bit.band(previous_data, SECOND_FORM_UNLOCKED_MASK) == 0 and bit.band(current_data, SECOND_FORM_UNLOCKED_MASK) ~= 0 then
    number_of_new_forms = number_of_new_forms + 1
  end

  if bit.band(previous_data, THIRD_FORM_UNLOCKED_MASK) == 0 and bit.band(current_data, THIRD_FORM_UNLOCKED_MASK) ~= 0 then
    number_of_new_forms = number_of_new_forms + 1
  end

  return number_of_new_forms

end

function character_unlock_hooks.current_number_of_forms_unlocked(character_data)

  local number_of_forms_unlocked = 0

  if bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], FIRST_FORM_UNLOCKED_MASK) ~= 0 then
    number_of_forms_unlocked = number_of_forms_unlocked + 1
  end

  if bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], SECOND_FORM_UNLOCKED_MASK) ~= 0 then
    number_of_forms_unlocked = number_of_forms_unlocked + 1
  end

  if bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], THIRD_FORM_UNLOCKED_MASK) ~= 0 then
    number_of_forms_unlocked = number_of_forms_unlocked + 1
  end

  return number_of_forms_unlocked
end

function character_unlock_hooks.number_of_locked_forms(character_data, character_index)

  -- Get number of unlocked forms, and subtract the number of total forms
  local number_of_unlocked_forms = character_unlock_hooks.current_number_of_forms_unlocked(character_data)

  return NUMBER_OF_FORMS[character_index] - number_of_unlocked_forms

end


function character_unlock_hooks.get_next_form(character_data)

  if bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], FIRST_FORM_UNLOCKED_MASK) == 0 then
    return FIRST_FORM_UNLOCKED_MASK
  end

  if bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], SECOND_FORM_UNLOCKED_MASK) == 0 then
    return SECOND_FORM_UNLOCKED_MASK
  end

  if bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], THIRD_FORM_UNLOCKED_MASK) == 0 then
    return THIRD_FORM_UNLOCKED_MASK
  end

  print("Invalid character data for get_next_form, this should not happen!: " .. character_data)

  return 0x00

end

function character_unlock_hooks.on_character_unlock()

  -- NEW:
  -- if the char is not random-unlocked yet (byte 16 == 0x00):
  --   we simply check if byte 0 is different to byte 15 ( = game updated a value) and detect the differences, then unlocking forms or the character and updating byte 15. afterwards, we write byte 16 into byte 0.
    
  -- if the char is random-unlocked (byte 16 != 0x00):
  --   we simply check if byte 0 is different to byte 16 ( = game updated a value) and detect the differences *TO BYTE 15*, then unlocking forms or the character and updating byte 15. afterwards, we write byte 16 into byte 0.

  -- we check for a change event by comparing byte 0 to byte 15/16 for each char 

  -- if change and unlocked new char/form:
  --   randomly unlock another char, form

  local chars_different = {}
  local num_chars_unlocked = 0
  local num_forms_unlocked = 0
  local temp_character_data = {}
  local randomizer_unlocked_indices = {}
  local num_locked_chars = 0
  local num_locked_forms = 0

  -- Ok, we have an issue when we unlock a form (0x80) and then unlock the game char for it.
  -- so we have 0x80 in RANDO, and GAME, then we have 0x01, and we unlock an additional form which we shouldn't do. 
  -- Also the game unlock isn't set correctly (it's set to 0x80 instead of 0x01)

  for character_id = 1, max_character_id do
    
    -- Read character data for each char (bytes 0, 15, 16)
    local character_data = character_unlock_hooks.read_character_data(character_id)

    -- Check if the char is random-unlocked yet or not
    local unlocked_and_form_byte = character_data.bytes[UNLOCKED_AND_FORM_BYTE]

    chars_different[character_id] = false



    if bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], CHARACTER_UNLOCKED_MASK) == 0x00 then
      if bit.band(character_data.bytes[UNLOCKED_AND_FORM_BYTE], CHARACTER_UNLOCKED_MASK) ~= 0x00 and bit.band(character_data.bytes[GAME_UNLOCK_BYTE], CHARACTER_UNLOCKED_MASK) == 0x00 then
        -- If the character was not randomizer-unlocked yet, we simply need to check if the unlocked byte is different than the value stored in GAME_UNLOCK_BYTE
        chars_different[character_id] = true
      end
    else
      if bit.band(character_data.bytes[UNLOCKED_AND_FORM_BYTE], CHARACTER_UNLOCKED_MASK) ~= 0x00 and bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], CHARACTER_UNLOCKED_MASK) == 0x00 then
        -- If the character was randomizer-unlocked already, we still need to check if the unlocked byte is different than the value stored in GAME_UNLOCK_BYTE
        chars_different[character_id] = true
      end
    end

    if bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], FORM_CHECK_BIT_MASK) == 0x00 then
      if bit.band(character_data.bytes[UNLOCKED_AND_FORM_BYTE], FORM_CHECK_BIT_MASK) ~= 0x00 and bit.band(character_data.bytes[GAME_UNLOCK_BYTE], FORM_CHECK_BIT_MASK) == 0x00 then
        -- If the character was not randomizer-unlocked yet, we simply need to check if the unlocked byte is different than the value stored in GAME_UNLOCK_BYTE
        chars_different[character_id] = true
      end
    else
      if bit.band(character_data.bytes[UNLOCKED_AND_FORM_BYTE], FORM_CHECK_BIT_MASK) ~= 0x00 and bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], FORM_CHECK_BIT_MASK) == 0x00 then
        -- If the character was randomizer-unlocked already, we still need to check if the unlocked byte is different than the value stored in GAME_UNLOCK_BYTE
        chars_different[character_id] = true
      end
    end


    if bit.band(character_data.bytes[GAME_UNLOCK_BYTE], CHARACTER_UNLOCKED_MASK) == 0x00 then
      num_locked_chars = num_locked_chars + 1
    end

    if bit.band(character_data.bytes[RANDOMIZER_UNLOCK_BYTE], CHARACTER_UNLOCKED_MASK) ~= 0x00 then
      randomizer_unlocked_indices[#randomizer_unlocked_indices + 1] = character_id
    end

    num_locked_forms = num_locked_forms + character_unlock_hooks.number_of_locked_forms(character_data, character_id)

    if chars_different[character_id] == true then
        
      -- Check differences in forms or unlock condition

      local new_character_unlock = character_unlock_hooks.is_character_unlocked(character_data.bytes[GAME_UNLOCK_BYTE], character_data.bytes[UNLOCKED_AND_FORM_BYTE])

      if new_character_unlock then
        num_chars_unlocked = num_chars_unlocked + 1
        print("New char unlock detected (unlocked game char: " .. tostring(character_id) .. ")")
      end

      local number_of_new_forms = character_unlock_hooks.number_of_forms_unlocked(character_data.bytes[GAME_UNLOCK_BYTE], character_data.bytes[UNLOCKED_AND_FORM_BYTE])

      -- Also check randomized byte in case we randomly unlocked a form. we don't want to loop ourselves with unlocked forms!

      if number_of_new_forms ~= 0 then
        num_forms_unlocked = num_forms_unlocked + number_of_new_forms
        print("New form unlock detected (unlocked game char: " .. tostring(character_id) .. ", number of forms: " .. tostring(number_of_new_forms) .. ")")
      end
      

      -- Make sure byte 15 (game unlock) is consistent again
      if new_character_unlock == true or number_of_new_forms ~= 0 then
        character_data.bytes[GAME_UNLOCK_BYTE] = character_data.bytes[UNLOCKED_AND_FORM_BYTE]
      end
      
    end

    temp_character_data[character_id] = character_data

  end


  -- Unlock characters via randomizer, and make sure to use special bits (0x15) to mark it so we can detect it later
  -- First, we check if there are even chars to be unlocked to avoid an endless loop
  num_chars_unlocked = math.min(num_locked_chars, num_chars_unlocked)

  while num_chars_unlocked > 0 do
    -- Randomly get an index, check if we already unlocked it, otherwise unlock and write unlock info into WRAM
    
    local random_char_id = math.random(max_character_id)
    
    if bit.band(temp_character_data[random_char_id].bytes[RANDOMIZER_UNLOCK_BYTE], CHARACTER_UNLOCKED_MASK) == 0 then
        num_chars_unlocked = num_chars_unlocked - 1
        
        -- Mark character as unlocked with "fourth form" that doesn't exist - that way we can check both nibbles for change
        temp_character_data[random_char_id].bytes[RANDOMIZER_UNLOCK_BYTE] = bit.bor(temp_character_data[random_char_id].bytes[RANDOMIZER_UNLOCK_BYTE], bit.bor(UNLOCK_CHECK_BIT_MASK, FORM_CHECK_BIT_MASK))
        temp_character_data[random_char_id].bytes[NUMBER_OF_LIMIT_CARDS_BYTE] = 0x03
        chars_different[random_char_id] = true

        -- Make sure to also store it in the "unlocked list" for this frame, in case we unlock forms in this frame as well

        local found = false

        for i, character_id in ipairs(randomizer_unlocked_indices) do
          if character_id == random_char_id then
            found = true
            break
          end
        end

        if found == false then
          randomizer_unlocked_indices[#randomizer_unlocked_indices + 1] = random_char_id
        end
      
        print("Randomly unlocked character " .. random_char_id)
    end

  end

  -- Unlock forms via randomizer by bit-or'ing the unlocked forms. 
  -- For forms, we first build a list of all rando-unlocked chars (see above) and combine it with the list of unlockable forms, so we prioritize unlocking forms of chars
  -- that we already unlocked

  -- Create list of randomizer-unlocked chars that actually have forms

  local randomizer_chars_with_forms = {}

  for i, character_id in ipairs(randomizer_unlocked_indices) do

    --print("loop test: ", character_id)
    
    local number_of_current_forms = character_unlock_hooks.current_number_of_forms_unlocked(temp_character_data[character_id])

    -- We only add it to the list of candidates if the char even has forms, and if we haven't unlocked them all via randomizer
    --print("NUM FORMS: ", NUMBER_OF_FORMS[character_id])
    --print("CURRENT num FORMS: ", number_of_current_forms)

    if NUMBER_OF_FORMS[character_id] ~= 0 and number_of_current_forms < NUMBER_OF_FORMS[character_id] then
      randomizer_chars_with_forms[#randomizer_chars_with_forms + 1] = character_id
    end

  end

  --print("randomizer chars with forms: ")
  --print(randomizer_chars_with_forms)

  -- We check the number of forms that are still locked and take the min 

  num_forms_unlocked = math.min(num_locked_forms, num_forms_unlocked)

  --print("num locked: ", num_locked_forms)
  --print("num unlocked: ", num_forms_unlocked)

  local loop_breaker = 0

  while num_forms_unlocked > 0 do
    -- Randomly get an index, check if we already unlocked it, otherwise unlock and write unlock info into WRAM

    -- First: check if we have something in our list and how many entries we have
    if #randomizer_chars_with_forms ~= 0 then
      -- This guarantees us a matching unlock
      local random_table_index = math.random(#randomizer_chars_with_forms)
      random_char_id = randomizer_chars_with_forms[random_table_index]
      
      num_forms_unlocked = num_forms_unlocked - 1
      local next_form = character_unlock_hooks.get_next_form(temp_character_data[random_char_id])
      temp_character_data[random_char_id].bytes[RANDOMIZER_UNLOCK_BYTE] = bit.bor(temp_character_data[random_char_id].bytes[RANDOMIZER_UNLOCK_BYTE], next_form)
      chars_different[random_char_id] = true
      -- Check if the char still has forms available
      local number_of_current_forms = character_unlock_hooks.current_number_of_forms_unlocked(temp_character_data[random_char_id])

      if NUMBER_OF_FORMS[random_char_id] ~= 0 and number_of_current_forms >= NUMBER_OF_FORMS[random_char_id] then
        -- If we reached the limit of forms, we need to remove the char
        table.remove(randomizer_chars_with_forms, random_table_index)
      end

      
      print("Randomly unlocked form " .. tostring(next_form) .. " for already unlocked char " .. tostring(random_char_id))

    else

      -- In this case, we randomly roll to unlock forms for characters that have one
      local random_char_id = math.random(#CHARS_WITH_FORMS)
      random_char_id = CHARS_WITH_FORMS[random_char_id]
      local number_of_current_forms = character_unlock_hooks.current_number_of_forms_unlocked(temp_character_data[random_char_id])
      if NUMBER_OF_FORMS[random_char_id] ~= 0 and number_of_current_forms < NUMBER_OF_FORMS[random_char_id] then
        num_forms_unlocked = num_forms_unlocked - 1
        chars_different[random_char_id] = true
        
        local next_form = character_unlock_hooks.get_next_form(temp_character_data[random_char_id])
        temp_character_data[random_char_id].bytes[RANDOMIZER_UNLOCK_BYTE] = bit.bor(temp_character_data[random_char_id].bytes[RANDOMIZER_UNLOCK_BYTE], next_form)
      
        
        print("Randomly unlocked form " .. tostring(next_form) .. " for not unlocked char " .. tostring(random_char_id))
        loop_breaker = 0
      end


    end

    loop_breaker = loop_breaker + 1

    if loop_breaker > 100 then
      print("Loop breaker")
      break
    end
    
  end



  -- Write back changed character data

  for character_id = 1, max_character_id do

    -- Set the game byte to the randomizer-unlock byte
    temp_character_data[character_id].bytes[UNLOCKED_AND_FORM_BYTE] = temp_character_data[character_id].bytes[RANDOMIZER_UNLOCK_BYTE]
      
    if chars_different[character_id] == true then
      character_unlock_hooks.write_character_data(temp_character_data[character_id], character_id)
    end

  end

end

return character_unlock_hooks
