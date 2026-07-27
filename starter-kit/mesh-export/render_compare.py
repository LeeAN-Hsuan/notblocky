# Blender headless：把「剛體」與「有骨架」並排，各自動起來，渲染成圖片序列。
# 用法：blender -b -P render_compare.py -- <rigged.glb> <texture.png> <out_dir> [frames]
#
# ★ 誠實範圍：這副骨架只有 6 根的脊椎鏈（腿沒有骨頭）⇒ 做的是「抬頭 + 身體擺動」，不是走路。

import bpy, sys, os, math
from mathutils import Euler

argv = sys.argv[sys.argv.index("--") + 1:]
GLB, TEX, OUT_DIR = argv[0], argv[1], argv[2]
FRAMES = int(argv[3]) if len(argv) > 3 else 24
TOTAL_DEG = 50.0          # 兩邊共用的總角度（公平對照的關鍵）
os.makedirs(OUT_DIR, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
mesh_obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")

# --- 材質：用從 Roblox 倒出來的貼圖 ---
mat = bpy.data.materials.new("DragonMat")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(TEX)
nt.links.new(bsdf.inputs["Base Color"], tex.outputs["Color"])
bsdf.inputs["Roughness"].default_value = 0.55
mesh_obj.data.materials.clear()
mesh_obj.data.materials.append(mat)

# --- 剛體對照組：複製一份、拿掉 armature modifier ---
rigid = mesh_obj.copy()
rigid.data = mesh_obj.data.copy()
rigid.animation_data_clear()
bpy.context.collection.objects.link(rigid)
for m in list(rigid.modifiers):
    rigid.modifiers.remove(m)
rigid.parent = None

# 量出模型尺寸，決定間距（不寫死）
bb = [mesh_obj.matrix_world @ v.co for v in mesh_obj.data.vertices]
width = max(v.x for v in bb) - min(v.x for v in bb)
depth = max(v.y for v in bb) - min(v.y for v in bb)
height = max(v.z for v in bb) - min(v.z for v in bb)
gap = max(width, depth) * 1.05
rigid.location.x = -gap
rigid.rotation_mode = "XYZ"
arm.location.x = gap
arm.rotation_mode = "XYZ"
arm.rotation_euler = Euler((0, 0, math.radians(-90)), "XYZ")
mesh_obj.location.x = gap if mesh_obj.parent is None else 0.0

# --- 動畫 ---
scene = bpy.context.scene
scene.frame_start, scene.frame_end = 1, FRAMES

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
bones = [b for b in arm.pose.bones]
bones.sort(key=lambda b: b.name)          # Spine1..Spine6

for f in range(1, FRAMES + 1):
    t = (f - 1) / FRAMES
    ease = (1 - math.cos(t * math.tau)) / 2     # 0 → 1 → 0：抬起來再放下，不是左右搖
    for i, pb in enumerate(bones):
        pb.rotation_mode = "XYZ"
        # ★ 總量 TOTAL_DEG 分散到每一根 ⇒ 累積起來就是一條彎起來的身體
        lift = math.radians(TOTAL_DEG / len(bones)) * ease
        sway = math.radians(3) * math.sin(t * math.tau * 2 + i * 0.7)
        pb.rotation_euler = Euler((lift, sway, 0), "XYZ")
        pb.keyframe_insert("rotation_euler", frame=f)
bpy.ops.object.mode_set(mode="OBJECT")

# 剛體版：只能整隻轉（同樣的節奏、同樣的幅度總和）
for f in range(1, FRAMES + 1):
    t = (f - 1) / FRAMES
    ease = (1 - math.cos(t * math.tau)) / 2
    rigid.rotation_mode = "XYZ"
    # 剛體只能整隻轉，轉的總量與綁骨版累積量【相同】，才是公平對照
    rigid.rotation_euler = Euler((math.radians(TOTAL_DEG) * ease, 0, math.radians(-90)), "XYZ")
    rigid.keyframe_insert("rotation_euler", frame=f)

# --- 燈光與相機 ---
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", type="SUN"))
sun.data.energy = 3.2
sun.rotation_euler = Euler((math.radians(55), 0, math.radians(35)), "XYZ")
bpy.context.collection.objects.link(sun)

fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", type="AREA"))
fill.data.energy = 220
fill.data.size = 8
fill.location = (0, -8, 5)
bpy.context.collection.objects.link(fill)

cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
# ★ 依「畫面要裝下的跨距」反算相機距離，不要手調
span = 2 * gap + max(width, depth)
hfov = 2 * math.atan(0.5 * cam_data.sensor_width / cam_data.lens)
dist = (span / 2) / math.tan(hfov / 2) * 1.18
cam.location = (0, -dist, height * 0.55)
cam.rotation_euler = Euler((math.radians(88), 0, 0), "XYZ")
bpy.context.collection.objects.link(cam)
scene.camera = cam

world = bpy.data.worlds.new("W")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.965, 0.975, 0.99, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
scene.world = world

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 640, 400
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = os.path.join(OUT_DIR, "f_")
bpy.ops.render.render(animation=True)

print("RENDER_DONE:" + str({
    "frames": FRAMES, "gap": round(gap, 3),
    "model_wdh": [round(width, 2), round(depth, 2), round(height, 2)],
    "bones": [b.name for b in bones],
}))
