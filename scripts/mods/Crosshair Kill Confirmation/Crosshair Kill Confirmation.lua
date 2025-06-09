local mod = get_mod("Crosshair Kill Confirmation")

local crit = false

mod:hook_safe(DamageUtils, "buff_on_attack", function(unit, hit_unit, attack_type, is_critical) -- Check if the attack is a critical hit
    local player = Managers.player:owner(unit)
    if not player or player ~= Managers.player:local_player() then
        return
    end
    if is_critical then
        
        crit = true
    else
        crit = false -- prevents false positives to reoccur after first positive
    end

    return true
end)

mod.get_color_from_settings = function(self, type)
    local red = mod:get("red" .. type)
    local green = mod:get("green" .. type)
    local blue = mod:get("blue" .. type)

    return { red or 255, green or 255, blue or 255 }
end

local unit_types = {
    "normal",
    "special",
    "elite",
    "boss"
}
local opacities = {}
local sizes = {}
local crosshairs = {}
local colors = {}
for i=1, #unit_types, 1 do
    unit_type = unit_types[i]
    opacities[unit_type] = 0
    sizes[unit_type] = 0
    crosshairs[unit_type] = "dot"
    colors[unit_type] = {255, 7, 7}
end

local duration = 0
local min_s = 0
local max_s = 0
local assists = {}
mod.gui = nil


--[[
    Functions
--]]

mod.change_setting = function(self)
    mod:destroy_gui()
end

mod.create_gui = function(self)
    if Managers.world:world("top_ingame_view") then
        local top_world = Managers.world:world("top_ingame_view")

        -- Create a screen overlay with specific materials we want to render
        mod.gui = World.create_screen_gui(top_world, "immediate",
            "material", "materials/Crosshair Kill Confirmation/icons"
        )

        -- Fetch mod settings
        for i=1, #unit_types, 1 do
            unit_type = unit_types[i]
            crosshairs[unit_type] = mod:get("crosshair_"..unit_type)
        end
        duration = mod:get("duration")
        min_s = mod:get("size")
        max_s = min_s * mod:get("pop")
    end
end

mod.destroy_gui = function(self)
    if Managers.world:world("top_ingame_view") then
        local top_world = Managers.world:world("top_ingame_view")
        if mod.gui then
            World.destroy_gui(top_world, mod.gui)
        end
        mod.gui = nil
    end
end

mod.unit_category = function(unit)
    local breed_categories = {}

    breed_categories["skaven_clan_rat"] = "normal"
    breed_categories["skaven_clan_rat_with_shield"] = "normal"
    breed_categories["skaven_dummy_clan_rat"] = "normal"
    breed_categories["skaven_slave"] = "normal"
    breed_categories["skaven_dummy_slave"] = "normal"
    breed_categories["chaos_marauder"] = "normal"
    breed_categories["chaos_marauder_with_shield"] = "normal"
    breed_categories["chaos_fanatic"] = "normal"
    breed_categories["beastmen_gor"] = "normal"
    breed_categories["beastmen_ungor"] = "normal"
    breed_categories["beastmen_ungor_archer"] = "normal"
    breed_categories["critter_rat"] = "normal"
    breed_categories["critter_pig"] = "normal"

for breed_name, breed in pairs(Breeds) do
    if breed.boss then
        breed_categories[breed_name] = "boss"
    elseif breed.elite then
        breed_categories[breed_name] = "elite"
    elseif breed.special then
        breed_categories[breed_name] = "special"
    end
end
    local breed_data = Unit.get_data(unit, "breed")
    breed_name = breed_data.name
    if breed_categories[breed_name] then
        return breed_categories[breed_name]
    else
            return "normal"
    end
end

mod.interp_opacity = function(opacity)
    -- Modify opacity to have exponetial falloff
    return math.floor(math.pow(opacity/255,2)*255)
end

mod.interp_size = function(size)
    -- Modify size to have exponetial falloff
    return (math.pow(size, 0.6)*(max_s-min_s))+min_s
end


