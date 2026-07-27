--[[
    SceneTerrain — 地形的存、取、清

    ★★ 為什麼需要它：Terrain 是「全域單例」

    一個 place 只有一個 Terrain，**它不歸任何實驗所有**。
    如果讓地形常駐在 place 裡，跑【任何】實驗都會看到它 ——
    上一個實驗的山谷會蓋在這一個實驗的水池上。

    ⇒ **地形跟 3D 模型一樣，是「實驗的素材」**：
        - Bootstrap 在啟動任何實驗前 `clear()` 掉上一個實驗留下的地形
        - 實驗自己 `load(場景名)` 貼回它要的地形

    ---

    ## 兩種地形，兩條路 —— ★ 先看清楚你要走哪一條

    ### A. 程序化生成（★ 推薦，【不需要任何素材、不需要使用者存檔】）

    直接用 `Terrain:WriteVoxels()` 用程式畫出來。山、峽谷、岩柱、水池 ——
    全部可以用 `math.noise` 生成，而且看不出是程式做的。

    **這條路完全用不到下面的 load / capture。**
    做法見 `docs/GOTCHAS.md` §8.6「規則來自 noise，不要來自迴圈」。

    ### B. 使用者手繪（他自己用 Studio 的地形筆刷畫的）

    ```
    ① 使用者在【Edit 模式】用地形筆刷畫好
    ② 你呼叫 SceneTerrain.capture("場景名")  ← 擷取成 TerrainRegion 存進 ReplicatedStorage
    ③ ★★ 請使用者按 Ctrl+S 存檔             ← 地形走「模型軌」，Rojo 同步不了
    ④ 之後實驗裡 SceneTerrain.load("場景名") 就會貼回來
    ```

    **★ 沒有第 ③ 步，Studio 一關地形就沒了。一定要【明確】請使用者按存檔。**

    ---

    ## 素材格式

    `ReplicatedStorage.Assets.TerrainAssets.<場景名>/` 底下是一組 `TerrainRegion`，
    每個帶 `cx` / `cy` / `cz` 屬性 = `PasteRegion` 時要用的 corner（voxel 座標）。

    **為什麼要分塊**：`CopyRegion` 單次上限 4,194,304 voxels，整片場景放不下。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SceneTerrain = {}

local RES = 4                            -- Roblox 的 voxel 解析度，固定 4
local MAX_VOXELS_PER_REGION = 4194304    -- CopyRegion 的單次上限

--[[
    世界上現在【有沒有】地形？

    ★★ 這裡踩過一個很好笑的坑，值得記下來：

        我原本用 `Terrain.MaxExtents` 判斷 —— **那是錯的。**
        `MaxExtents` 是「地形【最多】能長到哪」，是一個**常數**；
        空白的 Baseplate 上它一樣回傳一個巨大的範圍。
        ⇒ 判斷式**恆為 true** → 每個人第一天跑 Hello 都會被噴「你的地形沒了」（他根本沒有地形）。

    ⇒ **要量佔用，就去讀 voxel**（`ReadVoxels`），不要讀一個聽起來很像的屬性。
      **這正是這個框架的教條：不准用嘴巴保證，要量 —— 而且要量【對的東西】。**

    ⚠️ 這是一次【有界】的掃描（原點附近 ±512 studs、Y −64～192）。
       實測掃這個範圍約 73ms（伺服器啟動時跑一次，不影響體感）。

       ★ 為什麼是 ±512 而不是更小：Baseplate 本身就是 512×512，
         只掃 ±256 的話，人在地圖邊緣畫的地形會**掃不到**
         —— 而 `Terrain:Clear()` 【照樣會把它刪掉】，
         那句救命的 warn 就剛好在最需要的時候不出現。

       掃描範圍外的地形它看不到 → 那時候它會**安靜地回 false**。
       **失敗的方向是「不吵」，不是「亂吵」** —— 這是刻意選的：
       漏講一句提示，遠比每次開機都對著沒有地形的人喊「你的地形沒了」好。
]]
function SceneTerrain.hasTerrain()
    local ok, found = pcall(function()
        local region = Region3.new(Vector3.new(-512, -64, -512), Vector3.new(512, 192, 512))
                              :ExpandToGrid(RES)
        -- ★ ReadVoxels 回傳的是【巢狀的 Lua 表】（materials[x][y][z]），
        --   不是有 .Size 屬性的物件 —— 尺寸要用 # 取。
        local materials = workspace.Terrain:ReadVoxels(region, RES)

        for x = 1, #materials do
            local plane = materials[x]
            for y = 1, #plane do
                local row = plane[y]
                for z = 1, #row do
                    if row[z] ~= Enum.Material.Air then
                        return true   -- ★ 找到一格就夠了，立刻收工
                    end
                end
            end
        end
        return false
    end)

    return ok and found or false
end

--[[
    清空整個世界的地形。由 Bootstrap 在啟動實驗前呼叫。

    ★★ 清掉【非空】的地形時，一定要吵。

    因為這裡是一個很容易踩、而且【零錯誤訊息】的坑：
      使用者在 Studio 裡用地形筆刷辛辛苦苦畫了一片山、按了 Ctrl+S（他每一步都做對了）
      → 按 Play → **山不見了**（就是被這一行刪的）
      → Output 一片乾淨，他只會說「不能動」。

    ⇒ 手繪的地形【不會自己活過 Play】。要先 capture() 成素材，實驗再 load() 回來。
]]
function SceneTerrain.clear()
    local terrain = workspace.Terrain

    -- 先探一下「刪掉的是不是有東西」—— 有東西才吵，空的就安靜（不要每次啟動都洗版）
    local hadSomething = SceneTerrain.hasTerrain()

    terrain:Clear()

    if hadSomething then
        warn("[SceneTerrain] ★ 已清空世界上原有的地形（每個實驗啟動前都會清，因為 Terrain 是全域單例）")
        warn("  ⚠️ 如果那是【你自己用地形筆刷畫的】—— 它現在沒了，而且按停止也不會回來。")
        warn("  ⇒ 手繪地形不會自己活過 Play。要留住它：")
        warn("     ① 停止 Play，回 Edit 模式（畫的東西還在）")
        warn("     ② 請 Claude 呼叫 SceneTerrain.capture(\"場景名\") 把它擷取成素材")
        warn("     ③ 按 Ctrl+S 存檔")
        warn("     ④ 實驗裡 SceneTerrain.load(\"場景名\") 就會貼回來")
    end
end

--- 找（或建）素材庫的資料夾：ReplicatedStorage.Assets.TerrainAssets
local function assetsFolder(create)
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    if not assets and create then
        assets = Instance.new("Folder")
        assets.Name = "Assets"
        assets.Parent = ReplicatedStorage
    end
    if not assets then return nil end

    local terrain = assets:FindFirstChild("TerrainAssets")
    if not terrain and create then
        terrain = Instance.new("Folder")
        terrain.Name = "TerrainAssets"
        terrain.Parent = assets
    end
    return terrain
end

--[[
    把【現在世界上的地形】擷取成素材，存進 ReplicatedStorage。

    ★ 用在「使用者自己用 Studio 的地形筆刷畫了一片地形」的時候。
    ★ 只能在 Edit 模式跑（Play 模式擷取的東西，按停止就蒸發了）。
    ★★ 擷取完，一定要【明確請使用者按 Ctrl+S】—— 不然 Studio 一關就沒了。

    @param sceneName string — 存成什麼名字
    @param extent number?  — 擷取範圍（studs，以原點為中心的正方形），預設 512
    @param yMin number?    — 高度下界，預設 -256
    @param yMax number?    — 高度上界，預設 256
    @return boolean, string
]]
function SceneTerrain.capture(sceneName, extent, yMin, yMax)
    extent = extent or 512
    yMin = yMin or -256
    yMax = yMax or 256

    local terrain = workspace.Terrain
    local folder = assetsFolder(true)

    local old = folder:FindFirstChild(sceneName)
    if old then old:Destroy() end

    local scene = Instance.new("Folder")
    scene.Name = sceneName
    scene.Parent = folder

    -- ★ 分塊：CopyRegion 單次上限 4,194,304 voxels。依高度範圍反推每塊的 XZ 邊長。
    local yVox = math.max(1, (yMax - yMin) / RES)
    local maxXZ = math.floor(math.sqrt(MAX_VOXELS_PER_REGION / yVox * 0.8))
    local chunk = math.max(64, math.floor(maxXZ * RES / 8) * 8)   -- 對齊 8 studs

    local n = 0
    for x = -extent, extent - 1, chunk do
        for z = -extent, extent - 1, chunk do
            local vmin = Vector3int16.new(x / RES, yMin / RES, z / RES)
            local vmax = Vector3int16.new((x + chunk) / RES, yMax / RES, (z + chunk) / RES)

            local ok, region = pcall(function()
                return terrain:CopyRegion(Region3int16.new(vmin, vmax))
            end)

            if ok and region then
                n += 1
                region.Name = ("blk_%d_%d"):format(x, z)
                -- ★ 記下貼回去要用的 corner —— 沒有這個，load() 不知道該貼在哪
                region:SetAttribute("cx", vmin.X)
                region:SetAttribute("cy", vmin.Y)
                region:SetAttribute("cz", vmin.Z)
                region.Parent = scene
            else
                warn(("[SceneTerrain] 區塊 (%d, %d) 擷取失敗：%s"):format(x, z, tostring(region)))
            end
        end
    end

    if n == 0 then
        scene:Destroy()
        return false, "一個區塊都沒擷取到"
    end

    local msg = ("已擷取 %d 個區塊 → ReplicatedStorage.Assets.TerrainAssets.%s"):format(n, sceneName)
    print("[SceneTerrain] " .. msg)
    print("[SceneTerrain] ★★ 現在請使用者按 Ctrl+S 存檔 —— 地形不能自動同步，不存就沒了")
    return true, msg
end

--[[
    把某個場景的地形貼回世界。

    @param sceneName string — Assets.TerrainAssets 底下的資料夾名
    @return boolean — 是否真的貼上了（失敗時已 warn，呼叫端可以繼續跑）
]]
function SceneTerrain.load(sceneName)
    -- ★ 素材缺席要【吵】、不要靜默：講清楚「實際看到了什麼」、以及「該怎麼辦」
    local folder = assetsFolder(false)
    if not folder then
        warn(("[SceneTerrain] 找不到 ReplicatedStorage.Assets.TerrainAssets → 場景「%s」不會出現")
            :format(sceneName))
        warn("  地形走【模型軌】，Rojo 同步不了。兩條路：")
        warn("  (A) 改用程序化生成（Terrain:WriteVoxels + math.noise）—— 不需要素材，推薦")
        warn("  (B) 請使用者在 Studio 畫好地形 → 呼叫 SceneTerrain.capture() → 請他 Ctrl+S 存檔")
        return false
    end

    local scene = folder:FindFirstChild(sceneName)
    if not scene then
        local names = {}
        for _, child in ipairs(folder:GetChildren()) do
            table.insert(names, child.Name)
        end
        warn(("[SceneTerrain] TerrainAssets 底下沒有「%s」，實際只有：%s")
            :format(sceneName, #names > 0 and table.concat(names, ", ") or "（空的）"))
        return false
    end

    local terrain = workspace.Terrain
    local pasted = 0
    for _, region in ipairs(scene:GetChildren()) do
        if region:IsA("TerrainRegion") then
            local cx, cy, cz = region:GetAttribute("cx"), region:GetAttribute("cy"), region:GetAttribute("cz")
            if cx and cy and cz then
                -- pasteEmptyCells = true：連空氣一起貼，貼出來才跟原場景一模一樣
                terrain:PasteRegion(region, Vector3int16.new(cx, cy, cz), true)
                pasted += 1
            else
                warn(("[SceneTerrain] 區塊「%s」沒有 cx/cy/cz 屬性，不知道要貼回哪裡 → 跳過")
                    :format(region.Name))
            end
        end
    end

    if pasted == 0 then
        warn(("[SceneTerrain] 場景「%s」裡一個 TerrainRegion 區塊都沒有"):format(sceneName))
        return false
    end

    print(("[SceneTerrain] 場景「%s」已載入（%d 個區塊）"):format(sceneName, pasted))
    return true
end

return SceneTerrain
