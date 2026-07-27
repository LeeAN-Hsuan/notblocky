# -*- coding: utf-8 -*-
# build_rig.py — 用 Blender 產一隻【有骨架的生物】（skinned mesh）
#
# ★ 為什麼需要這支：
#   Roblox 官方的 AI（generate_mesh）造型很強，但生出來的模型【沒有骨頭】
#   ⇒ 你只能整塊剛體旋轉它，做不到「翅膀拍動時根部黏在身上」。
#   有骨頭的模型才能讓網格【真的彎】—— 而綁骨架是 Blender 的地盤。
#
# ★ 你不需要會用 Blender 建模。改 <name>.rig.json 這個檔案就好（一份範例在 creature.rig.json）。
#
# 用法：
#   blender --background --python build_rig.py -- creature.rig.json out/
#
# 產出：
#   out/<name>.glb        ← 拿這個匯進 Roblox Studio（Avatar → 3D Importer）
#   out/<name>.report.json ← 驗證報告（★ 一定要看 all_pass）

import bpy, bmesh, sys, os, json, math, mathutils

# ★ Windows 主控台預設 cp950，印不出 ✅ / 中文會崩潰或亂碼 ⇒ 強制 UTF-8
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SPEC_PATH, OUT_DIR = argv[0], argv[1]

with open(SPEC_PATH, encoding="utf-8") as f:
    SPEC = json.load(f)

os.makedirs(OUT_DIR, exist_ok=True)
V = mathutils.Vector

# ★ Roblox 的【硬性】規格上限（官方文件 create.roblox.com/docs/art/modeling/specifications）
#   Blender 完全不管這些，超標 Roblox 會【安靜地截斷】⇒ 這是本檔存在的一半理由
ROBLOX_MAX_TRIS = 20000
ROBLOX_MAX_BONE_INFLUENCES = 4


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


def loft(bm, sections):
    """把一串斷面（每個 4 個座標）縫成一條柱體。斷面越多，骨架彎折越平滑。"""
    rings = [[bm.verts.new(V(p)) for p in sec] for sec in sections]
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


def section(center, axis, w, d):
    """在 center 產生一個垂直於 axis 的矩形斷面（寬 w、厚 d）"""
    a = V(axis).normalized()
    up = V((0, 0, 1)) if abs(a.z) < 0.9 else V((1, 0, 0))
    side = a.cross(up).normalized()
    up = side.cross(a).normalized()
    c = V(center)
    return [tuple(c - side * (w / 2) - up * (d / 2)), tuple(c + side * (w / 2) - up * (d / 2)),
            tuple(c + side * (w / 2) + up * (d / 2)), tuple(c - side * (w / 2) + up * (d / 2))]


def build_body(bm, body):
    """軀幹：沿 +Z 疊斷面"""
    w, d, h = body["w"], body["d"], body["h"]
    taper, layers = body.get("taper", 0.3), body.get("layers", 6)
    secs = []
    for i in range(layers + 1):
        t = i / layers
        k = 1.0 - taper * t
        secs.append(section((0, 0, h * t), (0, 0, 1), w * k, d * k))
    loft(bm, secs)


def build_limb(bm, body, limb):
    """一隻肢體（翅膀 / 腿 / 尾巴 / 脖子）：從軀幹的 attach 點沿 dir 延伸"""
    ax, ay, az = limb["attach"]
    origin = V((body["w"] * ax, body["d"] * ay, body["h"] * az))
    d = V(limb["dir"]).normalized()

    length = limb["length"]
    segs = limb["segments"]
    SUB = 2                                   # 每節再切 2 段 → 變形平滑
    total = segs * SUB
    w0, t0 = limb["width"], limb["thick"]
    taper = limb.get("taper", 0.5)
    lift = limb.get("lift", 0.0)              # 沿途上揚（翅膀用）

    secs = []
    for i in range(total + 1):
        t = i / total
        p = origin + d * (length * t) + V((0, 0, lift * math.sin(t * math.pi * 0.6)))
        k = 1.0 - taper * t
        secs.append(section(p, d, w0 * k, t0 * k))
    loft(bm, secs)
    return origin, d


def build_armature(body, limbs, limb_origins):
    """Root → Spine → 每隻肢體一條骨鏈。★ 階層有分支，Roblox 端才動得出關節"""
    arm_data = bpy.data.armatures.new("Rig")
    arm_obj = bpy.data.objects.new("Rig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    h = body["h"]
    root = eb.new("Root")
    root.head, root.tail = (0, 0, 0), (0, 0, h * 0.4)

    spine = eb.new("Spine")
    spine.head, spine.tail = (0, 0, h * 0.4), (0, 0, h)
    spine.parent, spine.use_connect = root, True

    for limb, (origin, d) in zip(limbs, limb_origins):
        segs = limb["segments"]
        seg_len = limb["length"] / segs
        prev = spine
        for i in range(segs):
            b = eb.new(f"{limb['name']}_{i+1}")
            b.head = tuple(origin + d * (seg_len * i))
            b.tail = tuple(origin + d * (seg_len * (i + 1)))
            b.parent = prev
            b.use_connect = (i > 0)
            prev = b

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def point_seg_dist(p, a, b):
    ab = b - a
    L2 = ab.dot(ab)
    if L2 < 1e-9:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / L2))
    return (p - (a + ab * t)).length


