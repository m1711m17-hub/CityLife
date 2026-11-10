extends Node3D
## يبني المدينة التجريبية بالكامل بالكود (لا ملفات خارجية):
## شبكة طرق 6x6، 25 كتلة (وسط مدينة، سكن، شقق، محلات، صناعي، حديقة)،
## محل ومقهى قابلان للدخول بأبواب تعمل، إضاءة شوارع وأشجار.
## الأداء: كل كتلة تُدمج في Mesh واحد لكل خامة (قليل من Draw Calls) مع Collider واحد لكل كتلة.

const DoorScript = preload("res://scripts/door.gd")

const BLOCKS := 5
const BLOCK := 56.0
const ROAD := 16.0
const PITCH := BLOCK + ROAD            # 72
const TOTAL := BLOCKS * PITCH + ROAD   # 376
const HALF := TOTAL * 0.5              # 188
const LOT := BLOCK - 6.0
const SW := 0.12                       # ارتفاع الرصيف

# 0 حديقة، 1 وسط المدينة، 2 سكن، 3 شقق، 4 محلات، 5 صناعي، 6 محلات قابلة للدخول
# الصف = bz (0 الجنوب)، العمود = bx
const LAYOUT = [
    [2, 4, 6, 3, 2],
    [5, 1, 1, 1, 3],
    [2, 1, 0, 1, 4],
    [5, 1, 1, 1, 2],
    [2, 3, 4, 3, 2],
]

const TOWER_KEYS = ["tower_glass", "tower_grey", "tower_sand", "tower_dark"]
const HOUSE_KEYS = ["house_cream", "house_white", "house_brick"]
const APT_KEYS = ["apt_beige", "apt_brick"]
const SHOP_KEYS = ["shop_a", "shop_b", "shop_c"]
const NO_SHADOW = ["grass", "asphalt", "line", "lawn", "path", "floor"]

var spawn_point := Vector3.ZERO
var spawn_yaw := PI   # ينظر نحو +Z (الشمال) باتجاه المحلات

var _rng := RandomNumberGenerator.new()
var _mats := {}
var _st := {}
var _meshes: Array = []
var _cur_parent: Node3D
var _cur_body: StaticBody3D


static func road_coord(i: int) -> float:
    return -HALF + ROAD * 0.5 + i * PITCH


static func block_coord(i: int) -> float:
    return -HALF + ROAD + BLOCK * 0.5 + i * PITCH


func build() -> void:
    _rng.seed = 20260607
    _make_materials()

    _begin("Ground")
    _build_ground_and_roads()
    _end(false)

    for bz in range(BLOCKS):
        for bx in range(BLOCKS):
            _begin("Block_%d_%d" % [bx, bz])
            _build_block(bx, bz, LAYOUT[bz][bx])
            _end(true)

    _build_boundary()
    spawn_point = Vector3(block_coord(2), 0.3, road_coord(0) + 1.0)


## مسافة الرسم (تتغير مع مستوى الرسومات).
func set_view_distance(d: float) -> void:
    for mi in _meshes:
        mi.visibility_range_end = d


# ------------------------------------------------------------------ الخامات

func _solid(key: String, hex: String, rough: float = 0.9) -> void:
    var m = StandardMaterial3D.new()
    m.albedo_color = Color(hex)
    m.roughness = rough
    m.metallic_specular = 0.3
    m.cull_mode = BaseMaterial3D.CULL_DISABLED   # احتياط: يظهر الوجه حتى لو انعكس الترتيب
    _mats[key] = m


func _facade_mat(key: String, wall: String, glass_dark: String, glass_lit: String, chance: float, seed_v: int) -> void:
    var m = StandardMaterial3D.new()
    m.albedo_texture = _facade_texture(Color(wall), Color(glass_dark), Color(glass_lit), chance, seed_v)
    m.roughness = 0.8
    m.metallic_specular = 0.3
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    _mats[key] = m


