# Blender headless：把「從 Roblox 讀出來的 obj」綁上一副沿著身體重心走的脊椎骨架。
#
# ★ 與上一版的差別：不用 Blender 的自動權重（ARMATURE_AUTO）——它上次留下 22 個
#   完全沒有權重的頂點而且不報錯。這裡改用【決定論權重】：距離骨段最近的兩根，
#   反平方加權，並在腳本內自己驗「零權重頂點必須是 0」。
#
# 用法：blender -b -P rig_spine.py -- <in.obj> <out.glb> [骨頭數]

import bpy, sys, json, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
IN_OBJ, OUT_GLB = argv[0], argv[1]
N_JOINTS = int(argv[2]) if len(argv) > 2 else 7      # 關節點數 ⇒ 骨頭數 = N_JOINTS - 1

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=IN_OBJ)
me = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
mesh = me.data

report = {"verts": len(mesh.vertices), "polys": len(mesh.polygons),
          "uv_layers": len(mesh.uv_layers)}

co = [v.co.copy() for v in mesh.vertices]
mn = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
mx = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
ext = mx - mn
report["bbox_min"] = [round(v, 3) for v in mn]
report["bbox_max"] = [round(v, 3) for v in mx]

# --- 1. 找「身體的長軸」：三軸裡跨度最大的那個 ---
axis = max(range(3), key=lambda i: ext[i])
report["spine_axis"] = "XYZ"[axis]

# --- 2. 沿長軸切片，取每片的【重心】當關節點 ---
#     ★ 這一步是關鍵：直線骨架穿不過會彎的脖子與尾巴，重心線才貼合身體
lo, hi = mn[axis], mx[axis]
joints = []
empty_slices = 0
for i in range(N_JOINTS):
    a = lo + (hi - lo) * i / (N_JOINTS - 1)
    half = (hi - lo) / (N_JOINTS - 1) * 0.75          # 相鄰切片刻意重疊，避免空片
    sl = [c for c in co if abs(c[axis] - a) <= half]
    if not sl:
        empty_slices += 1
        p = Vector((0, 0, 0)); p[axis] = a
        # 空片就沿用上一個關節的橫向位置（不要跳回原點）
        if joints:
            for k in range(3):
                if k != axis:
                    p[k] = joints[-1][k]
    else:
        p = Vector((
            sum(c.x for c in sl) / len(sl),
            sum(c.y for c in sl) / len(sl),
            sum(c.z for c in sl) / len(sl),
        ))
        p[axis] = a                                    # 沿軸座標用切片位置，其餘兩軸用重心
    joints.append(p)
report["empty_slices"] = empty_slices
report["joints"] = [[round(v, 3) for v in j] for j in joints]

# --- 3. 建骨架（一條鏈，父子相連） ---
arm_data = bpy.data.armatures.new("Rig")
arm = bpy.data.objects.new("Rig", arm_data)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
prev = None
bone_names = []
for i in range(N_JOINTS - 1):
    b = arm_data.edit_bones.new(f"Spine{i+1}")
    b.head, b.tail = joints[i], joints[i + 1]
    if prev:
        b.parent = prev
        b.use_connect = True
    prev = b
    bone_names.append(b.name)
bpy.ops.object.mode_set(mode="OBJECT")
report["bones"] = bone_names

# --- 4. ★ 決定論權重：距離骨段最近的兩根，反平方加權 ---
def dist_to_segment(p, a, b):
    ab = b - a
    denom = ab.dot(ab)
    t = 0.0 if denom == 0 else max(0.0, min(1.0, (p - a).dot(ab) / denom))
    return (p - (a + ab * t)).length

for n in bone_names:
    me.vertex_groups.new(name=n)

MAX_INFLUENCE = 2
zero_weight = 0
bone_hit = {n: 0 for n in bone_names}
for v in mesh.vertices:
    p = v.co
    ds = []
    for i, n in enumerate(bone_names):
        d = dist_to_segment(p, joints[i], joints[i + 1])
        ds.append((max(d, 1e-6), n))
    ds.sort()
    top = ds[:MAX_INFLUENCE]
    ws = [1.0 / (d * d) for d, _ in top]
    s = sum(ws)
    if s <= 0:                                        # 理論上到不了，但不留靜默失敗
        top, ws, s = [ds[0]], [1.0], 1.0
    for (d, n), w in zip(top, ws):
        me.vertex_groups[n].add([v.index], w / s, "REPLACE")
    bone_hit[top[0][1]] += 1

mod = me.modifiers.new(name="Armature", type="ARMATURE")
mod.object = arm
me.parent = arm

# --- 5. ★ 自己驗，不信「沒報錯就是好的」 ---
for v in mesh.vertices:
    if sum(g.weight for g in v.groups) <= 1e-6:
        zero_weight += 1
report["zero_weight_verts"] = zero_weight
report["max_influences"] = max(len(v.groups) for v in mesh.vertices)
report["verts_per_bone"] = bone_hit                    # 尺的自檢：每根骨頭都要有頂點
report["bones_with_no_verts"] = [n for n, c in bone_hit.items() if c == 0]

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB",
                          use_selection=True, export_skins=True, export_yup=True)

print("REPORT_JSON:" + json.dumps(report, ensure_ascii=False))
