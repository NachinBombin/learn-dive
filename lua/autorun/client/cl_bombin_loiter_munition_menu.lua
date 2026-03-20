if not CLIENT then return end

-- ============================================================
-- SPAWNLIST REGISTRATION
-- ============================================================

hook.Add("PopulateContent", "BombinLoiterMunition_SpawnMenu", function(pnlContent, tree, node)
    local node = tree:AddNode("Bombin Support", "icon16/bomb.png")

    node:MakePopulator(function(pnlContent)
        local icon = vgui.Create("ContentIcon", pnlContent)
        icon:SetContentType("entity")
        icon:SetSpawnName("ent_bombin_loiter_munition")
        icon:SetName("Loiter Munition")
        icon:SetMaterial("entities/ent_bombin_loiter_munition.png")
        icon:SetToolTip("Autonomous TB-2 loiter munition.\nOrbits the target area, then dives and explodes on the nearest player.")
        pnlContent:Add(icon)
    end)
end)

-- ============================================================
-- CONSOLE COMMAND — manual test spawn
-- ============================================================

concommand.Add("bombin_spawnloiter", function()
    if not IsValid(LocalPlayer()) then return end
    net.Start("BombinLoiterMunition_ManualSpawn")
    net.SendToServer()
end)

-- ============================================================
-- CONTROL PANEL — Q Menu > Utilities tab
-- ============================================================

hook.Add("AddToolMenuTabs", "BombinLoiterMunition_Tab", function()
    spawnmenu.AddToolTab("Bombin Support", "Bombin Support", "icon16/bomb.png")
end)

hook.Add("AddToolMenuCategories", "BombinLoiterMunition_Categories", function()
    spawnmenu.AddToolCategory("Bombin Support", "Loiter Munition", "Loiter Munition")
end)

hook.Add("PopulateToolMenu", "BombinLoiterMunition_ToolMenu", function()
    spawnmenu.AddToolMenuOption("Bombin Support", "Loiter Munition", "bombin_loiter_munition_settings", "TB-2 Settings", "", "", function(panel)
        panel:ClearControls()
        panel:Help("NPC Call Settings")

        panel:CheckBox("Enable NPC calls", "npc_bombinloiter_enabled")

        panel:NumSlider("Call chance (per check)",    "npc_bombinloiter_chance",   0,   1,    2)
        panel:NumSlider("Check interval (seconds)",  "npc_bombinloiter_interval", 1,   60,   0)
        panel:NumSlider("NPC cooldown (seconds)",    "npc_bombinloiter_cooldown", 10,  300,  0)
        panel:NumSlider("Min call distance (HU)",    "npc_bombinloiter_min_dist", 100, 1000, 0)
        panel:NumSlider("Max call distance (HU)",    "npc_bombinloiter_max_dist", 500, 8000, 0)
        panel:NumSlider("Flare → arrival delay (s)", "npc_bombinloiter_delay",    1,   30,   0)

        panel:Help("Munition Behaviour")
        panel:NumSlider("Lifetime (seconds)",        "npc_bombinloiter_lifetime", 10,  120,  0)
        panel:NumSlider("Orbit speed (HU/s)",        "npc_bombinloiter_speed",    50,  800,  0)
        panel:NumSlider("Orbit radius (HU)",         "npc_bombinloiter_radius",   500, 6000, 0)
        panel:NumSlider("Altitude above ground (HU)","npc_bombinloiter_height",   500, 8000, 0)

        panel:Help("Dive Attack")
        panel:NumSlider("Explosion damage",          "npc_bombinloiter_dive_damage", 50,  1000, 0)
        panel:NumSlider("Explosion radius (HU)",     "npc_bombinloiter_dive_radius", 100, 2000, 0)

        panel:Help("Debug")
        panel:CheckBox("Enable debug prints", "npc_bombinloiter_announce")

        panel:Help("Manual spawn (for testing)")
        panel:Button("Spawn loiter munition now", "bombin_spawnloiter")
    end)
end)
