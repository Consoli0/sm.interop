dofile( "$SURVIVAL_DATA/Scripts/game/managers/UnitManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/recipes.lua" )

CreativeGame = class( nil )
CreativeGame.enableLimitedInventory = false
CreativeGame.enableRestrictions = true
CreativeGame.enableFuelConsumption = false
CreativeGame.enableAmmoConsumption = false
CreativeGame.enableUpgradeCost = true

g_godMode = true
g_disableScrapHarvest = true

function CreativeGame.server_onCreate( self )
	g_unitManager = UnitManager()
	g_unitManager:sv_onCreate( nil, { aggroCreations = true } )

	self:loadCraftingRecipes()
end

function CreativeGame.loadCraftingRecipes( self )
	LoadCraftingRecipes({
		craftbot = "$SURVIVAL_DATA/CraftingRecipes/craftbot.json"
	})
end

function CreativeGame.server_onFixedUpdate( self, timeStep )
	g_unitManager:sv_onFixedUpdate()
end

function CreativeGame.server_onPlayerJoined( self, player, newPlayer )
	g_unitManager:sv_onPlayerJoined( player )
end

function CreativeGame.client_onCreate( self )
  if not sm.isHost then
		self:loadCraftingRecipes()
	end

	-- Register /mod command
	local arguments = {
		{ 'string', 'command', true }
	}
	local nca = {}
	for i=1, 100 do
		local t = { 'string', 'arg'..i, true }
		arguments[i + 1] = t
		nca[i] = t
	end

	self.interop_newCommandArguments = nca

	sm.game.bindChatCommand('/mod', arguments, 'cl_onInteropCommand', 'Executes a mod command')

	sm.game.bindChatCommand( "/noaggro", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles the player as a target" )
	sm.game.bindChatCommand( "/noaggrocreations", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles whether the Tapebots will shoot at creations" )
	sm.game.bindChatCommand( "/aggroall", {}, "cl_onChatCommand", "All hostile units will be made aware of the player's position" )
	sm.game.bindChatCommand( "/popcapsules", { { "string", "filter", true } }, "cl_onChatCommand", "Opens all capsules. An optional filter controls which type of capsules to open: 'bot', 'animal'" )
	sm.game.bindChatCommand( "/killall", {}, "cl_onChatCommand", "Kills all spawned units" )
	sm.game.bindChatCommand( "/dropscrap", {}, "cl_onChatCommand", "Toggles the scrap loot from Haybots" )
	sm.game.bindChatCommand( "/place", { { "string", "harvestable", false } }, "cl_onChatCommand", "Places a harvestable at the aimed position. Must be placed on the ground. The harvestable parameter controls which harvestable to place: 'stone', 'tree', 'birch', 'leafy', 'spruce', 'pine'" )
	sm.game.bindChatCommand( "/restrictions", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles restrictions on creations" )

	self.cl = {}
	if sm.isHost then
		self.clearEnabled = false
		sm.game.bindChatCommand( "/allowclear", { { "bool", "enable", true } }, "cl_onChatCommand", "Enabled/Disables the /clear command" )
		sm.game.bindChatCommand( "/clear", {}, "cl_onChatCommand", "Remove all shapes in the world. It must first be enabled with /allowclear" )
	end

	sm.game.setTimeOfDay( 0.5 )
	sm.render.setOutdoorLighting( 0.5 )

	if g_unitManager == nil then
		assert( not sm.isHost )
		g_unitManager = UnitManager()
	end
	g_unitManager:cl_onCreate()
end

function CreativeGame.client_showMessage( self, params )
	sm.gui.chatMessage( params )
end

function CreativeGame.cl_onClearConfirmButtonClick( self, name )
	if name == "Yes" then
		self.cl.confirmClearGui:close()
		self.network:sendToServer( "sv_clear" )
	elseif name == "No" then
		self.cl.confirmClearGui:close()
	end
	self.cl.confirmClearGui = nil
end

function CreativeGame.sv_clear( self, _, player )
	if player.character and sm.exists( player.character ) then
		sm.event.sendToWorld( player.character:getWorld(), "sv_e_clear" )
	end
end

function CreativeGame.cl_onChatCommand( self, params )
	if params[1] == "/place" then
		local range = 7.5
		local success, result = sm.localPlayer.getRaycast( range )
		if success then
			params.aimPosition = result.pointWorld
		else
			params.aimPosition = sm.localPlayer.getRaycastStart() + sm.localPlayer.getDirection() * range
		end
		self.network:sendToServer( "sv_n_onChatCommand", params )
	elseif params[1] == "/allowclear" then
		local clearEnabled = not self.clearEnabled
		if type( params[2] ) == "boolean" then
			clearEnabled = params[2]
		end
		self.clearEnabled = clearEnabled
		sm.gui.chatMessage( "/clear is " .. ( self.clearEnabled and "Enabled" or "Disabled" ) )
	elseif params[1] == "/clear" then
		if self.clearEnabled then
			self.clearEnabled = false
			self.cl.confirmClearGui = sm.gui.createGuiFromLayout( "$GAME_DATA/Gui/Layouts/PopUp/PopUp_YN.layout" )
			self.cl.confirmClearGui:setButtonCallback( "Yes", "cl_onClearConfirmButtonClick" )
			self.cl.confirmClearGui:setButtonCallback( "No", "cl_onClearConfirmButtonClick" )
			self.cl.confirmClearGui:setText( "Title", "#{MENU_YN_TITLE_ARE_YOU_SURE}" )
			self.cl.confirmClearGui:setText( "Message", "#{MENU_YN_MESSAGE_CLEAR_MENU}" )
			self.cl.confirmClearGui:open()
		else
			sm.gui.chatMessage( "/clear is disabled. It must first be enabled with /allowclear" )
		end
	else
		self.network:sendToServer( "sv_n_onChatCommand", params )
	end
end

function CreativeGame.sv_n_onChatCommand( self, params, player )
	if params[1] == "/noaggro" then
		local aggro = not sm.game.getEnableAggro()
		if type( params[2] ) == "boolean" then
			aggro = not params[2]
		end
		sm.game.setEnableAggro( aggro )
		self.network:sendToClients( "client_showMessage", "AGGRO: " .. ( aggro and "On" or "Off" ) )
	elseif params[1] == "/noaggrocreations" then
		local aggroCreations = not g_unitManager:sv_getHostSettings().aggroCreations
		if type( params[2] ) == "boolean" then
			aggroCreations = not params[2]
		end
		g_unitManager:sv_setHostSettings( { aggroCreations = aggroCreations } )
		self.network:sendToClients( "client_showMessage", "AGGRO CREATIONS: " .. ( aggroCreations and "On" or "Off" ) )
	elseif params[1] == "/popcapsules" then
		g_unitManager:sv_openCapsules( params[2] )
	elseif params[1] == "/dropscrap" then
		local disableScrapHarvest = not g_disableScrapHarvest
		if type( params[2] ) == "boolean" then
			disableScrapHarvest = not params[2]
		end
		g_disableScrapHarvest = disableScrapHarvest
		self.network:sendToClients( "client_showMessage", "SCRAP LOOT: " .. ( g_disableScrapHarvest and "Off" or "On" ) )
	elseif params[1] == "/restrictions" then
		local restrictions = not sm.game.getEnableRestrictions()
		if type( params[2] ) == "boolean" then
			restrictions = params[2]
		end
		sm.game.setEnableRestrictions( restrictions )
		self.network:sendToClients( "client_showMessage", "RESTRICTIONS: " .. ( restrictions and "On" or "Off" ) )
	else
		if sm.exists( player.character ) then
			params.player = player
			sm.event.sendToWorld( player.character:getWorld(), "sv_e_onChatCommand", params )
		end
	end
end

function CreativeGame.server_onPlayerJoined( self, player, newPlayer )
    if sm.interop ~= nil then
        -- Load startup scripts for this person
        self.network:sendToClient(player, 'cl_interopLoadStartups', {
            startupScripts = sm.interop.startup.getStartupScripts()
        })

        -- Emit playerJoined event
        sm.interop.events.emit('scrapmechanic:playerJoined', {
            player = player,
            newPlayer = newPlayer
        }, 'both', true)
    end
end

function CreativeGame.cl_interopLoadStartups(self, params)
    sm.interop.startup.restoreStartupScripts(params.startupScripts)
    self.network:sendToServer('sv_interopLoadStartups', {})
end

function CreativeGame.sv_interopLoadStartups(self, params)
    sm.interop.startup.startRunOldScripts()
end

function CreativeGame.client_onUpdate(self, dt)
    if sm.interop ~= nil then
        local toRegister = sm.interop.commands.getCommandsToRegister()
        if toRegister ~= nil then
            if v ~= 'mod' then
                for i,commandName in ipairs(toRegister) do
                    sm.game.bindChatCommand('/'..commandName, self.interop_newCommandArguments, 'cl_onInteropCommand2', 'Executes the '..commandName..' command')
                end
            end
        end
    end
end

function CreativeGame.cl_onInteropCommand(self, params)
    if sm.interop == nil then
        sm.gui.chatMessage('#ff0000Error: #ffffffMod "sm.interop" is missing, or no part using the coremod has been placed in the world yet.')
        return
    end
    if not params[2] then
        sm.gui.chatMessage('#ff0000Syntax: #ffffff/mod <commandName> [arguments...]')
        return
    end
    local commandName = params[2]
    local args = {unpack(params, 3)}
    local world = sm.localPlayer.getPlayer():getCharacter():getWorld()
    self.network:sendToServer('sv_interopCommandExecute', {
        player = sm.localPlayer.getPlayer(),
        commandName = commandName,
        args = args
    })
    if sm.interopGamefileModVersion < 3 then
        sm.gui.chatMessage('#ff0000Error: Due to a bug, custom mod commands do not work in custom creative worlds. You have to update sm.interop in order to fix this. Go to the sm.interop Steam Workshop page to read how to do this.')
    end
end

function CreativeGame.cl_onInteropCommand2(self, params)
    if sm.interop == nil then
        sm.gui.chatMessage('#ff0000Error: #ffffffMod "sm.interop" is missing, or no part using the coremod has been placed in the world yet.')
        return
    end
    local commandName = params[1]:sub(2)
    local args = {unpack(params, 2)}
    self.network:sendToServer('sv_interopCommandExecute', {
        player = sm.localPlayer.getPlayer(),
        commandName = commandName,
        args = args
    })
    if sm.interopGamefileModVersion < 3 then
        sm.gui.chatMessage('#ff0000Error: Due to a bug, custom mod commands do not work in custom creative worlds. You have to update sm.interop in order to fix this. Go to the sm.interop Steam Workshop page to read how to do this.')
    end
end

function CreativeGame.sv_interopCommandExecute(self, params)
    local world = params.player:getCharacter():getWorld()
    sm.event.sendToWorld(world, 'sv_interopCommandExecute', params)
end
