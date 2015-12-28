local me, ns = ...
ns.Configure()
local addon=addon --#addon
local _G=_G
-- Courtesy of Motig
-- Concept and interface reused with permission
-- Mission building rewritten from scratch
--local GMC_G = {}
local factory=addon:GetFactory()
--GMC_G.frame = CreateFrame('FRAME')
local aMissions={}
local chardb
local db
local GMF=GarrisonMissionFrame
local GMCUsedFollowers={}
local wipe=wipe
local pairs=pairs
local tinsert=tinsert
local tremove=tremove
local dbg
local tItems ={
	--[[
	{t = 'Enable/Disable money rewards.', i = 'Interface\\Icons\\inv_misc_coin_01', key = 'gold'},
	{t = 'Enable/Disable resource awards. (Resources/Seals)', i= 'Interface\\Icons\\inv_garrison_resource', key = 'resources'},
	{t = 'Enable/Disable oil awards.', i= 'Interface\\Icons\\garrison_oil', key = 'oil'},
	{t = 'Enable/Disable rush scroll.', i= 'Interface\\ICONS\\INV_Scroll_12', key = 'rush'},
	{t = 'Enable/Disable Follower XP Bonus rewards.', i = 'Interface\\Icons\\XPBonus_Icon', key = 'xp'},
	{t = 'Enable/Disable Follower equip upgrade.', i = 'Interface\\ICONS\\Garrison_ArmorUpgrade', key = 'followerUpgrade'},
	{t = 'Enable/Disable item tokens.', i = "Interface\\ICONS\\INV_Bracer_Cloth_Reputation_C_01", key = 'itemLevel'},
	{t = 'Enable/Disable apexis.', i = "Interface\\Icons\\inv_apexis_draenor", key = 'apexis'},
	{t = 'Enable/Disable generc rewards.', i = "Interface\\ICONS\\INV_Box_02", key = 'other'},
	{t = 'Enable/Disable Seal of Tempered Fate.', i = "Interface\\Icons\\ability_animusorbs", key = 'seal'},
	{t = 'Enable/Disable Primal Spirit.', i = "Interface\\Icons\\6BF_Explosive_shard", key = 'primalspirit'},
	--]]
	}
for _,data in ipairs(addon:GetRewardClasses()) do
	tItems[data.key]=data
end
local classlist={} ---#table local reference to settings.rewardList
local class2order={} ---#table maps a classname to its priority
local settings
local module=addon:NewSubClass("MissionControl") --#module
function module:GMCBusy(followerID)
	return GMCUsedFollowers[followerID]
end
addon.GMCBusy=module.GMCBusy
---
-- Builds a mission list based on user preferences
-- @param #module self self
-- @param #table workList table to be filled with mission list
function module:GMCCreateMissionList(workList)
	--First get rid of unwanted rewards and missions that are too long
	local settings=self.privatedb.profile.missionControl
	local ar=settings.allowedRewards
	wipe(workList)
	for _,missionID in self:GetMissionIterator() do
		local discarded=false
		local class=self:GetMissionData(missionID,"class")
		repeat
			--@debug@
			print("|cffff0000",'Examining',missionID,self:GetMissionData(missionID,"name"),class,"|r")
			--@end-debug@
			local durationSeconds=self:GetMissionData(missionID,'durationSeconds')
			if (durationSeconds > settings.maxDuration * 3600 or durationSeconds <  settings.minDuration * 3600) then
				--@debug@
				print("  ",missionID,"discarded due to duration",durationSeconds /3600)
				--@end-debug@
				break
			end -- Mission too long, out of here
			if self:GetMissionData(missionID,'isRare') and addon:GetBoolean('GCSKIPRARE') then
				--@debug@
				print("  ",missionID,"discarded due to rarity")
				--@end-debug@
				break
			end
			if (not ar[class]) then
				--@debug@
				print("  ",missionID,"discarded due to class == ", class)
				--@end-debug@
				discarded=true
				break
			end
			if class=="itemLevel" then
				if self:GetMissionData(missionID,'itemLevel') < settings.minLevel then
					--@debug@
					print("  ",missionID,"discarded due to ilevel == ", self:GetMissionData(missionID,'itemLevel'))
					--@end-debug@
					discarded=true
					break
				end
			elseif class=="followerUpgrade" then
				if self:GetMissionData(missionID,'followerUpgrade') < settings.minUpgrade and
					self:GetMissionData(missionID,'followerUpgrade') > 600 then
					--@debug@
					print("  ",missionID,"discarded due to followerUpgrade == ", self:GetMissionData(missionID,'followerUpgrade'))
					--@end-debug@
					discarded=true
					break
				end
			end
			if (not discarded) then
				tinsert(workList,missionID)
			end
		until true
	end
	local parties=self:GetParty()
	local function msort(i1,i2)
		local c1=addon:GetMissionData(i1,'class','other')
		local c2=addon:GetMissionData(i2,'class','other')
		if (c1==c2) then
			return addon:GetMissionData(i1,c1,0) > addon:GetMissionData(i2,c2,0)
		else
			return (class2order[c1] or i1)<(class2order[c2] or i2)
		end
	end
	table.sort(workList,msort)
	--@debug@
	for i=1,#workList do
		local id=workList[i]
		print(self:GetMissionData(id,'name'),self:GetMissionData(id,'class'),self:GetMissionData(id,self:GetMissionData(id,'class')))
	end
	--@end-debug@
