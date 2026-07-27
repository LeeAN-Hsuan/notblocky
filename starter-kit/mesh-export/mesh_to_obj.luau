--!strict
-- 在 Studio（Edit 模式）執行：把一個網格資產的幾何讀出來，組成 .obj 送到本機。
-- ★ 先跑 dump_server.py，否則 PostAsync 會失敗。
-- ★ 實測可用（2026-07-27）：官方 generate_mesh 生的資產也讀得到。

local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")

local ASSET_ID = "rbxassetid://0"        -- ← 改成你的 MeshId
local OUT_NAME = "mesh.obj"              -- ← 落地的檔名
local ENDPOINT = "http://127.0.0.1:5599/"

-- HttpEnabled 預設是 false；這是 place 設定，用完要還原
local httpBefore = HS.HttpEnabled
HS.HttpEnabled = true

local em = AS:CreateEditableMeshAsync(Content.fromUri(ASSET_ID))
local vs, uvs, ns, fs = em:GetVertices(), em:GetUVs(), em:GetNormals(), em:GetFaces()

-- ★ id 是稀疏的大數字（例如 4294967297），.obj 要的是 1-based 連續索引 ⇒ 自己建對照表
local vi, ui, ni = {}, {}, {}
for i, id in ipairs(vs) do vi[id] = i end
for i, id in ipairs(uvs) do ui[id] = i end
for i, id in ipairs(ns) do ni[id] = i end

-- ★ 不猜 API：法線讀不讀得到，先探再用
local hasNormal = pcall(function() return em:GetNormal(ns[1]) end)

local out = {}
out[#out + 1] = ("# 來源 %s  頂點=%d UV=%d 法線=%d 面=%d"):format(ASSET_ID, #vs, #uvs, #ns, #fs)

for _, id in ipairs(vs) do
	local p = em:GetPosition(id)
	out[#out + 1] = ("v %.6f %.6f %.6f"):format(p.X, p.Y, p.Z)
end
for _, id in ipairs(uvs) do
	local uv = em:GetUV(id)
	out[#out + 1] = ("vt %.6f %.6f"):format(uv.X, uv.Y)
end
if hasNormal then
	for _, id in ipairs(ns) do
		local n = em:GetNormal(id)
		out[#out + 1] = ("vn %.6f %.6f %.6f"):format(n.X, n.Y, n.Z)
	end
end
for _, fid in ipairs(fs) do
	local fv, fu, fn = em:GetFaceVertices(fid), em:GetFaceUVs(fid), em:GetFaceNormals(fid)
	if hasNormal then
		out[#out + 1] = ("f %d/%d/%d %d/%d/%d %d/%d/%d"):format(
			vi[fv[1]], ui[fu[1]], ni[fn[1]],
			vi[fv[2]], ui[fu[2]], ni[fn[2]],
			vi[fv[3]], ui[fu[3]], ni[fn[3]])
	else
		out[#out + 1] = ("f %d/%d %d/%d %d/%d"):format(
			vi[fv[1]], ui[fu[1]], vi[fv[2]], ui[fu[2]], vi[fv[3]], ui[fu[3]])
	end
end

-- ★ 分段送：單次 body 太大會失敗
local text = table.concat(out, "\n")
local CHUNK = 60000
local sent = 0
for i = 1, #text, CHUNK do
	HS:PostAsync(ENDPOINT .. OUT_NAME, text:sub(i, i + CHUNK - 1), Enum.HttpContentType.TextPlain)
	sent += 1
end

HS.HttpEnabled = httpBefore   -- 還原

-- ★ 回報的數字只是「我以為送出了多少」——落地之後要拿【檔案自己】再數一次
return ("頂點=%d UV=%d 法線=%d 面=%d｜位元組=%d｜分 %d 段送出（★ 請用檔案自己數一次核對）")
	:format(#vs, #uvs, #ns, #fs, #text, sent)
