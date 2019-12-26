-- 0x0EA7 - 0x0EA9: dropped cards after battle, can probably intercept writes to this address to automatically patch randomized loot.
local max_character_id = 27
local character_start_address = 0x0C1D
local character_struct_size = 16

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
local character_reward_bool = false

local character_unlock_hooks = {}

character_unlock_hooks.character_data = {}

function character_unlock_hooks.init()
    -- TODO: initialize character data by reading a specific byte and checking for a specific value
    --       we need a value that signifies that the story has unlocked this character, since we overwrite the values with 00 when unlocked

    for i = 1, max_character_id do
        print("Initializing character data for char " .. tostring(i))
        character_unlock_hooks.character_data[i] = character_unlock_hooks.read_character_data(i)
    end

end


-- Indexed from 1 ... max_character_id
function character_unlock_hooks.read_character_data(char_index)
    local character_data = {}
    
    character_data.unlocked = memory.readbyte(character_start_address + (char_index - 1) * character_struct_size, "WRAM")
    
    return character_data
end

function character_unlock_hooks.write_to_wram(char_index)

    -- TODO: other structs maybe
    
    --print("DEBUG: char start write: " .. tostring(character_start_address))
    --print("DEBUG: char index write: " .. tostring(char_index))
    --print("DEBUG: char struct size write: " .. tostring(character_struct_size))
    --print("DEBUG: char struct array len write: " .. tostring(#character_unlock_hooks.character_data))    
    
    memory.writebyte(character_start_address + (char_index - 1) * character_struct_size, character_unlock_hooks.character_data[char_index].unlocked, "WRAM")

end

function character_unlock_hooks.check_character_unlock(new_character_data, character_index)
  if new_character_data.unlocked ~= character_unlock_hooks.character_data[character_index].unlocked then
    -- Something has changed. might just be the "usable"/"unusable" state. 
    if bit.band(new_character_data.unlocked, game_unlock_changed_bit) ~= 0 and bit.band(character_unlock_hooks.character_data[character_index].unlocked, game_unlocked_bit) == 0 then
      -- now something has changed, but we now know for certain that a character has been unlocked (bit 0x01 is set) and has not been unlocked before (game_unlocked_bit not set)
      return true
    end         
  end
end

function character_unlock_hooks.check_form_unlock(new_character_data, character_index)
  if new_character_data.unlocked ~= character_unlock_hooks.character_data[character_index].unlocked then
    -- Something has changed. might just be the "usable"/"unusable" state. 
    if bit.band(new_character_data.unlocked, form_changed_bits) ~= 0 and bit.band(character_unlock_hooks.character_data[character_index].unlocked, game_unlocked_bit) == 0 then
      -- now something has changed, but we now know for certain that a character has been unlocked (bit 0x01 is set) and has not been unlocked before (game_unlocked_bit not set)
      return true
    end         
  end
end

function character_unlock_hooks.on_character_unlock()

    -- TODO: check every unlock flag, see if anything was changed compared to memory 
    --       for each character that changes, we need to generate a new random one and store the correct stuff inside WRAM
    local new_chars = 0
    local new_forms = 0
    
    --print("ASDF")
    
    for i = 1, max_character_id do
    
        --print("Character " .. tostring(i) .. " TESTTTTTTTT")
    
        local new_character_data =  character_unlock_hooks.read_character_data(i)
                
        if character_unlock_hooks.check_character_unlock(new_character_data, i) == true then
            print("Character " .. tostring(character_index) .. " was unlocked by game, patching to lock again!")
            -- Write game_unlocked_bit into character data
            character_unlock_hooks.character_data[character_index].unlocked = bit.bor(character_unlock_hooks.character_data[character_index].unlocked, game_unlocked_bit)
                
            -- Write game_unlocked_bit into WRAM (if this hasn't been randomizer-unlocked, this is still only 0x80, *nothing else*. With the randomizer, the only legit values after patching can be
            -- 0x00 (init/nothing), 0x10 (game unlocked, not randomizer unlocked), 0x05 (randomizer unlocked, not game unlocked), 0x15 (game unlocked and randomizer unlocked)
            -- The WRAM writing also helps us since we then don't run into this again
            character_unlock_hooks.write_to_wram(character_index)
            
            new_chars = new_chars + 1
        end
                
    end
    
    -- TODO: patch all data, it could be that the game removed chars due to story, we want to make sure the data is consistent
    -- TODO: change this to be event-based, since we can detect stuff with byte 15/16 now
    for i = 1, max_character_id do
        character_unlock_hooks.write_to_wram(i)
    end
    
    if new_chars == 0 then
        return
    end
    
    while new_chars > 0 do
        -- Randomly get an index, check if we already unlocked it, otherwise unlock and write unlock info into WRAM
        
        local random_char_id = math.random(max_character_id - 1) + 1
        
        if bit.band(character_unlock_hooks.character_data[random_char_id].unlocked, randomizer_unlocked_bit) == 0 then
            new_chars = new_chars - 1
            
            character_unlock_hooks.character_data[random_char_id].unlocked = bit.bor(character_unlock_hooks.character_data[random_char_id].unlocked, randomizer_unlocked_bit)
            
            character_unlock_hooks.write_to_wram(random_char_id)
            
            print("Randomly unlocked character " .. random_char_id)
        end

    end
    
    
    
    
    
    print("Patched character unlocks!")
end

return character_unlock_hooks