## واجهة: 4x4 خلايا (كل خلية = 4م عرضاً x 3.5م ارتفاعاً) فيها نافذة، بعضها مضاء عشوائياً.
func _facade_texture(wall: Color, glass_dark: Color, glass_lit: Color, chance: float, seed_v: int) -> ImageTexture:
    var rng = RandomNumberGenerator.new()
    rng.seed = seed_v * 7919
    var size = 128
    var cell = 32
    var img = Image.create(size, size, true, Image.FORMAT_RGBA8)
    var slab = wall.darkened(0.18)
    var frame = wall.darkened(0.38)
    for cy in range(4):
        for cx in range(4):
            var lit = rng.randf() < chance
            var glass = glass_dark.lerp(glass_dark.lightened(0.4), rng.randf())
            if lit:
                glass = glass_lit
            for y in range(cell):
                for x in range(cell):
                    var c = wall
                    if y >= cell - 4:
                        c = slab
                    if x >= 5 and x < 27 and y >= 4 and y < 24:
                        c = frame
                    if x >= 7 and x < 25 and y >= 6 and y < 22:
                        c = glass
                    img.set_pixel(cx * cell + x, cy * cell + y, c)
    img.generate_mipmaps()
    return ImageTexture.create_from_image(img)


func _make_materials() -> void:
    _solid("grass", "#5E8F4A", 0.95)
    _solid("lawn", "#6BA055", 0.95)
    _solid("asphalt", "#2E3136", 0.85)
    _solid("line", "#E8E4D0", 0.8)
    _solid("sidewalk", "#A7A9AB")
    _solid("concrete", "#8C8F92")
    _solid("path", "#B3B0A6")
    _solid("trunk", "#6B4A2F")
    _solid("leaf", "#3E7A3A")
    _solid("lamp_pole", "#3A3F45", 0.6)
    _solid("lamp_head", "#F3E6B0", 0.5)
    _solid("water", "#4C9CC4", 0.2)
    _solid("bench", "#7A5230")
    _solid("door", "#5A3B22", 0.7)
    _solid("roof", "#4B4F55")
    _solid("floor", "#6E6A64", 0.6)
    _solid("wood", "#8A6A4A", 0.7)
    _solid("wh_a", "#6D7C8C")
    _solid("wh_b", "#8C7A66")
    _solid("cont_a", "#B5452F", 0.6)
    _solid("cont_b", "#2F5FA8", 0.6)
    _solid("cont_c", "#3D8A5A", 0.6)
    _solid("shop_wall", "#E3D6B4")
    _solid("shop_accent", "#C0392B", 0.7)
    _solid("cafe_wall", "#C9B79C")
    _solid("cafe_accent", "#2E7D5B", 0.7)

    _facade_mat("tower_glass", "#3E5E7A", "#16222E", "#F6DC9A", 0.12, 1)
    _facade_mat("tower_grey", "#7C838A", "#1B232B", "#F6DC9A", 0.10, 2)
    _facade_mat("tower_sand", "#B9A98A", "#222B33", "#F6DC9A", 0.10, 3)
    _facade_mat("tower_dark", "#3B4048", "#0F161D", "#F2D58A", 0.15, 4)
    _facade_mat("house_cream", "#E6D8B8", "#2B3A48", "#F6DC9A", 0.10, 5)
    _facade_mat("house_white", "#EDEDED", "#2B3A48", "#F6DC9A", 0.10, 6)
    _facade_mat("house_brick", "#B5654A", "#202B36", "#F6DC9A", 0.10, 7)
    _facade_mat("apt_beige", "#C9B999", "#26323E", "#F6DC9A", 0.18, 8)
    _facade_mat("apt_brick", "#A6573F", "#1E2832", "#F6DC9A", 0.18, 9)
    _facade_mat("shop_a", "#D8A55A", "#243342", "#FFE9B0", 0.30, 10)
    _facade_mat("shop_b", "#7FA7B8", "#243342", "#FFE9B0", 0.30, 11)
    _facade_mat("shop_c", "#C77B7B", "#243342", "#FFE9B0", 0.30, 12)


