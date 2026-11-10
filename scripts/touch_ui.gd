extends Control
## واجهة اللمس: عصا حركة يسار، أزرار JUMP / RUN / USE / CAM / GFX يمين، سحب لتدوير الكاميرا،
## خريطة صغيرة، رصيد/معلومات. تعالج اللمس المتعدد بنفسها (كل إصبع له دور مستقل).

var player = null
var cam_rig = null
var minimap_tex: Texture2D = null
var on_gfx: Callable = Callable()
var gfx_name := "MED"

var stick_vec := Vector2.ZERO
var _touches := {}      # رقم الإصبع -> "stick" | "look" | "btn:NAME"
var _t0 := 0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _t0 = Time.get_ticks_msec()


# ------------------------------------------------------------------ التخطيط

func _scale() -> float:
    return get_viewport_rect().size.y / 1080.0


func _stick_center() -> Vector2:
    var s = get_viewport_rect().size
    var u = _scale()
    return Vector2(320.0 * u, s.y - 300.0 * u)


func _buttons() -> Dictionary:
    var s = get_viewport_rect().size
    var u = _scale()
    return {
        "JUMP": {"c": Vector2(s.x - 230.0 * u, s.y - 230.0 * u), "r": 100.0 * u},
        "USE": {"c": Vector2(s.x - 470.0 * u, s.y - 170.0 * u), "r": 75.0 * u},
        "RUN": {"c": Vector2(s.x - 250.0 * u, s.y - 470.0 * u), "r": 70.0 * u},
        "CAM": {"c": Vector2(s.x - 120.0 * u, 260.0 * u), "r": 65.0 * u},
        "GFX": {"rect": Rect2(s.x - 350.0 * u, 20.0 * u, 330.0 * u, 80.0 * u)},
    }


func _minimap_rect() -> Rect2:
    var u = _scale()
    return Rect2(30.0 * u, 30.0 * u, 290.0 * u, 290.0 * u)


## مركز زر بالإحداثيات (يستعمله الاختبار الآلي ليضغط الزر فعلياً).
func center_of(btn_name: String) -> Vector2:
    var d = _buttons()[btn_name]
    if d.has("rect"):
        return d["rect"].get_center()
    return d["c"]


func _hit_button(pos: Vector2) -> String:
    var b = _buttons()
    for k in b.keys():
        var d = b[k]
        if d.has("rect"):
            if d["rect"].has_point(pos):
                return k
        elif pos.distance_to(d["c"]) <= d["r"] * 1.1:
            return k
    return ""


# ------------------------------------------------------------------ اللمس

## يُستعمل في الاختبارات لإرسال لمسة حقيقية عبر نفس مسار اللمس الفعلي.
func fake_touch(index: int, pos: Vector2, pressed: bool) -> void:
    var ev = InputEventScreenTouch.new()
    ev.index = index
    ev.position = pos
    ev.pressed = pressed
    _input(ev)


func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            _down(event.index, event.position)
        else:
            _up(event.index)
    elif event is InputEventScreenDrag:
        _drag(event.index, event.position, event.relative)


func _down(index: int, pos: Vector2) -> void:
    var b = _hit_button(pos)
    if b != "":
        _touches[index] = "btn:" + b
        _press(b)
        return
    var s = get_viewport_rect().size
    if pos.x < s.x * 0.38:
        _touches[index] = "stick"
        _stick_to(pos)
    else:
        _touches[index] = "look"


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
    var role = _touches.get(index, "")
    if role == "stick":
        _stick_to(pos)
    elif role == "look":
        Ctl.add_look(rel * 0.14)


func _up(index: int) -> void:
    var role = _touches.get(index, "")
    if role == "stick":
        stick_vec = Vector2.ZERO
        Ctl.stick = Vector2.ZERO
    _touches.erase(index)


func _stick_to(pos: Vector2) -> void:
    var u = _scale()
    var maxr = 110.0 * u
    var v = pos - _stick_center()
    var m = v.length()
    if m > maxr:
        v = v / m * maxr
    stick_vec = v / maxr
    if stick_vec.length() >= 0.12:
        Ctl.stick = Vector2(stick_vec.x, -stick_vec.y)
    else:
        Ctl.stick = Vector2.ZERO