--[[
    Hooks
--]]
mod:hook(GenericHitReactionExtension, "_execute_effect", function(func, self, unit, effect_template, biggest_hit, parameters, ...)
    local death_ext = self.death_extension
    local death_has_started = death_ext and death_ext.death_has_started
    local killing_blow = parameters.death and death_ext and not death_has_started

    local attacker_unit = biggest_hit[DamageDataIndex.ATTACKER]
    local damage_amount = biggest_hit[DamageDataIndex.DAMAGE_AMOUNT]
    local damage_type = biggest_hit[DamageDataIndex.DAMAGE_TYPE]
    local hit_zone = biggest_hit[DamageDataIndex.HIT_ZONE]

    mod:pcall(function()
        local local_player = Managers.player:local_player()
        local player_unit = local_player.player_unit
        local network_manager = Managers.state.network
        local unit_id, is_level_unit = network_manager:game_object_or_level_id(unit)

        if DamageUtils.is_player_unit(attacker_unit) and damage_amount > 0 then
            if (not killing_blow) and attacker_unit == player_unit then
                assists[unit_id] = os.time()
            elseif killing_blow and (attacker_unit == player_unit or assists[unit_id]) then
                local unit_type = mod.unit_category(unit)

                if attacker_unit == player_unit then
                    sizes[unit_type] = 0
 
                   if (hit_zone == "head" or hit_zone == "weakspot") and crit then
                        color = mod:get_color_from_settings("crithead") -- colour for headcrit kill
                   elseif damage_type == "arrow_poison_dot" or damage_type == "bleed" or damage_type == "burninating" then
                        color = mod:get_color_from_settings("dot") -- colour for DoT kill
                   elseif crit then
                        color = mod:get_color_from_settings("crit") -- colour for crit kill
                   elseif hit_zone == "head" or hit_zone == "weakspot" then
                        color = mod:get_color_from_settings("head") -- colour for headshot kill
                   elseif opacities[unit_type] and opacities[unit_type] < 200 then
                        color = mod:get_color_from_settings("regular") -- colour for regular kill
                   end

                   if color then
                    colors[unit_type] = color
                   end              

                    opacities[unit_type] = 255
                elseif assists[unit_id] ~= nil then
                    if (os.time() - assists[unit_id]) <= 30 then -- Ignore assists older than 30 seconds
                        sizes[unit_type] = 0
                        if opacities[unit_type] < 200 then -- Low priority color
                            colors[unit_type] = mod:get_color_from_settings("assist") -- Blue for assist kills
                        end
                        opacities[unit_type] = 255
                    end
                    -- TODO show assists from non-player causes (e.g. gunner fire, barrel explosions...)
                end
                assists[unit_id] = nil  -- Remove assist from table
            end
        end
    end)

    func(self, unit, effect_template, biggest_hit, parameters, ...)
end)

mod:hook_safe(StateInGameRunning, "on_exit", function(...)
    -- Flush table for new mission
    assists = {}
end)

mod:hook_safe(CrosshairUI, "update_hit_markers", function(self, dt)
    if not mod.gui and Managers.world:world("top_ingame_view") then
        mod:create_gui()
    end
    for i=1, #unit_types, 1 do
        unit_type = unit_types[i]
        if crosshairs[unit_type] ~= "none" then
            opacities[unit_type] = math.max(0, opacities[unit_type] - (dt/duration)*255)
            interp_opacity = mod.interp_opacity(opacities[unit_type])
            if unit_type == "normal" then
                interp_size = min_s*0.8  -- no animation for normal enemies
            else
                sizes[unit_type] = sizes[unit_type] + (dt/duration)
                interp_size = mod.interp_size(sizes[unit_type])
            end
            local icon_size = math.floor(interp_size * RESOLUTION_LOOKUP.scale)
            local icon_x = math.floor(RESOLUTION_LOOKUP.res_w/2 - icon_size/2)  -- Center icon
            local icon_y = math.floor(RESOLUTION_LOOKUP.res_h/2 - icon_size/2)  -- Center icon
            Gui.bitmap(mod.gui, crosshairs[unit_type], Vector2(icon_x, icon_y), Vector2(icon_size, icon_size), Color(interp_opacity,colors[unit_type][1],colors[unit_type][2],colors[unit_type][3]))
        end
    end
end)


--[[
    Callback
--]]

mod.on_unload = function(exit_game)
    if mod.gui and Managers.world:world("top_ingame_view") then
        mod:destroy_gui()
    end
    return
end

mod.on_setting_changed = function(is_first_call)
    mod.change_setting()
end