# ------------------------------------------------------------------ الدمج (Batching)

func _begin(node_name: String) -> void:
    _cur_parent = Node3D.new()
    _cur_parent.name = node_name
    add_child(_cur_parent)
    _cur_body = StaticBody3D.new()
    _cur_body.name = "Collision"
    _cur_parent.add_child(_cur_body)
    _st.clear()


func _end(register: bool) -> void:
    for key in _st.keys():
        var st: SurfaceTool = _st[key]
        st.set_material(_mats[key])
        var mi = MeshInstance3D.new()
        mi.name = "M_" + str(key)
        mi.mesh = st.commit()
        if NO_SHADOW.has(key):
            mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _cur_parent.add_child(mi)
        if register:
            _meshes.append(mi)
    _st.clear()


func _get_st(key: String) -> SurfaceTool:
    if not _st.has(key):
        var st = SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        _st[key] = st
    return _st[key]


## مثلث بترتيب رؤوس صحيح (Godot: الوجه الأمامي = اتجاه عقارب الساعة عند النظر إليه من الخارج).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
    if (b - a).cross(c - a).dot(n) > 0.0:
        var t = b
        b = c
        c = t
        var tu = ub
        ub = uc
        uc = tu
    st.set_normal(n)
    st.set_uv(ua)
    st.add_vertex(a)
    st.set_normal(n)
    st.set_uv(ub)
    st.add_vertex(b)
    st.set_normal(n)
    st.set_uv(uc)
    st.add_vertex(c)


## mode: 0 بلا UV، 1 UV بمقياس العالم للجدران (نوافذ)، 2 نقطة ثابتة (سطح بلا نوافذ)
func _face(st: SurfaceTool, b: Basis, c: Vector3, n: Vector3, r: Vector3, u: Vector3, hw: float, hh: float, hd: float, tile: Vector2, mode: int) -> void:
    var cf = c + b * (n * hd)
    var rw = b * (r * hw)
    var uh = b * (u * hh)
    var nn = b * n
    var bl = cf - rw - uh
    var br = cf + rw - uh
    var tr = cf + rw + uh
    var tl = cf - rw + uh
    var uv_bl = Vector2.ZERO
    var uv_br = Vector2.ZERO
    var uv_tr = Vector2.ZERO
    var uv_tl = Vector2.ZERO
    if mode == 1:
        var us = 2.0 * hw / tile.x
        var vs = -2.0 * hh / tile.y
        uv_br = Vector2(us, 0.0)
        uv_tr = Vector2(us, vs)
        uv_tl = Vector2(0.0, vs)
    elif mode == 2:
        uv_bl = Vector2(0.5, 0.01)
        uv_br = uv_bl
        uv_tr = uv_bl
        uv_tl = uv_bl
    _tri(st, bl, br, tr, nn, uv_bl, uv_br, uv_tr)
    _tri(st, bl, tr, tl, nn, uv_bl, uv_tr, uv_tl)


func _add_col(c: Vector3, s: Vector3, rot_y: float) -> void:
    var cs = CollisionShape3D.new()
    var bs = BoxShape3D.new()
    bs.size = s
    cs.shape = bs
    cs.position = c
    cs.rotation.y = rot_y
    _cur_body.add_child(cs)


## صندوق (بلا وجه سفلي). mode=1 للمباني ذات النوافذ.
func box(key: String, c: Vector3, s: Vector3, collide: bool = true, rot_y: float = 0.0, mode: int = 0) -> void:
    var st = _get_st(key)
    var h = s * 0.5
    var b = Basis(Vector3.UP, rot_y)
    var tile = Vector2(16.0, 14.0)
    _face(st, b, c, Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3.UP, h.x, h.y, h.z, tile, mode)
    _face(st, b, c, Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3.UP, h.x, h.y, h.z, tile, mode)
    _face(st, b, c, Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3.UP, h.z, h.y, h.x, tile, mode)
    _face(st, b, c, Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3.UP, h.z, h.y, h.x, tile, mode)
    var top_mode = 2 if mode == 1 else 0
    _face(st, b, c, Vector3.UP, Vector3(1, 0, 0), Vector3(0, 0, -1), h.x, h.z, h.y, tile, top_mode)
    if collide:
        _add_col(c, s, rot_y)


