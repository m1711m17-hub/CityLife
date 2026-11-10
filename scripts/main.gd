extends Node3D
## نقطة البداية: يبني البيئة والمدينة واللاعب والكاميرا والواجهة والخريطة الصغيرة.

const CityBuilderScript = preload("res://scripts/city_builder.gd")
const PlayerScript = preload("res://scripts/player.gd")
const CameraRigScript = preload("res://scripts/camera_rig.gd")
const TouchUIScript = preload("res://scripts/touch_ui.gd")

const TIER_NAMES = ["LOW", "MED", "HIGH"]
const TIER_FAR = [220.0, 320.0, 450.0]

@export var female := false

var ready_done := false
var tier := -1
var player
var cam_rig
var ui
var city
var sun: DirectionalLight3D
var env: Environment
var minimap_vp: SubViewport
var minimap_cam: Camera3D

var _mm_timer := 0.0


func _ready() -> void:
    Ctl.reset()
    RenderingServer.set_default_clear_color(Color(0.05, 0.07, 0.1))

    # شاشة تحميل (بناء المدينة قد يستغرق عدة ثوانٍ على الهاتف)
    var loading = CanvasLayer.new()
    var lbl = Label.new()
    lbl.text = "CITY LIFE\nLoading..."
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    lbl.add_theme_font_size_override("font_size", 56)
    loading.add_child(lbl)
    add_child(loading)
    lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await get_tree().process_frame
    await get_tree().process_frame

    _build_world()
    loading.queue_free()
    ready_done = true


func _build_world() -> void:
    _setup_environment()

    city = CityBuilderScript.new()
    city.name = "City"
    add_child(city)
    city.build()

    player = PlayerScript.new()
    player.name = "Player"
    add_child(player)
    player.setup(female)
    player.set_spawn(city.spawn_point, city.spawn_yaw)
    player.teleport(city.spawn_point, city.spawn_yaw)

    cam_rig = CameraRigScript.new()
    cam_rig.name = "CameraRig"
    add_child(cam_rig)
    cam_rig.target = player
    cam_rig.yaw = city.spawn_yaw
    cam_rig.current = true
    player.cam_rig = cam_rig

    _setup_minimap()

    var layer = CanvasLayer.new()
    layer.name = "HudLayer"
    add_child(layer)
    ui = TouchUIScript.new()
    ui.name = "TouchUI"
    layer.add_child(ui)
    ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui.player = player
    ui.cam_rig = cam_rig
    ui.minimap_tex = minimap_vp.get_texture()
    ui.on_gfx = cycle_quality

    var cores = OS.get_processor_count()
    apply_quality(0 if cores <= 4 else (1 if cores <= 6 else 2))


func _setup_environment() -> void:
    env = Environment.new()
    var sky = Sky.new()
    sky.sky_material = ProceduralSkyMaterial.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 1.0
    env.fog_enabled = true
    env.fog_light_color = Color(0.72, 0.8, 0.9)
    env.fog_density = 0.0035
    var we = WorldEnvironment.new()
    we.name = "WorldEnvironment"
    we.environment = env
    add_child(we)

    sun = DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
    sun.light_energy = 1.1
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    sun.shadow_enabled = true
    add_child(sun)


func _setup_minimap() -> void:
    minimap_vp = SubViewport.new()
    minimap_vp.name = "MinimapViewport"
    minimap_vp.size = Vector2i(256, 256)
    minimap_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
    add_child(minimap_vp)

    minimap_cam = Camera3D.new()
    minimap_cam.name = "MinimapCam"
    minimap_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
    minimap_cam.size = 110.0
    minimap_cam.near = 1.0
    minimap_cam.far = 400.0
    # بيئة بلا ضباب خاصة بالخريطة
    var menv = Environment.new()
    menv.background_mode = Environment.BG_COLOR
    menv.background_color = Color(0.2, 0.3, 0.2)
    menv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    menv.ambient_light_color = Color(1, 1, 1)
    menv.ambient_light_energy = 0.9
    minimap_cam.environment = menv
    minimap_vp.add_child(minimap_cam)
    minimap_cam.current = true


func _process(delta: float) -> void:
    if not ready_done or player == null or minimap_cam == null:
        return
    # الخريطة تدور مع اتجاه النظر وتتحدث 5 مرات في الثانية (توفيراً للأداء)
    minimap_cam.global_transform = Transform3D(
        Basis.from_euler(Vector3(-PI * 0.5, cam_rig.yaw, 0.0)),
        player.global_position + Vector3(0.0, 150.0, 0.0))
    _mm_timer -= delta
    if _mm_timer <= 0.0:
        _mm_timer = 0.2
        minimap_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


# ------------------------------------------------------------------ مستويات الرسومات

func cycle_quality() -> void:
    apply_quality((tier + 1) % 3)


func apply_quality(t: int) -> void:
    tier = clampi(t, 0, 2)
    Engine.max_fps = 30 if tier == 0 else 60
    var far_d = TIER_FAR[tier]
    if cam_rig != null:
        cam_rig.far = far_d
    if city != null:
        city.set_view_distance(far_d)
    sun.shadow_enabled = tier > 0
    sun.directional_shadow_max_distance = 45.0 if tier == 1 else 80.0
    get_viewport().msaa_3d = Viewport.MSAA_DISABLED if tier == 0 else Viewport.MSAA_2X
    if ui != null:
        ui.gfx_name = TIER_NAMES[tier]
