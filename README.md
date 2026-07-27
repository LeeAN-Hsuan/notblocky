# NotBlocky

**跟 AI 一起做 Roblox 遊戲的工作方法。做出來的東西可以不醜。**
*A way of working with an AI to make Roblox games. And they don't have to look blocky.*

> ⚠️ **NotBlocky 是非官方的個人專案，與 Roblox Corporation 沒有任何從屬或背書關係。**
> Roblox 是 Roblox Corporation 的商標。本專案不提供技術支援，也沒有保固。
>
> **NotBlocky is an unofficial personal project, not affiliated with or endorsed by
> Roblox Corporation.** Roblox is a trademark of Roblox Corporation.
> No support and no warranty are provided.

---

## 這是什麼 / What this is

現在做一個「能玩」的 Roblox 遊戲已經不難了。難的是做出來**不像方塊人**。

Roblox 內建的 AI 生得出很好看的模型，**但它生不出骨頭**。沒有骨頭，角色就只能整隻轉，
動起來像一塊石頭。這套方法把缺的那一段接起來，同時讓 AI 幫你寫程式。

Making a *playable* Roblox game is no longer the hard part. Making one that doesn't look
blocky is. Roblox's built-in AI can generate good-looking models, **but it cannot generate
bones** — and without bones a character can only rotate as one rigid lump. This project
closes that gap, and lets the AI write the code for you.

**你不用學三樣東西：** 建模與綁骨架、寫 Luau、Roblox Studio 的操作介面。
**你要出的是：** 說清楚你想做什麼遊戲、自己玩一次、說出哪裡不對。

---

## 怎麼用 / How to use

1. 下載並解壓縮 `notblocky-starter-kit.zip`（或直接 clone 這個 repo）
2. 在那個資料夾裡打開 [Claude Code](https://claude.com/claude-code)
3. 跟它說：`先讀 START-HERE.md`
4. 它會帶你裝環境、跑通範例，然後開始問你想做什麼遊戲

**你不需要讀完裡面的文件。** 那些文件的第一讀者是 AI，不是人。

> 📄 **文件目前是繁體中文的。** Claude 讀中文完全沒問題，功能不受影響；
> 但如果你是英文使用者，人類可讀的部分（README / START-HERE）之後會補英文版。
>
> 📄 **The documents are currently in Traditional Chinese.** Claude reads them fine, so
> functionality is unaffected. English versions of the human-facing docs are planned.

---

## 你需要準備什麼 / Requirements

| | 費用 |
|---|---|
| [Claude Code](https://claude.com/claude-code) | 需要付費訂閱，會用到終端機 |
| Roblox Studio | 免費 |
| [Rojo](https://rojo.space) | 免費（starter kit 裡有安裝說明） |
| Blender | 免費，**只有要做「會動的模型」那段才需要** |

★ 只想快點做出第一個能玩的遊戲？**先去用 Roblox 官方的 Build 或線上生成器**，那更快。
當你發現做出來的東西都長得差不多、角色動起來像石頭，再回來這裡。

---

## 誠實的邊界 / Known limits

- 所有的坑都是在 **Windows** 上實測出來的，**Mac 完全沒有驗證過**
- 發布上架與平板遊玩**作者實際做過**（有一款遊戲已在線上），但 starter kit 裡那份**發布文件本身還沒被逐步驗證**
- 目前的骨架是脊椎鏈，**腿還沒有骨頭** ⇒ 做得到抬頭與身體起伏，做不到走路
- 這是一個人做的工具，**沒有客服**

---

## 授權 / License

MIT（見 [`LICENSE`](LICENSE)）。第三方素材的授權見 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。

★ 網站上示範用的那隻龍，**模型與貼圖是 Roblox Studio 內建 AI 生成的**，
骨架與權重才是本專案算的。因此 repo 只收錄渲染出來的畫面，不收錄該模型的原始檔。
