# NotBlocky — 跟 AI 一起做 Roblox 遊戲

> **你不需要會寫程式。你需要會說清楚你想做什麼遊戲。**
>
> 而且做出來的東西**可以不醜**：官方的 AI 生得出好看的模型，但生不出骨頭；
> 這裡把缺的那一段接起來，讓好看的模型變成真的會動的角色。

> ⚠️ **NotBlocky 是非官方的個人專案，與 Roblox Corporation 沒有任何從屬或背書關係。**
> Roblox 是 Roblox Corporation 的商標。本專案沒有保固（見 `LICENSE`）。
>
> **NotBlocky is an unofficial personal project, not affiliated with or endorsed by
> Roblox Corporation.** Roblox is a trademark of Roblox Corporation.
> No warranty is provided (see `LICENSE`).

---

## 怎麼開始（只有一步）

**打開 Claude Code，把這個資料夾的路徑給它，然後說：**

```
幫我開始做 Roblox 遊戲，先讀 START-HERE.md
```

**就這樣。**

Claude 會自己讀完所有該讀的東西，然後：
1. 檢查你電腦上缺什麼工具，**帶著你一步一步裝**
2. 跑一個範例，讓你**看到東西動起來**
3. 問你想做什麼遊戲

---

## 你會需要這些（Claude 會帶你一項一項裝，不用先自己弄）

| 東西 | 做什麼 | 要錢嗎 |
|---|---|---|
| **Roblox 帳號** | 沒帳號連 Studio 都開不了 | 免費 |
| **Roblox Studio** | 遊戲跑在裡面 | 免費 |
| **Rojo**（CLI + Studio 外掛） | 讓 Claude 寫的程式自動同步進 Studio | 免費 |
| **git** | ★ 讓你能「回到昨天那個還能跑的版本」 | 免費 |
| **Claude Code** | 你正在用的這個 | 你的訂閱 |

> **不需要 Blender、不需要學 3D 建模、不需要寫一行 Luau。**

---

## 這裡面有什麼

```
START-HERE.md        ← ★ Claude 讀這個（你不用讀）
CLAUDE.md            ← Claude 的工作規矩（你不用讀）
PLANNING-PROTOCOL.md ← Claude 當企劃師時的問答流程（你不用讀）
docs/GOTCHAS.md      ← Claude 的避坑清單（你不用讀）
docs/ASSETS.md       ← Claude 處理 3D 模型的手續（你不用讀）
docs/PUBLISH.md      ← 怎麼發布，讓你小孩在【平板】上玩到 ← ★ 這個你可以翻翻

src/                 ← 程式（Claude 寫）
experiments/         ← 每個遊戲點子的規劃書（你和 Claude 一起寫）
  _EXAMPLE-dragon-ride/PLAN.md   ← ★ 一份真的填完的規劃書，想像不出來就看這個
place/               ← Roblox 的場景檔（★ 你在 Studio 裡按 Ctrl+S 存 —— 這步 Claude 代勞不了）
```

**你會發現大部分文件都寫著「你不用讀」——那是刻意的。**

那些文件的讀者是 **Claude**，不是你。它們的作用是**替你把坑先填掉**——
Roblox 有一整類的錯誤是**不會報錯**的（東西就是不動、或長得不對），
那些文件就是為了讓 Claude 不必一個個去撞。

**你要做的事只有一件：說清楚你想做什麼遊戲，然後看它做出來、告訴它哪裡不對。**

---

## 一個心理準備

**Claude 會在動手之前先反問你一堆問題。**

「這是什麼遊戲？」「玩家反覆在做什麼？」「你賭它好玩的理由是什麼？」

**那不是它在拖延——那是最值錢的部分。**

大部分人腦中的「我想做一個 XX 遊戲」其實只有一個畫面，沒有玩法。
如果直接開工，會做出一個你自己也沒想清楚的東西，然後兩邊都很挫折。

**那些問題會逼出你自己也還沒想清楚的東西。那才是真正的規格。**

**回答「我不知道」是完全可以的。** Claude 會標記起來，之後再回頭處理。

---

## 一個誠實的限制

**AI 生成的 3D 模型沒有「骨架」。**

意思是：Claude 可以讓一個東西**整體**旋轉、移動、縮放（一條龍飛起來、一把劍揮下去），
但**做不到細緻的關節動作**（翅膀拍動時根部完美黏在身上、四肢自然彎曲）。

**這不是 Claude 不會寫——是模型裡沒有骨頭。**

如果你要的東西需要那種等級的動畫，Claude 會**一開始就告訴你**，
而不是讓你期待落空。（有付費的解法，到時候再說。）

---

## 兩件你會慶幸有做的事

**1. 給它一個 git（Claude 會幫你）**

不是為了「版控」那些工程師的理由，是為了**「回到昨天那個還能跑的版本」**。
跟 Claude 說一句「幫我把這個資料夾接上 git」就好，該忽略什麼已經設定好了。

**2. 存檔（這步只有你能做）**

**3D 模型和地形不會自動同步。** Claude 生完模型後會叫你按 **Ctrl+S** —— 一定要按。
不按的話，Studio 一關，龍就沒了。（程式碼不受影響，那個是自動的。）

---

**開始吧。把路徑給 Claude，說「先讀 START-HERE.md」。**
