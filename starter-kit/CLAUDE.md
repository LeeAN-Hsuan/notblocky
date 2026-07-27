# 專案規矩（給 Claude 的護欄）

> 這份文件的第一讀者是 **AI，不是人**。
> 使用者不該去記「MeshPart 的名字不能信」——那是你該替他避開的坑。
>
> **第一次進來請先讀 `START-HERE.md`。**

## 你手上有哪些文件

| 文件 | 什麼時候讀 |
|---|---|
| **`START-HERE.md`** | **第一次**進來（環境檢查、跑通範例、開始企劃） |
| **`docs/GOTCHAS.md`** | **開工前必讀**。Roblox 的坑清單，每一條都不會報錯 |
| **`PLANNING-PROTOCOL.md`** | 使用者說「我想做一個 XX 遊戲」時 |
| **`experiments/_EXAMPLE-dragon-ride/PLAN.md`** | ★ 企劃前**先看一眼**——一份真的填完的規劃書長什麼樣 |
| **`docs/ASSETS.md`** | ★ **要碰 3D 模型或地形時**（生成 → 整理 → 驗證 → 歸位 → 存檔的完整手續） |
| **`docs/PUBLISH.md`** | ★ 使用者問「怎麼讓我小孩在平板上玩到」時 |
| **`rigging/README.md`** | ★★ 使用者要**「會拍翅膀 / 會彎折」的生物**、而且可以接受樸素造型時。選配工具，要裝 Blender（免費） |
| **`mesh-export/README.md`** | ★★ 使用者要**官方那種漂亮造型、但要真的會彎**時（把官方生的網格弄出 Studio → Blender 綁骨 → 匯回。2026-07-27 實測跑通） |
| **`docs/GOTCHAS.md` §12** | ★★★ **開始「驗證」任何事情之前**。哪些測試手段根本測不到東西——這一節是三次錯誤結論換來的 |

---

## 定位

**使用者不需要會寫 Luau。他需要會說清楚他想做什麼遊戲。**

- 使用者出：規格與判斷（想做什麼、好不好玩、對不對）
- 你出：程式與避坑

---

## ★ 開新實驗時：先當企劃師，再當工程師

**觸發**：使用者說「我想做一個 XXX」「來做 XXX」「想試試 XXX」——**先切成企劃師模式反問，不要直接開工。**

依 `PLANNING-PROTOCOL.md` 走五階段 → 產出 `experiments/<編號>-<名>/PLAN.md`。
使用者確認草稿後才寫檔、才動程式。

**唯一例外**——沒有玩家的純技術驗證（如「驗 Rojo 能不能同步 X」）：不需要 PLAN.md，
直接寫 `NOTES.md` 的「想驗什麼」就開工。

**別讓企劃擋住實驗。** 企劃是為了留下依據，不是儀式。

---

## 新增一個實驗的完整流程

1. **企劃**（有玩家才要）：五階段問答 → `experiments/<編號>-<名>/PLAN.md`
2. **想驗什麼**：`experiments/<編號>-<名>/NOTES.md` —— ★ 在**動手之前**寫，不是做完補
3. **程式**：`src/ReplicatedStorage/Experiments/<名>/init.lua`，回傳 `{ start = function }`
4. **客戶端**（需要才加）：`src/StarterPlayerScripts/<名>Client.client.lua`
5. **切換**：`Config.lua` 改一行 `ACTIVE = "<名>"`。★ **舊實驗不刪不改**

---

## 四條鐵律

### ① 雙軌：腳本走 Rojo，模型走 place

腳本（`.lua`）→ Rojo 同步（改磁碟，Studio 自動更新）
模型（MeshPart / Terrain）→ **Rojo 同步不了**，只能存在 `place/*.rbxl` 裡，手動維護

**真正的分野**：能不能用腳本生出來。
Part（方塊、球、圓柱）→ 你全自動生。
MeshPart（自訂網格）→ 需要使用者在 Studio 裡操作一次（或你用 MCP 生），之後歸腳本管。

⇒ Rojo 的地盤**只限 `.Game` 子資料夾**，不映射整個服務 ——
這樣你放在 `ReplicatedStorage` / `ServerScriptService` 底下的**素材**（`Assets` 資料夾等）
才不會被 Rojo 的同步掃掉。

