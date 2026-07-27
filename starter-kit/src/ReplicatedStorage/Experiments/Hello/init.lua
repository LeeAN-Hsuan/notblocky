--[[
    Hello — 範例實驗：一群會跳的方塊

    ★ 這個範例【不需要任何 3D 素材】。純腳本，第一天就能跑。

    它存在的唯一目的：讓使用者【看到東西動】，確認整條管線通了：
        磁碟的 .lua  →  Rojo  →  Studio  →  Play  →  畫面上有東西

    跑通之後就可以刪掉它、或留著當參考。

    ★ 這裡示範了幾件之後每個實驗都會用到的事：
      - 實驗回傳 { start = function }，Bootstrap 會呼叫它
      - 東西全部由腳本生成（Part 可以，MeshPart 不行 —— 見 CLAUDE.md 鐵律①）
      - 用 RunService 做每幀更新，並且在關卡被銷毀時 disconnect（不然會洩漏）
]]

local RunService = game:GetService("RunService")

local M = {}

function M.start()
    local level = Instance.new("Model")
    level.Name = "HelloLevel"
    level.Parent = workspace

    -- 一排方塊
    local cubes = {}
    local COLORS = {
        Color3.fromRGB(239, 108, 96),
        Color3.fromRGB(246, 178, 84),
        Color3.fromRGB(126, 200, 130),
        Color3.fromRGB(96, 168, 232),
        Color3.fromRGB(168, 130, 228),
    }

    for i = 1, 5 do
        local cube = Instance.new("Part")
        cube.Name = "Cube" .. i
        cube.Size = Vector3.new(4, 4, 4)
        -- ★ Y = 3：方塊半高 2 + 地板頂面 1 = 3 → 底面【剛好貼在地板上】。
        --   （寫 4 的話它會浮在地板上方一格 —— 而「東西浮在半空」正是這個框架
        --     最常舉的失敗例子。連範例都不該犯。）
        cube.Position = Vector3.new((i - 3) * 7, 3, -12)
        cube.Anchored = true          -- 我們自己控制它的位置，不要物理插手
        cube.Color = COLORS[i]
        cube.Material = Enum.Material.SmoothPlastic
        cube.Parent = level
        table.insert(cubes, { part = cube, baseY = cube.Position.Y, phase = i * 0.6 })
    end

    -- 一塊地板（不然方塊會浮在空中，看起來很怪）
    -- ★ 往 -Z 挪開，避開 Baseplate 內建的 SpawnLocation（在原點，約 12×12）——
    --   兩者共面重疊會 z-fighting（出生點附近的地面會閃爍）
    local floor = Instance.new("Part")
    floor.Name = "Floor"
    floor.Size = Vector3.new(48, 1, 24)
    floor.Position = Vector3.new(0, 0.5, -20)   -- 涵蓋 z −32～−8，方塊在 z=−12 上面
    floor.Anchored = true
    floor.Color = Color3.fromRGB(72, 76, 88)
    floor.Material = Enum.Material.Slate
    floor.Parent = level

    -- 每幀讓方塊上下跳（各自差一個相位，看起來像波浪）
    local t0 = os.clock()
    local conn = RunService.Heartbeat:Connect(function()
        local t = os.clock() - t0
        for _, c in ipairs(cubes) do
            local y = c.baseY + math.abs(math.sin(t * 2 + c.phase)) * 5
            c.part.Position = Vector3.new(c.part.Position.X, y, c.part.Position.Z)
        end
    end)

    -- ★ 關卡被銷毀時要 disconnect，不然切換實驗之後這個迴圈還在跑
    level.Destroying:Connect(function()
        conn:Disconnect()
    end)

    print("[Hello] 五個方塊正在跳。如果你看得到它們 —— 恭喜，整條管線通了。")
    print("[Hello] 接下來：跟 Claude 說你想做什麼遊戲。")
end

return M
