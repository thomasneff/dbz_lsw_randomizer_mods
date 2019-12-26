-- 0x0DDF: card 1 in deck, up until 0x0DF0
-- 0x0DF3: first card in packs (3 phase attack) (number total)
-- 0x0E6F: last card in packs (avoiding)
-- max card id: 125
-- 0x0041: number of cards in deck
-- 0x0EA7 - 0x0EA9: dropped cards after battle, can probably intercept writes to this address to automatically patch randomized loot.


-- Idea: start battle mode with fixed save state (basic deck of some sort, characters have no assigned exp/levels but maxed XP)
--       roll N random chars and try to get as far as possible 

local max_card_id = 125
local card_start_addr = 0x0DDF
local num_cards_addr = 0x0041
local num_cards_in_deck = 20



for i = 0, num_cards_in_deck do
    memory.writebyte(card_start_addr + i, math.random(max_card_id - 1) + 1, "WRAM")
end