**唯一的例外**（`default.project.json` 裡看得到）：**`StarterPlayerScripts` 是整個服務直接映射的。**
因為那裡面**只會有客戶端腳本、不會放素材** —— 沒有東西需要被保護。
**⇒ 不要往 `StarterPlayerScripts` 裡塞任何非腳本的東西，Rojo 會把它清掉。**

### ② 舊實驗不刪不改

新實驗自己開資料夾。要重用就把模組提升到 `Shared/`，**不要去改舊的 init**。

### ③ `WaitForChild` 一律帶 timeout

```lua
local x = parent:WaitForChild("Name", 10) or error("[實驗] 找不到 Name")
```

**不帶 timeout 是【永遠 yield 而不是 error】** —— `pcall` 接不住，實驗會**靜默卡死**，
Output 連一行 warn 都不印。

### ④ ★ MCP 不准改腳本

腳本的家在**磁碟**（Rojo 管）。Studio 只是投影幕。

MCP 是你的**眼睛和手**（跑、看、測、查狀態），**不是編輯器**。

**為什麼**：Rojo 是單向水管（檔案 → Studio）。你用 MCP 改了 Studio 裡的腳本，磁碟紋風不動；
Rojo 一同步就把你的改動連根拔掉。而且在拔掉之前，Studio 跑 A、磁碟寫 B，**兩邊漂移且毫無警告**。

⇒ **要改腳本，改磁碟。**

**★ 規則很簡單：只有【兩件事】被禁，其餘的 MCP 工具全部可以用。**

### ❌ 黑名單（只有這兩條，但是絕對的）

| 禁的東西 | 為什麼 |
|---|---|
| **`multi_edit`** | 它會改 **Studio 裡**的腳本 → 寫在沙上，Rojo 一同步就連根拔掉 |
| **任何寫入 `Script.Source` 的操作**（含用 `execute_luau` 去寫） | 同上。**改腳本＝改磁碟，沒有例外** |

**要改腳本？用 `Edit` / `Write` 改磁碟上的 `.lua` 檔。就這樣。**

### ✅ 其餘全部可以用（下面只是常用的幾個，**沒列到的不代表禁用**）

| MCP 工具 | 用途 |
|---|---|
| `list_roblox_studios` | ★ **檢查 MCP 有沒有真的接上的唯一可靠方法** |
| `execute_luau` | 查狀態、量東西、整理**素材**（★ **但不准拿來寫 Script.Source**） |
| `get_console_output` | 讀 Output |
| `start_stop_play` | 自己 Play / 停止 |
| `user_keyboard_input` / `user_mouse_input` | 自己操作角色測試 |
| `screen_capture` | 只在「只有眼睛能判斷」時用（★ 吃帳號級圖片額度，省著用） |
| `generate_mesh` / `generate_procedural_model` / `generate_material` | 生素材（**素材不是腳本**） |
| `search_asset` / `insert_asset` | 找／插 Toolbox 的現成素材 |
| `inspect_instance` / `search_game_tree` | 查場景裡有什麼 |
| `script_read` / `script_grep` | ⚠️ **只准用來【比對】**（確認 Rojo 推送到了沒）。**絕不能當成事實來源** —— 磁碟才是 |

---

## ★★★ 兩條驗證紀律（比什麼都重要）

### 1. 不准用嘴巴保證，要量

Roblox 的失敗大多是**安靜的**：Output 零 error，但東西就是不動。

**回報「做好了」之前，先去量可觀察的事實：**

| 你想說 | 該去量的 |
|---|---|
| 「素材生成完了」 | **讀它的幾何**——官方的 AI 會回報 `HoleSpacing=3.8` 但一個孔都沒有 |
| 「角色會飛了」 | **量他的高度變化**，不是看 Output 有沒有印錯 |
| 「碰撞設好了」 | **寫入後等一幀再讀回來**（有些屬性不會立即生效） |
| 「定位件埋好了」 | **量它埋在哪**——順序寫錯會讓它飄到 32 studs 外 |

**只量一個指標，會選到「剛好也滿足那個指標」的錯誤答案。**
**驗涵蓋範圍，要驗邊界，不要驗中心。**

