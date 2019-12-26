local card_reward_hooks = require "hook_card_rewards"
local character_unlock_hooks = require "hook_character_unlock"

character_unlock_hooks.init()

function update()
    -- TODO: can pass args to specify the range / valid rewards
    card_reward_hooks.on_card_reward()
    character_unlock_hooks.on_character_unlock()
    
end

event.onframestart(update, "UPDATE")