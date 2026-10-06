local CheckIntervalSeconds <const> = 5.0
local GraceSeconds <const> = 30.0
local MinTownsLeft <const> = 2

-- A town is deleted when its WHOLE name is one of these words (any case, spaces around the name are ignored).
-- A name that only contains the word, like "Destroy City" or "Port Destroy", does not count.
local Keywords : {string} = { "destroy", "l\195\182schen", "loeschen" }

local normalize = function(name : string) : string
	local text = name or ""
	-- the upper case umlaut O (two bytes) becomes the lower case one, string.lower does not handle it
	text = string.gsub(text, "\195\150", "\195\182")
	text = string.lower(text)
	text = string.match(text, "^%s*(.-)%s*$") or text
	return text
end

local isMarked = function(name : string) : boolean
	local text = normalize(name)
	for _, keyword in ipairs(Keywords) do
		if text == keyword then
			return true
		end
	end
	return false
end

local countTowns = function() : integer
	local count = 0
	api.engine.forEachEntityWithComponent(function(_entity : Engine.Entity)
		count = count + 1
	end, api.type.ComponentType.TOWN)
	return count
end

-- state keys per town entity e:  "d"..e = clock when the name was first seen as a keyword (0 = not marked)
--                                "r"..e = 1 when the deletion was refused (too few towns), logged once
-- The clock runs in real seconds: dt is game time, so it is divided by the speed of the game.
local ret : GameScript<{string : number}> = {
	update = function(_userParams : table, state : GameScriptState<{string : number}>, dt : number) : any
		if dt == 0.0 then
			return
		end

		local gameSpeed : Engine.Component.GameSpeed = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED)
		local speed = gameSpeed and gameSpeed.speedup or 1
		if speed < 1 then
			speed = 1
		end
		local realDt = dt / speed

		local state2 = state:get() or { elapsed = 0.0, clock = 0.0 }
		state2.clock = (state2.clock or 0.0) + realDt
		state2.elapsed = (state2.elapsed or 0.0) + realDt
		if state2.elapsed < CheckIntervalSeconds then
			state:set(state2)
			return
		end
		state2.elapsed = 0.0

		local toDelete : {Engine.Entity} = {}
		api.engine.forEachEntityWithComponent(function(entity : Engine.Entity)
			local e = tostring(entity)
			local name = api.engine.util.getEntityName(entity)
			local firstSeen = state2["d" .. e] or 0.0

			if isMarked(name) then
				if firstSeen <= 0.0 then
					state2["d" .. e] = state2.clock
					log.message("TownDestroyer: town " .. e .. " '" .. tostring(name) .. "' is marked, it is deleted in " .. tostring(GraceSeconds) .. " seconds unless it is renamed")
				elseif state2.clock - firstSeen >= GraceSeconds then
					toDelete[#toDelete + 1] = entity
				end
			elseif firstSeen > 0.0 then
				state2["d" .. e] = 0.0
				state2["r" .. e] = 0.0
				log.message("TownDestroyer: town " .. e .. " was renamed to '" .. tostring(name) .. "', deletion cancelled")
			end
		end, api.type.ComponentType.TOWN)

		for _, entity in ipairs(toDelete) do
			local e = tostring(entity)
			local total = countTowns()
			if total <= MinTownsLeft then
				if (state2["r" .. e] or 0.0) == 0.0 then
					state2["r" .. e] = 1.0
					log.message("TownDestroyer: town " .. e .. " is not deleted, only " .. tostring(total) .. " towns exist and at least " .. tostring(MinTownsLeft) .. " must stay")
				end
			else
				log.message("TownDestroyer: deleting town " .. e .. " '" .. tostring(api.engine.util.getEntityName(entity)) .. "', towns before=" .. tostring(total))
				api.cmd.sendCommand(api.cmd.makeTownDestroyCmd(entity))
				state2["d" .. e] = 0.0
			end
		end

		state:set(state2)
	end,
}

return ret