### 2. 量了不夠，還要「看」

**這條是前一條的另一半，而且更容易忘。**

你可以把每一項數據都量成綠的，然後使用者一打開——**東西長得完全不對**。

- **要看真實的環境**：不要為了測試方便把東西固定住、把物理關掉。**假環境會給你一個假的綠燈。**
- **要看對的角度**：從正後方拍，被身體擋住的問題你永遠看不到。
- **有些事只有眼睛能判斷**：造型對不對、姿勢怪不怪、「這看起來像不像一條龍」——
  **量不出來。該截圖就截圖，該問使用者就問。**

---

## ★★ 素材的天花板：它在【素材】，不在【程式】

> **天花板不是「Roblox 做不到骨架動畫」——它做得到。**
> **天花板是「官方 AI 生的模型【沒有骨頭】」。沒有骨頭，就沒有東西可以動。**

官方的 AI 素材生成（`generate_mesh`）**生的是靜態網格 —— 沒有骨架**。

⇒ 對**這種**模型，你只能做「整塊剛體」的旋轉／移動／縮放，
   **做不到細緻的骨架動作**（翅膀拍動時根部黏在身上、四肢自然彎曲……）。

**症狀**：翅膀靜止時完美貼合，一拍動就整片飛出去。
**原因**：腳本讀不到 mesh 的頂點資料，你只能拿**包圍盒**猜「翅膀的根部在哪」，然後把整片翅膀
當硬板繞著那個猜出來的點旋轉。猜錯了，靜止時看不出來，一轉就露餡。

**⇒ 使用者要細緻的骨架動畫、而你手上只有官方 AI 生的模型
   ⇒【一開始就告訴他這條路走不通】。不要花好幾輪去修一個「素材裡根本沒有的東西」。**

### ★★★ 但模型只要【有骨頭】，程式這一側完全接得住

**實測驗證**（22 根骨頭的 Toolbox 模型）：只寫 `Spine` 一根骨頭的 `Transform`，
`neck` / `Head` 自動跟著走，網格**真的彎折**（skinned deformation），**翅膀不會飛出去**。
純 code 驅動，**不需要動畫檔**。

⚠️ **但 `Bone.Transform` 是 "Not Replicated"：伺服器寫，客戶端【看不到】** ⇒ 用它就得在客戶端跑。

★★★ **而 `Bone.CFrame` 會複製**（`Motor6D.C0` 同理）⇒ **多人遊戲可以走伺服器權威**，
不必每個客戶端各算一份。★ 代價：`CFrame` 是 rest pose，要疊在備份的原值上、不能直接覆蓋。
★ `Animator` 只要有軌道在播就每幀洗掉 `Transform`，但**不碰 `CFrame`** ⇒ 掛 `Humanoid` 的模型走 `CFrame`。
做法與三段證據鏈見 `docs/GOTCHAS.md` §7.3b / §7.3c。

**⇒ 所以正確的判斷順序是：先數骨頭（`d:IsA("Bone")`），再決定怎麼動它。**
（★ 名字不能信——`Rigged` / `Animated` 都是行銷詞，要數。）

### ★★ 使用者要「會拍翅膀的生物」時 → 帶他用 `rigging/`

**沒有骨頭就沒得動。所以要嘛去找有骨頭的模型，要嘛自己綁一副。**

`rigging/` 是本框架附的**骨架工廠**（選配，要裝 Blender —— 免費）：
改一個 JSON（`creature.rig.json`）描述生物（軀幹 + 幾隻肢體 + 每隻幾節），
Blender headless 自動建模＋綁骨架＋驗規格 → `.glb` → 匯進 Studio。**使用者不必學 Blender 介面。**

**★★★ 一定要跑 `python rigging/rig_check.py <glb>`** ——
Blender 說「匯出完成」**不代表 glb 裡有骨架**（可能是一塊死網格，而且完全不報錯）。

★ **誠實告訴使用者這個取捨** —— **有三條路，全部實測過**：

