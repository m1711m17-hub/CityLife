extends CharacterBody3D
## اللاعب: حركة (مشي/جري/قفز/جاذبية) نسبة إلى اتجاه الكاميرا، شخصية Low-Poly تُبنى بالكود،
## أنيميشن إجرائي، والبحث عن أقرب شيء قابل للتفاعل (باب).

const WALK := 2.6
const RUN := 5.8
const JUMP_H := 1.1
const GRAV := 22.0
const ACCEL := 20.0
const TURN := 14.0

var cam_rig = null
var current_interactable = null

var model: Node3D
var upper: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var body_meshes: Array = []

var _hvel := Vector3.ZERO
var _phase := 0.0
var _scan := 0.0
var _spawn_pos := Vector3.ZERO
var _spawn_yaw := 0.0
var _al := 0.0
var _ar := 0.0
var _ll := 0.0
var _lr := 0.0
var _lean := 0.0
var _bob := 0.0


func setup(female: bool) -> void:
    floor_snap_length = 0.3
    floor_max_angle = deg_to_rad(62.0)   # حافة الرصيف (12 سم) تُعامل كأرض قابلة للصعود
    var cs = CollisionShape3D.new()
    var cap = CapsuleShape3D.new()
    cap.radius = 0.32
    cap.height = 1.8
    cs.shape = cap
    cs.position = Vector3(0.0, 0.9, 0.0)
    add_child(cs)
    _build_model(female)


func teleport(pos: Vector3, yaw: float) -> void:
    global_position = pos
    velocity = Vector3.ZERO
    _hvel = Vector3.ZERO
    if model != null:
        model.rotation.y = yaw


func set_spawn(pos: Vector3, yaw: float) -> void:
    _spawn_pos = pos
    _spawn_yaw = yaw


func is_airborne() -> bool:
    return not is_on_floor()


# ------------------------------------------------------------------ الحركة

func _physics_process(delta: float) -> void:
    var input = Ctl.get_move()
    var yaw = cam_rig.yaw if cam_rig != null else 0.0
    var fwd = Vector3(-sin(yaw), 0.0, -cos(yaw))
    var right = Vector3(cos(yaw), 0.0, -sin(yaw))
    var dir = fwd * input.y + right * input.x
    if dir.length() > 1.0:
        dir = dir.normalized()

    var top = RUN if Ctl.is_running() else WALK
    _hvel = _hvel.move_toward(dir * top, ACCEL * delta)
    velocity.x = _hvel.x
    velocity.z = _hvel.z

    if is_on_floor():
        velocity.y = 0.0
        if Ctl.consume_jump():
            velocity.y = sqrt(2.0 * GRAV * JUMP_H)
    else:
        velocity.y -= GRAV * delta

    move_and_slide()

    # الدوران: في المنظور الأول يتبع الكاميرا، وفي الثالث يتجه نحو الحركة
    if model != null:
        var target_yaw = model.rotation.y
        if cam_rig != null and cam_rig.is_first_person():
            target_yaw = yaw
        elif _hvel.length_squared() > 0.04:
            target_yaw = atan2(-_hvel.x, -_hvel.z)
        model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-TURN * delta))

    # التفاعل
    if Ctl.consume_use() and current_interactable != null:
        current_interactable.interact()
    _scan -= delta
    if _scan <= 0.0:
        _scan = 0.1
        _find_interactable()

    if global_position.y < -30.0:
        teleport(_spawn_pos, _spawn_yaw)


func _find_interactable() -> void:
    var best = null
    var best_d = INF
    for n in get_tree().get_nodes_in_group("interactable"):
        if n.has_method("can_interact") and n.can_interact(global_position):
            var d = n.global_position.distance_squared_to(global_position)
            if d < best_d:
                best_d = d
                best = n
    current_interactable = best


# ------------------------------------------------------------------ الأنيميشن الإجرائي

func _process(delta: float) -> void:
    if model == null:
        return
    var speed = Vector2(velocity.x, velocity.z).length()
    var air = not is_on_floor()

    _phase += speed * 2.3 * delta
    var amp = clampf(speed * 14.0, 0.0, 58.0)
    var sw = sin(_phase) * amp

    var t_ll = sw
    var t_lr = -sw
    var t_al = -sw * 0.85
    var t_ar = sw * 0.85
    var t_lean = clampf(speed * 1.3, 0.0, 9.0)
    if air:
        t_ll = 25.0
        t_lr = -15.0
        t_al = 70.0
        t_ar = 70.0
        t_lean = 4.0

    var k = 1.0 - exp(-16.0 * delta)
    _ll = lerpf(_ll, t_ll, k)
    _lr = lerpf(_lr, t_lr, k)
    _al = lerpf(_al, t_al, k)
    _ar = lerpf(_ar, t_ar, k)
    _lean = lerpf(_lean, t_lean, k)

    leg_l.rotation_degrees = Vector3(_ll, 0.0, 0.0)
    leg_r.rotation_degrees = Vector3(_lr, 0.0, 0.0)
    arm_l.rotation_degrees = Vector3(_al, 0.0, 3.0)
    arm_r.rotation_degrees = Vector3(_ar, 0.0, -3.0)
    upper.rotation_degrees = Vector3(-_lean, 0.0, 0.0)

    var breathe = sin(Time.get_ticks_msec() / 1000.0 * 1.8) * 0.006 * (1.0 - clampf(speed, 0.0, 1.0))
    upper.scale = Vector3(1.0, 1.0 + breathe, 1.0)
    var bob_target = 0.0
    if speed > 0.3 and not air:
        bob_target = -absf(sin(_phase)) * 0.035
    _bob = lerpf(_bob, bob_target, k)
    model.position.y = _bob


