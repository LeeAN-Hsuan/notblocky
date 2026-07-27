--[[
    AssetSpec — 素材守門員（把「一坨網格」變成下游能安全使用的素材）

    ★ 為什麼需要它（2026-07-12 實測逼出來的）

    Roblox 官方的 AI 生成（generate_mesh / generate_procedural_model）造型很好，
    但它交給你的東西是「一坨漂亮的網格」：沒有定位件、沒有標籤、沒有朝向約定。
    更危險的是——**它會安靜地謊報成功**：實測讓它生「孔距 3.8 的角鋼架」，
    它回了 HoleSpacing=3.8 / HoleRadius=0.6 的漂亮 attributes，
    但幾何裡一個孔都沒有、一片層板都沒有。

    這跟本專案一路踩的坑同型（Importer 的 .001 命名、素材缺席的靜默 fallback）：
    **錯得很安靜。**

    ⇒ 所以這個模組的唯一信條：

        不准用嘴巴保證，要量。
        量不到，就回報 FAIL，不准裝作成功。

    （寫這個模組的當下，作者自己就連續踩了三次假 PASS：射線一條都沒命中卻回報「偵測成功」、
      把 U 形的側壁當成封閉側、把旋轉方向寫死在註解裡卻沒驗證。三次都是被「量出來的數字」抓到的。
      這正是這一層存在的理由。）

    ★ 分工：官方生皮，AssetSpec 驗骨。

    用法（★ 這是一個【例子】—— 一副會咬的假牙。你的素材當然是別的東西）：

        -- ★ 鐵律③：WaitForChild 一律帶 timeout（不帶是永遠 yield，pcall 接不住）
        local Game = ReplicatedStorage:WaitForChild("Game", 10)
        local Shared = Game:WaitForChild("Shared", 10)
        local AssetSpec = require(Shared:WaitForChild("AssetSpec", 10))

        local report = AssetSpec.certify(modelInWorkspace, {
            name          = "Denture",
            requiredParts = { "UpperJaw", "LowerJaw" },
            pairTolerance = 0.15,
            detectOpening = {
                from        = "LowerJaw",       -- 從哪個部件射出去
                plantAnchor = "HingeAnchor",    -- 把定位件埋在哪（Attachment 的名字）
                anchorAt    = "closed",         -- ★★ 埋在【開口側】還是【封閉側】？見下方
            },
            tags          = { UpperJaw = "Jaw_Upper", LowerJaw = "Jaw_Lower" },
            precise       = true,
        })
        if not report.ok then
            -- 素材缺席／不合格要吵，不要靜默
            for _, line in ipairs(report.lines) do warn(line) end
        end

    ★★★ `anchorAt` 為什麼一定要由【你】來指定，守門員不准替你猜：

        假牙是 U 形的。射線量得出「開口朝哪」—— 那是【幾何】。
        但「關節該裝在開口側還是封閉側」是【語意】：
          U 形的「開口」其實是嘴巴【後方】（喉嚨、下巴關節）；
          U 形的【底】才是門牙。
        作者曾經把「關節放封閉側」寫死在守門員裡，
        結果做出一副【門牙不動、智齒張開】的假牙 —— 幾何量對了，語意猜錯了。

        ⇒ `anchorAt = "opening"` 或 `"closed"`，**由使用端決定**。預設 `"opening"`。
        ⇒ 這就是本模組信條③：**幾何可以量，語意不能猜。**

    ⚠️ 射線偵測只對 **Workspace 裡** 的東西有效（ReplicatedStorage 裡的模型打不到）。
       要 certify 的模型必須先 clone 進 workspace。
]]

local CollectionService = game:GetService("CollectionService")

local AssetSpec = {}

-- 射線探測的方向（水平四方）
local PROBE_DIRS = {
	{ name = "+X", v = Vector3.new(1, 0, 0) },
	{ name = "-X", v = Vector3.new(-1, 0, 0) },
	{ name = "+Z", v = Vector3.new(0, 0, 1) },
	{ name = "-Z", v = Vector3.new(0, 0, -1) },
}

