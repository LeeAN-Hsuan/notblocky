--[[
    Flight — 角色垂直飛行（可被任何實驗重用的共用模組）

    做法：在 HumanoidRootPart 掛一個 LinearVelocity，用 **Line 模式只約束 Y 軸速度**。
    為什麼是 Line 而不是 Vector：Line 只管垂直分量，水平移動仍然完全交給 Humanoid →
    走路、轉身、WASD 的手感原封不動，我們只多接管「上下」這一個軸。

    另一個好處：Line 模式是「約束到指定速度」，引擎會自己算要出多少力（含抵抗重力）→
    LineVelocity = 0 就是【懸停】，不必自己算重力補償。

    三種狀態：
      lift  按住空白鍵 → 以 lift 速度上升
      glide 放開（翅膀類）→ 以 glide 速度緩降（滑翔感）
      off   放開（噴射背包）→ 停用約束，自由落體

    ★ 跑在客戶端：角色的物理本來就由本機玩家擁有，本地施力最跟手；
      位置變化會照常複製給伺服器。實驗場不做防作弊。
]]

local Flight = {}

--[[
    ★★★ MaxForce 必須依【實際質量】算，而且要算「加速度」不是「幾倍重力」
    （2026-07-13 血淚，實驗 006 的飛龍）

    原本寫死 100000 —— 那是給玩家角色（AssemblyMass ≈ 15）用的，綽綽有餘。
    飛龍的 AssemblyMass = 738，重了 50 倍。

    ★ 第一次修錯了：以為「4 倍重力就夠」（578,975 > 抵抗重力所需的 144,596）。
      結果龍還是一動也不動 —— 因為 **Humanoid 的地面控制會死命抵抗**，
      它要維持 HipHeight，會把龍往下按。光是撐住體重不夠，還要【壓過 Humanoid 的意志】。

    ★ 真正的判準是【加速度】：
        004 的玩家角色能飛，是因為 100000 / 15 = 6666 studs/s² —— 遠遠壓倒 Humanoid。
        我給龍的只有 578975 / 738 = 784 studs/s²，差了 8 倍。
      ⇒ 用同樣的加速度反推力：MaxForce = mass × TARGET_ACCEL。

    ⇒ 而且這一切【什麼錯誤都不會印】：LinearVelocity 顯示 Enabled=true、
      LineVelocity=55、方向正確 —— 全部看起來都對，龍就是不動。
]]
local TARGET_ACCEL = 6800     -- studs/s²（承 004 實證：100000 / 15 ≈ 6666，取整並留餘裕）
local MIN_FORCE = 100000      -- 輕量角色的下限（維持 004 原本的手感）

function Flight.attach(character)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    -- ★ 質量要在這一刻才讀（載具比玩家重 50 倍，寫死一定錯）
    local mass = hrp.AssemblyMass
    local MAX_FORCE = math.max(MIN_FORCE, mass * TARGET_ACCEL)

    local att = hrp:FindFirstChild("FlightAttachment")
    if not att then
        att = Instance.new("Attachment")
        att.Name = "FlightAttachment"
        att.Parent = hrp
    end

    --[[ ★ 先清掉舊的約束（重複 attach 是常態：角色重生、換載具、換實驗都會再呼叫一次）

         不清的話會有【兩個 LinearVelocity 疊在同一個 HRP 上】。
         如果舊的那個當時 Enabled = true，它就會**永遠拉著角色**，
         而新的那個怎麼設都壓不過它 —— **零 error，角色就是一直往上飄／往下沉。**
         （Attachment 本來就有重用邏輯，約束卻每次 new 一個 —— 這是我自己的疏漏。） ]]
    local oldLv = hrp:FindFirstChild("FlightVelocity")
    if oldLv then
        oldLv:Destroy()
    end

    local lv = Instance.new("LinearVelocity")
    lv.Name = "FlightVelocity"
    lv.Attachment0 = att
    lv.RelativeTo = Enum.ActuatorRelativeTo.World      -- 世界座標的「上」，不隨角色轉頭而歪
    lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
    lv.LineDirection = Vector3.new(0, 1, 0)            -- 只管垂直軸
    lv.LineVelocity = 0
    lv.MaxForce = MAX_FORCE
    lv.Enabled = false                                 -- 平時不介入，走路跳躍照常
    lv.Parent = hrp

    return { lv = lv, hrp = hrp, character = character }