end
---
-- This routine can be called both as coroutin and as a standard one
-- In standard version, delay between group building and submitting is done via a self schedule
-- @param #module self
-- @param #number missionID Optional, to run a single mission
-- @param #boolean start Optional, tells that follower already are on mission and that we need just to start it
function module:GMCRunMission(missionID,start)
	--@debug@
	print("Asked to start mission",missionID)
	--@end-debug@
	local GMC=GMF.MissionControlTab
	if (start) then
		G.StartMission(missionID)
		PlaySound("UI_Garrison_CommandTable_MissionStart")
		addon:RefreshFollowerStatus()
		return
	end
	for i=1,#GMC.list.Parties do
		local party=GMC.list.Parties[i]
		--@debug@
		print("Checking",party.missionID)
		--@end-debug@
		if (missionID and party.missionID==missionID or not missionID) then
			GMC.list.widget:RemoveChild(party.missionID)
			GMC.list.widget:DoLayout()
			if (party.full and not blacklist[party.missionID]) then
				for j=1,#party.members do
					G.AddFollowerToMission(party.missionID, party.members[j])
				end
				if (not missionID) then
					coroutine.yield(true)
					G.StartMission(party.missionID)
					PlaySound("UI_Garrison_CommandTable_MissionStart")
					coroutine.yield(true)
				else
					self:ScheduleTimer("GMCRunMission",0.25,party.missionID,true)
					return
				end
			else
				if not missionID then coroutine.yield(true) end
			end
		end
		addon:RefreshFollowerStatus()
	end
