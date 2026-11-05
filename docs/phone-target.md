# The phone target

The same program on the phone the designer carries, so a site can be drawn up where it is
rather than back at a desk. The device this was built against is a Samsung SM-A166W: 2340 by
1080 physical pixels on a 6.7 inch screen, which is 384.6 dots to the inch, arm64 only.

## 1. The build

`export_presets.cfg` holds `[preset.1]` "Android (phone)": arm64-v8a alone, package
`ca.storm.landscapingplanner`, signed with the debug keystore, immersive, sensor landscape,
endpoint `sensorLandscape` through `display/window/handheld/orientation = 4`.

There is no Gradle, no NDK and no CMake in this path. The prebuilt `android_debug.apk` export
template is the whole toolchain: an AAB or a plugin would need them, and this needs neither.
Tests, tools, docs and preview are left out of the export, as they are on the desktop preset.

Two things the first real export taught. **ETC2/ASTC has to be on** -
`rendering/textures/vram_compression/import_etc2_astc`, which a Windows-only project has
never needed - or the export refuses to start. And the build is one command:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . \
    --export-debug "Android (phone)" build/landscaping-planner-debug.apk
```

which signs with the debug keystore and writes about 48 MB, arm64 only, with the whole
project in `assets/`. `build/` is in `.gitignore`: the preset is the file to keep, not the
APK a tool run made from it.

Two project settings exist only because of a phone: `application/config/quit_on_go_back` is
off, so Back is ours to answer, and `input_devices/pointing/android/enable_long_press_as_right_click`
plus `enable_pan_and_scale_gestures` hand the platform's own gestures to the engine.

## 2. Touch is a second door onto the same commands, never a second command

Every command on a phone is reached through the control that already reaches it: the menu bar,
the palette, the page's own buttons. What is added is *input* - three seams, none of which can
disagree with the keyboard, because each of them ends in the same code the keyboard ends in.

### 2.1 Pinch and two-finger pan (`ViewMath`, `ViewController.touch_command`)

`ViewMath.zoom_factor_for_spread` and `focus_after_screen_drag` are pure arithmetic over the plan's
size, the drag and the viewport height: no camera, no node, no scene, so a test holds them down.
`ViewController.touch_command(event)` reads a magnify or pan gesture and answers `{kind, factor,
at | delta}` - it decides, and `pan_by_screen` is the one pan helper mouse and glass share, so the
two cannot drift apart.

### 2.2 Back is Escape (`Hud.back_puts_away`)

A back gesture arrives as `NOTIFICATION_WM_GO_BACK_REQUEST` and takes the same ladder Escape
takes: close the page in front by the door its own cross uses, else the ladder in
`escape_puts_away`, else ask about leaving - because a thumb brushes that gesture by accident and
a drawing lives in memory until it is written.

### 2.3 The ground view's thumb (`TouchPad`, `MoveInput.set_touch_stick`, `PlanPlayer.look_by_drag`)

The ground view needed movement *and* look, which were a polled keyboard and a captured mouse.
`TouchPad` is one transparent control over the whole screen, shown only in the ground view: the
left half is a stick, the right half turns the head. Its arithmetic is `drag_stick()` - a static,
so the dead zone and the rim are tested without a thumb.

The stick *composes* with the keys (`MoveInput.stick()` adds the two and clamps to a unit
length) rather than replacing them, so a laptop with a touch screen keeps its keyboard. The look
goes through `PlanPlayer.look_by_drag`, the same call the mouse makes, so a finger and a mouse
cannot have two sensitivities.

## 3. Storage: a file on a phone is handed over, not addressed (`PhoneFiles`)

Android gives a program permission to one document at a time, through its own picker. A path
under `/storage/emulated/0` is not something this program may open however it asks, and the
all-files permission that would change that is a Play-store restriction with no need here.

So `PhoneFiles.prepare(dialog)` hands every door that *already reaches the filesystem* to the
phone's picker (`use_native_dialog`, which on Android is only supported for
`ACCESS_FILESYSTEM`) and leaves every door that stays inside `user://` alone. That second half
is the rule worth keeping: a drawing is written to a temporary file and renamed into place, and a
hand-over cannot rename anything, so those doors must never be converted.

What comes back from the picker is read once and taken into the design - a photograph is copied
into the app's pictures, a survey becomes rows on the drawing - which is why no import keeps a
path to a file the phone could take away again.

## 4. The HUD on a phone: stated in millimetres (`PhoneHud`)

A 1600 by 900 layout stretched onto this screen draws a logical pixel 0.079 mm wide, so a 29-pixel
palette row measured 2.3 mm and twelve-pixel text about 1 mm. Both are statements in millimetres
rather than in pixels, which is why `PhoneHud` states its targets that way - `TOUCH_MM` 5.5 for a
thumb, `TEXT_MM` 1.6 for a capital - and converts through the window's own scale and the screen's
own density, taken as arguments so the arithmetic can be tested on a desk.

`PhoneHud.apply(window)` draws the canvas up by 1.35 on a phone, and the palette's buttons are
sized to the derived row and font in one deferred pass - deferred because during `_ready` the
window has not been laid out and reports a scale of 3.6 where the finished window uses 1.35, which
made every row *smaller* than the desk's own the first time it was tried.

On a computer every function here returns nothing to do, which is what keeps the desk's HUD
exactly as it was drawn.

## 5. What is not done

- The pages' *buttons* are made finger-sized in the one place a page is shown
  (`PageChrome.size_for_a_finger`, which `show_centred` calls), so a page's answering
  row is a thumb's size on a phone and untouched on a computer. Their text fields,
  pickers, lists and headings are still the desk's, because a field grows with its
  font and making one grow is a change to that page rather than to a thumb.
- The palette is the only screen surface resized. The menu bar, the top bar and the presentation
  panel are unchanged.
- The density, the picker and the touchscreen reading are the *device's* to state. Each has a
  demonstration that forces the device and proves the wiring (`touch_demo`, `touch_walk_demo`,
  `phone_files_demo`, `phone_hud_demo`); whether the phone agrees is what a run on it answers.

## 6. Where the device run actually stands

A signed debug APK is built (`build/landscaping-planner-debug.apk`: 48 MB, arm64-v8a,
`ca.storm.landscapingplanner`, landscape, targetSdk 36, **no permissions requested**) and it has
been **copied onto the SM-A166W** - `Internal storage/Download` - over MTP.

It is **not installed yet**, because Android installs an APK only through adb or a tap, and adb
has no ADB interface to talk to: the phone enumerates as `SAMSUNG Mobile USB Composite Device`
and `SAMSUNG Mobile USB Modem`, which proves the cable and the port carry data, but USB debugging
is off (About phone > Software information > Build number x7, then Developer options > USB
debugging, replug, Allow). Wireless debugging likewise advertises nothing (`adb mdns services`
is empty), and Samsung's MTP driver reports **0 bytes for every file** through the shell API, so
a copy cannot be verified by size - by name is the only check there.

So the three readings that only the phone can give are still open: the real
`DisplayServer.screen_get_dpi()`, whether the picker hands back a path `FileAccess` can read, and
whether the palette row lands at `TOUCH_MM`. With USB debugging on, they are one command away:
`adb install -r build/landscaping-planner-debug.apk`, then `adb logcat`.
