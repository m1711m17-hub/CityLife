extends Node3D
## باب بمفصلة يُفتح للداخل ويُغلق بزر USE. منطقة التفاعل تُحسب هندسياً (بدون فيزياء).

var width := 2.0
var height := 2.6
var open_angle := -100.0   # بالدرجات (سالب = يُفتح نحو +Z أي للداخل)
var speed := 260.0
var is_open := false
var hinge: Node3D

var _angle := 0.0


func setup(w: float, h: float, mat: Material) -> void:
    width = w
    height = h
    hinge = Node3D.new()
    hinge.name = "Hinge"
    hinge.position = Vector3(-w * 0.5, 0.0, 0.0)
    add_child(hinge)

    var panel = MeshInstance3D.new()
    var bm = BoxMesh.new()
    bm.size = Vector3(w, h, 0.1)
    panel.mesh = bm
    panel.material_override = mat
    panel.position = Vector3(w * 0.5, h * 0.5, 0.0)
    hinge.add_child(panel)

    var body = StaticBody3D.new()
    var cs = CollisionShape3D.new()
    var bs = BoxShape3D.new()
    bs.size = Vector3(w, h, 0.1)
    cs.shape = bs
    cs.position = panel.position
    body.add_child(cs)
    hinge.add_child(body)


func _ready() -> void:
    add_to_group("interactable")


func prompt() -> String:
    if is_open:
        return "Close door"
    return "Open door"


func interact() -> void:
    is_open = not is_open


## هل اللاعب (عند الموضع p بالإحداثيات العامة) قريب بما يكفي للتفاعل؟
func can_interact(p: Vector3) -> bool:
    var l = to_local(p)
    return absf(l.x) < width * 0.5 + 0.75 and absf(l.z) < 1.7 and l.y > -0.6 and l.y < 2.6


func _process(delta: float) -> void:
    var target = open_angle if is_open else 0.0
    _angle = move_toward(_angle, target, speed * delta)
    if hinge != null:
        hinge.rotation.y = deg_to_rad(_angle)
