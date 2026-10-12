-- BRPlayerCharacterBase.lua - Cleaned Game Logic Only
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local KismetMathLibrary = import("KismetMathLibrary")
local GameplayStatics = import("GameplayStatics")
local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")

local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {}
}

BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = { Reliable = true, Params = {} }
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = { Reliable = true, Params = { UEnums.EPropertyClass.Object } }
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = { Reliable = true, Params = { UEnums.EPropertyClass.Int } }
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = { Reliable = true, Params = { UEnums.EPropertyClass.Bool } }
BRPlayerCharacterBase.ClientRPC.ClientRPC_TriggerHighlightMoment = { Reliable = true, Params = { UEnums.EPropertyClass.UInt32, UEnums.EPropertyClass.UInt32 } }

function BRPlayerCharacterBase:ctor()
    self.bHasShownDevNotice = false
end

function BRPlayerCharacterBase:_PostConstruct()
    BRPlayerCharacterBase.__super._PostConstruct(self)
    self:InitAddSpecialMoveInfo()
    self.bCanNearDeathGiveup = true
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
    BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
    self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
    
    if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
        local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
        if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
            Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
        end
    end
    
    if slua.isValid(self.STCharacterMovement) then
        self.STCharacterMovement.bPositiveBlowUp = true
    end
    
    if self.Role == ENetRole.ROLE_AutonomousProxy then
        self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
        self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
        self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", { AttrName = { "bCanSelfRescue" } }, self.CharacterAttrChangeEvent, self)
    end
    
    if Client then
        GameplayData.AddCharacter(self.Object)
    else
        self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1] = "FinishedState" }, self.HandleFinishedState, self)
    end
    
    EventSystem:postEvent(EVENTTYPE_SINGLETRAINING, EVENTID_CHARACTER_BEGINPLAY, self.Object)
end

function BRPlayerCharacterBase:ReceiveEndPlay(endPlayReason)
    BRPlayerCharacterBase.__super.ReceiveEndPlay(self, endPlayReason)
    if Client and GameplayData.RemoveCharacter then
        GameplayData.RemoveCharacter(self.Object)
    end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew(Character, PrevMovementMode, MovementMode)
    if not self:HasAuthority() then return end
    if self.MovementMode == EPawnState.MOVE_Falling and self:GetIsInPassengerVehicle() then
        self:ServerRPC_CancelRideVehicle()
    end
end

function BRPlayerCharacterBase:OnPawnStateChange(State, bEnable)
    if State == EPawnState.Dying then
        self.bCanNearDeathGiveup = true
    end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(AttrName, Value)
    if AttrName == "bCanSelfRescue" and Value then
        self.bCanNearDeathGiveup = true
    end
end

function BRPlayerCharacterBase:HandleFinishedState()
    if self.IsInPlane then
        self:ClientRPC_TriggerHighlightMoment(1, 0)
    end
end

function BRPlayerCharacterBase:InitAddSpecialMoveInfo()
    if not Client then return end
    if not self.SpecialMoveComponent then return end
    self.SpecialMoveComponent:AddSpecialMoveInfo("/Game/Mod/EvoBase/BluePrints/Character/Player/SP/SpecialMoveData/SpecialMove_Death_Self. SpecialMove_Death_Self_C")
end

function BRPlayerCharacterBase:ServerRPC_RequestRespawn(DeathContext)
    if not self:HasAuthority() then return end
    if self.NearDeathComponent and self.NearDeathComponent.bCanRespawn then
        self:RespawnPawn(DeathContext)
        self.NearDeathComponent.bCanRespawn = false
    end
end

function BRPlayerCharacterBase:ServerRPC_CancelRideVehicle()
    if not self:HasAuthority() then return end
    if self:IsInPassengerVehicle() then
        local Vehicle = self:GetVehicle()
        if Vehicle and Vehicle.ExitVehicle then
            Vehicle:ExitVehicle(self)
        end
    end
end

function BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment(MomentID, Param)
    if not Client then return end
    local HighlightMomentMgr = import("HighlightMomentManager")
    if HighlightMomentMgr and HighlightMomentMgr.TriggerMoment then
        HighlightMomentMgr.TriggerMoment(MomentID, Param, self)
    end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(ActionID)
    if not self:HasAuthority() then return end
    if ActionID == 1 then
        self:SetActorEnableCollision(false)
    elseif ActionID == 2 then
        self:SetActorEnableCollision(true)
    end
end

function BRPlayerCharacterBase:ServerRPC_GmPlayAction(ActionID)
    if not self:HasAuthority() then return end
    self:MulticastRPC_GmPlayAction(ActionID)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bEnable)
    if not Client then return end
    self.bShouldCheckPassWall = bEnable
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
    if not self:HasAuthority() then return end
    if not self.bCanNearDeathGiveup then return end
    if self.NearDeathComponent and self.NearDeathComponent.GiveupRescue then
        self.NearDeathComponent:GiveupRescue()
        self.bCanNearDeathGiveup = false
    end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(TargetCharacter)
    if not self:HasAuthority() then return end
    if not slua.isValid(TargetCharacter) then return end
    if TargetCharacter:IsDead() then
        local DeadBox = TargetCharacter:GetDeadBox()
        if DeadBox and DeadBox.Carry then
            DeadBox:Carry(self)
        end
    end
