--   _____ ____  _____  ______ _  _____    _____  _____   ____  _____  _    _ ______          _   _______ _    _ 
--  / ____/ __ \|  __ \|  ____( )/ ____|  |  __ \|  __ \ / __ \|  __ \| |  | |  ____|   /\   | | |__   __| |  | |
-- | |   | |  | | |__) | |__  |/| (___    | |__) | |__) | |  | | |__) | |__| | |__     /  \  | |    | |  | |__| |
-- | |   | |  | |  _  /|  __|    \___ \   |  ___/|  _  /| |  | |  ___/|  __  |  __|   / /\ \ | |    | |  |  __  |
-- | |___| |__| | | \ \| |____   ____) |  | |    | | \ \| |__| | |    | |  | | |____ / ____ \| |____| |  | |  | |
--  \_____\____/|_|  \_\______| |_____/   |_|    |_|  \_\\____/|_|    |_|  |_|______/_/    \_\______|_|  |_|  |_|
--
-- Thank you for using my addon <3
-- Use it wisely...
                                                                                                               

-- Configuration Table
PropHealthConfig = PropHealthConfig or {
    enabled = true, -- Enable the prop health / reinforcement mechanic                                                   Default: true
    defaultPropHealth = 100, -- The default health of every newely spawned prop                                          Default: 100
    setCostPerHP = 5, -- How much money it cost per 1HP                                                                  Default: 5
    repairCostPerHP = 2, -- How much money it cost per repair 1HP                                                        Default: 2
    toolgunCooldown = 1, -- Toolgun usage cooldown on Prop reinforcement                                                 Default: 1
    maxDamagePerHit = 25, -- Global damage value for every weapon                                                        Default: 25
    minHealthToRestore = 1, -- The minimum repair health for the prop to not be destroyed                                Default: 1
    destroyedTransparency = 64, -- 0-255 (64 = 25%) Transparency value for destroyed prop                                Default: 64
    destroyedColor = Color(255, 0, 0), -- Red prop color when destroyed                                                  Default: Color(255, 0, 0)
    useIntegerValues = true, -- Use integer values instead of floats (Full number instead of a decimal number/value)     Default: true
    useWeaponDamage = false, -- Use weapon's real damage instead of max damage cap                                       Default: false
    allowToolgunOnDestroyed = false, -- Allow toolgun use on destroyed props (Editing the prop when destroyed)           Default: false
    removeWhenDestroyed = false, -- Remove prop from the world when destroyed                                            Default: false
    uiCooldown = 1.0, -- Cooldown for opening prop menu (seconds)                                                        Default: 1.0
    showHealthToEveryone = true, -- Show health bar to everyone (not just with toolgun)                                  Default: true
    
    -- Max health per usergroup
    maxHealthByGroup = {
        ["user"] = 500,
        ["vip"] = 1500,
        ["moderator"] = 1500,
        ["admin"] = 2500,
        ["superadmin"] = 3000,
    },
    
    -- Weapon blacklist (weapon class names)
    weaponBlacklist = {
        -- Example: ["weapon_crowbar"] = true,
    },
}