end

--[[
    每幀呼叫。回傳目前模式，**共有四個值**：

      "fly"    推進中（正在上升）
      "ceil"   ★ 已抵達飛行高度上限，懸在頂端（只有你傳了 ceiling 才可能出現）
      "glide"  滑翔中（放開按鍵、離地、正在下墜）
      "off"    沒介入（走路、跳躍、自由落體）

    ⚠️ **不要只判斷 "fly"**。像 `if mode == "fly" then 拍翅膀 end` 這種寫法，
       角色一飛到上限，`mode` 就變成 `"ceil"` → **翅膀會安靜地停下來**（零 error）。
       要判斷「是不是在飛」，寫 `mode == "fly" or mode == "ceil"`。

    參數：holding＝空白鍵按住；cfg＝{ lift, glide }；grounded＝腳是否踩在地上

    ★ 滑翔的條件寫死三個「而且」，每一個都是踩過的坑：
      1. 沒按空白鍵      —— 不然就變成推進
      2. 【腳沒踩在地上】—— 少了這條，站著也被恆定往下壓 → 壓穿地板掉出地圖（2026-07-12 實測）
      3. 【正在往下掉】  —— 少了這條，一跳起來上升速度就被壓成 glide 值 → 根本跳不起來

    滑翔是「接住下墜」，不是「持續往下拉」。少任何一條，它就從功能變成災難。
]]
-- ceiling：飛行高度上限（studs，相對地面）。altitude：目前離地高度。
--   兩者皆可省略 ＝ 無上限。
--   接近上限時線性減速（而不是硬撞一堵看不見的牆）→ 手感像「爬到極限、慢慢停住懸在那裡」
function Flight.update(handle, holding, cfg, grounded, altitude, ceiling)
    if not handle or not handle.lv or not handle.lv.Parent then return "off" end
    local lv = handle.lv

    if holding then
        local lift = cfg.lift
        if ceiling and altitude then
            -- 剩餘空間越小，容許的上升速度越小；到頂就是 0（＝懸停，Line 模式自動抵抗重力）
            lift = math.clamp((ceiling - altitude) * 6, 0, cfg.lift)
        end
        lv.LineVelocity = lift
        lv.Enabled = true
        return (lift > 0.5) and "fly" or "ceil"    -- ceil ＝ 已抵達上限、懸在頂端
    end

    local falling = handle.hrp.AssemblyLinearVelocity.Y < -0.5
    if cfg.glide and not grounded and falling then
        lv.LineVelocity = cfg.glide      -- 翅膀：張翼把下墜速度收斂到緩降
        lv.Enabled = true
        return "glide"
    end

    lv.Enabled = false                   -- 其餘一律不介入（走路、跳躍、自由落體）
    return "off"
end

--[[
    ★★ 這裡踩過一個【自己修出來的】坑，值得寫下來：

    `attach()` 的 Attachment 是**共用單例**（用名字找，有就重用）。
    我原本讓 `detach()` **無條件**把它銷毀 —— 結果：

        attach(A) → attach(B)（B 重用了同一顆 Attachment）→ detach(A)
        ⇒ Attachment 被拔掉 ⇒ **B 的 LinearVelocity.Attachment0 變成 nil**
        ⇒ B 看起來完全健康（lv.Parent 在、Enabled = true 設得下去、不報錯）
        ⇒ **引擎就是不施力。角色不飛。零 error。**

    而重複 attach **是常態**（角色重生、換載具、換實驗）。

    ⇒ 只有在「已經沒有別的約束還掛在那顆 Attachment 上」時，才清掉它。
]]
function Flight.detach(handle)
    if not handle then return end

    if handle.lv then
        handle.lv:Destroy()
    end

    if handle.hrp then
        -- ★ 還有別人在用這顆 Attachment（另一個 FlightVelocity）→ 不准動它
        if not handle.hrp:FindFirstChild("FlightVelocity") then
            local att = handle.hrp:FindFirstChild("FlightAttachment")
            if att then
                att:Destroy()
            end
        end
    end
end

return Flight