-- 建一份報告物件；check() 是唯一能改變 pass/fail 的入口
local function newReport(name)
	local r = { name = name, pass = 0, fail = 0, lines = {}, ok = true, data = {} }

	function r.check(label, ok, detail)
		if ok then
			r.pass += 1
		else
			r.fail += 1
			r.ok = false
		end
		table.insert(r.lines, string.format("[%s] %s — %s", ok and "PASS" or "FAIL", label, detail))
		return ok
	end

	return r
end

-- 找出模型底下指定名字的 BasePart（允許包在子 Model 裡）
local function findPart(model, partName)
	local direct = model:FindFirstChild(partName)
	if direct then
		if direct:IsA("BasePart") then
			return direct
		end
		-- 官方生成物常把每個部件再包一層 Model
		return direct:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

--[[
    ★ 偵測「開口朝哪」——官方不給，我們自己量。

    做法：從指定部件的 bbox 中心，往水平四方各射一條射線。
      - 射得出去（沒打到自己）的那一側 ＝ 開口
      - 打得到的那些側 ＝ 有實體（牆/牙齦）

    ⚠️ 五個當初踩過的坑，都寫死在這裡了：
      ① 改完 CollisionFidelity 必須 **等一幀** 讓碰撞盒重算，否則射線一條都打不到
      ② 射線一條都沒命中時，**必須回報 FAIL**，不准在四個相同的值裡隨便挑一個當答案
         （★ 這一支最常見的原因是 CollisionFidelity = Box，訊息裡要講出來）
      ③ 封閉側 ＝ 開口的「反方向」，**不是**「距離最短的方向」（那是側壁）
      ⑤ **四條全部命中 ＝ 四面都是牆、沒有開口** → 也必須 FAIL
         （不准把「最遠的那面牆」當成「門」）
      ④ ★★ **不只一個方向射得穿時，也必須 FAIL** ——
         這是坑②的另一半，而且更陰險：`hits > 0` 過得了關，
         但「最遠的方向」在兩個 math.huge 之間是**由 PROBE_DIRS 的排序決定的**，
         等於「在相同的值裡隨便挑了第一個」。管狀（兩端開口）的素材必中。
         而那個結果會決定**鉸鏈埋在哪一側** → 埋錯了，門牙不動、智齒張開。
         ⇒ 朝向不唯一 ＝ 量不出來 ＝ **回報 FAIL，請呼叫端自己指定**。
]]
local function detectOpening(part, report)
	task.wait() -- 坑①：等碰撞盒重算

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }

	local center = part.Position
	local reach = part.Size.Magnitude * 2
	local hits, pierced, results = 0, {}, {}
	local opening, maxDist = nil, -1

	for _, dir in ipairs(PROBE_DIRS) do
		local hit = workspace:Raycast(center, dir.v * reach, params)
		local dist = hit and (hit.Position - center).Magnitude or math.huge
		if hit then
			hits += 1
		else
			table.insert(pierced, dir.name)   -- 射得穿 ＝ 這一側是開口
		end
		table.insert(results, string.format("%s=%s", dir.name, hit and string.format("%.2f", dist) or "穿出"))
		if dist > maxDist then
			maxDist, opening = dist, dir
		end
	end

	local detail = "射線 " .. table.concat(results, " / ")

	--[[ 坑②：一條都沒打到 → 量不到就是量不到，不准裝作成功

	     ★ 這一支【最常見】的真正原因，不是「模型壞了」，而是**碰撞盒是 Box**：
	       射線從部件的**中心**射出，而 Roblox 的射線**打不到自己出發時所在的實體內部**。
	       Box 碰撞盒把「空的內部」也算成實心 → 起點在實體裡 → 四條全部落空。
	     ⇒ 所以訊息一定要把這條路指出來，不然人會跑去重生素材（查錯方向）。 ]]
	if hits == 0 then
		report.check("朝向偵測", false, detail ..
			" → 四方全部穿出，射線一次都沒命中，無法判斷朝向。" ..
			"★ 最可能的原因：這個部件的 CollisionFidelity 是 Box（空的內部被當成實心，" ..
			"射線起點卡在實體裡）→ 回 Edit 模式改成 PreciseConvexDecomposition 再試。" ..
			"（其次才是：它本來就是一塊實心的東西，那就不該對它做朝向偵測。）")
		return nil
	end

	--[[ 坑⑤：**四條全部命中 ＝ 沒有任何一側是開口**（中空、但四面都封起來的東西）

	     這是坑②的鏡像，而且更容易漏掉：`hits > 0` 過得了關（4/4 呢！），
	     然後程式會拿「命中距離最遠的那一側」當開口 —— **那是【最長的那條半徑】，不是開口。**
	     於是它會印出自相矛盾的一行：「開口朝 +X（4/4 命中，唯一）」，蓋章說可信，
	     接著把鉸鏈埋在一個**憑空捏造**的方向上。

	     ⇒ 沒有開口，就是**沒有開口**。不准把「最遠的牆」當成「門」。 ]]
	if #pierced == 0 then
		report.check("朝向偵測", false, detail ..
			" → 四方【全部命中】＝ 這個部件四面都是牆，沒有任何一側是開口。" ..
			"無法判斷朝向 —— 你是不是 detectOpening 指錯部件了？")
		return nil
	end

	-- 坑④：不只一側射得穿 → 開口不唯一 → 一樣是「量不出來」，不准挑第一個當答案
	if #pierced > 1 then
		report.check("朝向偵測", false, string.format(
			"%s → 有 %d 個方向同時射穿（%s），開口不唯一、無法判定。" ..
			"請呼叫端自己指定朝向，不要讓守門員猜",
			detail, #pierced, table.concat(pierced, "、")))
		return nil
	end

	report.check("朝向偵測", true, string.format("%s → 開口朝 %s（%d/4 命中，唯一）", detail, opening.name, hits))

	-- 坑③：封閉側 ＝ 開口的反方向（不是距離最短的那側，那是側壁）
	return {
		openingName = opening.name,
		openingDir = opening.v,
		closedDir = -opening.v,
	}
end

--[[
    certify — 驗證 + 規格化。回傳 report。

    spec 欄位（全部選填，有給才驗）：
      name          string          素材名（只用來顯示）
      requiredParts {string}        必須存在的部件名（缺一個就 FAIL）
      pairTolerance number          前兩個 requiredParts 的寬度差上限（0.15 ＝ 15%）
      precise       boolean         ★ 【只驗，不修】：檢查所有 MeshPart 的 CollisionFidelity
                                    是不是 PreciseConvexDecomposition。不是就 FAIL，叫人回 Edit 模式改。
                                    （runtime 腳本【改不了】這個屬性 —— 缺 Plugin 權限，見下方 ③）
                                    為什麼要 Precise：預設的 Box 會讓「空的內部」也算撞到。
      detectOpening { from=部件名, plantAnchor=Attachment名, anchorAt="opening"|"closed" }
                                    射線偵測開口朝向，並埋一顆 Attachment 當關節定位點。
                                    ★★ anchorAt 決定埋在【開口側】還是【封閉側】—— 預設 "opening"。
                                       ⚠️ 這一格【一定要你自己想清楚】，守門員不准替你猜：
                                          「開口朝哪」是幾何（量得出來）；
                                          「關節該裝哪一側」是語意（量不出來）。
                                          猜錯的後果見檔頭的假牙故事（門牙不動、智齒張開）。
      tags          { [部件名]=標籤 } 打上 CollectionService 標籤，讓下游程式認得出零件
]]
function AssetSpec.certify(model, spec)
	local report = newReport(spec.name or model.Name)

	-- ① 分件檢查：下游要用的零件，一個都不能少
	local parts = {}
	if spec.requiredParts then
		local missing = {}
		for _, partName in ipairs(spec.requiredParts) do
			local p = findPart(model, partName)
			if p then
				parts[partName] = p
			else
				table.insert(missing, partName)
			end
		end

		if #missing > 0 then
			-- ★ 素材缺席要吵：必須說出「實際看到了什麼」，不然使用者查不出原因
			local actual = {}
			for _, child in ipairs(model:GetDescendants()) do
				if child:IsA("BasePart") then
					table.insert(actual, child.Name)
				end
			end
			report.check(
				"分件",
				false,
				string.format(
					"缺少 %s；實際看到的部件是 [%s]",
					table.concat(missing, ", "),
					#actual > 0 and table.concat(actual, ", ") or "（一個 BasePart 都沒有）"
				)
			)
			return report -- 零件都不齊，後面沒得驗
		end

		report.check("分件", true, string.format("%s 全部到齊", table.concat(spec.requiredParts, " / ")))
	end

	-- ② 相稱檢查：成對的零件尺寸差太多，組起來會錯位
	if spec.pairTolerance and spec.requiredParts and #spec.requiredParts >= 2 then
		local a = parts[spec.requiredParts[1]]
		local b = parts[spec.requiredParts[2]]
		local diff = math.abs(a.Size.X - b.Size.X) / math.max(a.Size.X, b.Size.X)
		report.check(
			"成對相稱",
			diff <= spec.pairTolerance,
			string.format("寬度差 %.1f%%（上限 %.0f%%）", diff * 100, spec.pairTolerance * 100)
		)
	end

	--[[ ③ 碰撞精度：要做接觸判定就不能用 Box（空心的東西會誤判）

	     ★★ 坑（2026-07-12 實測）：**CollisionFidelity 在 runtime 腳本裡寫不了**
	     —— 會拋 "cannot write 'CollisionFidelity' (lacking capability Plugin)"，
	     而且這個 error 會把整個實驗的初始化打斷（玩家連道具都拿不到）。
	     它只能在 **Edit 模式 / Plugin**（例如 MCP 的 execute_luau）裡設。

	     ⇒ 所以守門員的角色是 **只驗，不修**：
	        發現不對就吵出來，叫人回 Edit 模式把素材修好（素材的問題要在素材階段解決）。

	     ★★ 這裡掃的是 **整個模型底下所有 MeshPart**，不是只掃 requiredParts。
	        原本只掃 requiredParts 命中的那些 —— 於是 `certify(model, { precise = true })`
	        （沒給 requiredParts）會**掃到零個零件、然後印出「1 PASS / 0 FAIL」**。
	        一個什麼都沒驗的空模型，拿到一張全綠的合格證。
	        ⇒ **量不到，就回報 FAIL，不准裝作成功** —— 包括「因為沒東西可量」而通過。 ]]
	if spec.precise then
		local wrong, checked = {}, 0
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("MeshPart") then
				checked += 1
				if p.CollisionFidelity ~= Enum.CollisionFidelity.PreciseConvexDecomposition then
					table.insert(wrong, string.format("%s=%s", p.Name, p.CollisionFidelity.Name))
				end
			end
		end

		if checked == 0 then
			-- ★ 零個零件被檢查 ＝ 這一項【沒有驗到】，不是「通過」
			report.check("碰撞精度", false,
				"模型底下一個 MeshPart 都沒有 → 沒有任何東西可驗。" ..
				"（你是不是 certify 錯了對象？或素材還沒 clone 進 workspace？）")
		else
			report.check(
				"碰撞精度",
				#wrong == 0,
				#wrong == 0 and string.format("%d 個 MeshPart 全是 PreciseConvexDecomposition", checked)
					or string.format(
						"%s ← 空心處會被當成實心。★ runtime 改不了（缺 Plugin 權限），要回 Edit 模式改 place 裡的素材",
						table.concat(wrong, ", ")
					)
			)
		end
	end

	--[[ ④ 朝向偵測 + 埋定位件（官方給的網格 0 個 Attachment、0 個 Tag，朝向只能自己量）

	     ★ `parts` 只有在呼叫端給了 `requiredParts` 時才會被填。
	       但 spec 的每一格都是**選填**的 —— 有人只給 `detectOpening` 完全合法。
	       原本直接讀 `parts[...]`，那種情況下會回報 **「找不到來源部件 LowerJaw」**，
	       而 LowerJaw **明明就在模型裡** ⇒ 一句把人送去查錯方向的錯誤訊息
	       （會跑去重生素材、檢查扁平化，其實只是 spec 少寫了一格）。
	     ⇒ 讀不到就退回去**真的到模型裡找一次**。 ]]
	if spec.detectOpening then
		local src = parts[spec.detectOpening.from] or findPart(model, spec.detectOpening.from)
		if not src then
			report.check("朝向偵測", false, "找不到來源部件 " .. tostring(spec.detectOpening.from))
		else
			local axis = detectOpening(src, report)
			report.data.axis = axis

			if axis and spec.detectOpening.plantAnchor then
				local anchorName = spec.detectOpening.plantAnchor
				local old = src:FindFirstChild(anchorName)
				if old then
					old:Destroy()
				end

				--[[ ★★ 鉸鏈放哪一側，**守門員不准替使用端決定**（2026-07-12 被使用者實測抓到的錯）

				     AssetSpec 只負責「量出 U 形的開口朝哪」這個**幾何事實**。
				     至於「關節該放在開口側還是封閉側」，那是**語意**，只有使用端知道：

				       假牙：U 形的「開口」＝嘴巴後方（喉嚨、下巴關節）→ 鉸鏈在 **開口側**
				             U 形的「底」＝門牙 → 這裡要張得最開
				       夾子/鉗子：同理，關節在叉開的那端

				     我原本寫死「關節放封閉側」，結果做出一副 **門牙不動、智齒張開** 的假牙。
				     ⇒ 幾何可以量，語意不能猜。 ]]
				local side = spec.detectOpening.anchorAt or "opening"
				local anchorDir = (side == "closed") and axis.closedDir or axis.openingDir

				local att = Instance.new("Attachment")
				att.Name = anchorName
				att.Parent = src
				att.WorldPosition = src.Position + anchorDir * (src.Size.Magnitude * 0.35)

				report.check(
					"定位件",
					true,
					string.format(
						"已埋 %s 於【%s側】（由使用端指定，不是我猜的），官方原本 0 個 Attachment",
						anchorName,
						side == "closed" and "封閉" or "開口"
					)
				)
			end
		end
	end

	-- ⑤ 標籤：讓下游程式靠 tag 認零件，不必靠名字硬猜
	if spec.tags then
		local tagged, notFound = {}, {}
		for partName, tag in pairs(spec.tags) do
			-- ★ 跟 detectOpening 同一個坑：沒給 requiredParts 時 parts 是空的 → 退回去模型裡找
			local p = parts[partName] or findPart(model, partName)
			if p then
				CollectionService:AddTag(p, tag)
				table.insert(tagged, tag)
			else
				table.insert(notFound, partName)   -- ★ 找不到就要講出【是哪一個】找不到
			end
		end

		if #notFound > 0 then
			report.check("標籤", false, string.format(
				"這些部件在模型裡找不到，標不上：%s（已標上的：%s）",
				table.concat(notFound, ", "),
				#tagged > 0 and table.concat(tagged, " / ") or "無"))
		else
			report.check("標籤", #tagged > 0, table.concat(tagged, " / ") .. "（官方原本 0 個 Tag）")
		end
	end

	return report
end

--[[
    印出報告。★ 不合格一定要用 warn 吵出來——靜默 fallback 是本專案最痛的教訓。
]]
function AssetSpec.printReport(report)
	local header = string.format("[AssetSpec] %s — %d PASS / %d FAIL", report.name, report.pass, report.fail)

	if report.ok then
		print(header)
		for _, line in ipairs(report.lines) do
			print("  " .. line)
		end
	else
		warn(header .. "  ← 素材不合格")
		for _, line in ipairs(report.lines) do
			warn("  " .. line)
		end
	end

	return report.ok
end

return AssetSpec