## مبنى بنوافذ: قاعدته على الارتفاع base_y.
func facade(key: String, x: float, z: float, base_y: float, s: Vector3) -> void:
    box(key, Vector3(x, base_y + s.y * 0.5, z), s, true, 0.0, 1)


## سطح أفقي رفيع (طرق، خطوط، عشب) بوجه علوي واحد فقط.
func flat(key: String, cx: float, y: float, cz: float, sx: float, sz: float) -> void:
    var st = _get_st(key)
    var a = Vector3(cx - sx * 0.5, y, cz - sz * 0.5)
    var b = Vector3(cx + sx * 0.5, y, cz - sz * 0.5)
    var c = Vector3(cx + sx * 0.5, y, cz + sz * 0.5)
    var d = Vector3(cx - sx * 0.5, y, cz + sz * 0.5)
    var z2 = Vector2.ZERO
    _tri(st, a, b, c, Vector3.UP, z2, z2, z2)
    _tri(st, a, c, d, Vector3.UP, z2, z2, z2)


## أسطوانة متعددة الأضلاع (قطر، ارتفاع) مركزها c.
func cyl(key: String, c: Vector3, diameter: float, height: float, collide: bool = true, segs: int = 10) -> void:
    var st = _get_st(key)
    var r = diameter * 0.5
    var y0 = c.y - height * 0.5
    var y1 = c.y + height * 0.5
    var z2 = Vector2.ZERO
    for i in range(segs):
        var a0 = TAU * i / segs
        var a1 = TAU * (i + 1) / segs
        var p0 = Vector3(cos(a0) * r, 0.0, sin(a0) * r)
        var p1 = Vector3(cos(a1) * r, 0.0, sin(a1) * r)
        var am = (a0 + a1) * 0.5
        var n = Vector3(cos(am), 0.0, sin(am))
        var b0 = Vector3(c.x + p0.x, y0, c.z + p0.z)
        var b1 = Vector3(c.x + p1.x, y0, c.z + p1.z)
        var t0 = Vector3(c.x + p0.x, y1, c.z + p0.z)
        var t1 = Vector3(c.x + p1.x, y1, c.z + p1.z)
        _tri(st, b0, b1, t1, n, z2, z2, z2)
        _tri(st, b0, t1, t0, n, z2, z2, z2)
        _tri(st, Vector3(c.x, y1, c.z), t0, t1, Vector3.UP, z2, z2, z2)
    if collide:
        var cs = CollisionShape3D.new()
        var sh = CylinderShape3D.new()
        sh.radius = r
        sh.height = height
        cs.shape = sh
        cs.position = c
        _cur_body.add_child(cs)


func _rf(a: float, b: float) -> float:
    return _rng.randf_range(a, b)


func _ri(a: int, b_exclusive: int) -> int:
    return _rng.randi_range(a, b_exclusive - 1)


func _pick(arr: Array) -> String:
    return arr[_ri(0, arr.size())]


# ------------------------------------------------------------------ الأرض والطرق

func _build_ground_and_roads() -> void:
    box("grass", Vector3(0.0, -0.5, 0.0), Vector3(900.0, 1.0, 900.0), true)   # سطحها عند y=0
    for i in range(BLOCKS + 1):
        var c = road_coord(i)
        flat("asphalt", 0.0, 0.05, c, TOTAL, ROAD)
        flat("asphalt", c, 0.05, 0.0, ROAD, TOTAL)
    # خطوط وسطية متقطعة بين التقاطعات
    for i in range(BLOCKS + 1):
        var c = road_coord(i)
        for s in range(BLOCKS):
            var start = -HALF + ROAD + s * PITCH
            for d in range(9):
                var pos = start + 3.0 + d * 6.0
                flat("line", pos, 0.07, c, 3.0, 0.25)
                flat("line", c, 0.07, pos, 0.25, 3.0)


