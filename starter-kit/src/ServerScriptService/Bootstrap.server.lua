--[[
    Bootstrap — 唯一的進入點（Script，跑在伺服器）

    讀 Config.ACTIVE → 找到對應實驗模組 → 呼叫它的 start()
    每個實驗只要回傳一張 { start = function() ... end } 的表就行。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ★ 鐵律③：WaitForChild 一律帶 timeout。
--   不帶 timeout 是【永遠 yield 而不是 error】—— pcall 接不住，會靜默卡死，
--   而且 Output 連一行 warn 都不印。
local Game = ReplicatedStorage:WaitForChild("Game", 10)
if not Game then
    warn("[Game] ReplicatedStorage.Game 不存在 —— Rojo 沒接上？")
    warn("  1) 終端機跑了 `rojo serve` 嗎？")
    warn("  2) Studio 裡按了 Rojo 外掛的 Connect 嗎？（這步一定要人按）")
    return
end

local configScript = Game:WaitForChild("Config", 10)
if not configScript then
    warn("[Game] 找不到 Game.Config")
    return
end
local Config = require(configScript)

if not Config.ACTIVE then
    print("[Game] Config.ACTIVE = false，不啟動任何實驗")
    return
end

local experiments = Game:WaitForChild("Experiments", 10)
local experiment = experiments and experiments:FindFirstChild(Config.ACTIVE)
if not experiment then
    warn(("[Game] 找不到實驗「%s」，檢查 src/ReplicatedStorage/Experiments/ 底下的資料夾名")
        :format(Config.ACTIVE))
    return
end

--[[
    ★ 地形是「全域單例」：一個 place 只有一個 Terrain，它不歸任何實驗所有。
    切換實驗時一律清空，由各實驗自己負責重建它要的地形。
    不清的話，上一個實驗的地形會蓋在這一個上面。
]]
local shared = Game:FindFirstChild("Shared")
local sceneTerrain = shared and shared:FindFirstChild("SceneTerrain")
if sceneTerrain then
    -- ★ 包 pcall：地形清除炸掉不該讓整個實驗跑不起來
    --   （不包的話，錯誤訊息會指向地形，但使用者看到的現象是「遊戲完全沒啟動」→ 找錯方向）
    local terrainOk, terrainErr = pcall(function()
        require(sceneTerrain).clear()
    end)
    if not terrainOk then
        warn(("[Game] 地形清除失敗（不影響實驗啟動）：%s"):format(tostring(terrainErr)))
    end
end

local ok, err = pcall(function()
    require(experiment).start()
end)

if ok then
    print(("[Game] 實驗「%s」已啟動"):format(Config.ACTIVE))
else
    -- 實驗炸掉不該讓整個場景停擺，這裡吞掉並印出來就好
    warn(("[Game] 實驗「%s」啟動失敗：%s"):format(Config.ACTIVE, tostring(err)))
end
