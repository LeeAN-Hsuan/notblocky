--[[
    實驗 <編號> — <名稱>

    想驗什麼見 experiments/<編號>-<名>/NOTES.md。一句話：
    **<這個實驗最想回答的那一個問題>**

    產品規劃見 experiments/<編號>-<名>/PLAN.md。

    分工：
      伺服器（本檔）＝建場景、生成東西、處理規則
      客戶端＝StarterPlayerScripts/<名>Client.client.lua（需要才加）
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ★ 鐵律③：WaitForChild 一律帶 timeout（不帶是永遠 yield，pcall 接不住）
local Game = ReplicatedStorage:WaitForChild("Game", 10) or error("[XXX] 找不到 ReplicatedStorage.Game")
local Shared = Game:WaitForChild("Shared", 10) or error("[XXX] 找不到 Game.Shared")

-- 需要用到的共用模組，在這裡 require
-- local AssetSpec = require(Shared:WaitForChild("AssetSpec", 10))
-- local SceneTerrain = require(Shared:WaitForChild("SceneTerrain", 10))

local M = {}

function M.start()
    local level = Instance.new("Model")
    level.Name = "XXXLevel"
    level.Parent = workspace

    -- 你的場景建在這裡

    -- ★ 如果用了 RunService 的每幀迴圈，記得在關卡銷毀時 disconnect
    -- local conn = RunService.Heartbeat:Connect(function() ... end)
    -- level.Destroying:Connect(function() conn:Disconnect() end)

    print("[XXX] 已就緒：<告訴玩家怎麼玩>")
end

return M