| 他要什麼 | 走哪條 | 代價 | 驗過了嗎 |
|---|---|---|---|
| **漂亮造型**（整隻飛、整隻轉就夠） | 官方 `generate_mesh` | 沒有骨頭，不能彎折 | ✅ |
| **漂亮造型 + 關節會動**（手臂擺、尾巴甩） | 官方 `generate_mesh` 給 **`partNames` 拆件** + 每件一個 `Motor6D`（寫 **`C0`**） | 關節處是**剛體接縫**，不會平滑彎折（岩石/機械質感吃得下，皮膚肌肉會露餡） | ✅ 2026-07-24 |
| **漂亮造型 + 真的會彎**（skinned deformation） | 官方 `generate_mesh` → **`EditableMesh` 讀幾何 → 送出 Studio → Blender 綁骨 → glb 匯回** | 多一段管線；貼圖要另外處理；**權重不能用 Blender 自動權重**（見下方） | ✅ 2026-07-27 |
| **精確規格的幾何**（孔距、對稱、可量產） | **`rigging/`** | 造型樸素（低多邊形、幾何感） | ✅ |

> ### ⚠️ 這裡原本寫「兩者不能兼得——官方生的模型出不來（Roblox 不讓你匯出）」
>
> **那句話是錯的，2026-07-27 實測推翻。** 它從來沒被測過，是推論，然後被抄進三份文件用了兩週。
>
> **實測**：`AssetService:CreateEditableMeshAsync` 對官方生的 assetId 直接成功，
> 讀出 1,016 頂點 / 1,208 面 / 1,016 UV / 1,016 法線；
> 用 `HttpService:PostAsync` 送到 `127.0.0.1` 落地成 `.obj`；
> Blender 綁 3 節骨架 → glb → `rig_check` PASS → 匯回 Studio → `HasSkinnedMesh=true`、
> 轉一根骨頭末端位移 0.93 studs、**截圖確認網格真的彎**（並用「整塊剛體轉」當陽性對照，兩者畫面明顯不同）。
>
> **做法見 `docs/GOTCHAS.md` §11。**

⇒ **建議順序不變**：先用官方的把遊戲做起來、確認好玩，**真的需要平滑彎折**再回頭走第三條路。

素材來源與成本（見 `docs/GOTCHAS.md` §3「素材三條路」）：
官方 `generate_mesh`（免費，**無骨架**）／ Toolbox 現成模型（免費，有骨架的多是人形）／
Meshy Rigging API（$0.80/模型）／ **`rigging/`（免費，本框架附）**

---

## ★★ 平板：鍵盤操作在平板上等於沒有操作

**大部分人用這個框架的【目的】就是「讓我小孩在平板上玩到」。**

**Roblox 免費送你搖桿和跳躍鈕。但你自己綁的每一顆鍵，在平板上【一顆按鈕都不會出現】。**

⇒ **企劃階段就要問「在什麼裝置上玩」**（`PLANNING-PROTOCOL.md` 階段 1）。
⇒ 只要會用平板玩：**`createTouchButton` 傳 `true`**，做法見 `docs/GOTCHAS.md` §6.6。
⇒ **★ 發布之前，自己用 Studio → Test → Device → iPad 驗一次。**

**你在電腦上用鍵盤測，每一項都會是綠的 —— 直到小孩在 iPad 上打開它。**
**那是一個假環境給的假綠燈。**

---

## 素材缺席要吵，不要靜默

實驗找不到手動匯入的素材時，**退回佔位版是對的**（實驗不該跑不起來），
但**必須 warn 出「實際看到了什麼」**：

```lua
warn(("[實驗] 找不到 %s，ReplicatedStorage 底下實際有：%s"):format(want, actual))
```

靜默 fallback 害人：使用者只看到「還是方塊」，完全查不出原因。

---

## 常用指令

```bash
rojo serve                       # 啟動同步（localhost:34872）
rojo build --output check.rbxlx  # 不開 Studio 驗證專案樹與檔名慣例
```

啟動 `rojo serve` 後，**還要使用者在 Studio 手動按 Rojo 外掛的 Connect**（這步你代勞不了）。

**Rojo 檔名慣例**：
`Foo.lua` = ModuleScript ／ `Foo.server.lua` = Script ／ `Foo.client.lua` = LocalScript ／
`Foo/init.lua` = 資料夾變 ModuleScript
