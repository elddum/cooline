local cooline = CreateFrame('Button', nil, UIParent)
cooline:SetScript('OnEvent', function()
	this[event]()
end)
cooline:RegisterEvent('VARIABLES_LOADED')

cooline_settings = { 
	x = 180, 
	y = 0, 
	lock = false	
}

cooline_ignore = {
	[1] = "hearthstone",
}

local frame_pool = {}
local cooldowns = {}

function cooline.hyperlink_name(hyperlink)
    local _, _, name = strfind(hyperlink, '|Hitem:%d+:%d+:%d+:%d+|h[[]([^]]+)[]]|h')
    return name
end

function cooline.detect_cooldowns()
	
	local function start_cooldown(name, texture, start_time, duration, is_spell)				
				for _,ignored_name in pairs(cooline_ignore) do
					if strupper(name) == strupper(ignored_name) then
						return
					end
				end		

				local end_time = start_time + duration
			
				for _, cooldown in pairs(cooldowns) do
					if cooldown.end_time == end_time then
						return
					end
				end

				cooldowns[name] = cooldowns[name] or tremove(frame_pool) or cooline.cooldown_frame()
				local frame = cooldowns[name]
				frame:SetWidth(cooline.icon_size)
				frame:SetHeight(cooline.icon_size)
				frame.icon:SetTexture(texture)
				if is_spell then
					frame:SetBackdropColor(unpack(cooline_theme.spellcolor))
				else
					frame:SetBackdropColor(unpack(cooline_theme.nospellcolor))
				end
				frame:SetAlpha((end_time - GetTime() > 360) and 0.6 or 1)
				frame.end_time = end_time												
				frame:Show()
	end
	
    for bag = 0,4 do
        if GetBagName(bag) then
            for slot = 1, GetContainerNumSlots(bag) do
				local start_time, duration, enabled = GetContainerItemCooldown(bag, slot)
				if enabled == 1 then
					local name = cooline.hyperlink_name(GetContainerItemLink(bag, slot))
					if duration > 3 and duration < 3601 then
						start_cooldown(
							name,
							GetContainerItemInfo(bag, slot),
							start_time,
							duration,
							false
						)
					elseif duration == 0 then
						cooline.clear_cooldown(name)
					end
				end
            end
        end
    end
	
	for slot=0,19 do
		local start_time, duration, enabled = GetInventoryItemCooldown('player', slot)
		if enabled == 1 then
			local name = cooline.hyperlink_name(GetInventoryItemLink('player', slot))
			if duration > 3 and duration < 3601 then
				start_cooldown(
					name,
					GetInventoryItemTexture('player', slot),
					start_time,
					duration,
					false
				)
			elseif duration == 0 then
				cooline.clear_cooldown(name)
			end
		end
	end
	
	local _, _, offset, spell_count = GetSpellTabInfo(GetNumSpellTabs())
	local total_spells = offset + spell_count
	for id=1,total_spells do
		local start_time, duration, enabled = GetSpellCooldown(id, BOOKTYPE_SPELL)
		local name = GetSpellName(id, BOOKTYPE_SPELL)
		if enabled == 1 and duration > 2.5 then
			start_cooldown(
				name,
				GetSpellTexture(id, BOOKTYPE_SPELL),
				start_time,
				duration,
				true
			)
		elseif duration == 0 then
			cooline.clear_cooldown(name)
		end
	end
	
	cooline.on_update(true)
end

function cooline.cooldown_frame()
	local frame = CreateFrame('Frame', nil, UIParent)	
	frame.icon = frame:CreateTexture(nil, 'ARTWORK')
	frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	frame.icon:SetPoint('TOPLEFT', 1, -1)
	frame.icon:SetPoint('BOTTOMRIGHT', -1, 1)
	frame.text = frame:CreateFontString(nil,'ARTWORK') 
	frame.text:SetPoint('CENTER',0,0)
	frame.text:SetFont(cooline_theme.font,cooline_theme.fontsize)	
	return frame
end

function cooline.clear_cooldown(name)
	if cooldowns[name] then
		cooldowns[name]:Hide()
		tinsert(frame_pool, cooldowns[name])
		cooldowns[name] = nil
	end
