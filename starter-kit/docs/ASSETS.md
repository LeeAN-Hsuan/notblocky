# ASSETS — 3D 素材的完整手續

> **這份文件是寫給 Claude 的。**
>
> **它回答一個問題：AI 生出來的 3D 模型，從生成到腳本能用，中間到底要做什麼？**
>
> 沒有這份文件，每一個新的 session 都會重新發明一套擺放規則，
> 然後下一個 session 的 Claude 找不到上一個放的東西。**慣例的價值就在於統一。**

---

## 0. 先問一句：這個東西真的需要 3D 模型嗎？

**很多東西用 `Part`（方塊、球、圓柱、楔形）就夠了，而且 `Part` 全部歸你管——不必碰下面這整套流程。**

| 要做的東西 | 建議 |
|---|---|
| 平台、牆、階梯、箱子、按鈕、道路 | **用 `Part`**。腳本直接生，零手續 |
| 角色、生物、武器、家具、載具 | 需要 MeshPart → 走下面的流程 |
| 地形（山、峽谷、水） | 用 `Terrain`（見 `Shared/SceneTerrain.lua`） |
| 火焰、煙、光暈、閃電 | **用 `ParticleEmitter` + `PointLight`，不要做成網格**。特效不是幾何 |

**★ 第一個實驗盡量不要碰 MeshPart。** 讓使用者先看到東西動、先確認整條管線通了，再引入素材。

---

## 1. 素材的生命週期（五步，缺一不可）

```
① 生成      你用 MCP 的 generate_mesh 生出來 → 它掉在 Workspace 裡
② 整理      扁平化、改名、打標籤、埋定位件、設碰撞  ← ★ 你做，用 execute_luau
③ 驗證      用 AssetSpec 量它 —— 不要相信它自己說的  ← ★ 你做
④ 歸位      搬到 ReplicatedStorage 的正確位置        ← ★ 你做
⑤ 存檔      ★★ 使用者在 Studio 按 Ctrl+S            ← ★★★ 你做不到，一定要請他按
```

### ⚠️⚠️ 第 ⑤ 步是整條流程最容易白做工的地方

**3D 模型走的是「模型軌」——Rojo 同步不了它**（幾何是二進位，塞不進文字檔）。

⇒ 它**只活在 Studio 的記憶體裡**，直到有人存檔。

⇒ **而且如果你是在 Play 模式生成的，按下停止的那一刻它就蒸發了。**

**所以：**

1. **一定要在 Edit 模式（停止狀態）生成、整理素材**
2. **整理完，明確地請使用者按 Ctrl+S**。不要假設他知道要按。就直接說：

> 「龍已經整理好放進素材庫了。**請你在 Studio 按一下 Ctrl+S 存檔**——
> 3D 模型不能自動同步，不存檔的話 Studio 一關它就沒了。」

---

## 2. ★ 擺放慣例（這是本文件的核心）

**所有 3D 素材一律放在 `ReplicatedStorage` 底下，照這個結構：**

```
ReplicatedStorage
└── Assets                      ← 所有手動素材的家（跟 Rojo 管的 Game 分開）
    ├── DragonAssets            ← 一個「素材家族」一個資料夾
    │   └── Dragon              ← Model：扁平化後，MeshPart 直接掛在底下
    │       ├── Head    [MeshPart]
    │       ├── Body    [MeshPart]
    │       ├── WingL   [MeshPart]
    │       └── ...
    ├── WeaponAssets
    │   ├── Sword   [Model]
    │   └── Shield  [Model]
    └── TerrainAssets           ← ★ 地形是特例，見 Shared/SceneTerrain.lua
        └── RockScene           ← 一組 TerrainRegion（分塊，各帶 cx/cy/cz 屬性）
```

**規則：**

| | 規則 |
|---|---|
| **家族資料夾** | `<類別>Assets`（`DragonAssets` / `WeaponAssets` / `TerrainAssets`） |
| **模型名** | 大駝峰，語意化（`Dragon`、`Sword`、`Crate`） |
| **部件名** | 大駝峰（`Head` / `Body` / `WingL` / `WingR`）。★ 官方生的名字要改（它會給 `head_geom` 這種） |
| **結構** | **扁平**——MeshPart 直接掛在 Model 底下，不要有中間層 |
| **PrimaryPart** | 一定要設（通常是軀幹） |
| **Anchored** | 素材庫裡的一律 `Anchored = true`。實驗生成時再自己決定 |

