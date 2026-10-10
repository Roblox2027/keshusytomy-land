-- Fix lobby part positions from default.project.json
local Workspace = game:GetService("Workspace")
local lobby = Workspace:FindFirstChild("Lobby")
if not lobby then return "no lobby" end

do
    local obj = lobby:FindFirstChild("LobbyFloor")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, -1, 0)
    end
end
do
    local obj = lobby:FindFirstChild("LobbyCenter")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 0.2, 0)
    end
end
do
    local obj = lobby:FindFirstChild("LobbyReturn")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 0.2, 46)
    end
end
do
    local obj = lobby:FindFirstChild("LobbyNorth")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 0.2, -40)
    end
end
do
    local obj = lobby:FindFirstChild("LobbySouth")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 0.2, 40)
    end
end
do
    local obj = lobby:FindFirstChild("LobbyWall_N")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 7, -115)
    end
end
do
    local obj = lobby:FindFirstChild("LobbyWall_S")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 7, 115)
    end
end
do
    local obj = lobby:FindFirstChild("LobbyWall_W")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-115, 7, 0)
    end
end
do
    local obj = lobby:FindFirstChild("LobbyWall_E")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(115, 7, 0)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Shop_Pad")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(20, 0.25, -35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Shop_Post")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(20, 3, -35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Shop_Lamp")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(20, 6, -35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Inventory_Pad")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(35, 0.25, -20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Inventory_Post")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(35, 3, -20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Inventory_Lamp")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(35, 6, -20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Missions_Pad")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(35, 0.25, 20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Missions_Post")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(35, 3, 20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Missions_Lamp")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(35, 6, 20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Season_Pad")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(20, 0.25, 35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Season_Post")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(20, 3, 35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Season_Lamp")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(20, 6, 35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Party_Pad")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-20, 0.25, 35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Party_Post")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-20, 3, 35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Party_Lamp")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-20, 6, 35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Rankings_Pad")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-35, 0.25, 20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Rankings_Post")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-35, 3, 20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Rankings_Lamp")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-35, 6, 20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Training_Pad")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-35, 0.25, -20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Training_Post")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-35, 3, -20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Training_Lamp")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-35, 6, -20)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Events_Pad")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-20, 0.25, -35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Events_Post")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-20, 3, -35)
    end
end
do
    local obj = lobby:FindFirstChild("Station_Events_Lamp")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-20, 6, -35)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(100, 5, 0)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(100, 10.2, 0)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(87, 5, 50)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(87, 10.2, 50)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(50, 5, 87)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(50, 10.2, 87)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_3")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 5, 100)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_3")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 10.2, 100)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_4")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-50, 5, 87)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_4")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-50, 10.2, 87)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_5")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-87, 5, 50)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_5")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-87, 10.2, 50)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_6")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-100, 5, 0)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_6")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-100, 10.2, 0)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_7")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-87, 5, -50)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_7")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-87, 10.2, -50)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_8")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-50, 5, -87)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_8")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-50, 10.2, -87)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_9")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 5, -100)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_9")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 10.2, -100)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_10")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(50, 5, -87)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_10")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(50, 10.2, -87)
    end
end
do
    local obj = lobby:FindFirstChild("Lamp_11")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(87, 5, -50)
    end
end
do
    local obj = lobby:FindFirstChild("LampGlow_11")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(87, 10.2, -50)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Floor")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, -0.8, 82)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_CenterLine")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 0.15, 82)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Wall_S")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 4, 105)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Wall_E")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(33, 4, 82)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Wall_W")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-33, 4, 82)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Wall_N_L")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-19.5, 4, 59)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Wall_N_R")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(19.5, 4, 59)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Pillar_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(33, 5, 105)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Torch_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(33, 10.6, 105)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Pillar_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-33, 5, 105)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Torch_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-33, 10.6, 105)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Pillar_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(33, 5, 59)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Torch_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(33, 10.6, 59)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Pillar_3")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-33, 5, 59)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Torch_3")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-33, 10.6, 59)
    end
end
do
    local obj = lobby:FindFirstChild("PvPArena_Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 11, 59)
    end
end
do
    local obj = lobby:FindFirstChild("PvPCenter")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 0.2, 82)
    end
end
do
    local obj = lobby:FindFirstChild("PvPSpawn_A")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-22, 0.2, 94)
    end
end
do
    local obj = lobby:FindFirstChild("PvPSpawn_B")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(22, 0.2, 94)
    end
end
do
    local obj = lobby:FindFirstChild("PvPEntry")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 0.2, 56)
    end
end
do
    local obj = lobby:FindFirstChild("Podium_Base")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(62, 0.25, 18)
    end
end
do
    local obj = lobby:FindFirstChild("Podium_2nd")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(56, 1.5, 18)
    end
end
do
    local obj = lobby:FindFirstChild("Podium_1st")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(62, 2.5, 18)
    end
end
do
    local obj = lobby:FindFirstChild("Podium_3rd")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(68, 1, 18)
    end
end
do
    local obj = lobby:FindFirstChild("Podium_Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(62, 10, 14)
    end
end
do
    local obj = lobby:FindFirstChild("Podium_Crown")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(62, 7.5, 18)
    end
end
do
    local obj = lobby:FindFirstChild("ShopHall_Floor")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-58, 0.1, 14)
    end
