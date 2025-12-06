-- ProfileStore by ltp make sure to look at the ReadMe Module for more information

local ds = game:GetService("DataStoreService")
local rs = game:GetService("ReplicatedStorage")
local RunS = game:GetService("RunService")
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local modules
local SaveLoop = false
local DATAHANDLING_ATTEMPTS = 3
local SESSION_TIMEOUT = 60 * 5 -- saves must happen every SESSION_TIMEOUT seconds or the data will be handelable by another server
local AUTOSAVE_DELAY = 60 * 3

local INCREMENT_SIGNALFIRING_KEYS

local Ready = false

local profilestore = {}

local PlayersData = {}
local DataBase
if RunS:IsServer() then DataBase = ds:GetDataStore("Profilestore") end

local ResetProfile = function(Key: string) -- debug
	if not RunS:IsServer() then return 0 end
	
	local sccs,result = pcall(function()
	return DataBase:RemoveAsync(Key)
	end)
	if not sccs then warn("No profile found") end
end


--task.spawn(function() -- debug
--	ResetProfile("7104164056")
--end)

profilestore.Init = function(data)
	if RunS:IsServer() then
	
		profilestore["Data"] = {

			["ProfileTemplate"] = {
				["Global"] = require(script.Template),
				["MetaData"] = {
					["Lock"] = {
						["SessionId"] = nil,
						["SessionTime"] = nil
					}
				}
			}

			-- future eventual additions
		}
		SaveLoop = true
	end
	
	modules = data
	
	task.wait(0.05)
	Ready = true -- this line must remain at the end of the function
end