end

local relevel, throt = false, 0

function getKeysSortedByValue(tbl, sortFunction)
	local keys = {}
	for key in pairs(tbl) do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		return sortFunction(tbl[a], tbl[b])
	end)

	return keys
end

function cooline.update_cooldown(name, frame, position, tthrot, relevel)
	throt = min(throt, tthrot)
	
	if frame.end_time - GetTime() < cooline_theme.threshold then
		local sorted = getKeysSortedByValue(cooldowns, function(a, b) return a.end_time > b.end_time end)
		for i, k in ipairs(sorted) do
			if name == k then				
				frame:SetFrameLevel(i+2)					
			end
		end
	else
		if relevel then
			frame:SetFrameLevel(random(1,5) + 2)						
		end
	end	
	
	local remaining = frame.end_time - GetTime()
	frame.text:SetText('')
	if remaining >= 1 then
		local txt = (remaining < 60 and math.floor(remaining)) or (remaining < 3600 and math.ceil(remaining / 60) .. "m") or math.ceil(remaining / 3600) .. "h"
		frame.text:SetText(txt)   		
	else 
		local txt = string.format("%.1f", round(remaining,1))
		if remaining > 0 then
			frame.text:SetText(txt)   					
		end 
	end
	
	frame:SetPoint('CENTER', cooline, 'LEFT', position + 2, 0)
	
end

do
	local last_update, last_relevel = GetTime(), GetTime()
	
	function cooline.on_update(force)
		if GetTime() - last_update < throt and not force then return end
		last_update = GetTime()
		
		relevel = false
		if GetTime() - last_relevel > 0.4 then
			relevel, last_relevel = true, GetTime()
		end
		
		isactive, throt = false, 1.5
		for name, frame in pairs(cooldowns) do
			local time_left = frame.end_time - GetTime()
			isactive = isactive or time_left < 360
							
			if time_left < -1 then
				throt = min(throt, 0.2)
				isactive = true
				cooline.clear_cooldown(name)
			elseif time_left < 0 then
				cooline.update_cooldown(name, frame, 0, 0, relevel)
				frame:SetAlpha(1 + time_left)  -- fades
			elseif time_left < 0.3 then
				local size = cooline.icon_size * (0.5 - time_left) * 5  -- icon_size + icon_size * (0.3 - time_left) / 0.2
				frame:SetWidth(size)
				frame:SetHeight(size)
				cooline.update_cooldown(name, frame, cooline.section * time_left, 0, relevel)
			elseif time_left < 1 then
				cooline.update_cooldown(name, frame, cooline.section * time_left, 0, relevel)
			elseif time_left < 3 then
				cooline.update_cooldown(name, frame, cooline.section * (time_left + 1) * 0.5, 0.02, relevel)  -- 1 + (time_left - 1) / 2
			elseif time_left < 10 then
				cooline.update_cooldown(name, frame, cooline.section * (time_left + 11) * 0.14286, time_left > 4 and 0.05 or 0.02, relevel)  -- 2 + (time_left - 3) / 7
			elseif time_left < 30 then
				cooline.update_cooldown(name, frame, cooline.section * (time_left + 50) * 0.05, 0.06, relevel)  -- 3 + (time_left - 10) / 20
			elseif time_left < 120 then
			 	cooline.update_cooldown(name, frame, cooline.section * (time_left + 330) * 0.011111, 0.18, relevel)  -- 4 + (time_left - 30) / 90
			elseif time_left < 360 then
			 	cooline.update_cooldown(name, frame, cooline.section * (time_left + 1080) * 0.0041667, 1.2, relevel)  -- 5 + (time_left - 120) / 240
				frame:SetAlpha(cooline_theme.activealpha)
			else
				cooline.update_cooldown(name, frame, 6 * cooline.section, 2, relevel)
			end
		end
		cooline:SetAlpha(isactive and cooline_theme.activealpha or cooline_theme.inactivealpha)
	end
end

