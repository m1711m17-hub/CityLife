extends Node
## مدخلات اللاعب المشتركة (لمس + لوحة مفاتيح للاختبار). تُسجَّل كـ Autoload باسم Ctl.
## باقي الأنظمة تقرأ من هنا فقط فلا تعتمد على مصدر الإدخال.

var stick := Vector2.ZERO        # عصا اللمس: x يمين، y أمام
var key_move := Vector2.ZERO     # لوحة المفاتيح
var run_toggle := false
var key_run := false
var look_accum := Vector2.ZERO   # بالدرجات

var _jump_t := -10.0
var _use_t := -10.0
var _cam_t := -10.0


func _now() -> float:
    return Time.get_ticks_msec() / 1000.0


func press_jump() -> void:
    _jump_t = _now()


func press_use() -> void:
    _use_t = _now()


func press_cam() -> void:
    _cam_t = _now()


func consume_jump() -> bool:
    var ok = _now() - _jump_t < 0.25
    _jump_t = -10.0
    return ok


func consume_use() -> bool:
    var ok = _now() - _use_t < 0.25
    _use_t = -10.0
    return ok


func consume_cam() -> bool:
    var ok = _now() - _cam_t < 0.25
    _cam_t = -10.0
    return ok


func get_move() -> Vector2:
    var m = stick + key_move
    if m.length_squared() > 1.0:
        return m.normalized()
    return m


func is_running() -> bool:
    return run_toggle or key_run


func add_look(deg: Vector2) -> void:
    look_accum += deg


func consume_look() -> Vector2:
    var d = look_accum
    look_accum = Vector2.ZERO
    return d


func reset() -> void:
    stick = Vector2.ZERO
    key_move = Vector2.ZERO
    run_toggle = false
    key_run = false
    look_accum = Vector2.ZERO
    _jump_t = -10.0
    _use_t = -10.0
    _cam_t = -10.0


func _process(_delta: float) -> void:
    var x = 0.0
    var y = 0.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        y += 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        y -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        x += 1.0
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        x -= 1.0
    key_move = Vector2(x, y)
    key_run = Input.is_key_pressed(KEY_SHIFT)


func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_SPACE:
            press_jump()
        elif event.keycode == KEY_E:
            press_use()
        elif event.keycode == KEY_V:
            press_cam()
    elif event is InputEventMouseMotion:
        # الماوس الأيمن + سحب لتدوير الكاميرا (للاختبار على الكمبيوتر)
        if (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
            add_look(event.relative * 0.15)