func _build_boundary() -> void:
    # جدران غير مرئية تمنع الخروج من العالم
    var e = HALF + 70.0
    var body = StaticBody3D.new()
    body.name = "Boundary"
    add_child(body)
    var defs = [
        [Vector3(0, 15, e), Vector3(2 * e, 30, 2)],
        [Vector3(0, 15, -e), Vector3(2 * e, 30, 2)],
        [Vector3(e, 15, 0), Vector3(2, 30, 2 * e)],
        [Vector3(-e, 15, 0), Vector3(2, 30, 2 * e)],
    ]
    for d in defs:
        var cs = CollisionShape3D.new()
        var bs = BoxShape3D.new()
        bs.size = d[1]
        cs.shape = bs
        cs.position = d[0]
        body.add_child(cs)


# ------------------------------------------------------------------ الكتل

func _build_block(bx: int, bz: int, type: int) -> void:
    var cx = block_coord(bx)
    var cz = block_coord(bz)
    box("sidewalk", Vector3(cx, SW * 0.5, cz), Vector3(BLOCK, SW, BLOCK), true)
    match type:
        0:
            _park(cx, cz)
        1:
            _downtown(cx, cz)
        2:
            _residential(cx, cz)
        3:
            _apartments(cx, cz)
        4:
            _shops(cx, cz)
        5:
            _industrial(cx, cz)
        6:
            _enterable_shops(cx, cz)
    var o = BLOCK * 0.5 - 1.0
    for sx in [-1.0, 1.0]:
        for sz in [-1.0, 1.0]:
            _lamp(cx + sx * o, cz + sz * o)


func _lamp(x: float, z: float) -> void:
    box("lamp_pole", Vector3(x, SW + 3.0, z), Vector3(0.18, 6.0, 0.18), true)
    box("lamp_head", Vector3(x, SW + 6.1, z), Vector3(0.7, 0.18, 0.35), false)


func _tree(x: float, z: float, y: float) -> void:
    var h = _rf(2.6, 3.6)
    box("trunk", Vector3(x, y + h * 0.5, z), Vector3(0.4, h, 0.4), true)
    var d = _rf(2.8, 3.8)
    box("leaf", Vector3(x, y + h + 0.9, z), Vector3(d, d * 0.8, d), false)
    box("leaf", Vector3(x, y + h + 0.9, z), Vector3(d, d * 0.8, d), false, PI * 0.25)


func _park(cx: float, cz: float) -> void:
    var top = SW + 0.03
    flat("lawn", cx, SW + 0.02, cz, BLOCK - 4.0, BLOCK - 4.0)
    flat("path", cx, SW + 0.04, cz, BLOCK - 4.0, 4.0)
    flat("path", cx, SW + 0.04, cz, 4.0, BLOCK - 4.0)
    cyl("concrete", Vector3(cx, SW + 0.35, cz), 9.0, 0.7, true)
    cyl("water", Vector3(cx, SW + 0.62, cz), 8.2, 0.1, false)
    cyl("concrete", Vector3(cx, SW + 1.4, cz), 0.8, 2.4, true)
    for i in range(28):
        var x = cx + _rf(-LOT * 0.5, LOT * 0.5)
        var z = cz + _rf(-LOT * 0.5, LOT * 0.5)
        if absf(x - cx) < 4.0 or absf(z - cz) < 4.0:
            continue   # لا أشجار على المسارات
        _tree(x, z, top)
    _bench(cx - 9.0, cz + 3.2, 0.0)
    _bench(cx + 9.0, cz - 3.2, PI)
    _bench(cx + 3.2, cz + 9.0, PI * 0.5)
    _bench(cx - 3.2, cz - 9.0, -PI * 0.5)


