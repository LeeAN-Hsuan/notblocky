# Blender headless：把「從 Roblox 讀出來的 obj」載入 → 驗幾何 → 綁一副骨架 → 匯出 glb
#
# ★ 這支是實驗用的最小可行版本，不是要取代 game-asset-forge 的 creature 家族。
#   它要回答的只有一件事：官方 AI 生的網格，出得來、綁得上、回得去嗎。
#
# 用法：blender -b -P rig_imported.py -- <in.obj> <out.glb>

import bpy, sys, json, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
IN_OBJ, OUT_GLB = argv[0], argv[1]

# --- 0. 清空預設場景 ---
bpy.ops.wm.read_factory_settings(use_empty=True)

# --- 1. 匯入 ---
bpy.ops.wm.obj_import(filepath=IN_OBJ)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
assert len(objs) == 1, f"預期 1 個網格物件，實際 {len(objs)}"
me = objs[0]
mesh = me.data

report = {
    "verts": len(mesh.vertices),
    "polys": len(mesh.polygons),
    "uv_layers": len(mesh.uv_layers),
    "has_uv": len(mesh.uv_layers) > 0,
}

# UV 是不是全零（＝有欄位但其實沒資料，典型的「假綠燈」）
if mesh.uv_layers:
    uvs = [tuple(l.uv) for l in mesh.uv_layers.active.data]
    report["uv_count"] = len(uvs)
    report["uv_all_zero"] = all(abs(u) < 1e-9 and abs(v) < 1e-9 for u, v in uvs)
    report["uv_unique"] = len(set(round(u, 5) for u, v in uvs))
    report["uv_min"] = [round(min(u for u, v in uvs), 4), round(min(v for u, v in uvs), 4)]
    report["uv_max"] = [round(max(u for u, v in uvs), 4), round(max(v for u, v in uvs), 4)]

# 幾何健全性
co = [v.co for v in mesh.vertices]
report["bbox_min"] = [round(min(c[i] for c in co), 4) for i in range(3)]
report["bbox_max"] = [round(max(c[i] for c in co), 4) for i in range(3)]
report["has_nan"] = any(any(math.isnan(x) for x in c) for c in co)
report["loose_verts"] = sum(1 for v in mesh.vertices if not any(v.index in p.vertices for p in mesh.polygons)) if len(mesh.vertices) < 3000 else "skipped"

# --- 2. 綁一副骨架（沿最長軸 3 節，決定論） ---
bmin = Vector(report["bbox_min"]); bmax = Vector(report["bbox_max"])
axis = max(range(3), key=lambda i: bmax[i] - bmin[i])
report["long_axis"] = "XYZ"[axis]

arm_data = bpy.data.armatures.new("Rig")
arm = bpy.data.objects.new("Rig", arm_data)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")

N_BONES = 3
lo, hi = bmin[axis], bmax[axis]
mid = [(bmin[i] + bmax[i]) / 2 for i in range(3)]
prev = None
for i in range(N_BONES):
    b = arm_data.edit_bones.new(f"Bone{i+1}")
    h = list(mid); t = list(mid)
    h[axis] = lo + (hi - lo) * i / N_BONES
    t[axis] = lo + (hi - lo) * (i + 1) / N_BONES
    b.head, b.tail = Vector(h), Vector(t)
    if prev:
        b.parent = prev
        b.use_connect = True
    prev = b
bpy.ops.object.mode_set(mode="OBJECT")

# 自動權重（Blender 內建的骨頭包絡）
me.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

# --- 3. 綁完之後【自己驗】權重，不信 parent_set 沒報錯 ---
vg_names = [g.name for g in me.vertex_groups]
report["vertex_groups"] = vg_names
weighted = 0
zero_weight = 0
for v in mesh.vertices:
    total = sum(g.weight for g in v.groups)
    if total > 1e-6:
        weighted += 1
    else:
        zero_weight += 1
report["weighted_verts"] = weighted
report["zero_weight_verts"] = zero_weight

# --- 4. 匯出 glb ---
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB",
                          use_selection=True, export_skins=True, export_yup=True)

print("REPORT_JSON:" + json.dumps(report, ensure_ascii=False))