def skin(obj, arm_obj, max_influences=2):
    """
    ★ 確定性權重：每個頂點取【最近的 N 根骨頭】，權重＝距離倒數，正規化。

    為什麼不用 Blender 的 automatic weights（bone heat）：
      ① 它是黑箱，出錯了你不知道為什麼
      ② 對「分離的幾何」會直接失敗
      ③ ★ 它【不保證】每頂點的骨頭數 ≤ 4 —— 那是 Roblox 的硬上限，超過會被安靜截斷
    """
    bones = [(b.name, V(b.head_local), V(b.tail_local)) for b in arm_obj.data.bones]
    groups = {name: obj.vertex_groups.new(name=name) for name, _, _ in bones}

    for vert in obj.data.vertices:
        p = V(vert.co)
        d = sorted(((point_seg_dist(p, h, t), name) for name, h, t in bones), key=lambda x: x[0])
        picked = d[:max_influences]
        inv = [(1.0 / max(dist, 0.5), name) for dist, name in picked]
        total = sum(w for w, _ in inv)
        for w, name in inv:
            groups[name].add([vert.index], w / total, "REPLACE")

    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    obj.parent = arm_obj


def validate(obj, arm_obj, expect_bones):
    me = obj.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)

    max_inf, unweighted = 0, 0
    for v in me.vertices:
        n = len([g for g in v.groups if g.weight > 1e-6])
        max_inf = max(max_inf, n)
        if n == 0:
            unweighted += 1

    bones = [b.name for b in arm_obj.data.bones]
    checks = {
        # ★ Roblox 硬上限（Blender 不管，超標會被安靜截斷）
        "roblox_tri_limit": {"tris": tris, "limit": ROBLOX_MAX_TRIS, "pass": tris <= ROBLOX_MAX_TRIS},
        "roblox_bone_influence_limit": {"max_per_vertex": max_inf, "limit": ROBLOX_MAX_BONE_INFLUENCES,
                                        "pass": max_inf <= ROBLOX_MAX_BONE_INFLUENCES},
        # 權重全 0 的頂點在 Roblox 裡會【留在原地】⇒ 網格被撕開，而且沒有任何錯誤訊息
        "no_unweighted_verts": {"unweighted": unweighted, "pass": unweighted == 0},
        "bone_count": {"actual": len(bones), "expect": expect_bones, "pass": len(bones) == expect_bones},
        "not_empty": {"verts": len(me.vertices), "pass": len(me.vertices) > 0},
    }
    checks["all_pass"] = all(c["pass"] for c in checks.values() if isinstance(c, dict) and "pass" in c)

    return {"name": SPEC["name"], "tris": tris, "verts": len(me.vertices),
            "bones": bones,
            "bone_hierarchy": {b.name: (b.parent.name if b.parent else None) for b in arm_obj.data.bones},
            "checks": checks}


def main():
    clear_scene()
    body, limbs = SPEC["body"], SPEC["limbs"]

    bm = bmesh.new()
    build_body(bm, body)
    origins = [build_limb(bm, body, L) for L in limbs]
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.05)

    name = SPEC["name"]
    me = bpy.data.meshes.new(name)      # ★ mesh 名＝Roblox Importer 認的名字（不是物件名）
    bm.to_mesh(me)
    bm.free()

    mat = bpy.data.materials.new("Body")
    mat.diffuse_color = (*SPEC.get("color", [0.6, 0.6, 0.65]), 1.0)
    me.materials.append(mat)

    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)

    arm = build_armature(body, limbs, origins)
    skin(obj, arm, SPEC.get("max_influences", 2))

    expect = 2 + sum(L["segments"] for L in limbs)      # Root + Spine + 每隻肢體的節數
    rep = validate(obj, arm, expect)

    # 匯出 glb（★ mesh + armature 都要選，skin 才會被匯出）
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    glb = os.path.join(OUT_DIR, f"{name}.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True,
                              export_skins=True, export_yup=True)
    rep["glb"] = glb

    with open(os.path.join(OUT_DIR, f"{name}.report.json"), "w", encoding="utf-8") as f:
        json.dump(rep, f, ensure_ascii=False, indent=2)

    ok = rep["checks"]["all_pass"]
    print(f"\n[rig] {name}: tris={rep['tris']} bones={len(rep['bones'])} "
          f"max_inf={rep['checks']['roblox_bone_influence_limit']['max_per_vertex']} "
          f"=> {'✅ all_pass' if ok else '❌ 有檢查沒過，看 report.json'}")
    print(f"[rig] glb  -> {glb}")
    print(f"[rig] 骨頭 -> {', '.join(rep['bones'])}")


main()