### 腳本怎麼找它（一律這樣寫）

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local assets = ReplicatedStorage:FindFirstChild("Assets")
local family = assets and assets:FindFirstChild("DragonAssets")
local src = family and family:FindFirstChild("Dragon")

if not src then
    -- ★ 素材缺席要【吵】，不要靜默（鐵律：講清楚實際看到了什麼）
    warn("[實驗] 找不到 ReplicatedStorage.Assets.DragonAssets.Dragon")
    warn("  3D 模型走「模型軌」，Rojo 同步不了 —— 要在 Studio 裡生成並【存檔】")
    local names = {}
    for _, c in ipairs(assets and assets:GetChildren() or ReplicatedStorage:GetChildren()) do
        table.insert(names, c.Name)
    end
    warn(("  實際看到的是：%s"):format(table.concat(names, ", ")))
    return nil     -- 退回佔位版（用 Part 拼一個），但一定要 warn 出來
end

local dragon = src:Clone()
```

**★ 為什麼要吵**：靜默 fallback 害人——使用者只看到「還是方塊」，完全查不出原因。

---

## 3. 整理素材的標準流程（用 `execute_luau` 做，Edit 模式）

官方 AI 生出來的東西**沒有一項是可以直接用的**。這五件事每次都要做：

### ① 扁平化（官方會多包一層 Model）

```
生出來長這樣：              要整理成這樣：
Dragon [Model]              Dragon [Model]
  ├─ body [Model]             ├─ Body  [MeshPart]
  │    └─ Body [MeshPart]     ├─ Head  [MeshPart]
  └─ head [Model]             └─ ...
       └─ Head [MeshPart]
```

⇒ 不扁平化，`FindFirstChild("Body")` **找不到**（它不是直接子物件）。

### ② 改名（`head_geom` → `Head`）

### ③ 打標籤（`CollectionService:AddTag`）

**官方給 0 個 Tag。** 想用 `CollectionService` 找東西，就自己補。

### ④ 埋定位件（Attachment）

**官方給 0 個 Attachment。** 掛載點、樞軸、座位——全部要你自己算、自己埋。

⚠️ **`Attachment.WorldPosition` 一定要在設 `Parent` 之後才寫**：

```lua
-- ❌ 錯：此時它還沒有 Parent，這個值會被當成「相對偏移」重新解釋，位置整個跑掉
a.WorldPosition = pos
a.Parent = part

-- ✅ 對
a.Parent = part
a.WorldPosition = pos
```

### ⑤ 設碰撞精度與 Anchored

**★ 碰撞精度要選哪一個，取決於【這個素材要不要做「內部」的接觸判定】：**

| 你的素材 | 用哪個 | 為什麼 |
|---|---|---|
| **實心的東西**（龍、車、劍、箱子） | `Box` | **便宜**。外形碰一碰就夠了 |
| **★ 空心／有開口的東西**（假牙咬合、杯子裝東西、環圈穿過） | `PreciseConvexDecomposition` | **Box 會把「空的內部」也算成實心** → 東西永遠塞不進去、咬不下去 |

```lua
-- 實心的東西（大多數情況）
p.CollisionFidelity = Enum.CollisionFidelity.Box
p.Anchored = true            -- 素材庫裡一律 Anchored
p.CanCollide = false         -- 部件之間不要互相卡

-- ★ 空心／要做內部接觸判定的東西，改用：
-- p.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
```

**⚠️ 這一格要跟 `AssetSpec.certify` 的 `precise` 對齊：**
`precise = true` 的意思是「**我要求這個素材是 `PreciseConvexDecomposition`**」，
不是就 FAIL。**所以：素材設 `Box` 就不要傳 `precise = true`**，否則保證拿到一張 FAIL
（而你會以為素材壞了，其實只是兩邊沒對齊）。

⚠️ **`CollisionFidelity` 在 runtime 腳本裡寫不了**（`lacking capability Plugin`）——
只能在 **Edit 模式 / Plugin**（MCP 的 `execute_luau` 算）裡設。
**⇒ 這也是為什麼 `AssetSpec` 對它是【只驗，不修】**：它修不了，只能吵。
⚠️ 而且**寫入後不會立即反映**，要等一幀才讀得到新值。

---

## 4. ★★★ 驗證：不要相信它，去量

**官方的 AI 會回報「已完成，完全符合規格」——然後幾何是空的。**

（實測：叫它生「孔距精確 3.8 studs 的架子」→ 一個孔都沒有，但 attributes 寫著 `HoleSpacing=3.8`。）

⇒ **用 `Shared/AssetSpec.lua` 去量。** 它驗六項：分件、成對相稱、碰撞精度、朝向、定位件、標籤。

### ★★★★ 而且：「零件叫什麼名字」也不能信

**這條害人害得最慘。** 實測一條龍：

- **`Body` 不是軀幹** —— 它是**脖子＋胸口，而且是垂直站著的**
- **`Tail` 才是軀幹＋尾巴**（體積是 Body 的**三倍**）

**你要求 `partNames = "body, tail, ..."`，它確實照著命名了——但它對「body」的理解跟你不一樣。**

⇒ **不要用名字找東西。用可觀察的事實找：**

```lua
-- 找「軀幹」：體積最大的那塊（排除翅膀和頭）
local torso, maxVol = nil, 0
for _, p in ipairs(model:GetChildren()) do
    if p:IsA("MeshPart") and p.Name ~= "WingL" and p.Name ~= "WingR" and p.Name ~= "Head" then
        local vol = p.Size.X * p.Size.Y * p.Size.Z
        if vol > maxVol then maxVol, torso = vol, p end
    end
