--[[
    Config — 總開關

    改 ACTIVE 這一行，Bootstrap 就只啟動那一個實驗。
    舊實驗原封不動留在 Experiments/ 底下，不會互相污染。

    ACTIVE = false 則什麼都不跑（想單純在 Studio 手動測東西時用）
]]

return {
    -- 對應 src/ReplicatedStorage/Experiments/ 底下的資料夾名
    --   "Hello" — 範例：一群會跳的方塊（純腳本，不需要任何 3D 素材）
    ACTIVE = "Hello",
}