## في المنظور الأول نُخفي الجسم مع إبقاء ظله.
func set_body_visible(vis: bool) -> void:
    var mode = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if vis else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
    for mi in body_meshes:
        mi.cast_shadow = mode


# ------------------------------------------------------------------ بناء الشخصية

func _mat(hex: String, rough: float = 0.8) -> StandardMaterial3D:
    var m = StandardMaterial3D.new()
    m.albedo_color = Color(hex)
    m.roughness = rough
    return m


func _box(size: Vector3) -> BoxMesh:
    var b = BoxMesh.new()
    b.size = size
    return b


func _sphere(r: float) -> SphereMesh:
    var s = SphereMesh.new()
    s.radius = r
    s.height = r * 2.0
    s.radial_segments = 12
    s.rings = 6
    return s


func _capsule(r: float, h: float) -> CapsuleMesh:
    var c = CapsuleMesh.new()
    c.radius = r
    c.height = maxf(h, r * 2.0)
    c.radial_segments = 10
    c.rings = 4
    return c


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
    var mi = MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    mi.position = pos
    parent.add_child(mi)
    body_meshes.append(mi)
    return mi


func _limb(parent: Node3D, nm: String, pivot_pos: Vector3, top_len: float, bottom_len: float, thick: float, top_mat: Material, bottom_mat: Material) -> Node3D:
    var pivot = Node3D.new()
    pivot.name = nm
    pivot.position = pivot_pos
    parent.add_child(pivot)
    if top_len > 0.0:
        _part(pivot, _capsule(thick * 0.5, top_len), Vector3(0.0, -top_len * 0.5, 0.0), top_mat)
    if bottom_len > 0.0:
        _part(pivot, _capsule(thick * 0.46, bottom_len), Vector3(0.0, -top_len - bottom_len * 0.5, 0.0), bottom_mat)
    return pivot


func _build_model(female: bool) -> void:
    var skin = _mat("#E0B08C", 0.7)
    var shirt = _mat("#D9608A" if female else "#2F6DB5")
    var pants = _mat("#4A6FA5" if female else "#2B2F3A")
    var hair = _mat("#5A3A22" if female else "#2A1E16", 0.6)
    var shoes = _mat("#F2F2F2")
    var eye = _mat("#101010", 0.4)

    model = Node3D.new()
    model.name = "Model"
    add_child(model)

    # الشخصية تنظر نحو -Z (اتجاه Godot الأمامي)
    upper = Node3D.new()
    upper.name = "Upper"
    upper.position = Vector3(0.0, 0.9, 0.0)
    model.add_child(upper)

    var torso_w = 0.38 if female else 0.46
    _part(upper, _box(Vector3(torso_w, 0.58, 0.25)), Vector3(0.0, 0.27, 0.0), shirt)
    _part(upper, _box(Vector3(0.40, 0.2, 0.25)), Vector3(0.0, -0.04, 0.0), pants)
    _part(upper, _box(Vector3(0.1, 0.08, 0.1)), Vector3(0.0, 0.6, 0.0), skin)

    var head = Node3D.new()
    head.name = "Head"
    head.position = Vector3(0.0, 0.74, 0.0)
    upper.add_child(head)
    var skull = _part(head, _sphere(0.125), Vector3.ZERO, skin)
    skull.scale = Vector3(0.96, 1.08, 1.0)
    _part(head, _sphere(0.02), Vector3(-0.055, 0.02, -0.115), eye)
    _part(head, _sphere(0.02), Vector3(0.055, 0.02, -0.115), eye)
    # الشعر: كرة أعلى الرأس وخلفه فقط كي لا تغطي الوجه
    var hair_cap = _part(head, _sphere(0.132), Vector3(0.0, 0.05, 0.035), hair)
    hair_cap.scale = Vector3(1.0, 0.95, 1.0)
    if female:
        _part(head, _capsule(0.05, 0.22), Vector3(0.0, -0.08, 0.15), hair)

    arm_l = _limb(upper, "ArmL", Vector3(-(torso_w * 0.5 + 0.06), 0.52, 0.0), 0.3, 0.3, 0.11, shirt, skin)
    arm_r = _limb(upper, "ArmR", Vector3(torso_w * 0.5 + 0.06, 0.52, 0.0), 0.3, 0.3, 0.11, shirt, skin)

    leg_l = _limb(model, "LegL", Vector3(-0.11, 0.88, 0.0), 0.8, 0.0, 0.15, pants, pants)
    leg_r = _limb(model, "LegR", Vector3(0.11, 0.88, 0.0), 0.8, 0.0, 0.15, pants, pants)
    _part(leg_l, _box(Vector3(0.15, 0.08, 0.28)), Vector3(0.0, -0.84, -0.04), shoes)
    _part(leg_r, _box(Vector3(0.15, 0.08, 0.28)), Vector3(0.0, -0.84, -0.04), shoes)