function cooline.VARIABLES_LOADED()

	cooline:SetClampedToScreen(true)
	cooline:SetMovable(true)
	cooline:RegisterForDrag('LeftButton')
	
	function cooline:on_drag_stop()
		this:StopMovingOrSizing()
		local x, y = this:GetCenter()
		local ux, uy = UIParent:GetCenter()
		cooline_settings.x, cooline_settings.y = floor(x - ux + 0.5), floor(y - uy + 0.5)
		this.dragging = false
	end
	
	cooline:SetScript('OnDragStart', function()
		if cooline_settings.lock ~= true then
			this.dragging = true
			this:StartMoving()
		end
	end)

	cooline:SetScript('OnDragStop', function()		
		this:on_drag_stop()
	end)

	cooline:SetScript('OnUpdate', function()		
		cooline.on_update()
	end)

	cooline:SetWidth(cooline_theme.width)
	cooline:SetHeight(cooline_theme.height)
	cooline:SetPoint('CENTER', cooline_settings.x, cooline_settings.y)		

	cooline.bg = cooline:CreateTexture(nil, 'ARTWORK')
	cooline.bg:SetTexture(cooline_theme.statusbar)
	cooline.bg:SetVertexColor(unpack(cooline_theme.bgcolor))
	cooline.bg:SetAllPoints(cooline)
	cooline.bg:SetTexCoord(0, 1, 0, 1)

	if cooline_settings.lock == true then
		cooline:EnableMouse(false)	
		cooline.bg:Hide();
	end

	cooline.section = cooline_theme.width / 6
	cooline.icon_size = cooline_theme.height + cooline_theme.iconoutset * 2

	-- added ignore list
	if type(cooline_ignore) ~= 'table' then 
		cooline_ignore = {}
	end
	
	cooline:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	cooline:RegisterEvent('BAG_UPDATE_COOLDOWN')
	
	cooline.detect_cooldowns()

	DEFAULT_CHAT_FRAME:AddMessage(COOLINE_LOADED_MESSAGE);
end

function cooline.BAG_UPDATE_COOLDOWN()
	cooline.detect_cooldowns()
end

function cooline.SPELL_UPDATE_COOLDOWN()
	cooline.detect_cooldowns()
end

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function slash(msg, editbox)
	-- pattern matching for cmd and args
	-- whitespace at end of args is retained
	local _, _, cmd, args = string.find(msg, "%s?(%w+)%s?(.*)")
	 
	if cmd == "lock" then	  
	  if cooline_settings.lock == true then		
		cooline_settings.lock = false		
		cooline:EnableMouse(true)
		cooline.bg:Show()		
	  else		
		cooline_settings.lock = true
		cooline:EnableMouse(false)
		cooline.bg:Hide()		
	  end 	  	
	  DEFAULT_CHAT_FRAME:AddMessage(COOLINE_TITLE .. " setting lock to " .. tostring(cooline_settings.lock))	  
	elseif cmd == "ignore" and args ~= "" then				
		for k,v in pairs(cooline_ignore) do
			if strupper(v) == strupper(args) then
				table.remove(cooline_ignore, k)
				DEFAULT_CHAT_FRAME:AddMessage(COOLINE_TITLE .. " removing " .. args .. " from the ignore list")
				return
			end
		end
		table.insert(cooline_ignore, args)
		DEFAULT_CHAT_FRAME:AddMessage(COOLINE_TITLE .. " added  " .. args .. " to the ignore list")		
	elseif cmd == "ignore" and args == "" then				
		DEFAULT_CHAT_FRAME:AddMessage(COOLINE_TITLE .. " current ignore list:")
		for k,v in pairs(cooline_ignore) do							
			DEFAULT_CHAT_FRAME:AddMessage(v)			
		end				
	else	  
	  DEFAULT_CHAT_FRAME:AddMessage(COOLINE_TITLE .. " usage:")	  
	  DEFAULT_CHAT_FRAME:AddMessage("/cooline lock - lock or unlock frame");
	  DEFAULT_CHAT_FRAME:AddMessage("/cooline ignore - show current spell ignore list");	  
	  DEFAULT_CHAT_FRAME:AddMessage("/cooline ignore spell - add or remove spell to ignore");	  
	end
end

SLASH_COOLINE1 = "/cooline"

SlashCmdList["COOLINE"] = slash