end

-- 找「背」：對軀幹發射線，看打到哪裡、多高
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include   -- ★ 不是 Whitelist（那是舊名，已 deprecated）
params.FilterDescendantsInstances = { torso }
local hit = workspace:Raycast(origin, Vector3.new(0, -120, 0), params)
local backY = hit and hit.Position.Y
```

⚠️ **`workspace:Raycast` 只認 workspace 樹裡的東西。**
模型還在 `ReplicatedStorage` 或 `nil` 底下，射線會**什麼都打不到**（回傳 nil），
然後你的 fallback 靜靜接手，沒人知道。
⇒ **要先 `Parent` 進 workspace、先 `PivotTo` 到定位，才能用射線找東西。**

---

## 5. ★★ 有些東西量不出來 —— 那就請使用者標

**你讀不到 mesh 的頂點資料**（Roblox 不開放給腳本）。所以有些東西你**永遠只能猜**：

- 翅膀從**哪個關節**長出來？
- 劍該**握在哪個位置**？
- 騎士該**坐在哪裡**？

**這些是「語意」，不是「幾何」。幾何可以量，語意不能猜。**

⇒ **請使用者在 Studio 裡放一個 `Attachment` 標出來。** 那一個點，是他一眼看得到、你永遠看不到的。

```lua
-- 人標的優先，你猜的墊底
local att = wing:FindFirstChild("WingPivot")
if att then
    local dist = (att.WorldPosition - wing.Position).Magnitude
    if dist <= wing.Size.Magnitude / 2 + 1 then     -- ★ 還是要驗：標錯位置也要抓出來
        return att.WorldPosition
    end
    warn("[Rig] WingPivot 標的位置離翅膀太遠，改用猜的")
end
return guessFromBoundingBox(wing)     -- 會怪，但不會壞
```

**這揭示了這個框架真正的工作流：**

> **AI 生素材 → 人標定關節（放幾個 Attachment）→ AI 接手驅動**

**放一個 Attachment 不需要懂 Luau。使用者做得到。**
而且這比「AI 全自動」誠實得多——**因為 AI 真的做不到。**

---

## 6. ★★★ 天花板：AI 生的模型沒有骨架

> **★ 先講清楚天花板在哪：它在【素材】，不在【程式】。**
> **「Roblox 做不到骨架動畫」是【錯的】——它做得到（見下面「有骨頭的話」）。**
> **真相是：官方 AI 生的模型【沒有骨頭】，而沒有骨頭就沒有東西可以動。**

**這條一定要在使用者提出需求的當下就告訴他，不要等他期待了三天。**

**你只能對 AI 生的模型做「整塊剛體」的旋轉／移動／縮放。**

**做不到**：翅膀拍動時根部漂亮地黏在身上、四肢自然彎曲、尾巴柔軟擺動。

**症狀**：翅膀靜止時完美貼合，**一拍動就整片飛出去**。
**原因**：讀不到頂點資料 → 只能拿包圍盒猜樞軸 → 把整片翅膀當硬板繞著猜出來的點轉。
猜錯了，靜止時看不出來（根本沒動它），一轉就露餡。

### ★★★ 有骨頭的話：純 code 就能驅動，網格會【真的變形】（實測驗證）

**⇒ 拿到任何模型，第一件事是【數骨頭】，不是看名字**（`Rigged` / `Animated` 都是行銷詞）：

```lua
local bones = 0
for _, d in ipairs(model:GetDescendants()) do
    if d:IsA("Bone") then bones += 1 end
