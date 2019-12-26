-- 0x0EA7 - 0x0EA9: dropped cards after battle, can probably intercept writes to this address to automatically patch randomized loot.
local max_card_id = 125
local num_card_rewards = 3
local card_reward_addr = 0x0EA7
local card_reward_bool = false

local card_reward_hooks = {}

function card_reward_hooks.on_card_reward()
    
    local card_reward_first = memory.readbyte(card_reward_addr, "WRAM")
    
    if card_reward_first == 0 then
        card_reward_bool = false
        return
    end
    
    -- Only do this once per card reward
    if card_reward_bool == true then
        return
    end
    
    card_reward_bool = true
    
    -- Write random cards 
    for i = 0, num_card_rewards do
        memory.writebyte(card_reward_addr + i, math.random(max_card_id - 1) + 1, "WRAM")
    end

    print("Patched card reward!")
end


return card_reward_hooks