end
do
    local obj = lobby:FindFirstChild("ShopHall_Pillar_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-71, 4, 6)
    end
end
do
    local obj = lobby:FindFirstChild("ShopHall_Pillar_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-45, 4, 6)
    end
end
do
    local obj = lobby:FindFirstChild("ShopHall_Pillar_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-71, 4, 22)
    end
end
do
    local obj = lobby:FindFirstChild("ShopHall_Pillar_3")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-45, 4, 22)
    end
end
do
    local obj = lobby:FindFirstChild("ShopHall_Roof")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-58, 8.8, 14)
    end
end
do
    local obj = lobby:FindFirstChild("ShopHall_Counter")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-58, 1.5, 8)
    end
end
do
    local obj = lobby:FindFirstChild("ShopHall_Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-58, 11, 23)
    end
end
do
    local obj = lobby:FindFirstChild("ShopPoint")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-58, 0.4, 16)
    end
end
do
    local obj = lobby:FindFirstChild("Plaza_Party_Rug")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-52, 0.15, -52)
    end
end
do
    local obj = lobby:FindFirstChild("Plaza_Party_Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-52, 6, -60)
    end
end
do
    local obj = lobby:FindFirstChild("PartyPoint")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-52, 0.3, -52)
    end
end
do
    local obj = lobby:FindFirstChild("Plaza_Codes_Rug")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(52, 0.15, -52)
    end
end
do
    local obj = lobby:FindFirstChild("Plaza_Codes_Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(52, 6, -60)
    end
end
do
    local obj = lobby:FindFirstChild("CodesPoint")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(52, 0.3, -52)
    end
end
do
    local obj = lobby:FindFirstChild("SafeZone_Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 13, 46)
    end
end
do
    local obj = lobby:FindFirstChild("SafeZone_Beacon_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(20, 3, 46)
    end
end
do
    local obj = lobby:FindFirstChild("SafeZone_Beacon_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-20, 3, 46)
    end
end
do
    local obj = lobby:FindFirstChild("SafeZone_Beacon_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(20, 3, -8)
    end
end
do
    local obj = lobby:FindFirstChild("SafeZone_Beacon_3")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-20, 3, -8)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CoreBase")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 0.5, 0)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CorePlinth")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 1.75, 0)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CoreDais")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 3.2, 0)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CoreOrb")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 8, 0)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CoreGlow")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 8, 0)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CoreRing_A")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 8, 0)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CoreRing_B")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 8, 0)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CorePillar_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(7, 4, 7)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CorePillarLight_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(7, 8.4, 7)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CorePillar_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-7, 4, 7)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CorePillarLight_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-7, 8.4, 7)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CorePillar_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(7, 4, -7)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CorePillarLight_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(7, 8.4, -7)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CorePillar_3")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-7, 4, -7)
    end
end
do
    local obj = lobby:FindFirstChild("KeshusyCore"):FindFirstChild("CorePillarLight_3")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-7, 8.4, -7)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("Base")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-32, 0.5, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("Lintel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-32, 9, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("PortalPanel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-32, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("Glow")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-32, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-32, 10.6, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("PostL")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-37.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("PostR")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-26.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("Canopy")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-32, 9.6, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("CanopyTop")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-32, 12, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("Root_L")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-39, 0.7, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Forest"):FindFirstChild("Root_R")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-25, 0.7, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("Base")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-16, 0.5, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("Lintel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-16, 9, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("PortalPanel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-16, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("Glow")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-16, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-16, 10.6, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("PostL")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-21.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("PostR")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-10.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("Capital_L")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-21.5, 9.4, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("Capital_R")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-10.5, 9.4, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Desert"):FindFirstChild("Sun_Disc")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-16, 12.4, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("Base")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 0.5, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("Lintel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 9, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("PortalPanel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("Glow")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 10.6, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("PostL")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-5.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("PostR")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(5.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("Arch_Top")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(0, 9.8, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("Shard_L")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(-7.4, 2.2, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Ice"):FindFirstChild("Shard_R")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(7.4, 2.2, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("Base")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(16, 0.5, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("Lintel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(16, 9, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("PortalPanel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(16, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("Glow")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(16, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(16, 10.6, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("PostL")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(10.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("PostR")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(21.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("Mouth_L")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(10.5, 9.4, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("Mouth_R")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(21.5, 9.4, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("Ember_L")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(10.5, 1.4, -32.2)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Volcano"):FindFirstChild("Ember_R")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(21.5, 1.4, -32.2)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Base")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(32, 0.5, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Lintel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(32, 9, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("PortalPanel")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(32, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Glow")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(32, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Sign")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(32, 10.6, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("PostL")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(26.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("PostR")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(37.5, 4.75, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Band_L_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(26.5, 2, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Band_R_0")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(37.5, 2, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Band_L_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(26.5, 4.6, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Band_R_1")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(37.5, 4.6, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Band_L_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(26.5, 7.2, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Band_R_2")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(37.5, 7.2, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Holo_Ring_A")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(32, 12, -34)
    end
end
do
    local obj = lobby:FindFirstChild("Portals"):FindFirstChild("Portal_Cyber"):FindFirstChild("Holo_Ring_B")
    if obj and obj:IsA("Part") then
        obj.Position = Vector3.new(32, 13.4, -34)
    end
end

return "Fixed 175 parts"