func _press(b: String) -> void:
    if b == "JUMP":
        Ctl.press_jump()
    elif b == "USE":
        Ctl.press_use()
    elif b == "RUN":
        Ctl.run_toggle = not Ctl.run_toggle
    elif b == "CAM":
        Ctl.press_cam()
    elif b == "GFX":
        if on_gfx.is_valid():
            on_gfx.call()


# ------------------------------------------------------------------ الرسم

func _process(_delta: float) -> void:
    queue_redraw()


func _label(font: Font, text: String, c: Vector2, fs: int, col: Color, w: float) -> void:
    var pos = Vector2(c.x - w * 0.5, c.y + fs * 0.35)
    draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 6, Color(0, 0, 0, 0.7))
    draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)


func _draw() -> void:
    var s = get_viewport_rect().size
    var u = _scale()
    var font = ThemeDB.fallback_font
    var white = Color(1, 1, 1, 0.92)

    # عصا الحركة
    var sc = _stick_center()
    draw_circle(sc, 155.0 * u, Color(1, 1, 1, 0.14))
    draw_arc(sc, 155.0 * u, 0.0, TAU, 48, Color(1, 1, 1, 0.4), 3.0)
    draw_circle(sc + stick_vec * 110.0 * u, 65.0 * u, Color(1, 1, 1, 0.5))

    # الأزرار
    var b = _buttons()
    var use_on = player != null and player.current_interactable != null
    for k in b.keys():
        var d = b[k]
        var col = Color(0.1, 0.12, 0.16, 0.6)
        var text = k
        if k == "RUN" and Ctl.run_toggle:
            col = Color(0.15, 0.6, 0.3, 0.85)
        if k == "USE":
            col = Color(0.95, 0.65, 0.1, 0.9) if use_on else Color(0.1, 0.12, 0.16, 0.35)
        if k == "CAM":
            text = "1ST" if (cam_rig != null and cam_rig.is_first_person()) else "3RD"
        if k == "GFX":
            text = "GFX " + gfx_name
            draw_rect(d["rect"], col, true)
            draw_rect(d["rect"], Color(1, 1, 1, 0.5), false, 2.0)
            _label(font, text, d["rect"].get_center(), int(34.0 * u), white, d["rect"].size.x)
        else:
            draw_circle(d["c"], d["r"], col)
            draw_arc(d["c"], d["r"], 0.0, TAU, 40, Color(1, 1, 1, 0.55), 3.0)
            _label(font, text, d["c"], int(36.0 * u), white, d["r"] * 2.0)

    # الخريطة الصغيرة
    var mr = _minimap_rect()
    if minimap_tex != null:
        draw_texture_rect(minimap_tex, mr, false)
    else:
        draw_rect(mr, Color(0.1, 0.2, 0.1, 0.8), true)
    draw_rect(mr, Color(1, 1, 1, 0.8), false, 4.0)
    var mc = mr.get_center()
    var tri = PackedVector2Array([mc + Vector2(0, -18.0 * u), mc + Vector2(-12.0 * u, 12.0 * u), mc + Vector2(12.0 * u, 12.0 * u)])
    draw_colored_polygon(tri, Color(1.0, 0.25, 0.2))

    # معلومات
    _label(font, "FPS %d" % Engine.get_frames_per_second(), Vector2(s.x - 190.0 * u, 140.0 * u), int(28.0 * u), Color(1, 1, 0.6), 200.0 * u)
    if use_on:
        _label(font, "USE: " + player.current_interactable.prompt(), Vector2(s.x * 0.5, s.y - 120.0 * u), int(40.0 * u), Color(1, 0.85, 0.3), 900.0 * u)
    if Time.get_ticks_msec() - _t0 < 14000:
        _label(font, "Stick: move | Drag right side: look | CAM: 1st/3rd person | USE near doors", Vector2(s.x * 0.5, 150.0 * u), int(26.0 * u), Color(1, 1, 1, 0.85), 1100.0 * u)