if SERVER then
    AddCSLuaFile()
    
    -- Save/Load Config
    local function SaveConfig()
        if not file.Exists("coreprophealth", "DATA") then
            file.CreateDir("coreprophealth")
        end
        file.Write("coreprophealth/config.txt", util.TableToJSON(PropHealthConfig, true))
    end
    
    local function LoadConfig()
        if file.Exists("coreprophealth/config.txt", "DATA") then
            local data = file.Read("coreprophealth/config.txt", "DATA")
            local loaded = util.JSONToTable(data)
            if loaded then
                local oldBlacklist = PropHealthConfig.weaponBlacklist
                PropHealthConfig = table.Merge(PropHealthConfig, loaded)
                PropHealthConfig.weaponBlacklist = loaded.weaponBlacklist or {}
            end
        else
            SaveConfig()
        end
    end
    
    LoadConfig()
    
    -- Network strings
    util.AddNetworkString("PropHealth_SetHealth")
    util.AddNetworkString("PropHealth_Repair")
    util.AddNetworkString("PropHealth_OpenMenu")
    util.AddNetworkString("PropHealth_SyncConfig")
    util.AddNetworkString("PropHealth_UpdateConfig")
    
    -- Send config to client
    local function SyncConfig(ply)
        net.Start("PropHealth_SyncConfig")
            net.WriteTable(PropHealthConfig)
        if ply then
            net.Send(ply)
        else
            net.Broadcast()
        end
    end
    
    hook.Add("PlayerInitialSpawn", "PropHealth_SyncOnJoin", function(ply)
        timer.Simple(1, function()
            if IsValid(ply) then
                SyncConfig(ply)
            end
        end)
    end)
    
    -- Update config from admin panel
    net.Receive("PropHealth_UpdateConfig", function(len, ply)
        if not ply:IsAdmin() then return end
        
        local newConfig = net.ReadTable()
        PropHealthConfig = newConfig
        SaveConfig()
        SyncConfig()
        
        DarkRP.notify(ply, 0, 4, "Prop Health config updated!")
    end)
    
    -- Cooldown tracking
    local playerCooldowns = {}
    local playerUICooldowns = {}
    
    -- Get max health for player's usergroup
    local function GetMaxHealthForPlayer(ply)
        local group = ply:GetUserGroup()
        return PropHealthConfig.maxHealthByGroup[group] or PropHealthConfig.maxHealthByGroup["user"] or 500
    end
    
    -- Initialize prop health when spawned
    hook.Add("PlayerSpawnedProp", "PropHealth_Initialize", function(ply, model, ent)
        if not PropHealthConfig.enabled then return end
        if IsValid(ent) then
            ent:SetNWInt("PropHealth", PropHealthConfig.defaultPropHealth)
            ent:SetNWInt("PropMaxHealth", PropHealthConfig.defaultPropHealth)
            ent:SetNWString("PropOwnerSID", ply:SteamID())
            ent:SetNWBool("PropDestroyed", false)
        end
    end)
    
    -- Handle prop damage
    hook.Add("EntityTakeDamage", "PropHealth_TakeDamage", function(ent, dmg)
        if not PropHealthConfig.enabled then return end
        if not IsValid(ent) or not ent:IsValid() then return end
        if ent:IsPlayer() or ent:IsNPC() or ent:IsVehicle() then return end
        
        -- Check if weapon is blacklisted
        local attacker = dmg:GetAttacker()
        if IsValid(attacker) and attacker:IsPlayer() then
            local weapon = attacker:GetActiveWeapon()
            if IsValid(weapon) then
                local weaponClass = weapon:GetClass()
                if PropHealthConfig.weaponBlacklist[weaponClass] then
                    return -- Ignore damage from blacklisted weapons
                end
            end
        end
        
        -- Check if this prop has health system enabled
        local maxHealth = ent:GetNWInt("PropMaxHealth", 0)
        if maxHealth <= 0 then return end
        
        local currentHealth = ent:GetNWInt("PropHealth", 0)
        if currentHealth <= 0 then return end
        if ent:GetNWBool("PropDestroyed", false) then 
            dmg:SetDamage(0)
            return true
        end
        
        -- Calculate damage
        local originalDamage = dmg:GetDamage()
        local cappedDamage
        
        if PropHealthConfig.useWeaponDamage then
            cappedDamage = originalDamage -- Use actual weapon damage
        else
            cappedDamage = math.min(originalDamage, PropHealthConfig.maxDamagePerHit) -- Use cap
        end
        
        -- Apply integer rounding if enabled
        if PropHealthConfig.useIntegerValues then
            cappedDamage = math.floor(cappedDamage)
        end
        
        -- Actually modify the damage dealt to prevent prop physics breaking
        dmg:SetDamage(0)
        
        local newHealth = math.max(0, currentHealth - cappedDamage)
        
        ent:SetNWInt("PropHealth", newHealth)
        
        if newHealth <= 0 then
            if PropHealthConfig.removeWhenDestroyed then
                -- Remove prop completely
                ent:Remove()
                local ownerSID = ent:GetNWString("PropOwnerSID", "")
                if ownerSID != "" then
                    local owner = player.GetBySteamID(ownerSID)
                    if IsValid(owner) then
                        DarkRP.notify(owner, 1, 4, "Your prop was destroyed and removed!")
                    end
                end
            else
                -- Make prop destroyed state
                ent:SetNWBool("PropDestroyed", true)
                ent:SetRenderMode(RENDERMODE_TRANSALPHA)
                local col = PropHealthConfig.destroyedColor
                ent:SetColor(Color(col.r, col.g, col.b, PropHealthConfig.destroyedTransparency))
                ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
                
                local ownerSID = ent:GetNWString("PropOwnerSID", "")
                if ownerSID != "" then
                    local owner = player.GetBySteamID(ownerSID)
                    if IsValid(owner) then
                        DarkRP.notify(owner, 1, 4, "Your prop was destroyed! Use the toolgun to repair it.")
                    end
                end
            end
        end
        
        return true
    end)
    
    -- Helper function to check cooldown
    local function IsOnCooldown(ply)
        if PropHealthConfig.toolgunCooldown <= 0 then return false end
        local steamid = ply:SteamID()
        if playerCooldowns[steamid] and playerCooldowns[steamid] > CurTime() then
            return true
        end
        return false
    end
    
    -- Helper function to set cooldown
    local function SetCooldown(ply)
        local steamid = ply:SteamID()
        playerCooldowns[steamid] = CurTime() + PropHealthConfig.toolgunCooldown
    end
    
    -- Helper function to check UI cooldown
    local function IsOnUICooldown(ply)
        if PropHealthConfig.uiCooldown <= 0 then return false end
        local steamid = ply:SteamID()
        if playerUICooldowns[steamid] and playerUICooldowns[steamid] > CurTime() then
            return true
        end
        return false
    end
    
    -- Helper function to set UI cooldown
    local function SetUICooldown(ply)
        local steamid = ply:SteamID()
        playerUICooldowns[steamid] = CurTime() + PropHealthConfig.uiCooldown
    end
    
    -- Open reinforcement menu server request
    net.Receive("PropHealth_OpenMenu", function(len, ply)
        local ent = net.ReadEntity()
        if not IsValid(ent) or not IsValid(ply) then return end
        
        if IsOnUICooldown(ply) then
            DarkRP.notify(ply, 1, 3, "Please wait before opening the menu again!")
            return
        end
        
        if ent:GetNWString("PropOwnerSID", "") != ply:SteamID() then
            DarkRP.notify(ply, 1, 4, "You don't own this prop!")
            return
        end
        
        SetUICooldown(ply)
        
        -- Send prop data back
        net.Start("PropHealth_OpenMenu")
            net.WriteEntity(ent)
            net.WriteInt(ent:GetNWInt("PropHealth", 0), 16)
            net.WriteInt(ent:GetNWInt("PropMaxHealth", 0), 16)
            net.WriteBool(ent:GetNWBool("PropDestroyed", false))
            net.WriteInt(GetMaxHealthForPlayer(ply), 16)
        net.Send(ply)
    end)
    
    -- Set prop max health
    net.Receive("PropHealth_SetHealth", function(len, ply)
        if not PropHealthConfig.enabled then return end
        local ent = net.ReadEntity()
        local newMaxHealth = net.ReadInt(16)
        
        if not IsValid(ent) or not IsValid(ply) then return end
        
        if IsOnCooldown(ply) then return end
        
        if ent:GetNWString("PropOwnerSID", "") != ply:SteamID() then
            DarkRP.notify(ply, 1, 4, "You don't own this prop!")
            SetCooldown(ply)
            return
        end
        
        if newMaxHealth <= 0 then return end
        
        local playerMaxHealth = GetMaxHealthForPlayer(ply)
        if newMaxHealth > playerMaxHealth then
            newMaxHealth = playerMaxHealth
        end
        
        local currentMaxHealth = ent:GetNWInt("PropMaxHealth", PropHealthConfig.defaultPropHealth)
        
        if newMaxHealth == currentMaxHealth then
            DarkRP.notify(ply, 1, 4, "Prop is already at " .. newMaxHealth .. " HP!")
            SetCooldown(ply)
            return
        end
        
        local totalCost = newMaxHealth * PropHealthConfig.setCostPerHP
        
        if not ply:canAfford(totalCost) then
            DarkRP.notify(ply, 1, 4, "You can't afford this! Cost: " .. DarkRP.formatMoney(totalCost))
            SetCooldown(ply)
            return
        end
        
        ply:addMoney(-totalCost)
        ent:SetNWInt("PropMaxHealth", newMaxHealth)
        ent:SetNWInt("PropHealth", newMaxHealth)
        
        DarkRP.notify(ply, 0, 4, "Prop max health set to " .. newMaxHealth .. " HP for " .. DarkRP.formatMoney(totalCost))
        SetCooldown(ply)
    end)
    
    -- Repair prop
    net.Receive("PropHealth_Repair", function(len, ply)
        if not PropHealthConfig.enabled then return end
        local ent = net.ReadEntity()
        local repairPercent = net.ReadFloat()
        
        if not IsValid(ent) or not IsValid(ply) then return end
        
        if IsOnCooldown(ply) then return end
        
        if ent:GetNWString("PropOwnerSID", "") != ply:SteamID() then
            DarkRP.notify(ply, 1, 4, "You don't own this prop!")
            SetCooldown(ply)
            return
        end
        
        local currentHealth = ent:GetNWInt("PropHealth", 0)
        local maxHealth = ent:GetNWInt("PropMaxHealth", PropHealthConfig.defaultPropHealth)
        local isDestroyed = ent:GetNWBool("PropDestroyed", false)
        
        if currentHealth >= maxHealth and not isDestroyed then
            DarkRP.notify(ply, 1, 4, "This prop is already at full health!")
            SetCooldown(ply)
            return
        end
        
        -- Calculate repair amount based on percentage
        repairPercent = math.Clamp(repairPercent, 0, 1)
        local healthNeeded = (maxHealth - currentHealth) * repairPercent
        
        -- Apply integer rounding if enabled
        if PropHealthConfig.useIntegerValues then
            healthNeeded = math.floor(healthNeeded)
        end
        
        local repairCost = healthNeeded * PropHealthConfig.repairCostPerHP
        
        if repairCost <= 0 then
            DarkRP.notify(ply, 1, 4, "Nothing to repair!")
            SetCooldown(ply)
            return
        end
        
        if not ply:canAfford(repairCost) then
            DarkRP.notify(ply, 1, 4, "You can't afford repairs! Cost: " .. DarkRP.formatMoney(repairCost))
            SetCooldown(ply)
            return
        end
        
        ply:addMoney(-repairCost)
        local newHealth = math.min(currentHealth + healthNeeded, maxHealth)
        ent:SetNWInt("PropHealth", newHealth)
        
        -- Restore prop if it was destroyed and repaired above threshold
        if isDestroyed and newHealth >= PropHealthConfig.minHealthToRestore then
            ent:SetNWBool("PropDestroyed", false)
            ent:SetRenderMode(RENDERMODE_NORMAL)
            ent:SetColor(Color(255, 255, 255, 255))
            ent:SetCollisionGroup(COLLISION_GROUP_NONE)
        end
        
        DarkRP.notify(ply, 0, 4, "Prop repaired +" .. healthNeeded .. " HP for " .. DarkRP.formatMoney(repairCost) .. "!")
        SetCooldown(ply)
    end)
    
    -- Allow physgun pickup of destroyed props by owner
    hook.Add("PhysgunPickup", "PropHealth_AllowPickup", function(ply, ent)
        if ent:GetNWBool("PropDestroyed", false) then
            if ent:GetNWString("PropOwnerSID", "") == ply:SteamID() then
                return true
            end
        end
    end)
    
    -- Clean up cooldowns when player disconnects
    hook.Add("PlayerDisconnected", "PropHealth_CleanupCooldown", function(ply)
        local steamid = ply:SteamID()
        if playerCooldowns[steamid] then
            playerCooldowns[steamid] = nil
        end
        if playerUICooldowns[steamid] then
            playerUICooldowns[steamid] = nil
        end
    end)
    
    -- Admin command to open config
    concommand.Add("prophealthconfig", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        net.Start("PropHealth_SyncConfig")
            net.WriteTable(PropHealthConfig)
        net.Send(ply)
    end)

    -- Prevent toolgun use on destroyed props (if configured)
    hook.Add("CanTool", "PropHealth_PreventToolgunOnDestroyed", function(ply, trace, tool)
        local ent = trace.Entity
        if IsValid(ent) and ent:GetNWBool("PropDestroyed", false) then
            if not PropHealthConfig.allowToolgunOnDestroyed and tool != "prophealthtool" then
                DarkRP.notify(ply, 1, 3, "You cannot use tools on destroyed props! Repair it first.")
                return false
            end
        end
    end)

    -- Admin command to reload config
    concommand.Add("prophealthreload", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then return end
        LoadConfig()
        SyncConfig()
        if IsValid(ply) then
            DarkRP.notify(ply, 0, 4, "Prop Health config reloaded from file!")
        else
            print("[Core_PropHealth] Config reloaded from file!")
        end
    end)
