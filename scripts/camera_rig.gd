extends Camera3D
## كاميرا الشخص الأول والثالث مع انتقال سلس، تدوير بالسحب، ومنع اختراق الجدران (شعاع فيزيائي).

var target: Node3D = null
var yaw := PI              # بالراديان؛ yaw=PI يعني النظر نحو +Z
var pitch := -12.0         # بالدرجات؛ موجب = نظر للأعلى
var third_distance := 4.2
var head_height := 1.62
var first_person := false

var _dist := 4.2
var _allowed := 4.2


func _ready() -> void:
    near = 0.08
    far = 320.0
    fov = 70.0


## نعتبر الكاميرا "أول شخص" عندما تقترب بما يكفي من الرأس.
func is_first_person() -> bool:
    return _dist < 0.7


func _process(delta: float) -> void:
    if target == null:
        return

    if Ctl.consume_cam():
        first_person = not first_person

    var look = Ctl.consume_look()
    yaw -= deg_to_rad(look.x)
    pitch -= look.y
    if first_person:
        pitch = clampf(pitch, -85.0, 85.0)
    else:
        pitch = clampf(pitch, -70.0, 25.0)

    var goal = 0.0 if first_person else third_distance
    _dist = lerpf(_dist, goal, 1.0 - exp(-12.0 * delta))
    if absf(_dist - goal) < 0.01:
        _dist = goal

    var rot = Basis.from_euler(Vector3(deg_to_rad(pitch), yaw, 0.0))
    var pivot = target.global_position + Vector3.UP * head_height
    var back = rot * Vector3(0.0, 0.0, 1.0)

    var wanted = _dist
    if wanted > 0.15:
        var space = get_world_3d().direct_space_state
        var q = PhysicsRayQueryParameters3D.create(pivot, pivot + back * (wanted + 0.25))
        q.exclude = [target.get_rid()]
        var hit = space.intersect_ray(q)
        if not hit.is_empty():
            wanted = maxf(0.3, pivot.distance_to(hit.position) - 0.25)
    # الاقتراب فوري (لا نخترق الجدار)، والابتعاد تدريجي
    if wanted < _allowed:
        _allowed = wanted
    else:
        _allowed = lerpf(_allowed, wanted, 1.0 - exp(-10.0 * delta))

    var pos = pivot + back * _allowed
    if _dist < 0.7:
        pos += rot * Vector3(0.0, 0.0, -0.12)   # أمام العينين قليلاً

    global_transform = Transform3D(rot, pos)
    fov = lerpf(75.0, 62.0, clampf(_dist / third_distance, 0.0, 1.0))

    if target.has_method("set_body_visible"):
        target.set_body_visible(_dist >= 0.7)