end
```

- `bones > 0` → **skinned mesh**：改 `bone.Transform`（可寫的 CFrame）就能驅動，
  **骨頭階層自動生效**（動 `Spine`，`neck`/`Head` 跟著走），**翅膀不會飛出去**，
  **不需要動畫檔**。⚠️ **但只有【客戶端】寫得動** —— 完整做法與實測見 `docs/GOTCHAS.md` §7.3
- `bones = 0` → 靜態網格：只能剛體旋轉，回到上面的天花板

### ★★ 沒有現成的有骨頭模型？自己綁一副 → `rigging/`

本框架附了一個**骨架工廠**（選配，要裝 Blender —— 免費）：
改一個 JSON 描述生物（軀幹 + 幾隻肢體 + 每隻幾節）→ 自動建模＋綁骨架＋驗規格 → `.glb` → 匯進 Studio。
**使用者不必學 Blender 的介面。** 見 `rigging/README.md`。

**★ 但要誠實告訴他取捨**：官方 AI 的造型漂亮得多，`rigging/` 產的造型樸素（低多邊形）。

> ### ⚠️ 這裡原本寫「兩者不能兼得——官方生的模型出不來」。**那是錯的，2026-07-27 實測推翻。**
>
> 那句話從來沒有人測過，它是推論，然後被抄進三份文件用了兩週。
> **官方生的網格出得來** —— 只是不是用「匯出」鍵，是用 `EditableMesh` 讀幾何 + `HttpService` 送出來。
> 完整做法與實測數據見 **`docs/GOTCHAS.md` §11「把資料弄出 Studio」**。

⇒ **所以現在有三條路，不是兩條**（見下方對照表）。

### 替代方案（都要額外成本，讓使用者選）

| 方案 | 有骨架？ | 成本 | 備註 |
|---|---|---|---|
| **改設計，避開骨架** | — | 免費 | ★ **先試這個**。翅膀「張開滑翔」不拍動，在空中看起來其實很對 |
| **Toolbox 現成模型** | 有些有 | 免費 | 用 `search_asset` 找。★ 但實測：有骨架的**清一色是直立人形**，四足生物幾乎沒有 |
| **Meshy Rigging API** | ✅ | 約 US$0.80/模型＋訂閱 | 有 REST API（你可以自己呼叫）。支援四足，附 600+ 預設動作 |
| **Blender 手綁** | ✅ | 免費 | 要學要裝，推翻「不必碰 3D 建模」的前提 |

**★ 建議的說法**（直接照抄）：

> 「這個可以做——**但有一件事我必須現在講**：**翅膀不會「拍」**。
>
> AI 生的 3D 模型**沒有骨架**。我能讓整條龍飛、能讓你騎上去，但**做不到翅膀拍動時根部黏在身上**。
> 這不是我不會寫，是模型裡沒有骨頭。
>
> 所以請你選：**(A) 翅膀張開滑翔、不拍動**（免費，而且在空中看起來其實很對）／
> **(B) 花 US$0.80 用 Meshy 綁骨架**（翅膀就能真的拍，但要註冊付費）。
>
> **我建議先做 A**——先把「騎上去、飛起來」跑通、確認好玩了，再決定值不值得為翅膀花那 0.8 塊。」

---

## 7. Toolbox：直接拿現成的來用

**如果使用者不在意「自己生」，Toolbox 有大量免費模型，而且你可以直接搜尋、直接插入。**

```
search_asset  → 找（可以篩免費、篩已驗證創作者）
insert_asset  → 插進場景
```

**但要先驗**（名字一樣不能信）：

```lua
-- 有沒有【真的骨頭】？
local bones = 0
for _, x in ipairs(model:GetDescendants()) do
    if x:IsA("Bone") then bones += 1 end
end
-- bones > 0 → skinned mesh，可以做骨架動畫
-- bones = 0 → 靜態網格，跟 AI 生的一樣，只能剛體旋轉
```

**實測的現實**（別抱太大期望）：
- **免費的舊模型**（2009–2012）：Part 拼的，沒有網格、更沒有骨架
- **免費的新模型**：有骨架，但**清一色是直立人形**（實測一隻「Dragon」，22 根骨頭全是 `Hips`/`Spine`/`Arm`，
  **沒有翅膀骨、沒有尾巴骨**——那是一個穿龍皮的人形角色，騎不上去）
- **付費模型**：選擇極少，而且**買了才能測**（不能先插進來驗）