end
do
	local function leftclick(this)
		print("leftclick")
		local missionID=this.frame.info.missionID
		if (blacklist[missionID]) then return end
		module:GMCRunMission(missionID)
		GMF.MissionControlTab.list.widget:RemoveChild(missionID)
	end
	local function rightclick(this)
		print("rightclick")
		local missionID=this.frame.info.missionID
		blacklist[missionID]=not blacklist[missionID]
		module:Refresh()
	end
	local timeElapsed=0
	local currentMission=0
	local x=0
	function module:GMCCalculateMissions(this,elapsed)
		local GMC=GMF.MissionControlTab
		db.news.MissionControl=true

		timeElapsed = timeElapsed + elapsed
		if (#aMissions == 0 ) then
			if timeElapsed >= 1 then
				currentMission=0
				x=0
				self:Unhook(this,"OnUpdate")
				GMC.list.widget:SetTitle(READY)
				GMC.list.widget:SetTitleColor(C.Green())
				wipe(GMCUsedFollowers)
				this:Enable()
				GMC.runButton:Enable()
				if (#GMC.list.Parties>0) then
					GMC.runButton:Enable()
				end
			end
			return
		end
		if (timeElapsed >=0.05) then
			currentMission=currentMission+1
			if (currentMission > #aMissions) then
				wipe(aMissions)
				currentMission=0
				x=0
				timeElapsed=0.5
			else
				local missionID=aMissions[currentMission]
				GMC.list.widget:SetFormattedTitle("Processing mission %d of %d (%s)",currentMission,#aMissions,G.GetMissionName(missionID))
				local class=self:GetMissionData(missionID,"class")
				--print(C("Processing ","Red"),missionID,addon:GetMissionData(missionID,"name"))
				local minimumChance=0
				if (settings.useOneChance) then
					minimumChance=tonumber(settings.minimumChance) or 100
				else
					minimumChance=tonumber(settings.rewardChance[class]) or 100
				end
				local party={members={},perc=0}
				self:MCMatchMaker(missionID,party,settings.skipEpic,minimumChance)
				--@debug@
				print(missionID,"  Requested",class,";",minimumChance,"Mission",party.perc,party.full,settings)
				--@end-debug@
				if ( party.full and party.perc >= minimumChance) then
					--@debug@
					print(missionID,"  Accepted",party)
					--@end-debug@
					local mb=AceGUI:Create("GMCMissionButton")
					if not blacklist[missionID] then
						for i=1,#party.members do
							GMCUsedFollowers[party.members[i]]=true
						end
					end
					party.missionID=missionID
					tinsert(GMC.list.Parties,party)
					GMC.list.widget:PushChild(mb,missionID)
					mb:SetFullWidth(true)
					mb:SetMission(self:GetMissionData(missionID),party,false,"control")
					mb:Blacklist(blacklist[missionID])
					mb:SetCallback("OnClick",leftclick)
					mb:SetCallback("OnRightClick",rightclick)
				end
				timeElapsed=0
			end
		end
	end
end

function module:GMC_OnClick_Run(this,button)
	local GMC=GMF.MissionControlTab
	this:Disable()
	GMC.logoutButton:Disable()
	do
		local elapsed=0
		local co=coroutine.wrap(self.GMCRunMission)
		self:RawHookScript(GMC.runButton,'OnUpdate',function(this,ts)
			elapsed=elapsed+ts
			if (elapsed>0.25) then
				elapsed=0
				local rc=co(self)
				if (not rc) then
					self:Unhook(GMC.runButton,'OnUpdate')
					GMC.logoutButton:Enable()
				end
			end
		end
		)
	end
end
function module:GMC_OnClick_Start(this,button)
	local GMC=GMF.MissionControlTab
	--@debug@
	print(C("-------------------------------------------------","Yellow"))
	--@end-debug@
	GMC.list.widget:ClearChildren()
	if (self:GetTotFollowers(AVAILABLE) == 0) then
		GMC.list.widget:SetTitle("All followers are busy")
		GMC.list.widget:SetTitleColor(C.Orange())
		return
	end
	if ( G.IsAboveFollowerSoftCap(1) ) then
		GMC.list.widget:SetTitle(GARRISON_MAX_FOLLOWERS_MISSION_TOOLTIP)
		GMC.list.widget:SetTitleColor(C.Red())
		return
	end
	this:Disable()
	GMC.list.widget:SetTitleColor(C.Green())
	self:GMCCreateMissionList(aMissions)
	wipe(GMCUsedFollowers)
	wipe(GMC.list.Parties)
	self:RefreshFollowerStatus()
	if (#aMissions>0) then
		GMC.list.widget:SetFormattedTitle(L["Processing mission %d of %d"],1,#aMissions)
	else
		GMC.list.widget:SetTitle("No mission matches your criteria")
		GMC.list.widget:SetTitleColor(C.Red())
	end
	self:RawHookScript(GMC.startButton,'OnUpdate',"GMCCalculateMissions")

end
local chestTexture
local function buildDragging(frame,drawItemButtons)
	local GMC=GMF.MissionControlTab
	frame:SetScript('OnClick', function(this)
		settings.allowedRewards[this.key] = not settings.allowedRewards[this.key]
		drawItemButtons()
		GMC.startButton:Click()
	end)
	frame:SetScript('OnEnter', function(this)
		GameTooltip:SetOwner(this, 'ANCHOR_BOTTOMRIGHT')
		GameTooltip:AddLine(this.tooltip);
		for _,line in ipairs(this.list) do
			local info=GetItemInfo(line,2)
			if info then GameTooltip:AddLine(info) end
		end
		GameTooltip:Show()
	end)
	frame:RegisterForDrag("LeftButton")
	frame:SetMovable(true)
	frame:SetScript("OnDragStart",function(this,button)
			--@debug@
			print("Start",this:GetName(),GetMouseFocus():GetName(),this:GetID(),this.key)
			--@end-debug@
			local f=GMC.ignoreFrames[this:GetID()+1]
			if f then f:ClearAllPoints() end
			this:StartMoving()
			this.oldframestrata=this:GetFrameStrata()
			this:SetFrameStrata("FULLSCREEN_DIALOG")
	end)
	frame:SetScript("OnDragStop",function(this,button)
		this:StopMovingOrSizing()
		--@debug@
		print("Stopped",this:GetName(),GetMouseFocus():GetName(),this:GetID(),this.key)
		--@end-debug@
		this:SetFrameStrata(this.oldframestrata)
	end)
	frame:SetScript("OnReceiveDrag",function(this,...)
			--@debug@
			print("Receive",this:GetName(),GetMouseFocus():GetName(),this:GetID(),this.key,...)
			--@end-debug@
			local from=this:GetID()
			local to
			local x,y=this:GetCenter()
			local id=this:GetID()
			for i=1,#GMC.ignoreFrames do
				local f=GMC.ignoreFrames[i]
				if f:GetID() ~= id then
					if f:IsMouseOver()  then
						to=f:GetID()
						break
					end
					if y>=f:GetBottom() and y<=f:GetTop() and x>=f:GetLeft() and x<=f:GetRight() then
						to=f:GetID()
						break
					end
				end
			end
			if (to) then
				local appo=tremove(classlist,from)
				tinsert(classlist,to,appo)
				--@debug@
				print(appo,"from:",from,"to:",to)
				DevTools_Dump(classlist)
				--@end-debug@
			end
			drawItemButtons()
			--module:Refresh()
	end)
	frame:SetScript('OnLeave', function() GameTooltip:Hide() end)

end
local function drawItemButtons(frame)
	local GMC=GMF.MissionControlTab
	frame=frame or GMC.rewards
	local scale=1.0
	local h=37 -- itemButtonTemplate standard size
	local gap=5
	local single=settings.useOneChance
	--for j = 1, #tItems do
	--local i=tOrder[j]
	local wrap=#classlist/2 +1
	for frameIndex,i in ipairs(classlist) do
		local row = GMC.ignoreFrames[frameIndex]
		if not row then
			row= CreateFrame('BUTTON', "Priority" .. frameIndex, frame, 'ItemButtonTemplate')
			row.chance=settings.rewardChance[row.key] or 100
			GMC.ignoreFrames[frameIndex] = row
			row.slider=row.slider or factory:Slider(row,0,100,row.chance,row.chance)
			row.slider:SetWidth(128)
			row.slider:SetPoint('BOTTOMLEFT',row,'BOTTOMRIGHT',15,0)
			row.slider.Text:SetFontObject('NumberFont_Outline_Med')
			row.slider.isPercent=true
			row.slider:SetScript("OnValueChanged",function(this,value)
				settings.rewardChance[this:GetParent().key]=this:OnValueChanged(value)
				module:Refresh()
			end
			)
			row.chest = row.chest or row:CreateTexture(nil, 'BACKGROUND')
			row.chest:SetTexture('Interface\\Garrison\\GarrisonMissionUI2.blp')
			row.chest:SetAtlas(chestTexture)
			row.chest:SetSize((209-(209*0.25))*0.30, (155-(155*0.25)) * 0.30)
			row.chest:SetPoint('CENTER',row.slider, 0, 15)
			buildDragging(row,drawItemButtons)
		end
		row:SetID(frameIndex)
		row:ClearAllPoints()
		row:SetScale(scale)
		--frame:SetPoint('TOPLEFT', 10,(j) * ((-h * scale) -gap))
		if frameIndex==1 then
			row:SetPoint('TOPLEFT', 10,-35)
		elseif frameIndex==wrap then
			row:SetPoint('TOPRIGHT', -(10 + 145),-35)
		else
			row:SetPoint('TOPLEFT', GMC.ignoreFrames[frameIndex-1],'BOTTOMLEFT',0,-5)
		end
		row.icon:SetTexture(tItems[i].i)
		row.key=tItems[i].key
		class2order[row.key]=frameIndex
		row.tooltip=tItems[i].t
		row.list=tItems[i].list
		row.allowed=settings.allowedRewards[row.key]
		row.chance=settings.rewardChance[row.key] or 100
		row.icon:SetDesaturated(not row.allowed)
		if row.key=="itemLevel" then
			row.Count:SetText(settings.minLevel)
			row.Count:SetJustifyH("RIGHT")
			row.Count:SetPoint('BOTTOMRIGHT',0,5)
			row.Count:Show()
		elseif row.key=="followerUpgrade" then
			row.Count:SetText(settings.minUpgrade)
			row.Count:SetJustifyH("RIGHT")
			row.Count:SetPoint('BOTTOMRIGHT',0,5)
			row.Count:Show()
		else
			row.Count:Hide()
		end
		-- Need to resave them asap in order to populate the array for future scans
		settings.allowedRewards[row.key]=row.allowed
		settings.rewardChance[row.key]=row.chance
		--row.slider:OnValueChanged(row.chance)
		row.slider:SetValue(row.chance)
		if (single) then
			row.slider:SetTextColor(C.Silver())
		else
			row.slider:SetTextColor(C.Green())
		end
		row.slider:OnValueChanged(settings.rewardChance[row.key] or 100)
		--frame.slider:SetText(settings.rewardChance[frame.key])
		if (single) then
			row.chest:SetDesaturated(true)
		else
			row.chest:SetDesaturated(false)
		end
		row.chest:Show()
		row:Show()
		row.top=row:GetTop()
		row.bottom=row:GetBottom()
	end
	if not GMC.rewardinfo then
		GMC.rewardinfo = frame:CreateFontString()
		local info=GMC.rewardinfo
		info:SetFontObject('GameFontHighlight')
		info:SetText("Click to enable/disable a reward. Drag to reorder")
		info:SetTextColor(1, 1, 1)
		info:SetPoint("BOTTOM",0,-5)
	end
	return GMC.ignoreFrames[#tItems]
end
local function dbfixV1()
--@debug@
	print('dbfixV1')
--@end-debug@
	if type(settings.allowedRewards['equip'])~='nil' then
		settings.allowedRewards['itemLevel']=settings.allowedRewards['equip']
		settings.rewardChance['itemLevel']=settings.rewardChance['equip']
		settings.allowedRewards['equip']=nil
		settings.rewardChance['equip']=nil
	end
	if type(settings.allowedRewards['followerEquip'])~='nil' then
		settings.allowedRewards['followerUpgrade']=settings.allowedRewards['followerEquip']
		settings.rewardChance['followerUpgrade']=settings.rewardChance['followerEquip']
		settings.allowedRewards['followerEquip']=nil
		settings.rewardChance['followerEquip']=nil
	end
	settings.version=2
end
local function dbfixV2()
--@debug@
	print('dbfixV2')
--@end-debug@
	local old=
		{
			'gold',
			'resources',
			'oil',
			'rush',
			'xp',
			'followerUpgrade',
			'itemLevel',
			'apexis',
			'seal',
			'other'
		}
	settings.rewardList={}
	settings.itemIgnoreList=nil
	local a=settings.rewardList
	if type(settings.rewardOrder)=="table" then
		for _,i in ipairs(settings.rewardOrder) do
			if old[i] ~='-' then
				tinsert(a,old[i])
				old[i]='-'
			end
		end
	end
	for  _,v in ipairs(old) do
		if v~='-' then
			tinsert(a,v)
		end
	end
	for index,key in ipairs(a) do
		class2order[key]=index
	end
	for _,v in ipairs(addon:GetRewardClasses()) do
		if not class2order[v.key] then
			tinsert(a,v.key)
		end
	end
	settings.rewardOrder=nil
	settings.version=3
end
local function toggleEpicWarning()
	local GMC=GMF.MissionControlTab
	local warning=GMC.warning
	if not warning then return end
	if (settings.skipEpic) then
		warning:Show()
		GMC.list.widget:SetPoint("TOPLEFT",GMC.chance,"TOPRIGHT",0,ns.bigscreen and -60 or -50)
	else
		warning:Hide()
		GMC.list.widget:SetPoint("TOPLEFT",GMC.chance,"TOPRIGHT",0,-30)
	end
end
function module:OnInitialized()
	local bigscreen=ns.bigscreen
	db=addon.db.global
	chardb=addon.privatedb.profile
	chestTexture='GarrMission-'..UnitFactionGroup('player').. 'Chest'
	local GMC = CreateFrame('FRAME', nil, GMF)
	GMF.MissionControlTab=GMC
	settings=chardb.missionControl
	if settings.version < 2 then
		dbfixV1()
	end
	if settings.version < 3 or type(settings.rewardOrder)=='table' or #settings.rewardList==0 then
		dbfixV2()
	end
	wipe(class2order)
	classlist=settings.rewardList
	for index,key in ipairs(classlist) do
		class2order[key]=index
	end
	if settings.itemPrio then
		settings.itemPrio=nil
	end
	GMC:SetAllPoints()
	--GMC:SetPoint('LEFT')
	--GMC:SetSize(GMF:GetWidth(), GMF:GetHeight())
	GMC:Hide()
	GMC.chance=self:GMCBuildChance()
	GMC.duration=self:GMCBuildDuration()
	GMC.rewards=self:GMCBuildRewards()
	GMC.list=self:GMCBuildMissionList()
	GMC.flags=self:GMCBuildFlags()
	local chance=GMC.chance
	local duration=GMC.duration
	local rewards=GMC.rewards
	local list=GMC.list
	local flags=GMC.flags
	list.widget:SetPoint("TOPLEFT",chance,"TOPRIGHT",0,-30)
	list.widget:SetPoint("BOTTOMRIGHT",GMF,"BOTTOMRIGHT",-25,25)
	duration:SetPoint("TOPLEFT",20,-25)
	chance:SetPoint("TOPLEFT",duration,"TOPRIGHT",0,0)
	rewards:SetPoint("TOPLEFT",duration,"BOTTOMLEFT",0,0)
	rewards:SetPoint("BOTTOMLEFT",20,25)
	toggleEpicWarning()
	if flags then
		flags:SetPoint("TOPLEFT",chance,"BOTTOMLEFT",0,0)
	end
	--@debug@
	--AddBackdrop(rewards)
	--AddBackdrop(duration,0,1,0)
	--AddBackdrop(chance,0,0,1)
	--	AddBackdrop(flags,0,1,1)
	--@end-debug@
	GMC.Credits=GMC:CreateFontString(nil,"ARTWORK","QuestFont_Shadow_Small")
	GMC.Credits:SetWidth(0)
	GMC.Credits:SetFormattedText(C(L["Original concept and interface by %s"],'Yellow'),C("Motig","Red") )
	GMC.Credits:SetJustifyH("RIGHT")
	GMC.Credits:SetPoint("BOTTOMRIGHT",-50,5)
	return GMC
end
local refreshTimer
function module:Refresh()
	if not GMF.MissionControlTab.startButton then return end
	if GMF.MissionControlTab.startButton:IsEnabled() and not IsMouseButtonDown("LeftButton") then
		self:GMC_OnClick_Start(GMF.MissionControlTab.startButton,"LeftUp")
	else
		if refreshTimer then
			self:CancelTimer(refreshTimer)
			refreshTimer=nil
		end
		refreshTimer=self:ScheduleTimer("Refresh",0.5)
	end
end
function module:GMCBuildChance()
	local GMC=GMF.MissionControlTab
	--Chance
	local frame= CreateFrame('FRAME', nil, GMC)
	frame:SetSize(210, 165)
	GMC.cp = frame:CreateTexture(nil, 'BACKGROUND') --Chest
	GMC.cp:SetTexture('Interface\\Garrison\\GarrisonMissionUI2.blp')
	GMC.cp:SetAtlas(chestTexture)
	GMC.cp:SetDesaturated(not settings.useOneChance)
	GMC.cp:SetSize((209-(209*0.25))*0.60, (155-(155*0.25))*0.60)
	GMC.cp:SetPoint('CENTER', 0, 40)

	GMC.ct = frame:CreateFontString() --Chance number
	GMC.ct:SetFontObject('ZoneTextFont')
	GMC.ct:SetFormattedText('%d%%',settings.minimumChance)
	GMC.ct:SetPoint('CENTER', 0,25)
	if settings.useOneChance then
		GMC.ct:SetTextColor(C:Green())
	else
		GMC.ct:SetTextColor(C:Silver())
	end
	GMC.cs = factory:Slider(frame,0,100,settings.minimumChance,L['Minumum needed chance'],L["Mission with lower success chance will be ignored"]) -- Slider
	GMC.cs:SetPoint('CENTER', 0, -25)
	GMC.cs:SetScript('OnValueChanged', function(self, value)
		local value = math.floor(value)
		GMC.ct:SetText(value..'%')
		settings.minimumChance = value
		module:Refresh()
	end)
	GMC.cs:SetValue(settings.minimumChance)
	GMC.ck=factory:Checkbox(frame,settings.useOneChance,L["Global success chance"],L["Unchecking this will allow you to set specific success chance for each reward type"])
	GMC.ck:SetPoint("BOTTOM",0,5)
	GMC.ck:SetScript("OnClick",function(this)
		settings.useOneChance=this:GetChecked()
		if (settings.useOneChance) then
			GMC.cp:SetDesaturated(false)
			GMC.ct:SetTextColor(C.Green())
		else
			GMC.cp:SetDesaturated(true)
			GMC.ct:SetTextColor(C.Silver())
		end
		drawItemButtons()
		module:Refresh()
	end)
	return frame
end
local function timeslidechange(this,value)
	local GMC=GMF.MissionControlTab
	local value = math.floor(value)
	if (this.max) then
		settings.maxDuration = max(value,settings.minDuration)
		if (value~=settings.maxDuration) then this:SetValue(settings.maxDuration) end
	else
		settings.minDuration = min(value,settings.maxDuration)
		if (value~=settings.minDuration) then this:SetValue(settings.minDuration) end
	end
	local c = 1-(value*(1/24))
	if c < 0.3 then c = 0.3 end
	GMC.mt:SetTextColor(1, c, c)
	GMC.mt:SetFormattedText("%d-%dh",settings.minDuration,settings.maxDuration)
end
function addon:ApplyGCMINLEVEL(value)
	settings.minLevel=value
	drawItemButtons()
	module:Refresh()
end
function addon:ApplyGCMINUPGRADE(value)
	settings.minUpgrade=value
	drawItemButtons()
	module:Refresh()
end
function addon:ApplyGCSKIPEPIC(value)
	settings.skipEpic=value
	toggleEpicWarning()
	module:Refresh()
end
function addon:ApplyGCSKIPRARE(value)
	settings.skipRare=value
	module:Refresh()
end
function module:GMCBuildFlags()
	local GMC=GMF.MissionControlTab
	local warning=GMC:CreateFontString(nil,"ARTWORK",ns.bigscreen and "GameFontNormalHuge" or "GameFontNormal")
	warning:SetText(L["Epic followers are NOT sent alone on xp only missions"])
	warning:SetPoint("TOPLEFT",GMC.chance,"TOPRIGHT",0,0)
	warning:SetPoint("TOPRIGHT",GMC,"TOPRIGHT",0,-25)
	warning:SetJustifyH("CENTER")
	warning:SetTextColor(C.Orange())
	GMC.warning=warning
	if true then
		addon:AddLabel(L["Mission Control"])
		addon:AddSlider("GCMINLEVEL",settings.minLevel,535,715,L["Item minimum level"],L['Minimum requested level for equipment rewards'],15)
		addon:AddSlider("GCMINUPGRADE",settings.minUpgrade,600,675,L["Follower set minimum upgrade"],L['Minimum requested upgrade for followers set (Enhancements are always included)'],15)
		addon:AddToggle("GCSKIPEPIC",settings.skipEpic,L["Ignore epic for xp missions."],L["IF you have a Salvage Yard you probably dont want to have this one checked"])
		addon:AddToggle("GCSKIPRARE",settings.skipRare,L["Ignore rare missions"],L["Rare missions will not be considered"])
	else
		-- Duration
		local frame= CreateFrame('FRAME', nil, GMC) -- Flags frame
		frame:SetSize(210, 30+40*5)
		local title = frame:CreateFontString() -- Title
		title:SetFontObject('GameFontNormalHuge')
		title:SetText(L['Other settings'])
		title:SetPoint('TOPLEFT', 0, -5)
		title:SetPoint('TOPRIGHT', 0, -5)
		title:SetTextColor(1, 1, 1)
		title:SetJustifyH("CENTER")
		GMC.skipRare=factory:Checkbox(frame,settings.skipRare,L["Ignore rare missions"],L["Rare missions will not be considered"])
		GMC.skipRare:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-5)
		GMC.skipRare:SetScript("OnClick",function(this)
			settings.skipRare=this:GetChecked()
			module:GMC_OnClick_Start(GMC.startButton,"LeftUp")
		end)
		GMC.skipEpic=factory:Checkbox(frame,settings.skipEpic,L["Ignore epic for xp missions."],L["IF you have a Salvage Yard you probably dont want to have this one checked"])
		GMC.skipEpic:SetPoint("TOPLEFT",GMC.skipRare,"BOTTOMLEFT",0,-5)
		GMC.skipEpic:SetScript("OnClick",function(this)
			settings.skipEpic=this:GetChecked()
			toggleEpicWarning(warning)
			module:Refresh()
		end)
		GMC.minLevel=factory:Slider(frame,540,715,settings.minLevel,L["Item minimum level"],L['Minimum requested level for equipment rewards'])
		GMC.minLevel:SetPoint('TOP', GMC.skipEpic,"BOTTOM",0, -25)
		GMC.minLevel:SetScript('OnValueChanged', function(self, value)
			local value = math.floor(value)
			settings.minLevel = value
			drawItemButtons()
			module:Refresh()
		end)
		--GMC.minLevel:SetValue(settings.minLevel)
		GMC.minLevel:SetStep(15)
		GMC.minUpgrade=factory:Slider(frame,600,675,settings.minUpgrade,L["Follower set minimum upgrade"],L['Minimum requested upgrade for followers set (Enhancements are always included)'])
		GMC.minUpgrade:SetPoint('TOP', GMC.minLevel,"BOTTOM",0, -25)
		GMC.minUpgrade:SetScript('OnValueChanged', function(self, value)
			local value = math.floor(value)
			settings.minUpgrade = value
			drawItemButtons()
			module:Refresh()
		end)
		--GMC.minUpgrade:SetValue(settings.minUpgrade)
		GMC.minUpgrade:SetStep(15)
		return frame
	end
end
function module:GMCBuildDuration()
	-- Duration
	local GMC=GMF.MissionControlTab
	local frame= CreateFrame('FRAME', 'PIPPO', GMC) -- Dutation frame
	frame:SetSize(210, 165)
	frame:SetPoint('TOP',0, -20)

	GMC.hg = frame:CreateTexture(nil, 'BACKGROUND') -- Hourglass
	GMC.hg:SetTexture('Interface\\Timer\\Challenges-Logo.blp')
	GMC.hg:SetSize(7, 70)
	GMC.hg:SetPoint('CENTER', 0, 10)
	GMC.hg:SetBlendMode('ADD')

	GMC.rune = frame:CreateTexture(nil, 'BACKGROUND') --Rune
	--bb:SetTexture('Interface\\Timer\\Challenges-Logo.blp')
	--bb:SetTexture('dungeons\\textures\\devices\\mm_clockface_01.blp')
	GMC.rune:SetTexture('World\\Dungeon\\Challenge\\clockRunes.blp')
	GMC.rune:SetSize(80, 80)
	GMC.rune:SetPoint('CENTER', 0, 10)
	GMC.rune:SetBlendMode('ADD')

	GMC.mt = frame:CreateFontString() -- Duration string over hourglass
	GMC.mt:SetFontObject('ZoneTextFont')
	GMC.mt:SetFormattedText('%d-%dh',settings.minDuration,settings.maxDuration)
	GMC.mt:SetPoint('CENTER', 0, 0)
	GMC.mt:SetTextColor(1, 1, 1)

	GMC.ms1 = factory:Slider(frame,0,24,settings.minDuration,L['Minimum mission duration.'])
	GMC.ms2 = factory:Slider(frame,0,24,settings.maxDuration,L['Maximum mission duration.'])
	GMC.ms1:SetPoint('TOP', frame,'TOP',0, -10)
	GMC.ms2:SetPoint('BOTTOM', frame,'BOTTOM',0, 15)
	GMC.ms2.max=true
	GMC.ms1:SetScript('OnValueChanged', timeslidechange)
	GMC.ms2:SetScript('OnValueChanged', timeslidechange)
	timeslidechange(GMC.ms1,settings.minDuration)
	timeslidechange(GMC.ms2,settings.maxDuration)
	return frame
end
function module:GMCBuildRewards()
	--Allowed rewards
	local GMC=GMF.MissionControlTab
	local frame = CreateFrame('FRAME', nil, GMC)
	frame:SetWidth(420)
	GMC.itf = frame:CreateFontString()
	GMC.itf:SetFontObject('GameFontNormalHuge')
	GMC.itf:SetText(L['Allowed Rewards'])
	GMC.itf:SetPoint('TOP', 0, 0)
	GMC.itf:SetTextColor(1, 1, 1)
	GMC.ignoreFrames = {}
	drawItemButtons(frame)
	return frame
end

function module:GMCBuildMissionList()
	local ml={widget=AceGUI:Create("GMCLayer"),Parties={}}
	local GMC=GMF.MissionControlTab
	ml.widget:SetTitle(READY)
	ml.widget:SetTitleColor(C.Green())
	ml.widget:SetTitleHeight(40)
	ml.widget:SetParent(GMC)
	ml.widget:Show()
	GMC.startButton = CreateFrame('BUTTON',nil,  ml.widget.frame, 'GameMenuButtonTemplate')
	GMC.startButton:SetText('Calculate')
	GMC.startButton:SetWidth(148)
	GMC.startButton:SetPoint('TOPLEFT',10,25)
	GMC.startButton:SetScript('OnClick', function(this,button) self:GMC_OnClick_Start(this,button) end)
	GMC.startButton:SetScript('OnEnter', function() GameTooltip:SetOwner(GMC.startButton, 'ANCHOR_TOPRIGHT') GameTooltip:AddLine('Assign your followers to missions.') GameTooltip:Show() end)
	GMC.startButton:SetScript('OnLeave', function() GameTooltip:Hide() end)
	GMC.runButton = CreateFrame('BUTTON', nil,ml.widget.frame, 'GameMenuButtonTemplate')
	GMC.runButton:SetText('Send all mission at once')
	GMC.runButton:SetScript('OnEnter', function()
		GameTooltip:SetOwner(GMC.runButton, 'ANCHOR_TOPRIGHT')
		GameTooltip:AddLine(L["Submit all your mission at once. No question asked."])
		GameTooltip:AddLine(L["You can also send mission one by one clicking on each button."])
		GameTooltip:Show()
	end)
	GMC.runButton:SetScript('OnLeave', function() GameTooltip:Hide() end)
	GMC.runButton:SetWidth(148)
	GMC.runButton:SetScript('OnClick',function(this,button) self:GMC_OnClick_Run(this,button) end)
	GMC.runButton:Disable()
	GMC.runButton:SetPoint('TOPRIGHT',-10,25)
	GMC.logoutButton=CreateFrame('BUTTON', nil,ml.widget.frame, 'GameMenuButtonTemplate')
	GMC.logoutButton:SetText(LOGOUT)
	GMC.logoutButton:SetWidth(ns.bigscreen and 148 or 90)
	GMC.logoutButton:SetScript("OnClick",function() GMF:Hide() Logout() end )
	GMC.logoutButton:SetPoint('TOP',0,25)
	return ml

end
