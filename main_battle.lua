local card_reward_hooks = require "hook_card_rewards"
local character_unlock_hooks = require "hook_character_unlock"

-- TODO: clear deck, clear card pack/stash
-- TODO: clear chars
-- TODO: randomize pack of N cards
-- TODO: randomly unlock N chars with their full forms, 3 limit, 200 (?) exp
local max_card_id = 125
local deck_card_start_addr = 0x0DDF
local num_cards_addr = 0x0041
local num_cards_in_deck = 20
local pack_card_start_addr = 0x0DF3
local NUM_RANDOM_CARDS = 50
local NUM_RANDOM_CHARS = 5

-- Clear deck
for i = 0, num_cards_in_deck do
    memory.writebyte(deck_card_start_addr + i, 0x00, "WRAM")
end

-- Clear pack
for i = 1, max_card_id do
    memory.writebyte(pack_card_start_addr + (i - 1), 0x00, "WRAM")
end

-- Randomize N cards
for i = 0, NUM_RANDOM_CARDS do
    local rand_card_offset = math.random(max_card_id) - 1 -- value between 0 and (max_card_id - 1)

    local previous_num = memory.readbyte(pack_card_start_addr + rand_card_offset, "WRAM")
    memory.writebyte(pack_card_start_addr + rand_card_offset, previous_num + 1, "WRAM")
end

-- Unlock N random chars
character_unlock_hooks.clear_chars()
character_unlock_hooks.unlock_random_chars(NUM_RANDOM_CHARS)


function update()
    card_reward_hooks.on_card_reward()
end

event.onframestart(update, "UPDATE")