end

if CLIENT then

    language.Add("tool.prophealthtool.name", "Prop Reinforcement")
    language.Add("tool.prophealthtool.desc", "Set prop health and/or repair your props")
    language.Add("tool.prophealthtool.0", "Left click: Open reinforcement menu")

    -- Modern flat UI colors
    local UI = {
        primary = Color(41, 128, 185),
        success = Color(46, 204, 113),
        danger = Color(231, 76, 60),
        background = Color(44, 62, 80),
        surface = Color(52, 73, 94),
        text = Color(236, 240, 241),
        textDark = Color(149, 165, 166),
        border = Color(127, 140, 141, 100),
    }

    -- Receive config from server
    PropHealthConfig = PropHealthConfig or {}
    
    net.Receive("PropHealth_SyncConfig", function()
        PropHealthConfig = net.ReadTable()
    end)

    hook.Add("OnPlayerChat", "PropHealth_ChatCommand", function(ply, text, team, isdead)
        if ply == LocalPlayer() then
            if string.lower(text) == "!prophealthconfig" then
                if LocalPlayer():IsAdmin() then
                    isOpeningConfig = true
                    RunConsoleCommand("prophealthconfig")
                end
                return true
            end
            if string.lower(text) == "!prophealthreload" then
                if LocalPlayer():IsAdmin() then
                    RunConsoleCommand("prophealthreload")
                end
                return true
            end
        end
    end)
    
    -- Prop menu
    local propMenu = nil
    local currentProp = nil
    
    net.Receive("PropHealth_OpenMenu", function()
        local ent = net.ReadEntity()
        local currentHP = net.ReadInt(16)
        local maxHP = net.ReadInt(16)
        local isDestroyed = net.ReadBool()
        local playerMaxHP = net.ReadInt(16)
        
        if IsValid(propMenu) then propMenu:Close() end
        
        currentProp = ent
        
        local w, h = 500, 300
        propMenu = vgui.Create("DFrame")
        propMenu:SetSize(w, h)
        propMenu:Center()
        propMenu:SetTitle("")
        propMenu:SetDraggable(true)
        propMenu:ShowCloseButton(false)
        propMenu:MakePopup()
        
        function propMenu:Paint(w, h)
            draw.RoundedBox(8, 0, 0, w, h, UI.background)
            draw.RoundedBox(8, 0, 0, w, 40, UI.surface)
            draw.SimpleText("Prop Reinforcement", "DermaLarge", w/2, 20, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        -- Close button
        local closeBtn = vgui.Create("DButton", propMenu)
        closeBtn:SetPos(w - 35, 5)
        closeBtn:SetSize(30, 30)
        closeBtn:SetText("✕")
        closeBtn:SetFont("DermaLarge")
        closeBtn:SetTextColor(UI.text)
        function closeBtn:Paint(w, h)
            if self:IsHovered() then
                draw.RoundedBox(4, 0, 0, w, h, UI.danger)
            end
        end
        closeBtn.DoClick = function()
            propMenu:Close()
        end
        
        -- Health info
        local infoPanel = vgui.Create("DPanel", propMenu)
        infoPanel:SetPos(20, 50)
        infoPanel:SetSize(w - 40, 60)
        function infoPanel:Paint(w, h)
            draw.RoundedBox(6, 0, 0, w, h, UI.surface)
            
            local healthFrac = currentHP / maxHP
            draw.RoundedBox(4, 5, 30, w - 10, 20, Color(30, 30, 30))
            draw.RoundedBox(4, 5, 30, (w - 10) * healthFrac, 20, UI.success)
            
            draw.SimpleText("Current Health: " .. currentHP .. " / " .. maxHP .. " HP", "DermaDefault", w/2, 10, UI.text, TEXT_ALIGN_CENTER)
            draw.SimpleText(math.floor(healthFrac * 100) .. "%", "DermaDefault", w/2, 40, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        -- Set Health Section
        local setLabel = vgui.Create("DLabel", propMenu)
        setLabel:SetPos(20, 120)
        setLabel:SetSize(w - 40, 20)
        setLabel:SetText("Set Max Health (Max: " .. playerMaxHP .. " HP)")
        setLabel:SetTextColor(UI.text)
        setLabel:SetFont("DermaDefaultBold")
        
        local healthSlider = vgui.Create("DNumSlider", propMenu)
        healthSlider:SetPos(20, 140)
        healthSlider:SetSize(w - 40, 30)
        healthSlider:SetText("")
        healthSlider:SetMin(50)
        healthSlider:SetMax(playerMaxHP)
        healthSlider:SetDecimals(0)
        healthSlider:SetValue(maxHP)
        healthSlider.Label:SetTextColor(UI.text)
        
        -- Repair Section
        local repairLabel = vgui.Create("DLabel", propMenu)
        repairLabel:SetPos(20, 180)
        repairLabel:SetSize(w - 40, 20)
        repairLabel:SetText("Repair Percentage")
        repairLabel:SetTextColor(UI.text)
        repairLabel:SetFont("DermaDefaultBold")

        local repairSlider = vgui.Create("DNumSlider", propMenu)
        repairSlider:SetPos(20, 200)
        repairSlider:SetSize(w - 40, 30)
        repairSlider:SetText("")
        repairSlider:SetMin(0)
        repairSlider:SetMax(100)
        repairSlider:SetDecimals(0)
        repairSlider:SetValue(100)
        repairSlider.Label:SetTextColor(UI.text)
        
        local lastSetClick = 0
        local lastRepairClick = 0
        local BUTTON_COOLDOWN = 2 -- 2 second cooldown between button clicks

        local setBtn = vgui.Create("DButton", propMenu)
        setBtn:SetPos(20, h - 55)
        setBtn:SetSize((w - 50) / 2, 35)
        setBtn:SetText("")
        function setBtn:Paint(w, h)
            local timeLeft = BUTTON_COOLDOWN - (CurTime() - lastSetClick)
            if timeLeft > 0 then
                local col = Color(100, 100, 100)
                draw.RoundedBox(6, 0, 0, w, h, col)
                draw.SimpleText(string.format("Wait: %.1fs", timeLeft), "DermaDefaultBold", w/2, h/2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                local col = self:IsHovered() and Color(52, 152, 219) or UI.primary
                draw.RoundedBox(6, 0, 0, w, h, col)
                local hp = healthSlider:GetValue()
                local cost = hp * PropHealthConfig.setCostPerHP
                draw.SimpleText("Set HP: $" .. cost, "DermaDefaultBold", w/2, h/2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        setBtn.DoClick = function()
            if CurTime() - lastSetClick < BUTTON_COOLDOWN then return end
            lastSetClick = CurTime()
            
            net.Start("PropHealth_SetHealth")
                net.WriteEntity(currentProp)
                net.WriteInt(healthSlider:GetValue(), 16)
            net.SendToServer()
            propMenu:Close()
        end

        local repairBtn = vgui.Create("DButton", propMenu)
        repairBtn:SetPos((w / 2) + 10, h - 55)
        repairBtn:SetSize((w - 50) / 2, 35)
        repairBtn:SetText("")
        function repairBtn:Paint(w, h)
            local timeLeft = BUTTON_COOLDOWN - (CurTime() - lastRepairClick)
            if timeLeft > 0 then
                local col = Color(100, 100, 100)
                draw.RoundedBox(6, 0, 0, w, h, col)
                draw.SimpleText(string.format("Wait: %.1fs", timeLeft), "DermaDefaultBold", w/2, h/2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                local col = self:IsHovered() and Color(39, 174, 96) or UI.success
                draw.RoundedBox(6, 0, 0, w, h, col)
                local percent = repairSlider:GetValue() / 100
                local healthNeeded = (maxHP - currentHP) * percent
                if PropHealthConfig.useIntegerValues then
                    healthNeeded = math.floor(healthNeeded)
                end
                local cost = healthNeeded * PropHealthConfig.repairCostPerHP
                draw.SimpleText("Repair: $" .. cost, "DermaDefaultBold", w/2, h/2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        repairBtn.DoClick = function()
            if CurTime() - lastRepairClick < BUTTON_COOLDOWN then return end
            lastRepairClick = CurTime()
            
            net.Start("PropHealth_Repair")
                net.WriteEntity(currentProp)
                net.WriteFloat(repairSlider:GetValue() / 100)
            net.SendToServer()
            propMenu:Close()
        end
    end)
    
    -- Create the toolgun
    TOOL.Category = "Construction"
    TOOL.Name = "#Prop Reinforcement"
    TOOL.Command = nil
    TOOL.ConfigName = ""
    
    local lastToolgunUse = 0

    function TOOL:LeftClick(trace)
        if SERVER then return false end
        if not PropHealthConfig.enabled then return false end
        
        -- Client-side cooldown check
        if CurTime() - lastToolgunUse < 0.5 then
            return false
        end
        
        local ent = trace.Entity
        if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWorld() then return false end
        
        lastToolgunUse = CurTime()
        
        -- Request menu from server
        net.Start("PropHealth_OpenMenu")
            net.WriteEntity(ent)
        net.SendToServer()
        
        return true
    end
    
    function TOOL:RightClick(trace)
        return false
    end
    
    function TOOL:DrawHUD()
        local trace = LocalPlayer():GetEyeTrace()
        local ent = trace.Entity
        
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsWorld() then
            local currentHealth = ent:GetNWInt("PropHealth", 0)
            local maxHealth = ent:GetNWInt("PropMaxHealth", 0)
            
            if maxHealth > 0 then
                local scrW, scrH = ScrW(), ScrH()
                local barW, barH = 250, 30
                local barX, barY = scrW / 2 - barW / 2, scrH / 2 + 60
                
                -- Background
                draw.RoundedBox(6, barX, barY, barW, barH, Color(0, 0, 0, 200))
                
                -- Health bar
                local healthFrac = math.Clamp(currentHealth / maxHealth, 0, 1)
                draw.RoundedBox(4, barX + 2, barY + 2, (barW - 4) * healthFrac, barH - 4, UI.success)
                
                -- Text
                draw.SimpleText(currentHealth .. " / " .. maxHealth .. " HP", "DermaDefaultBold", 
                    scrW / 2, barY + barH/2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    
                draw.SimpleText("Left Click: Open Menu", "DermaDefault",
                    scrW / 2, barY - 10, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
            end
        end
    end

    -- Show health bar to everyone if enabled
    hook.Add("HUDPaint", "PropHealth_ShowHealthBar", function()
        if not PropHealthConfig.showHealthToEveryone then return end
        if not PropHealthConfig.enabled then return end
        
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        
        local trace = ply:GetEyeTrace()
        local ent = trace.Entity
        
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsWorld() then
            local currentHealth = ent:GetNWInt("PropHealth", 0)
            local maxHealth = ent:GetNWInt("PropMaxHealth", 0)
            
            if maxHealth > 0 then
                local scrW, scrH = ScrW(), ScrH()
                local barW, barH = 250, 30
                local barX, barY = scrW / 2 - barW / 2, scrH / 2 + 60
                
                -- Background
                draw.RoundedBox(6, barX, barY, barW, barH, Color(0, 0, 0, 200))
                
                -- Health bar
                local healthFrac = math.Clamp(currentHealth / maxHealth, 0, 1)
                draw.RoundedBox(4, barX + 2, barY + 2, (barW - 4) * healthFrac, barH - 4, UI.success)
                
                -- Text
                draw.SimpleText(currentHealth .. " / " .. maxHealth .. " HP", "DermaDefaultBold", 
                    scrW / 2, barY + barH/2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end)
    
    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", {Description = "Left click on props to open the reinforcement menu"})
        
        if LocalPlayer():IsAdmin() then
            panel:AddControl("Button", {
                Label = "Open Config (Admin)",
                Command = "prophealthconfig"
            })
        end
    end
    
    local isOpeningConfig = false

    -- Admin Config Menu
    net.Receive("PropHealth_SyncConfig", function()
        local config = net.ReadTable()
        
        if not LocalPlayer():IsAdmin() then return end
        if not isOpeningConfig then
            isOpeningConfig = true
            return
        end

        isOpeningConfig = false
        
        local w, h = 700, 1000
        local configMenu = vgui.Create("DFrame")
        configMenu:SetSize(w, h)
        configMenu:Center()
        configMenu:SetTitle("")
        configMenu:SetDraggable(true)
        configMenu:ShowCloseButton(false)
        configMenu:MakePopup()
        
        function configMenu:Paint(w, h)
            draw.RoundedBox(8, 0, 0, w, h, UI.background)
            draw.RoundedBox(8, 0, 0, w, 40, UI.surface)
            draw.SimpleText("Prop Health Configuration", "DermaLarge", w/2, 20, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        -- Close button
        local closeBtn = vgui.Create("DButton", configMenu)
        closeBtn:SetPos(w - 35, 5)
        closeBtn:SetSize(30, 30)
        closeBtn:SetText("✕")
        closeBtn:SetFont("DermaLarge")
        closeBtn:SetTextColor(UI.text)
        function closeBtn:Paint(w, h)
            if self:IsHovered() then
                draw.RoundedBox(4, 0, 0, w, h, UI.danger)
            end
        end
        closeBtn.DoClick = function()
            configMenu:Close()
        end
        
        -- Scroll panel
        local scroll = vgui.Create("DScrollPanel", configMenu)
        scroll:SetPos(10, 50)
        scroll:SetSize(w - 20, h - 110)
        
        local y = 10
        
        -- Helper function to add labeled control
        local function AddControl(label, control, height)
            local lbl = vgui.Create("DLabel", scroll)
            lbl:SetPos(10, y)
            lbl:SetSize(w - 40, 20)
            lbl:SetText(label)
            lbl:SetTextColor(UI.text)
            lbl:SetFont("DermaDefaultBold")
            
            control:SetParent(scroll)
            control:SetPos(10, y + 25)
            control:SetSize(w - 40, height)
            
            y = y + height + 35
            return control
        end
        
        -- Enable/Disable
        local enableCheck = vgui.Create("DCheckBoxLabel")
        enableCheck:SetText("Enable Prop Health System")
        enableCheck:SetValue(config.enabled)
        enableCheck.Label:SetTextColor(UI.text)
        AddControl("System Toggle", enableCheck, 20)
        
        -- Use Integer Values
        local integerCheck = vgui.Create("DCheckBoxLabel")
        integerCheck:SetText("Use Integer Values (No Decimals)")
        integerCheck:SetValue(config.useIntegerValues or true)
        integerCheck.Label:SetTextColor(UI.text)
        AddControl("Integer Mode", integerCheck, 20)
        
        -- Use Weapon Damage
        local weaponDmgCheck = vgui.Create("DCheckBoxLabel")
        weaponDmgCheck:SetText("Use Weapon's Actual Damage (Ignore Max Damage Cap)")
        weaponDmgCheck:SetValue(config.useWeaponDamage or false)
        weaponDmgCheck.Label:SetTextColor(UI.text)
        AddControl("Weapon Damage Mode", weaponDmgCheck, 20)
        
        -- Allow Toolgun on Destroyed
        local allowToolgunCheck = vgui.Create("DCheckBoxLabel")
        allowToolgunCheck:SetText("Allow Toolgun Use on Destroyed Props")
        allowToolgunCheck:SetValue(config.allowToolgunOnDestroyed or false)
        allowToolgunCheck.Label:SetTextColor(UI.text)
        AddControl("Toolgun on Destroyed", allowToolgunCheck, 20)
        
        -- Remove When Destroyed
        local removeCheck = vgui.Create("DCheckBoxLabel")
        removeCheck:SetText("Remove Props When Destroyed (Instead of Making Transparent)")
        removeCheck:SetValue(config.removeWhenDestroyed or false)
        removeCheck.Label:SetTextColor(UI.text)
        AddControl("Remove When Destroyed", removeCheck, 20)

        -- Show Health to Everyone
        local showHealthCheck = vgui.Create("DCheckBoxLabel")
        showHealthCheck:SetText("Show Prop Health Bar to Everyone")
        showHealthCheck:SetValue(config.showHealthToEveryone or false)
        showHealthCheck.Label:SetTextColor(UI.text)
        AddControl("Show Health bar globally", showHealthCheck, 20)
        
        -- Default Health
        local defaultHP = vgui.Create("DNumSlider")
        defaultHP:SetText("")
        defaultHP:SetMin(10)
        defaultHP:SetMax(1000)
        defaultHP:SetDecimals(0)
        defaultHP:SetValue(config.defaultPropHealth)
        defaultHP.Label:SetTextColor(UI.text)
        AddControl("Default Prop Health", defaultHP, 30)
        
        -- Set Cost
        local setCost = vgui.Create("DNumSlider")
        setCost:SetText("")
        setCost:SetMin(1)
        setCost:SetMax(100)
        setCost:SetDecimals(0)
        setCost:SetValue(config.setCostPerHP)
        setCost.Label:SetTextColor(UI.text)
        AddControl("Set Health Cost (per HP)", setCost, 30)
        
        -- Repair Cost
        local repairCost = vgui.Create("DNumSlider")
        repairCost:SetText("")
        repairCost:SetMin(1)
        repairCost:SetMax(100)
        repairCost:SetDecimals(0)
        repairCost:SetValue(config.repairCostPerHP)
        repairCost.Label:SetTextColor(UI.text)
        AddControl("Repair Cost (per HP)", repairCost, 30)
        
        -- Cooldown
        local cooldown = vgui.Create("DNumSlider")
        cooldown:SetText("")
        cooldown:SetMin(0)
        cooldown:SetMax(5)
        cooldown:SetDecimals(1)
        cooldown:SetValue(config.toolgunCooldown)
        cooldown.Label:SetTextColor(UI.text)
        AddControl("Toolgun Cooldown (seconds)", cooldown, 30)
        
        -- UI Cooldown
        local uiCooldown = vgui.Create("DNumSlider")
        uiCooldown:SetText("")
        uiCooldown:SetMin(0)
        uiCooldown:SetMax(10)
        uiCooldown:SetDecimals(1)
        uiCooldown:SetValue(config.uiCooldown or 1.0)
        uiCooldown.Label:SetTextColor(UI.text)
        AddControl("UI Open Cooldown (seconds)", uiCooldown, 30)
        
        -- Max Damage Per Hit
        local maxDmg = vgui.Create("DNumSlider")
        maxDmg:SetText("")
        maxDmg:SetMin(1)
        maxDmg:SetMax(500)
        maxDmg:SetDecimals(0)
        maxDmg:SetValue(config.maxDamagePerHit)
        maxDmg.Label:SetTextColor(UI.text)
        AddControl("Max Damage Per Hit (If Not Using Weapon Damage)", maxDmg, 30)
        
        local minRestore = vgui.Create("DNumSlider")
        minRestore:SetText("")
        minRestore:SetMin(1)
        minRestore:SetMax(1000)
        minRestore:SetDecimals(0)
        minRestore:SetValue(config.minHealthToRestore or 1)
        minRestore.Label:SetTextColor(UI.text)
        AddControl("Minimum HP to Restore Destroyed Props", minRestore, 30)

        -- Destroyed Transparency
        local transparency = vgui.Create("DNumSlider")
        transparency:SetText("")
        transparency:SetMin(0)
        transparency:SetMax(255)
        transparency:SetDecimals(0)
        transparency:SetValue(config.destroyedTransparency)
        transparency.Label:SetTextColor(UI.text)
        AddControl("Destroyed Transparency (0-255)", transparency, 30)
        
        -- Destroyed Color
        local colorMixer = vgui.Create("DColorMixer")
        colorMixer:SetColor(config.destroyedColor)
        colorMixer:SetAlphaBar(false)
        colorMixer:SetPalette(false)
        AddControl("Destroyed Prop Color", colorMixer, 120)
        
        -- Max Health by Usergroup
        local groupLabel = vgui.Create("DLabel", scroll)
        groupLabel:SetPos(10, y)
        groupLabel:SetSize(w - 40, 20)
        groupLabel:SetText("Max Health by Usergroup")
        groupLabel:SetTextColor(UI.text)
        groupLabel:SetFont("DermaLarge")
        y = y + 30

        local groupInputs = {}
        local groupPanels = {}

        -- Declare these early so addGroupBtn can reference them
        local blacklistLabel
        local blacklistText
        local addGroupBtn

        local function CreateGroupEntry(group, maxHP, yPos)
            local groupPanel = vgui.Create("DPanel", scroll)
            groupPanel:SetPos(10, yPos)
            groupPanel:SetSize(w - 40, 30)
            function groupPanel:Paint(w, h)
                draw.RoundedBox(4, 0, 0, w, h, UI.surface)
            end
            
            local groupLbl = vgui.Create("DLabel", groupPanel)
            groupLbl:SetPos(10, 5)
            groupLbl:SetSize(120, 20)
            groupLbl:SetText(group)
            groupLbl:SetTextColor(UI.text)
            
            local groupSlider = vgui.Create("DNumSlider", groupPanel)
            groupSlider:SetPos(150, 0)
            groupSlider:SetSize(w - 280, 30)
            groupSlider:SetText("")
            groupSlider:SetMin(100)
            groupSlider:SetMax(10000)
            groupSlider:SetDecimals(0)
            groupSlider:SetValue(maxHP)
            groupSlider.Label:SetTextColor(UI.text)
            
            -- Delete button
            local delBtn = vgui.Create("DButton", groupPanel)
            delBtn:SetPos(w - 130, 2)
            delBtn:SetSize(70, 26)
            delBtn:SetText("Delete")
            delBtn:SetTextColor(UI.text)
            function delBtn:Paint(w, h)
                local col = self:IsHovered() and Color(192, 57, 43) or UI.danger
                draw.RoundedBox(4, 0, 0, w, h, col)
            end
            delBtn.DoClick = function()
                groupInputs[group] = nil
                groupPanel:Remove()
                
                -- Reposition remaining panels
                local newY = 0
                for g, data in pairs(groupInputs) do
                    if IsValid(data.panel) then
                        data.panel:SetPos(10, groupLabel:GetY() + 30 + newY)
                        newY = newY + 35
                    end
                end
                
                -- Reposition add button and blacklist
                local addBtnY = groupLabel:GetY() + 30 + newY
                addGroupBtn:SetPos(10, addBtnY)
                
                local blacklistY = addBtnY + 45
                if IsValid(blacklistLabel) then
                    blacklistLabel:SetPos(10, blacklistY)
                    blacklistY = blacklistY + 30
                end
                if IsValid(blacklistText) then
                    blacklistText:SetPos(10, blacklistY)
                end
            end
            
            groupInputs[group] = {slider = groupSlider, panel = groupPanel}
            return groupPanel
        end

        -- Add existing groups
        for group, maxHP in pairs(config.maxHealthByGroup) do
            CreateGroupEntry(group, maxHP, y)
            y = y + 35
        end

        -- Add new group button
        addGroupBtn = vgui.Create("DButton", scroll)
        addGroupBtn:SetPos(10, y)
        addGroupBtn:SetSize(w - 40, 35)
        addGroupBtn:SetText("")
        function addGroupBtn:Paint(w, h)
            local col = self:IsHovered() and Color(52, 152, 219) or UI.primary
            draw.RoundedBox(6, 0, 0, w, h, col)
            draw.SimpleText("+ Add Usergroup", "DermaDefaultBold", w/2, h/2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        addGroupBtn.DoClick = function()
            Derma_StringRequest(
                "Add Usergroup",
                "Enter usergroup name (e.g., vip, moderator, donator):",
                "",
                function(text)
                    text = string.lower(string.Trim(text))
                    if text == "" then return end
                    if groupInputs[text] then
                        Derma_Message("This usergroup already exists!", "Error", "OK")
                        return
                    end
                    
                    local newY = addGroupBtn:GetY()
                    CreateGroupEntry(text, 500, newY)
                    
                    -- Update positions
                    newY = newY + 35
                    addGroupBtn:SetPos(10, newY)
                    
                    newY = newY + 45
                    if IsValid(blacklistLabel) then
                        blacklistLabel:SetPos(10, newY)
                        newY = newY + 30
                    end
                    if IsValid(blacklistText) then
                        blacklistText:SetPos(10, newY)
                    end
                end
            )
        end

        y = y + 45

        -- Weapon Blacklist (now the variables are assigned)
        blacklistLabel = vgui.Create("DLabel", scroll)
        blacklistLabel:SetPos(10, y)
        blacklistLabel:SetSize(w - 40, 20)
        blacklistLabel:SetText("Weapon Blacklist (one per line)")
        blacklistLabel:SetTextColor(UI.text)
        blacklistLabel:SetFont("DermaLarge")
        y = y + 30

        blacklistText = vgui.Create("DTextEntry", scroll)
        blacklistText:SetPos(10, y)
        blacklistText:SetSize(w - 40, 100)
        blacklistText:SetMultiline(true)

        local blacklistStr = ""
        for weapon, _ in pairs(config.weaponBlacklist) do
            blacklistStr = blacklistStr .. weapon .. "\n"
        end
        blacklistText:SetValue(blacklistStr)

        y = y + 110
        
        -- Save button
        local saveBtn = vgui.Create("DButton", configMenu)
        saveBtn:SetPos(10, h - 50)
        saveBtn:SetSize(w - 20, 40)
        saveBtn:SetText("")
        function saveBtn:Paint(w, h)
            local col = self:IsHovered() and Color(39, 174, 96) or UI.success
            draw.RoundedBox(6, 0, 0, w, h, col)
            draw.SimpleText("Save Configuration", "DermaLarge", w/2, h/2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        saveBtn.DoClick = function()
            -- Build new config
            local newConfig = {
                enabled = enableCheck:GetChecked(),
                useIntegerValues = integerCheck:GetChecked(),
                useWeaponDamage = weaponDmgCheck:GetChecked(),
                allowToolgunOnDestroyed = allowToolgunCheck:GetChecked(),
                removeWhenDestroyed = removeCheck:GetChecked(),
                showHealthToEveryone = showHealthCheck:GetChecked(),
                defaultPropHealth = defaultHP:GetValue(),
                setCostPerHP = setCost:GetValue(),
                repairCostPerHP = repairCost:GetValue(),
                toolgunCooldown = cooldown:GetValue(),
                uiCooldown = uiCooldown:GetValue(),
                maxDamagePerHit = maxDmg:GetValue(),
                minHealthToRestore = minRestore:GetValue(),
                destroyedTransparency = transparency:GetValue(),
                destroyedColor = colorMixer:GetColor(),
                maxHealthByGroup = {},
                weaponBlacklist = {},
            }
            
            for group, data in pairs(groupInputs) do
                if IsValid(data.slider) then
                    newConfig.maxHealthByGroup[group] = data.slider:GetValue()
                end
            end
            
            local blacklist = string.Explode("\n", blacklistText:GetValue())
            for _, weapon in pairs(blacklist) do
                weapon = string.Trim(weapon)
                if weapon != "" then
                    newConfig.weaponBlacklist[weapon] = true
                end
            end
            
            net.Start("PropHealth_UpdateConfig")
                net.WriteTable(newConfig)
            net.SendToServer()
            
            timer.Simple(0.5, function()
                PropHealthConfig = newConfig
            end)

            configMenu:Close()
        end
    end)
end

print("[Core_PropHealth] Loaded version 1.0.0 successfully!")