func _bench(x: float, z: float, yaw: float) -> void:
    var o = Vector3(x, SW + 0.06, z)
    var b = Basis(Vector3.UP, yaw)
    box("bench", o + b * Vector3(0.0, 0.45, 0.0), Vector3(1.8, 0.1, 0.5), true, yaw)
    box("bench", o + b * Vector3(0.0, 0.85, -0.22), Vector3(1.8, 0.5, 0.08), true, yaw)
    box("lamp_pole", o + b * Vector3(-0.8, 0.2, 0.0), Vector3(0.1, 0.4, 0.45), false, yaw)
    box("lamp_pole", o + b * Vector3(0.8, 0.2, 0.0), Vector3(0.1, 0.4, 0.45), false, yaw)


func _downtown(cx: float, cz: float) -> void:
    var cell = LOT * 0.5
    for ix in range(2):
        for iz in range(2):
            var x = cx + (ix - 0.5) * cell
            var z = cz + (iz - 0.5) * cell
            var w = _rf(16.0, 21.0)
            var d = _rf(16.0, 21.0)
            var h = _rf(28.0, 110.0)
            facade(_pick(TOWER_KEYS), x, z, SW, Vector3(w, h, d))
            box("roof", Vector3(x, SW + h + 0.4, z), Vector3(w * 0.5, 0.8, d * 0.5), false)
            if _ri(0, 10) < 4:
                box("lamp_pole", Vector3(x, SW + h + 6.0, z), Vector3(0.3, 12.0, 0.3), false)


func _residential(cx: float, cz: float) -> void:
    var cell = LOT / 3.0
    for ix in range(3):
        for iz in range(3):
            var x = cx + (ix - 1) * cell
            var z = cz + (iz - 1) * cell
            if _ri(0, 9) == 0:
                _tree(x, z, SW)
                continue
            var w = _rf(10.0, 12.5)
            var d = _rf(9.0, 11.0)
            var h = _rf(6.0, 8.5)
            facade(_pick(HOUSE_KEYS), x, z, SW, Vector3(w, h, d))
            box("roof", Vector3(x, SW + h + 0.2, z), Vector3(w + 0.8, 0.4, d + 0.8), false)
            box("door", Vector3(x, SW + 1.1, z - d * 0.5 - 0.06), Vector3(1.2, 2.2, 0.12), false)
            if _ri(0, 3) == 0:
                _tree(x + w * 0.5 + 1.5, z, SW)


func _apartments(cx: float, cz: float) -> void:
    for i in range(2):
        var z = cz + (-1.0 if i == 0 else 1.0) * 13.0
        var w = _rf(36.0, 44.0)
        var h = _rf(15.0, 32.0)
        facade(_pick(APT_KEYS), cx, z, SW, Vector3(w, h, 17.0))
        box("roof", Vector3(cx, SW + h + 0.25, z), Vector3(w + 0.6, 0.5, 17.6), false)


func _shops(cx: float, cz: float) -> void:
    var front = cz - LOT * 0.5 + 6.0
    for i in range(4):
        var x = cx + (i - 1.5) * 12.5
        var h = _rf(6.0, 9.0)
        facade(_pick(SHOP_KEYS), x, front, SW, Vector3(12.0, h, 12.0))
        box("roof", Vector3(x, SW + 3.2, front - 6.8), Vector3(9.0, 0.15, 1.6), false)
    for i in range(3):
        var x = cx + (i - 1.0) * 16.0
        facade(_pick(SHOP_KEYS), x, cz + LOT * 0.5 - 8.0, SW, Vector3(15.0, _rf(5.0, 8.0), 14.0))


