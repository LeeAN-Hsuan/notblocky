# -*- coding: utf-8 -*-
# rig_check.py — 拆開 .glb 的二進位，驗它【真的】帶骨架
#
# ★★★ 為什麼一定要跑這支（不要跳過）：
#   Blender 說「匯出完成」不代表 glb 裡面有骨架。
#   匯出一樣成功、檔案一樣產生、Blender 一樣不報錯 ——
#   但你拿到的可能是【一塊死網格】，而你會一路以為自己有骨架，
#   直到匯進 Roblox、翅膀怎麼都拍不動，才發現白忙一場。
#
#   ⇒ 這就是這個框架反覆講的那句：**不准用嘴巴保證，要量。**
#
# 只用 Python 標準函式庫（不必 pip install 任何東西）。
# 用法：python rig_check.py out/flyer.glb

import sys, json, struct

# ★ Windows 的主控台預設是 cp950（Big5），印不出 ✅ 這類字元 —— 會直接 UnicodeEncodeError 崩潰，
#   而且 exit code 變 1，看起來像「驗證失敗」，其實只是印不出字。中文也會變亂碼。
#   ⇒ 強制 stdout 走 UTF-8。（這是 Windows 上的老坑，不是這支程式的問題）
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def read_glb(path):
    """glb 容器：magic(4) version(4) length(4) | chunkLen(4) chunkType(4) chunkData... ×2"""
    with open(path, "rb") as f:
        magic, version, _ = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:                      # 'glTF'
            raise ValueError(f"這不是 glb 檔（magic={magic:#x}）")
        clen, ctype = struct.unpack("<II", f.read(8))
        if ctype != 0x4E4F534A:                      # 'JSON'
            raise ValueError("第一個 chunk 不是 JSON，檔案可能壞了")
        gltf = json.loads(f.read(clen).decode("utf-8"))
        blob = b""
        head = f.read(8)
        if len(head) == 8:
            blen, btype = struct.unpack("<II", head)
            if btype == 0x004E4942:                  # 'BIN'
                blob = f.read(blen)
        return gltf, version, blob


_CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
       5125: ("I", 4), 5126: ("f", 4)}
_NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_accessor(gltf, blob, idx):
    """把 accessor 的實際數值讀出來（★ 不讀值，就不知道權重是不是一堆 0）"""
    acc = gltf["accessors"][idx]
    ncomp = _NCOMP[acc["type"]]
    fmt, size = _CT[acc["componentType"]]
    bv = gltf["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or (size * ncomp)
    return [struct.unpack_from("<" + fmt * ncomp, blob, base + i * stride)
            for i in range(acc["count"])]


def check(path):
    g, version, blob = read_glb(path)
    skins = g.get("skins", [])
    meshes = g.get("meshes", [])
    nodes = g.get("nodes", [])

    # ① 有沒有 skin？
    has_skin = len(skins) > 0

    # ② 頂點有沒有綁在骨頭上？（JOINTS_0 = 綁到哪根骨頭，WEIGHTS_0 = 綁多緊）
    attrs = set()
    for m in meshes:
        for p in m.get("primitives", []):
            attrs |= set(p.get("attributes", {}).keys())
    has_joints, has_weights = "JOINTS_0" in attrs, "WEIGHTS_0" in attrs

    # ★★★ ③ 【值】對不對 —— 有 WEIGHTS_0 這個欄位，不代表裡面不是一堆 0。
    #     權重全 0 的頂點在 Roblox 裡會【留在原地】⇒ 網格被撕開，而且沒有任何錯誤訊息。
    #     ★ 只驗②不驗③，就是「只量一個指標，選到剛好也滿足那個指標的錯誤答案」。
    weights = None
    for m in meshes:
        for p in m.get("primitives", []):
            a = p.get("attributes", {})
            if "WEIGHTS_0" in a and blob:
                W = read_accessor(g, blob, a["WEIGHTS_0"])
                zero = sum(1 for w in W if sum(w) < 1e-6)
                weights = {"vertex_count": len(W), "zero_weight_verts": zero, "pass": zero == 0}

    joint_idx = skins[0].get("joints", []) if has_skin else []
    parent_of = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent_of[c] = i

    ok = (has_skin and has_joints and has_weights
          and any("skin" in n for n in nodes)
          and bool(weights) and weights["pass"])

    return {
        "file": path,
        "有骨架(skins)": has_skin,
        "頂點綁到骨頭(JOINTS_0)": has_joints,
        "頂點有權重(WEIGHTS_0)": has_weights,
        "★權重的值": weights,
        "骨頭數": len(joint_idx),
        "骨頭": [nodes[i].get("name") for i in joint_idx],
        "骨頭階層": {nodes[i].get("name"): (nodes[parent_of[i]].get("name") if i in parent_of else None)
                     for i in joint_idx},
        "網格名(Importer認的是這個)": [m.get("name") for m in meshes],
        "PASS": ok,
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python rig_check.py <path.glb>")
        sys.exit(1)
    r = check(sys.argv[1])
    print(json.dumps(r, ensure_ascii=False, indent=2))
    print("\n✅ 這個 glb 真的帶骨架，可以匯進 Roblox" if r["PASS"]
          else "\n❌ 有問題 —— 不要匯進 Roblox，先修好（看上面哪一項是 false）")
    sys.exit(0 if r["PASS"] else 1)