profilestore.Start = function()
	while not Ready do print("Not ready") task.wait(1) end
	
	task.spawn(function()
		task.wait(0.05)
		INCREMENT_SIGNALFIRING_KEYS = {
			["Money"] = modules["SignalManager"]["MoneyAdded"]
		}
	end)
	
	function Save(Data)
		while not Ready do print("Not ready") task.wait(1) end
		local MetaData = Data["MetaData"]
		local Lock = MetaData["Lock"]

		Lock["SessionId"] = Http:GenerateGUID(false)
		Lock["SessionTime"] = os.time()
		return Data
	end

	profilestore.Onjoin = function(player)
		if not RunS:IsServer() then return 0 end
		
		for i = 1, DATAHANDLING_ATTEMPTS do
			local Break = false
			local success, result = pcall(function()
				return DataBase:UpdateAsync(tostring(player.UserId),function(OldData)
					local Data = modules["Utility"].MergeTables(OldData,profilestore.Data.ProfileTemplate) or modules["Utility"].DeepcopyTable(profilestore.Data.ProfileTemplate)
					Data.Global = modules["Utility"].RemoveExcedantKeys(Data.Global, profilestore.Data.ProfileTemplate.Global)
					local MetaData = Data["MetaData"]
					local Lock = MetaData["Lock"]
					if Lock and Lock["SessionId"] and Lock["SessionTime"] then
						local now = os.time()
						local Dif = now - Lock["SessionTime"]
						if Dif > SESSION_TIMEOUT then
							return Save(Data)
						else
							if player.Parent == Players then player:Kick("Session is locked try joining back later") end
							Break = true
						end
					else
						return Save(Data)
					end
				end)
			end)
			if Break then break end
			if success and result then
				PlayersData[tostring(player.UserId)] = result
				break
			end
		end

	end

	function HandleLock(Data, OldData, player: Player)
		if not RunS:IsServer() then return 0 end
		
		if Data["MetaData"]["Lock"] then
			local SessionLock = PlayersData[tostring(player.UserId)]["MetaData"]["Lock"]
			local SessionId = SessionLock["SessionId"]

			Data["Global"] = PlayersData[tostring(player.UserId)]["Global"]

			local LockId = Data["MetaData"]["Lock"]["SessionId"]
			if not SessionId then return OldData end
			if not LockId then
				Data["MetaData"]["Lock"] = nil
				return Data
			end
			if SessionId == LockId then
				Data["MetaData"]["Lock"] = nil
				return Data
			end

			local now = os.time()
			local Dif = now - SessionLock["SessionTime"]

			if Dif > SESSION_TIMEOUT then
				Data["MetaData"]["Lock"] = nil
				return Data
			end
			return OldData
		else
			Data["MetaData"]["Lock"] = nil
			return Data
		end
	end

	profilestore.OnLeave = function(player)
		if not RunS:IsServer() then return 0 end
		
		local sccs,result = pcall(function()
			DataBase:UpdateAsync(tostring(player.UserId),function(OldData)
				local Data = PlayersData[tostring(player.UserId)] or OldData
				return HandleLock(Data, OldData, player)
			end)
		end)
	end

	profilestore.AutoSave = function(plr: Player)
		if not RunS:IsServer() then return 0 end
		
		local sccs, result = pcall(function()
			return DataBase:UpdateAsync(tostring(plr.UserId), function(OldData)
				local Data = PlayersData[tostring(plr.UserId)] or OldData
				Data["MetaData"]["Lock"]["SessionTime"] = os.time()
				if OldData["MetaData"]["Lock"]["SessionId"] == Data["MetaData"]["Lock"]["SessionId"] then return Data end
				return nil
				
			end)
		end)
	end
	
	-- Start AutoSavingLoop
	task.spawn(function()
		if not RunS:IsServer() then return 0 end
		
		while SaveLoop do
			for i, v: Player in pairs(Players:GetPlayers()) do
				if PlayersData[tostring(v.UserId)] and v.Parent == game.Players then
					profilestore.AutoSave(v)
				end
			end
			task.wait(AUTOSAVE_DELAY)
		end
	end)
	
	-- handle server crash
	game:BindToClose(function()
		if not RunS:IsServer() then return 0 end
		
		warn("ServerClosing !")
		SaveLoop = false
		for i, v: Player in pairs(Players:GetPlayers()) do
			task.spawn(function()
				if PlayersData[tostring(v.UserId)] and v.Parent == game.Players then
					task.spawn(function()
						profilestore.OnLeave(v)
					end)
				end
			end)
		end
		task.wait(3) -- gives time to save
	end)
	
	
	profilestore.Api = {}
	profilestore.Api.IncremenKeyValue = function(plr: Player, key: string, x: number)
		if not RunS:IsServer() then return 0 end
		
		print("Incremting key: " .. key .. " player: " .. plr.Name)
		local Data = PlayersData[tostring(plr.UserId)]
		if not Data then warn("no Data for player") return 0 end
		local HasKey = Data["Global"][key]
		if not HasKey then warn("no key in data") return 0 end
		
		-- increment key
		Data["Global"][key] += x
		--Fire Signals 
		if not INCREMENT_SIGNALFIRING_KEYS[key] then print("No Signal with key: " .. key) print(INCREMENT_SIGNALFIRING_KEYS) return 0 end
		pcall(function() INCREMENT_SIGNALFIRING_KEYS[key]:Fire({Amount=100}) end)
	end

	profilestore.Api.SetKeyValue = function(plr: Player, key: string, x)
		if not RunS:IsServer() then return 0 end
		
		print("Setting key: " .. key .. " player: " .. plr.Name)
		local Data = PlayersData[tostring(plr.UserId)]
		if not Data then warn("no Data for player") return 0 end
		local HasKey = Data["Global"][key]
		if not HasKey then warn("no key in data") return 0 end
		Data["Global"][key] = x
	end
	
	profilestore.Api.GetProfile = function(plr: Player)
		if RunS:IsServer() then return PlayersData[tostring(plr.UserId)] end -- if server return the data
		-- client return the data if player is local player
		if plr == Players.LocalPlayer then return PlayersData[tostring(Players.LocalPlayer.UserId)]["Global"] end
	end
	
	profilestore.Api.GetKeyValue = function(plr: Instance, key:string)
		local Profile = profilestore.GetProfile(plr)
		if not Profile then return 0 end
		if Profile["Global"] then -- case 1 called from server see GetProfile above to compehend
			return Profile["Global"][key] or 0
		end
		return Profile[key] or 0
	end

	Players.PlayerAdded:Connect(function(plr)
		profilestore.Onjoin(plr)
	end)
	Players.PlayerRemoving:Connect(function(plr)
		profilestore.OnLeave(plr)
	end)
end

return profilestore