end




-- ============================================
-- BIZAPRO MOD MENU (WITH PC VIEW SLIDER & NATIVE ESP)
-- ============================================
-- Global State Initialization
_G.LexusState = _G.LexusState or {
    CustomTextData = {}
}

-- Global Config Table
_G.LexusConfig = _G.LexusConfig or {
    Mod_WallHighlight = true,
    Mod_iPadView = true,
    Mod_iPadFOV = 110,
    Mod_ESPHP = true,
    Mod_ColorBodyNew= true  
}



-- ============================================
-- CONFIG PATHS & SAVE/LOAD SYSTEM
-- ============================================
local function GetConfigPaths(fileName)
    local paths = {
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/Paks/ZETxLabs" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/Paks/puffer_temp/" .. fileName,
        "/com.tencent.ig/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/com.vng.pubgmobile/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/com.pubg.krmobile/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/com.rekoo.pubgm/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/com.pubg.imobile/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "../../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "../../../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
        fileName
    }
    pcall(function()
        if os and os.getenv then
            local homeDir = os.getenv("HOME")
            if homeDir and homeDir ~= "" then
                table.insert(paths, 1, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName)
                table.insert(paths, 2, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Paks/puffer_temp/" .. fileName)
            end
        end
    end)
    return paths
end

local ConfigFileName = "ZETxLabs.txt"
_G.LastConfigSaveStr = ""

_G.SaveModSettings = function()
    pcall(function()
        local data = "return {\nLexusConfig = {\n"
        for k, v in pairs(_G.LexusConfig or {}) do
            data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
        end
        data = data .. "},\nCustomTextData = {\n"
        if _G.LexusState and _G.LexusState.CustomTextData then
            for k, v in pairs(_G.LexusState.CustomTextData) do
                data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
            end
        end
        data = data .. "}\n}"
        
        if data == _G.LastConfigSaveStr then return end
        _G.LastConfigSaveStr = data

        local paths = GetConfigPaths(ConfigFileName)
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(data)
                file:close()
                break
            end
        end
    end)
end

_G.LoadModSettings = function()
    pcall(function()
        local paths = GetConfigPaths(ConfigFileName)
        local content = nil
        for _, path in ipairs(paths) do
            local file = io.open(path, "r")
            if file then
                content = file:read("*a")
                file:close()
                break
            end
        end

        if content then
            local func = load(content)
            if func then
                local savedData = func()
                if savedData and type(savedData) == "table" then
                    if savedData.LexusConfig then
                        for k, v in pairs(savedData.LexusConfig) do
                            _G.LexusConfig[k] = v
                        end
                    end
                    if savedData.CustomTextData then
                        _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {}
                        for k, v in pairs(savedData.CustomTextData) do
                            _G.LexusState.CustomTextData[k] = v
                        end
                    end
                end
            end
        end
        _G.SaveModSettings() 
    end)
end

local function AutoSaveLoop()
    pcall(function() if _G.SaveModSettings then _G.SaveModSettings() end end)
    pcall(function()
        local okTicker, ticker = pcall(require, "common.time_ticker") 
        if okTicker and ticker and ticker.AddTimerOnce then 
            ticker.AddTimerOnce(3.0, AutoSaveLoop)
        end
    end)
end

if not _G.ModConfigLoaded then
    _G.LoadModSettings()
    AutoSaveLoop()
    _G.ModConfigLoaded = true
end

_G.ReadLiveConfig = function()
    if _G.SaveModSettings then _G.SaveModSettings() end
end

local function T(mm, en)
    return en 
end


-- ============================================================
-- COLOR BODY NEW UPDATE FUNCTION (FROM BRPlayerCharacterBase.lua)
-- ============================================================
function _G.UpdateColorBodyNew()
    if is_mod_expired() then return end
    if not Client then return end
    
    local localPlayer = GameplayData.GetPlayerCharacter()
    if not slua.isValid(localPlayer) then return end
    
    local allPawns = Game:GetAllPlayerPawns()
    if not allPawns then return end

    -- Console Commands ကို စတင်သတ်မှတ်ခြင်း
    if not _G.ConsoleNewWallReady then
        local KismetSystemLibrary = import("KismetSystemLibrary")
        local world = slua.getWorld()
        if KismetSystemLibrary and world then
            KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
            KismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3")
            KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
            KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
            _G.ConsoleNewWallReady = true
        end
    end

    local isEnabled = _G.LexusConfig.Mod_ColorBodyNew or false
    local SecurityUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
    
    for _, pawn in pairs(allPawns) do
        if slua.isValid(pawn) and pawn ~= localPlayer then
            local isEnemy = (pawn.TeamID ~= localPlayer.TeamID and pawn.TeamID ~= 0)
            if not isEnemy then goto continue end
            
            local isAlive = pawn.HealthStatus and SecurityUtils.IsHealthStatusAlive(pawn.HealthStatus)
            if not isAlive then goto continue end
            
            -- ခန္ဓာကိုယ်တစ်ခုလုံးအတွက် Mesh တွေကို စုဆောင်းခြင်း
            local meshes = {}
            
            -- Main Mesh
            if slua.isValid(pawn.Mesh) then
                table.insert(meshes, pawn.Mesh)
            end
            
            -- Avatar Component
            local avatarComp = pawn:getAvatarComponent2()
            if slua.isValid(avatarComp) then
                if slua.isValid(avatarComp.Mesh) then
                    table.insert(meshes, avatarComp.Mesh)
                end
            end
            
            -- Weapon Mesh
            local weapon = pawn:GetCurrentWeapon()
            if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                table.insert(meshes, weapon.Mesh)
            end
            
            -- SkeletalMesh Components အားလုံး
            local allSkeletalMeshes = pawn:GetComponentsByClass(import("SkeletalMeshComponent"))
            if allSkeletalMeshes then
                for _, mesh in pairs(allSkeletalMeshes) do
                    if slua.isValid(mesh) then
                        local isDuplicate = false
                        for _, existing in ipairs(meshes) do
                            if existing == mesh then isDuplicate = true break end
                        end
                        if not isDuplicate then
                            table.insert(meshes, mesh)
                        end
                    end
                end
            end
            
            if isEnabled then
                local LinearColorClass = import("LinearColor") or _G.FLinearColor
                local c_vis = LinearColorClass and LinearColorClass(0, 100, 0, 1) or {R=0, G=100, B=0, A=1}
                local c_occ = LinearColorClass and LinearColorClass(100, 0, 0, 1) or {R=100, G=0, B=0, A=1}
                
                for _, mesh in ipairs(meshes) do
                    if slua.isValid(mesh) then
                        pcall(function()
                            if type(mesh.SetDrawDyeing) == "function" then
                                mesh:SetDrawDyeing(true)
                                mesh:SetDrawDyeingMode(1)
                                mesh:SetVisibleDyeingColor(c_vis)
                                mesh:SetOccludedDyeingColor(c_occ)
                                mesh:SetDyeingColorFadeDistance(99999.0)
                                mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
                                mesh:SetDrawHighlight(true)
                                mesh:OverrideHighlightColor(c_vis)
                                mesh:SetHighlightCanBeOccluded(false)
                                mesh:SetDrawIdeaOutline(true)
                                mesh:SetIdeaOutlineNew(true)
                                mesh:SetIdeaOutlineOcclusionHighlight(true)
                                mesh:OverrideIdeaOutlineColor(c_vis)
                                mesh:SetIdeaOutlineOcclusionColor(c_occ)
                                mesh:OverrideIdeaOutlineThickness(20.0)
                                mesh:SetIdeaOverrideOutlineAndOcclusion(true)
                                mesh:SetRenderCustomDepth(true)
                                mesh:SetCustomDepthStencilValue(255)
                            end
                        end)
                    end
                end
            else
                for _, mesh in ipairs(meshes) do
                    if slua.isValid(mesh) then
                        pcall(function()
                            if type(mesh.SetDrawDyeing) == "function" then
                                mesh:SetDrawDyeing(false)
                                mesh:SetDrawHighlight(false)
                                mesh:SetDrawIdeaOutline(false)
                                mesh:SetRenderCustomDepth(false)
                            end
                        end)
                    end
                end
            end
            
            ::continue::
        end
    end
end

local function InitModMenuTab()
    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = require("client.common.LocUtil")
    end
    

    
    if LocUtil and not LocUtil._IsModMenuHooked then
        local old_get = LocUtil.GetLocalizeResStr
        LocUtil.GetLocalizeResStr = function(id)
            if type(id) == "string" and not tonumber(id) then
                return id
            end
            return old_get(id)
        end
        LocUtil._IsModMenuHooked = true
    end

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    
    if not SettingPageDefine.BizaproMod then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
        
        local ESPStack = {
            { UI = AliasMap.Title, Text = T("အီးအက်စ်ပီ ဖန်ရှင်များ", "ESP FEATURES") },
            {
                Key = "Mod_WallHighlight",
                UI = AliasMap.Switcher,
                Text = T("နံရံထိုးဖောက် မြင်ကွင်း (ESP)", "Wall Highlight (ESP)"),
                GetFunc = function() 
                    if is_mod_expired() then return false end
                    return _G.LexusConfig.Mod_WallHighlight or false 
                end,
                SetFunc = function(_, value)
                    if is_mod_expired() then return false end
                    _G.LexusConfig.Mod_WallHighlight = value
                    _G.SaveModSettings()
                    if _G.UpdateWallHighlight then
                        _G.UpdateWallHighlight()
                    end
                    return true
                end
            },
            {
                Key = "Mod_ColorBodyNew",
                UI = AliasMap.Switcher,
                Text = T("နံရံအရောင်အသစ် (အင်ဂျင်မှ အစိမ်း/အနီ တောက်ပြောင်)", "NEW ENGINE CHAMS (Red/Green)"),
                GetFunc = function() 
                    if is_mod_expired() then return false end
                    return _G.LexusConfig.Mod_ColorBodyNew or false 
                end,
                SetFunc = function(_, value)
                    if is_mod_expired() then return false end
                    _G.LexusConfig.Mod_ColorBodyNew = value
                    _G.SaveModSettings()
                    if _G.UpdateColorBodyNew then
                        _G.UpdateColorBodyNew()
                    end
                    return true
                end
            },

            {
                Key = "Mod_ESPHP",
                UI = AliasMap.Switcher,
                Text = T("အသက်နှင့် အကွာအဝေး ပြသရန် (ESP HP & Distance)", "ESP HP & Distance"),
                GetFunc = function() 
                    if is_mod_expired() then return false end
                    return _G.LexusConfig.Mod_ESPHP or false 
                end,
                SetFunc = function(_, value)
                    if is_mod_expired() then return false end
                    _G.LexusConfig.Mod_ESPHP = value
                    _G.SaveModSettings()
                    if _G.UpdateNativeESPSubsystem then
                        _G.UpdateNativeESPSubsystem()
                    end
                    return true
                end
            },
            { UI = AliasMap.Title, Text = T("မြင်ကွင်း ဆက်တင်များ", "VIEW SETTINGS") },
            {
                Key = "Mod_iPadView",
                UI = AliasMap.Switcher,
                Text = T("အိုင်ပက် မြင်ကွင်း ဖွင့်ရန်", "Enable iPad View"),
                GetFunc = function() 
                    if is_mod_expired() then return false end
                    return _G.LexusConfig.Mod_iPadView or false 
                end,
                SetFunc = function(_, value)
                    if is_mod_expired() then return false end
                    _G.LexusConfig.Mod_iPadView = value
                    _G.SaveModSettings()
                    if _G.UpdateiPadView then
                        _G.UpdateiPadView()
                    end
                    return true
                end
            },


            {
                Key = "Mod_iPadFOV",
                UI = AliasMap.Slider,
                Text = T("အိုင်ပက် မြင်ကွင်းကျယ် တန်ဖိုး (iPad FOV)", "iPad FOV Value"),
                Min = 40,
                Max = 150,
                Step = 1,
                GetFunc = function()
                    if is_mod_expired() then return 90 end
                    return _G.LexusConfig.Mod_iPadFOV or 110
                end,
                SetFunc = function(_, value)
                    if is_mod_expired() then return false end
                    _G.LexusConfig.Mod_iPadFOV = math.floor(value)
                    _G.SaveModSettings()
                    if _G.UpdateiPadView then
                        _G.UpdateiPadView()
                    end
                    return true
                end
            }
        }


        
        SettingPageDefine.BizaproMod = {
            Key = "BizaproMod",
            Text = "BIZAPRO ESP",
            UIKey = "Setting_Page_Privacy",
            Category = {

                { Key = "Cat_ESP", Text = T("အီးအက်စ်ပီ ဖန်ရှင်များ", "ESP FEATURES"), Stack = ESPStack },
                                { Key = "Cat_AimbotV2", Text ="AimbotV2", Stack = StackAimbotV2 }
            }
        }
        
    end
  end

-- ============================================================
-- MOD EXPIRATION (2027-08-20)
-- ============================================================
local EXPIRY_TABLE = { year = 2027, month = 8, day = 20, hour = 0, min = 0, sec = 0 }
local EXPIRY_TIMESTAMP = os.time(EXPIRY_TABLE)

function is_mod_expired()
    return os.time(os.date("!*t")) > EXPIRY_TIMESTAMP
end

_G.ModMenuShown = false
InitModMenuTab()

-- ============================================================
-- IMPORTS
-- ============================================================
local class = require("class")
local CharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local combine_class = require("combine_class")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local SecurityUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
local TimeTicker = require("common.time_ticker")
local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")

-- ============================================================
-- SECURITY BYPASS
-- ============================================================
local function nop() end

local function bypass_telemetry()
    if _G.CrashSight then
        _G.CrashSight.ReportException = nop
        _G.CrashSight.SetCustomData = nop
        _G.CrashSight.SetAppVersion = nop
    end
    if _G.FPlatformMisc then
        _G.FPlatformMisc.RequestExit = nop
    end

    local sdks = {
        "TDM", "TencentDataMaster", "TDataMaster", "GCloud", "GCloudVoice",
        "APM", "INTL", "Safeguard", "Beacon"
    }
    for _, name in ipairs(sdks) do
        local sdk = _G[name]
        if type(sdk) == "table" then
            sdk.ReportEvent = nop
            sdk.ReportBinary = nop
            sdk.Send = nop
            sdk.SetServerInfo = nop
        end
    end

    for k, v in pairs(_G) do
        if type(v) == "table" then
            local lower = tostring(k):lower()
            if lower:find("tdm") or lower:find("gcloud") or lower:find("report") or
               lower:find("crash") or lower:find("apm") or lower:find("intl") or
               lower:find("beacon") or lower:find("safeguard") then
                pcall(function()
                    v.ReportEvent = nop
                    v.ReportBinary = nop
                    v.Send = nop
                    v.SetServerInfo = nop
                end)
            end
        end
    end

    if _G.GC then
        local gc = _G.GC
        gc.SendTssSdkAntiDataToLobby = nop
        gc.SendDSErrorLogToLobby = nop
        gc.SendDSHawkEyePatrolLogToLobby = nop
        gc.SendSecTLog = nop
        gc.SendDataMiningTLog = nop
        gc.SendActivityTLog = nop
        gc.OnPlayerRPCValidateFailed = nop
        gc.OnPlayerActorChannelError = nop
        gc.OnPlayerSpectateException = nop
    end
end

bypass_telemetry()

-- ============================================================
-- MOD MENU NOTIFICATION
-- ============================================================
function _G.TryShowModMenu()
    if _G.ModMenuShown then return end
    _G.ModMenuShown = true

    pcall(function()
        local msgbox = require("client.slua.logic.common.logic_common_msg_box")
        if not msgbox or not msgbox.Show then return end

        if is_mod_expired() then
            msgbox.Show(1, "BIZAPRO MOD EXPIRED", 
                [[Mod has expired!
Expiry Date: 2027-08-20
Please contact: @Ryan_m_m_m]], nil, nil)
            return
        end

        msgbox.Show(1, "BIZAPRO MOD ACTIVATED",
            [[Bypass Activated Successfully!
@Username : @Ryan_m_m_m
Official Channel : @BIZAPRO2007]], nil, nil)
    end)
end

-- ============================================================
-- 165 FPS MODULE
-- ============================================================
local GSC_FPS = package.loaded["client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS"]
    or require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")

if GSC_FPS and GSC_FPS.__inner_impl then
    if not is_mod_expired() then
        local impl = GSC_FPS.__inner_impl
        local origCtor = impl.ctor
        impl.ctor = function(self)
            if origCtor then origCtor(self) end
            self.FPSButtons = {}
            for i = 1, 8 do self.FPSButtons[i] = { false, false } end
        end

        local origRegistEvents = impl.RegistEvents
        impl.RegistEvents = function(self)
            if origRegistEvents then origRegistEvents(self) end
            if self.UIRoot and self.UIRoot.Btn_fpslv8 then
                self.UIRoot:AddControlEventByControl("Btn_fpslv8", "OnClicked", self.ClickFPS, self)
            end
            self:AddCommonEvent(EVENTTYPE_SETTING, EVENTID_SETTING_FPS_LIMIT_CONFIRM, self.OnFPSPopConfirm, self)
        end

        impl.GetMaxFPSLevel = function() return 8, 8 end
        impl.CanChangeQualityAndFPSPreCheck = function() return true end

        impl.InitRealSupportFPS = function(self)
            local tbl = {}
            for i = 1, 8 do tbl[i] = { true, true } end
            GraphicSettingDB:UpdateUIData(GraphicSettingDB.RealSupportFPS, tbl, false)
            return tbl
        end

        impl.SetFPSAndQualityEnable = function(self, enable)
            if self.UIRoot and self.UIRoot.Image_Mask then
                self:SetWidgetVisible(self.UIRoot.Image_Mask, false)
            end
        end

        impl.UpdateSelectedFPSState = function(self, level)
            local names = {
                [2]="NodeFps20", [3]="NodeFps25", [4]="NodeFps30",
                [5]="NodeFps40", [6]="NodeFps60", [7]="NodeFps90", [8]="NodeFps120"
            }
            if not names[level] then return end
            for k, v in pairs(names) do
                if self.UIRoot[v] then
                    self:WidgetSelfHit(self.UIRoot[v])
                    self.UIRoot[v]:SetIsEnabled(true)
                    local sw = self.UIRoot["WidgetSwitcher_" .. k]
                    if sw then sw:SetActiveWidgetIndex(k == level and 0 or 1) end
                end
            end
        end
    end
end

-- ============================================================
-- IPAD VIEW UPDATE FUNCTION
-- ============================================================
function _G.UpdateiPadView()
    if is_mod_expired() then return end
    if not _G.LexusConfig.Mod_iPadView then return end
    
    local localPlayer = GameplayData.GetPlayerCharacter()
    if not slua.isValid(localPlayer) then return end
    
    local camera = localPlayer.ThirdPersonCameraComponent
    if slua.isValid(camera) then
        local fov = _G.LexusConfig.Mod_iPadFOV or 110
        if fov < 70 then fov = 70 end
        if fov > 150 then fov = 150 end
        camera:SetFieldOfView(fov)
    end
end

-- ============================================================
-- WALL HIGHLIGHT - RED CIRCLE STYLE (FIXED)
-- ============================================================
function _G.UpdateWallHighlight()
    if is_mod_expired() then return end
    if not Client then return end
    
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not pc then return end
    
    local STExtraPlayerController = import("/Script/ShadowTrackerExtra.STExtraPlayerController")
    if not Game:IsClassOf(pc, STExtraPlayerController) then return end

    local myPawn = pc:GetCurPawn()
    local myTeamID = 0
    local STExtraPlayerCharacter = import("STExtraPlayerCharacter")
    if Game:IsClassOf(myPawn, STExtraPlayerCharacter) and myPawn.TeamID then
        myTeamID = myPawn.TeamID
    end

    local allPawns = Game:GetAllPlayerPawns()
    if not allPawns then return end

    -- ============================================================
    -- RED CIRCLE CONFIG
    -- ============================================================
    local RED = { R = 1.0, G = 0.0, B = 0.0, A = 1.0 }
    local CIRCLE_SCALE = 1.0
    local CIRCLE_THICKNESS = 3.0
    local PULSE_SPEED = 2.0

    -- ✅ FIX: currentTime ကို မှန်ကန်စွာ ရယူခြင်း
    local currentTime = os.clock()
    if Game.GetTimeSeconds then
        local ok, t = pcall(function() return Game:GetTimeSeconds() end)
        if ok and t then currentTime = t end
    end
    local pulse = 1.0 + (math.sin(currentTime * PULSE_SPEED) * 0.1)

    for _, pawn in pairs(allPawns) do
        if slua.isValid(pawn) and pawn.Replay_CreateEnemyFrameUI and pawn.Replay_SetVisiableOfFrameUI and pawn.Replay_IsEnemyFrameUIExisted then
            local isEnemy = (pawn.TeamID ~= myTeamID and pawn.TeamID ~= 0)
            local isAlive = pawn.HealthStatus and SecurityUtils.IsHealthStatusAlive(pawn.HealthStatus)
            
            if _G.LexusConfig.Mod_WallHighlight and isEnemy and isAlive then
                if not pawn:Replay_IsEnemyFrameUIExisted() then
                    pawn:Replay_CreateEnemyFrameUI(true, true)
                end
                pawn:Replay_SetVisiableOfFrameUI(true)

                pcall(function()
                    local frameUI = pawn.EnemyFrameUI or pawn.Replay_EnemyFrameUI or pawn.FrameUIComponent
                    if not slua.isValid(frameUI) then return end

                    if frameUI.SetColorAndOpacity then
                        frameUI:SetColorAndOpacity(RED)
                    end

                    if frameUI.SetMaterialColorParameter then
                        frameUI:SetMaterialColorParameter("Color", RED)
                        frameUI:SetMaterialColorParameter("TintColor", RED)
                        frameUI:SetMaterialColorParameter("BaseColor", RED)
                        frameUI:SetMaterialColorParameter("OutlineColor", RED)
                        frameUI:SetMaterialColorParameter("FrameColor", RED)
                    end

                    if frameUI.SetMaterialScalarParameter then
                        frameUI:SetMaterialScalarParameter("CircleScale", CIRCLE_SCALE * pulse)
                        frameUI:SetMaterialScalarParameter("Thickness", CIRCLE_THICKNESS)
                        frameUI:SetMaterialScalarParameter("IsCircle", 1.0)
                        frameUI:SetMaterialScalarParameter("ShapeType", 1.0)
                        frameUI:SetMaterialScalarParameter("CornerRadius", 1.0)
                    end

                    if frameUI.SetRenderScale then
                        frameUI:SetRenderScale({ X = CIRCLE_SCALE * pulse, Y = CIRCLE_SCALE * pulse })
                    end
                    if frameUI.SetRenderOpacity then
                        frameUI:SetRenderOpacity(1.0)
                    end
                end)

                pcall(function()
                    local MPC = pawn.EnemyFrameMPC or pawn.FrameMPC
                    if slua.isValid(MPC) and MPC.SetVectorParameterValue then
                        MPC:SetVectorParameterValue("FrameColor", { X = RED.R, Y = RED.G, Z = RED.B, W = RED.A })
                        MPC:SetVectorParameterValue("OutlineColor", { X = RED.R, Y = RED.G, Z = RED.B, W = RED.A })
                        MPC:SetVectorParameterValue("CircleColor", { X = RED.R, Y = RED.G, Z = RED.B, W = RED.A })
                    end
                    if slua.isValid(MPC) and MPC.SetScalarParameterValue then
                        MPC:SetScalarParameterValue("CircleScale", CIRCLE_SCALE * pulse)
                        MPC:SetScalarParameterValue("Thickness", CIRCLE_THICKNESS)
                        MPC:SetScalarParameterValue("IsCircle", 1.0)
                    end
                end)

                pcall(function()
                    local outlineComp = pawn.OutlineComponent or pawn.EnemyOutlineComponent
                    if slua.isValid(outlineComp) then
                        if outlineComp.SetOutlineColor then
                            outlineComp:SetOutlineColor(RED)
                        end
                        if outlineComp.SetOutlineMode then
                            outlineComp:SetOutlineMode(1)
                        end
                        if outlineComp.SetOutlineThickness then
                            outlineComp:SetOutlineThickness(CIRCLE_THICKNESS)
                        end
                        if outlineComp.SetOutlineScale then
                            outlineComp:SetOutlineScale(CIRCLE_SCALE * pulse)
                        end
                    end
                end)

            else
                pawn:Replay_SetVisiableOfFrameUI(false)
            end
        end
    end
end

-- ============================================================
-- NATIVE DISTANCE SUBSYSTEM (DISTANCE / MARK ONLY - HP REMOVED)
-- ============================================================
function _G.UpdateNativeESPSubsystem()
    if is_mod_expired() then return end
    local enabled = _G.LexusConfig.Mod_ESPHP or false

    local FVector = import("Vector") or import("FVector") or _G.FVector or function(x,y,z) return {X=x, Y=y, Z=z} end

    pcall(function()
        local GamePlayTools_1 = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
        local var_33 = GamePlayTools_1.GetCurrentConfig("ScreenMarkConfig")
        
        if var_33 then
            if not var_33[9999] then
                var_33[9999] = {
                    UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                    bIsBindingActor = true,
                    BindSocketName = "head", 
                    bUseLuaWorldSocketName = true,
                    WorldPositionOffset = FVector(0, 0, 60),
                    bNeedPreLoad = true,
                    Priority = 2
                }
                local InGameMarkTools_1 = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
                if InGameMarkTools_1 and InGameMarkTools_1.ScreenMarkManager and InGameMarkTools_1.ScreenMarkManager.OnInitMarkGroupData then
                    pcall(function() InGameMarkTools_1.ScreenMarkManager:OnInitMarkGroupData(9999) end)
                end
            end
        end

        for k, var_76 in pairs(package.loaded) do
            if type(k) == "string" and string.find(k, "ScreenMarkConfig") then
                if type(var_76) == "table" then
                    var_76[9999] = {
                        UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                        bIsBindingActor = true,
                        BindSocketName = "head",
                        bUseLuaWorldSocketName = true,
                        WorldPositionOffset = FVector(0, 0, 60),
                        bNeedPreLoad = true,
                        Priority = 2
                    }
                end
            end
        end
    end)

    pcall(function()
        local distance = enabled and 6000000 or 0
        local numLimit = enabled and 99 or 0
        
        local GamePlayTools_1 = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
        local var_33 = GamePlayTools_1.GetCurrentConfig("ScreenMarkConfig")
        if var_33 then
            if var_33[9999] then
                var_33[9999].bBindBlocked = enabled     
                var_33[9999].bBindOutScreen = enabled   
                var_33[9999].MaxWidgetNum = numLimit
                var_33[9999].MaxShowDistance = distance
                var_33[9999].bScaleByDistance = false 
            end
        end

        for k, var_76 in pairs(package.loaded) do
            if type(k) == "string" and string.find(k, "ScreenMarkConfig") then
                if type(var_76) == "table" then
                    if var_76[9999] then
                        var_76[9999].bBindBlocked = enabled     
                        var_76[9999].bBindOutScreen = enabled   
                        var_76[9999].MaxWidgetNum = numLimit
                        var_76[9999].MaxShowDistance = distance
                        var_76[9999].bScaleByDistance = false
                    end
                end
            end
        end
    end)

    pcall(function()
        local localPlayer = GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPlayer) then return end
        
        local GameplayData_3 = GameplayData
        local InGameMarkTools_1 = InGameMarkTools

        local var_95 = {}
        if GameplayData_3.GetAllPlayerCharacters then
            var_95 = GameplayData_3.GetAllPlayerCharacters()
        elseif GameplayData_3.GameCharacters then
            for _, char in pairs(GameplayData_3.GameCharacters) do table.insert(var_95, char) end
        end

        if not _G.AK_Active_Marks_Cache then _G.AK_Active_Marks_Cache = {} end

        for cacheKey, cacheData in pairs(_G.AK_Active_Marks_Cache) do
            local var_77 = false
            if not slua.isValid(cacheData.actor) then 
                var_77 = true 
            end

            -- [FIX] သေသွားတဲ့သူဆိုရင်လည်း ဖယ်ရှားမယ်
            if slua.isValid(cacheData.actor) then
                local isAlive = cacheData.actor.HealthStatus and SecurityUtils.IsHealthStatusAlive(cacheData.actor.HealthStatus)
                if not isAlive then
                    var_77 = true
                end
            end

            if var_77 then
                pcall(function()
                    if InGameMarkTools_1 and InGameMarkTools_1.ClientRemoveMapMark then
                        if cacheData.distMark then InGameMarkTools_1.ClientRemoveMapMark(cacheData.distMark) end
                    elseif InGameMarkTools_1 and InGameMarkTools_1.HideMapMark then
                        if cacheData.distMark then InGameMarkTools_1.HideMapMark(cacheData.distMark) end
                    end
                end)
                _G.AK_Active_Marks_Cache[cacheKey] = nil
            end
        end

        -- [FIX] SecurityUtils ကို ရယူခြင်း
        local SecurityUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
        
        for _, enemy in pairs(var_95) do
            if slua.isValid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
                
                -- [FIX] သေဆုံးသွားတဲ့သူဆိုရင် Mark ကို ဖယ်ရှားမယ်
                local isAlive = enemy.HealthStatus and SecurityUtils.IsHealthStatusAlive(enemy.HealthStatus)
                
                if not isAlive then
                    -- သေသွားရင် Mark ကို ဖယ်ရှားမယ်
                    if enemy.bHasAKNativeDistBar and InGameMarkTools_1 then
                        pcall(function()
                            if InGameMarkTools_1.ClientRemoveMapMark then 
                                if enemy.NativeDistMark then InGameMarkTools_1.ClientRemoveMapMark(enemy.NativeDistMark) end
                            end
                            if InGameMarkTools_1.HideMapMark then
                                if enemy.NativeDistMark then InGameMarkTools_1.HideMapMark(enemy.NativeDistMark) end
                            end
                        end)
                        enemy.NativeDistMark = nil
                        enemy.bHasAKNativeDistBar = false
                        _G.AK_Active_Marks_Cache[tostring(enemy)] = nil
                    end
                else
                    -- အသက်ရှင်နေတဲ့သူများအတွက်
                    if not enabled then
                        if enemy.bHasAKNativeDistBar and InGameMarkTools_1 then
                            pcall(function()
                                if InGameMarkTools_1.ClientRemoveMapMark then 
                                    if enemy.NativeDistMark then InGameMarkTools_1.ClientRemoveMapMark(enemy.NativeDistMark) end
                                end
                                if InGameMarkTools_1.HideMapMark then
                                    if enemy.NativeDistMark then InGameMarkTools_1.HideMapMark(enemy.NativeDistMark) end
                                end
                            end)
                            enemy.NativeDistMark = nil
                            enemy.bHasAKNativeDistBar = false
                            _G.AK_Active_Marks_Cache[tostring(enemy)] = nil
                        end
                    else
                        if enabled then
                            if not enemy.bHasAKNativeDistBar then
                                pcall(function()
                                    if InGameMarkTools_1 and InGameMarkTools_1.ClientAddMapMark then
                                        enemy.NativeDistMark = InGameMarkTools_1.ClientAddMapMark(9999, FVector(0,0,0), 0, "", 4, enemy)
                                        enemy.bHasAKNativeDistBar = true

                                        _G.AK_Active_Marks_Cache[tostring(enemy)] = {
                                            actor = enemy,
                                            distMark = enemy.NativeDistMark
                                        }
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end)
end


-- ============================================================
-- TIME TICKER LOOP (0.5s TIME INTERVAL FOR ESP & VIEWS)
-- ============================================================
local function ESPAndViewLoop()
    if is_mod_expired() then return end
    
    pcall(function()

        if _G.LexusConfig.Mod_WallHighlight then
            pcall(_G.UpdateWallHighlight)
        end

        if _G.LexusConfig.Mod_iPadView then
            pcall(_G.UpdateiPadView)
        end

        if _G.LexusConfig.Mod_ESPHP then
            pcall(_G.UpdateNativeESPSubsystem)
        end
        
        if _G.LexusConfig.Mod_ColorBodyNew ~= nil then
            pcall(_G.UpdateColorBodyNew)
        end
    end)
    
    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.01, ESPAndViewLoop)
    end
end

if not is_mod_expired() then
    ESPAndViewLoop()
end
local class = require("class")
local CharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local BRCharacterClass = class(CharacterBase, nil, BRPlayerCharacterBase)

return require("combine_class").DeclareFeature(BRCharacterClass, {
    { SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature" },
    { CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature" },
    { SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature" },
    { TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature" },
    { LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature" },
    { FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature" },
    { CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature" },
    { BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature" },
    { CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature" },
    { ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature" }
}, "BRPlayerCharacterBase")