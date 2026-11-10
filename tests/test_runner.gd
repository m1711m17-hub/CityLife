extends Node
## اختبارات آلية (تعمل بدون شاشة: godot --headless res://tests/test_runner.tscn).
## تتحقق من المنطق: الحركة، الجري، القفز، الكاميرا، الباب، الجدران، الرصيف، وأزرار الواجهة.
## لا تتحقق من شكل الرسومات (يُحكم عليه من الـ APK على الهاتف).

var failures := 0
var checks := 0
var main


func check(cond: bool, msg: String) -> void:
    checks += 1
    if cond:
        print("PASS: ", msg)
    else:
        print("FAIL: ", msg)
        failures += 1


func wait(sec: float) -> void:
    await get_tree().create_timer(sec).timeout


func reset_view() -> void:
    Ctl.reset()
    main.cam_rig.yaw = PI


func to_spawn() -> void:
    reset_view()
    main.player.teleport(main.city.spawn_point, PI)


func _ready() -> void:
    _run()


func _run() -> void:
    main = load("res://scenes/main.tscn").instantiate()
    add_child(main)
    var guard = 0
    while not main.ready_done and guard < 1200:
        await get_tree().process_frame
        guard += 1
    check(main.ready_done, "world built (ready_done)")
    if not main.ready_done:
        _finish()
        return

    var p = main.player
    var rig = main.cam_rig
    var ui = main.ui

    # ---- 1) البنية
    check(main.city.get_child_count() >= 26, "city has ground + 25 blocks (%d children)" % main.city.get_child_count())
    check(get_tree().get_nodes_in_group("interactable").size() >= 2, "at least 2 interactable doors")
    check(p != null and rig != null and ui != null, "player, camera rig and UI exist")

    # ---- 2) يقف على الأرض
    await wait(1.0)
    check(p.is_on_floor(), "player stands on floor")
    check(p.global_position.y > -0.2 and p.global_position.y < 0.6, "player height sane (%.2f)" % p.global_position.y)

    # ---- 3) عصا الحركة تحرك اللاعب للأمام
    to_spawn()
    await wait(0.4)
    var a = p.global_position
    Ctl.stick = Vector2(0, 1)
    await wait(1.5)
    Ctl.stick = Vector2.ZERO
    var walked = a.distance_to(p.global_position)
    check(walked > 2.0, "stick moves player (%.2f m in 1.5s)" % walked)
    check(p.global_position.z > a.z, "player moved toward camera forward (+Z)")

    # ---- 4) الجري أسرع من المشي
    to_spawn()
    await wait(0.4)
    Ctl.stick = Vector2(0, 1)
    var s0 = p.global_position
    await wait(1.0)
    var walk_d = s0.distance_to(p.global_position)
    Ctl.run_toggle = true
    s0 = p.global_position
    await wait(1.0)
    var run_d = s0.distance_to(p.global_position)
    Ctl.stick = Vector2.ZERO
    Ctl.run_toggle = false
    check(run_d > walk_d * 1.2, "running faster than walking (walk %.2f, run %.2f)" % [walk_d, run_d])

    # ---- 5) القفز
    to_spawn()
    await wait(0.6)
    var y0 = p.global_position.y
    Ctl.press_jump()
    var max_y = y0
    for i in range(30):
        await get_tree().physics_frame
        max_y = maxf(max_y, p.global_position.y)
    check(max_y > y0 + 0.4, "jump raises player (%.2f m)" % (max_y - y0))
    await wait(1.0)
    check(p.is_on_floor(), "player lands after jump")

    # ---- 6) تبديل الكاميرا
    to_spawn()
    await wait(0.5)
    check(not rig.is_first_person(), "starts in third person")
    Ctl.press_cam()
    await wait(1.0)
    check(rig.is_first_person(), "switches to first person")
    var eye = p.global_position + Vector3(0, 1.62, 0)
    check(rig.global_position.distance_to(eye) < 0.5, "first-person camera at eye position")
    Ctl.press_cam()
    await wait(1.0)
    check(not rig.is_first_person(), "switches back to third person")
    check(rig.global_position.distance_to(eye) > 1.5, "third-person camera behind player")

    # ---- 7) سحب الكاميرا
    reset_view()
    var yaw0 = rig.yaw
    Ctl.add_look(Vector2(30, 0))
    await wait(0.2)
    check(absf((yaw0 - rig.yaw) - deg_to_rad(30.0)) < 0.01, "look drag rotates camera yaw")

    # ---- 8) الباب (زر USE عبر الإدخال)
    var door = get_tree().get_nodes_in_group("interactable")[0]
    reset_view()
    p.teleport(door.global_position + Vector3(0, 0.1, -1.0), PI)
    await wait(0.5)
    check(p.current_interactable == door, "door detected near player")
    Ctl.press_use()
    await wait(1.0)
    check(door.is_open and absf(rad_to_deg(door.hinge.rotation.y)) > 60.0, "USE opens the door")
    # دخول المبنى عبر الباب المفتوح
    Ctl.stick = Vector2(0, 1)
    await wait(1.2)
    Ctl.stick = Vector2.ZERO
    check(p.global_position.z > door.global_position.z + 0.6, "player walks through open door")
    Ctl.press_use()
    await wait(0.3)

    # ---- 9) الجدران تمنع الاختراق
    reset_view()
    var wall_start = door.global_position + Vector3(-4.0, 0.1, -2.0)
    p.teleport(wall_start, PI)
    await wait(0.5)
    Ctl.stick = Vector2(0, 1)
    await wait(1.5)
    Ctl.stick = Vector2.ZERO
    check(p.global_position.z < door.global_position.z, "wall blocks the player (z %.2f < door z %.2f)" % [p.global_position.z, door.global_position.z])

    # ---- 10) صعود حافة الرصيف
    to_spawn()
    await wait(0.4)
    Ctl.stick = Vector2(0, 1)
    Ctl.run_toggle = true
    await wait(3.5)
    Ctl.stick = Vector2.ZERO
    Ctl.run_toggle = false
    check(p.global_position.z > -168.0, "player climbs the curb (z %.2f)" % p.global_position.z)

    # ---- 11) أزرار الواجهة الحقيقية
    to_spawn()
    await wait(0.6)
    var yb = p.global_position.y
    ui.fake_touch(11, ui.center_of("JUMP"), true)
    ui.fake_touch(11, ui.center_of("JUMP"), false)
    var maxb = yb
    for i in range(30):
        await get_tree().physics_frame
        maxb = maxf(maxb, p.global_position.y)
    check(maxb > yb + 0.4, "UI JUMP button makes player jump")
    await wait(1.0)

    ui.fake_touch(12, ui.center_of("CAM"), true)
    ui.fake_touch(12, ui.center_of("CAM"), false)
    await wait(1.0)
    check(rig.is_first_person(), "UI CAM button switches camera")
    ui.fake_touch(12, ui.center_of("CAM"), true)
    ui.fake_touch(12, ui.center_of("CAM"), false)
    await wait(0.8)

    check(not Ctl.run_toggle, "run starts off")
    ui.fake_touch(13, ui.center_of("RUN"), true)
    ui.fake_touch(13, ui.center_of("RUN"), false)
    check(Ctl.run_toggle, "UI RUN button toggles run on")
    ui.fake_touch(13, ui.center_of("RUN"), true)
    ui.fake_touch(13, ui.center_of("RUN"), false)
    check(not Ctl.run_toggle, "UI RUN button toggles run off")

    var tier0 = main.tier
    ui.fake_touch(14, ui.center_of("GFX"), true)
    ui.fake_touch(14, ui.center_of("GFX"), false)
    check(main.tier == (tier0 + 1) % 3, "UI GFX button cycles quality")

    # عصا اللمس الحقيقية: ضغط أعلى مركز العصا ثم تحريكها للأمام
    reset_view()
    p.teleport(main.city.spawn_point, PI)
    await wait(0.4)
    var sc = ui._stick_center()
    var ps = p.global_position
    ui.fake_touch(15, sc, true)
    ui._drag(15, sc + Vector2(0, -100), Vector2.ZERO)
    await wait(1.2)
    ui.fake_touch(15, sc, false)
    check(ps.distance_to(p.global_position) > 1.5, "on-screen stick moves player")
    check(Ctl.stick == Vector2.ZERO, "stick releases to zero")

    door.is_open = false
    _finish()


func _finish() -> void:
    print("")
    print("RESULT: %d checks, %d failed" % [checks, failures])
    get_tree().quit(1 if failures > 0 else 0)