func _industrial(cx: float, cz: float) -> void:
    for i in range(2):
        var z = cz + (-1.0 if i == 0 else 1.0) * 13.0
        var key = "wh_a" if i == 0 else "wh_b"
        box(key, Vector3(cx, SW + 4.5, z), Vector3(44.0, 9.0, 20.0), true)
        box("roof", Vector3(cx, SW + 9.2, z), Vector3(45.0, 0.4, 21.0), false)
    var conts = ["cont_a", "cont_b", "cont_c"]
    for i in range(6):
        box(conts[i % 3], Vector3(cx - 20.0 + i * 8.0, SW + 1.3, cz), Vector3(6.1, 2.6, 2.4), true)


func _enterable_shops(cx: float, cz: float) -> void:
    var front = cz - LOT * 0.5 + 6.0
    _enterable("shop", cx - 9.0, front, 14.0, 12.0, 4.2)
    _enterable("cafe", cx + 9.0, front, 14.0, 12.0, 4.2)
    for i in range(3):
        var x = cx + (i - 1.0) * 16.0
        facade(_pick(SHOP_KEYS), x, cz + LOT * 0.5 - 8.0, SW, Vector3(15.0, _rf(5.0, 8.0), 14.0))


## مبنى مجوّف بباب أمامي (جهة -Z) يُفتح بزر USE، مع أرضية وسقف وإضاءة وعداد ورفوف.
func _enterable(nm: String, x: float, z: float, w: float, d: float, h: float) -> void:
    var wall = nm + "_wall"
    var accent = nm + "_accent"
    var y0 = SW
    var t = 0.3
    var door_w = 2.0
    var door_h = 2.6
    var seg_w = (w - door_w) * 0.5
    var fz = z - d * 0.5 + t * 0.5

    box(wall, Vector3(x - door_w * 0.5 - seg_w * 0.5, y0 + h * 0.5, fz), Vector3(seg_w, h, t))
    box(wall, Vector3(x + door_w * 0.5 + seg_w * 0.5, y0 + h * 0.5, fz), Vector3(seg_w, h, t))
    box(wall, Vector3(x, y0 + door_h + (h - door_h) * 0.5, fz), Vector3(door_w, h - door_h, t))
    box(wall, Vector3(x, y0 + h * 0.5, z + d * 0.5 - t * 0.5), Vector3(w, h, t))
    box(wall, Vector3(x - w * 0.5 + t * 0.5, y0 + h * 0.5, z), Vector3(t, h, d - 2.0 * t))
    box(wall, Vector3(x + w * 0.5 - t * 0.5, y0 + h * 0.5, z), Vector3(t, h, d - 2.0 * t))
    flat("floor", x, y0 + 0.01, z, w - 2.0 * t, d - 2.0 * t)
    box("roof", Vector3(x, y0 + h + 0.15, z), Vector3(w + 0.4, 0.3, d + 0.4))
    box(accent, Vector3(x, y0 + h - 0.6, z - d * 0.5 - 0.1), Vector3(w * 0.6, 0.8, 0.15), false)
    box("wood", Vector3(x, y0 + 0.5, z + 1.5), Vector3(w * 0.55, 1.0, 0.8))
    for i in range(3):
        box("wood", Vector3(x - w * 0.3 + i * (w * 0.3), y0 + 1.0, z + d * 0.5 - t - 0.35), Vector3(w * 0.22, 2.0, 0.5))

    # الباب (ديناميكي)
    var door = DoorScript.new()
    door.name = nm + "_Door"
    add_child(door)
    door.setup(door_w, door_h, _mats["door"])
    door.position = Vector3(x, y0, fz)

    # إضاءة داخلية
    var lg = OmniLight3D.new()
    lg.name = nm + "_Light"
    lg.light_color = Color(1.0, 0.92, 0.78)
    lg.light_energy = 1.2
    lg.omni_range = w * 1.1
    lg.shadow_enabled = false
    lg.position = Vector3(x, y0 + h - 0.8, z)
    add_child(lg)
