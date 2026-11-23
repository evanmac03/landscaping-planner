# The phone, the tablet and the desk: one program, three devices

The same program on the phone the designer carries, so a site can be drawn up where it is
rather than back at a desk. The device this was built against is a Samsung SM-A166W: 2340 by
1080 physical pixels on a 6.7 inch screen, arm64 only. Measured on the device it reports
**450 dots to the inch** - the 384.6 in this document's first draft was an estimate from the
screen's advertised size, and the program reads the real number either way, so only the
arithmetic in the demonstrations moved with it.

## Where to start, if you have not designed for a phone before

**The order that works here is: read the rule, find the module that already owns it, then measure on the phone.**
Nothing on these pages was designed by eye at a desk. A desk cannot answer for a phone - its band is nothing, its
density is a monitor's, its finger is a mouse - and the instruments in section 13 exist because the rectangle a
program draws and the pixels a person sees are two different statements that are allowed to disagree.

**1. This document is already the digest.** Read section 4 (the HUD on a phone, stated in millimetres), then section
5 (which devices are answered with a finger, and which are not), then sections 10, 11 and 12 for the row a menu's
own entries are given, the window's size class, and what a press looks like. **Section 14 is the one to come back
to:** it states the two numbers this program took from Android, the one Android rule it breaks and why, and where
each of them was read from - and `tests/test_phone_target.gd` reads those numbers back out of the modules that own
them, so the prose cannot drift away from the code.

**2. Then the platform's own sources, in this order.**

- **Material 3** (`m3.material.io`) - its **Target sizes** page and its **Grids & spacing** page carry the rule that
  changes every layout decision: how large a target a fingertip needs, and how far apart two of them must stand
  before a thumb can tell them apart. Section 14 works the platform's numbers into this phone's own pixels, and
  says why this program states a smaller floor anyway.
- **Android's accessibility help on touch target size** (`support.google.com/accessibility/android`) - the same
  rule, and a short procedure for checking it by hand. The probe's own lines are that procedure done for every
  control on the screen at once, which is section 13.
- **Android's adaptive app guidance** (`developer.android.com/develop/adaptive-apps`, and **Adapt layouts** under
  `developer.android.com/design/ui/mobile`) - the quality guidelines there are a checklist with guideline IDs and
  test IDs, so they read as a familiar document rather than a foreign one, this program already keeping an audit of
  itself. Two of its rules matter most here: decide from the **window's size class** first and its height second,
  and adapt by **reflow, reveal or a change of presentation** rather than by stretching a component. One line of it
  is a rule this program obeys by construction - **do not lock an app to portrait**, because a window that cannot
  turn is a window that letterboxes.

**3. Godot's own page is "Multiple resolutions"**, under *Rendering* in the online manual (`docs.godotengine.org`),
and most of what it asks for is already taken in `project.godot`: the `canvas_items` stretch mode, the `expand`
aspect, and a handheld orientation of `sensor`, so the device may turn the window and `OrientationChoice` decides
case by case what the board does about it. The one piece of that page's advice this program **declines** is the
default theme scale of 1.5 to 2.0, because this program carries no theme at all - its words are sized per device at
run time instead (`PhoneHud.font_size`, `ReadingSize`). A static scale is one answer for every screen, and the whole
of this document is about one program giving two answers.

**4. The rule already has a module, and that is where a number changes.** The table below is a map and not a second
statement of anything: **no row in it may name a number**, because the file each row points at is where the number
lives.

| the rule | the file that owns it |
| --- | --- |
| how large a target a finger must have | `scripts/touch_target.gd`, and the device floor in `PhoneHud` |
| how close two targets may stand | `scripts/spacing.gd` |
| the bands the device keeps for itself | `scripts/safe_area.gd`, `PhoneHud.cutout_here` |
| words large enough for the density | `scripts/legibility.gd`, `ReadingSize` |
| ink a person can read against what is behind it | `scripts/contrast.gd` |
| the window's size class and its breakpoints | `WindowClass` |
| which way up the window is, and its shape | `WindowPosture`, `scripts/held_orientation.gd` |
| a control the room cannot hold | `scripts/in_view.gd` |
| two controls drawn in one rectangle | `scripts/stacked.gd` |

**5. And the rule of the house that makes all of it safe: ask a capability, never a platform.** A difference between
a desk and a phone is a question with **one owner** - `shows_touch_controls()` for whether a finger is being served,
`PhoneHud` for the device's own numbers, `DevicePlatform` for the platform's name - and
`tests/test_device_doctrine.gd` names any file that asks the machine for itself. That is what lets an edit meant for
the phone leave a desk exactly where it was, and it is also why "make it Android-only" cannot be done by putting
code somewhere else: there is one GUI, one set of scenes and one HUD, and it *asks*.

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

### 2.4 The Undo a thumb can reach (`TouchFurniture.stand_the_gesture_button`)

A desk's palette is put away on a finger (`show_the_furniture` does that), and the palette is where the one undo
button on the screen lives - so a thumb had no undo at all. What a phone gains is the **reach**, not a second
button: the palette's own is *moved* into the dock's strip, reporting the same `draft_undo` command the menu bar
reports, and handed back to the palette wearing exactly what it wore. That is section 2's rule applied to a
`Button`.

It stands **outside the strip's own scroll**, which is the difference between one tap and a hunt: the strip scrolls
on a narrow phone, so a control left inside it is a control to scroll past a tool to find. `ToolStrip` is a
`PanelContainer` and a `PanelContainer` holds exactly one child, so the scroll is wrapped in a row the furniture
makes - the scene is not changed, and the wrap is the same `reparent` the strip's borrowed tools already use.

The words stay "Undo", because the recorded rule for these two buttons is that the text is the verb and the
gesture's name goes to the tooltip. A thumb sees no tooltip, so the naming reaches a finger through the sentence
the status line says the moment the button is pressed ("undid drawing a new line").

Measured on the desk-side phone run of `tools/touch_hud_workspace.tscn` (2026-11-23), the button stands at
`screen (1404, 624) .. (1519, 722) 115x98 px`, 41 px of type at the A16W's 450 dpi, with the six drawing tools
inside the scroll beside it and nothing in a row it may not share.

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

### 4.1 The palette's width, and its foot

The palette is the one panel whose *width* is worked out at run time rather than in the scene, and the
first pass at it on a phone still took **810 of the canvas's 1444 logical pixels - 56% of the drawing -
with its own labels running out of their cells and under the panel's edge**. Four separate causes, each
of them measured by `tools/palette_probe.tscn`, run as `application/run/main_scene` for one build because
`tools/` never reaches an APK:

- **a cell was as wide as a desk, not as wide as its words.** `PALETTE_CELL_WIDTH` was 86 while at the
  phone's own font "Angular dim" is 155, so its label ran across its neighbour's cell and its last letter
  sat under the panel's edge. A cell is `max(the words, the desk's cell)` now.
- **the room was a ratchet.** `_palette_room()` answered `max(size.x, designed)`, so every showing of the
  palette read back the width the previous row had grown the panel to: measured, the edit row went from
  three columns to four on the second pass. The room is the scene's own anchors (392) and nothing else.
- **a row was as wide as the sum of its controls.** Three buttons in a row ask for all three side by side,
  and at 45 px "Plot a sheet" beside "Painted plan" is 549 px of a 392 px panel. The palette's rows and the
  plant panel's are `HFlowContainer`s now, whose minimum is their *widest single control*, so a phone wraps
  a row onto a second line - and a desk, where every sum already fits, draws exactly what it drew before.
- **a picker was as wide as its longest item.** Godot sizes an `OptionButton` to its longest entry, so a
  layer named "500-IRRIGATION" - held but never chosen - made the layer picker 453 px wide while it was
  showing "Design". `fit_to_longest_item` is false for every picker the palette carries now.

Its **foot** was the last fault, and the one that put the palette over the hint strip: a landscape canvas
is 666 logical pixels tall and the palette had a fixed bottom at 838, so its last 172 px were off the
screen and the strip was buried under it. It is anchored to the foot now (`anchor_bottom` 1.0,
`offset_bottom` -62), the way `Hints` and `DraftHints` already were, which leaves exactly the 8 px of
clearance the desk has always had.

Measured on the SM-A166W: **692 logical pixels to 406 (58% to 34%)** on a portrait canvas, **810 to 690
physical (56% to 29%)** on the landscape one, every label inside its cell, and about a seventh of the
screen handed back to the drawing. On the desk nothing moved: `Palette x 12..404, y 70..838` is the
rectangle the audit measured before the change and after it.

On a computer every function here returns nothing to do, which is what keeps the desk's HUD
exactly as it was drawn.

### 4.2 The top bar: a plate that runs under the camera, and a rule inside it

The bar is anchored to the top of the screen, and where the device keeps a band along that edge - the
A16W's is 110 px of the room, on the `insets` line of the probe's own block - the plate is drawn from the
glass's own top edge, so that the band is covered by the bar rather than by bare board, and the row of
menus inside it is pushed clear by exactly what the device keeps. The plate keeps the 8 px rounded top
corners and the 12 px the scene insets it by at the sides, so it reads as one pane running off the top of
the glass rather than as a strip laid across it. Measured standing: the strip the bar reserves went from
the 91 px a landscape bar had left behind to **247 px** of the room, the row's own first line from
`at=(16, 9)` to `at=(16, 131)`, and the three view buttons out of the band altogether - six `unsafe` and
`middle` findings became none.

**And the row itself was wider than a standing room** - found 2026-11-23 with the phone attached, and
invisible on a desk for three reasons at once. The row wanted **1289 layout px of a 1185 px room**, so the
bar's own plate ran 61 px past the left edge of the glass and 62 past the right, `TouchRow` and its `Menu`
button 47 px past one edge, and `GroundButton` 47 px past the other - and 47 px inside the band the device
keeps, so a control a finger is meant to press stood under the system's own gesture area. A desk hides all of
it: standing is the *narrowest* room the program is ever drawn in, the phone's scale differs (0.91 standing,
1.62 lying), and its font is the device's own, so the same row of words measures differently there than on
the desk that laid the scene out.

**The cure is the words, because a thumb's floor leaves nowhere else.** `dress_for_a_finger` holds every
button at `PhoneHud.row_height` square (107 px here) whatever its text, so a shorter word is the only saving
a bar can make - and two of the three view buttons were wearing a **keyboard shortcut a phone does not
have**: "2D plan  (Q)", "Ground view  (G)". That is the same fault `HINTS_OVERHEAD_ON_A_FINGER` was written
to end for the foot line, and `Hud._view_button_words` answers both from the same reading
(`shows_touch_controls`), so a button and the line beneath it cannot disagree about what this device has.
Nothing is lost with the hint: the key it named was never one a thumb could press. Removing it took 119 of
the 136 px the bar needed; the last 17 came off "Ground view", which a phone's bar shows as "Ground" - the
same name with its second word off. The way *out* of the ground view keeps its whole sentence, because the
other two controls are hidden there and there is room for it.

**Measured on the A16W standing, the same block before and after**: the row 1289 -> **1076**, the bar's plate
61/62 px past the glass -> **inside it**, four `offscreen` lines and one `unsafe` line -> **none**, and every
control's own rectangle - `Menu` at 26..147 through to `Ground` at 881..1054 - inside a 1080 px screen. The
desk is untouched, and its own instrument says so: `hud_layout_check` still prints `TopBar row wants 1544.0
px, panel is 1576.0 px -> FITS`, the number this project recorded for it before the change.

The plate is a `StyleBoxFancy` (`addons/StyleboxFancy/`, vendored) rather than the scene's `StyleBoxFlat`,
and `scripts/chrome_style.gd` is its **one owner**. Two things about it are worth writing down, because
both were learned by looking at the glass rather than by reading a property:

- **The plate is derived from the one the scene drew.** `ChromeStyle.bar_plate` reads the paper, the
  corners and the insets off `hud.tscn`'s own plate instead of stating them a second time, so a change to
  the desk's bar cannot leave the phone's describing a different pane. The scene gives its bar, its
  palette and both hint plates the *same* sub-resource, so the phone's plate is a new stylebox besides:
  growing a shared one in place would push the contents of all four.
- **The rule inside the edge is three pixels and sits six inside it, and neither number is a taste.** In
  `StyleBoxFancy._draw_border`'s anti-aliased path the outer rect is pulled in by half the anti-aliasing
  width and the inner rect pushed out by the same half, so the ring that actually reaches the glass is
  `width - anti_aliasing_size` wide. A one-pixel hairline therefore draws **nothing at all**, and the first
  version of this plate was indistinguishable from the flat box it replaced. That is a fault no rectangle
  reports and no test could have guessed at, which is why the plate was cropped twice and looked at.

Where a device keeps no band the override is taken away and the bar is the bar the scene drew, to the
pixel. `tests/test_chrome_style.gd` holds the scene's plate and this file's numbers together, and
`tests/test_phone_hud.gd` holds the lift itself.

**A phone lying on its side has no band along the top at all.** The A16W's notch turns with the device, so
the inset it keeps - 110 px of the room standing - is 62 px along the *left* edge once the phone is lying,
which is why the palette is given ground on that side, and the bar keeps the landscape bar it always had:
the 91 px strip. Measured on the A16W on 2026-11-18: lying, the probe's own `insets` line reads
`room l=62 t=0` and the strip is 91; standing, the band is along the top and the strip is 247.

**The foot of the screen keeps a band the program is told rather than reads.** The A16W's own report names
it - `overrideNonDecorFrame=[0,100][1080,2298]` upright, `[100,0][2340,1038]` lying, so **42 px** along the
foot either way - and Godot has **no answer for it**: `screen_get_usable_rect` reports the whole screen
there, so a band built out of both readings comes back to the cutout alone. Every other surface had already
learned about the top; the plate at the foot was still anchored 12 px above the bottom of the room, so its
own lowest row stood in the band the system draws over. `PhoneHud.KEPT_FEET` states the number for the
screens this project has measured and answers **zero** for any other, and `Hud.give_the_foot_line` takes it
off the offsets the scene drew - 12 for the working line, 62 for the one a tool in hand reads - rather than
writing new ones, so a device that turns out to keep nothing is handed the scene's own numbers back to the
pixel. The band, and its share of the room, are printed in the block beside `insets`, because that line is
the cutout alone and would otherwise read as a program giving the foot no ground at all.

**And the whole chrome is now stated once per shape, not once per launch.** `get_viewport().size_changed`
re-runs the pass that sizes the chrome for the device, so a phone turned after starting gets the new
room's bar, strip and palette rather than the ones it launched with. Before that the row stood **81 px
inside** the camera band with its own middles inside it once the glass had turned, and the bar's words
were fitted once at the other shape's scale - 25 px where the screen asks 45, and rows 54 px tall where a
finger wants 97. Both move with the shape now.

## 5. Which devices are answered with a finger, and which are not

The question is not which operating system the program is running on. `TouchInput` asks the device, and
answers "a finger" only when all three of these hold:

- **there is a touchscreen** (`DisplayServer.is_touchscreen_available()`), because a desk with a mouse and
  no glass has nothing to size for;
- **the screen is held rather than sat at** - the density is at least `HELD_DPI`, 200 dots to the inch.
  This one is load-bearing: the desktop this was written on answers `is_touchscreen_available()` with true
  in a headless run and reports 144, which is Windows' *logical* density for a 1.5x scale, while Android
  reports a panel's physical 450. 200 sits above every Windows scaling step and below every phone and
  tablet, and it is the reading that separates the two cleanly - an inch worked out from a desktop's
  logical density is not a physical inch;
- **the row the program already draws is thinner than a thumb here** - 29 px at 450 is 1.6 mm, at 144 it
  is 5.1 mm, and at 96 it is 7.7 mm. This is the measurement the other two are a shortcut for.

A density nobody could read is not a "no" that resizes anything: the layout keeps the size it was built
at, because a size worked out from a number that does not exist is worse than the one on screen.

Two answers follow from that decision, and they are separate on purpose:

- **sized for a thumb** (`PhoneHud.on_a_finger_here`): the palette's rows and the pages' buttons are
  derived from `TOUCH_MM` and `TEXT_MM`. True on a phone, on a tablet, and on a dense touchscreen laptop.
- **the canvas drawn up** (`PhoneHud.zooming_here`): `content_scale_factor` 1.35, and only on a window
  small enough to be worth it - a **compact** one, under 600 dp on its shorter side. A tablet is the
  first answer without being the second: it has the room at its own scale, and drawing it up would cost
  it a third of its drawing area to make controls bigger than they already are. The class is stated in
  `WindowClass`, and section 11 is where the measurement that replaced the diagonal is written down.

`scenes/tablet_demo.tscn` states a ten-inch tablet's density and measures what it gets - a palette 507 px
wide on a 1600 px canvas, a row at 5.50 mm, and no zoom. `scenes/phone_hud_demo.tscn` prints what *this*
device would be told beside what a phone is told, which on a desk is "touchscreen no, 144 dpi, a thumb is
needed: no".

### What is still not done

- The pages' *buttons*, and the menus their pickers open, are made finger-sized in the one place a
  page is shown (`PageChrome.size_for_a_finger`, which `show_centred` calls); a menu is fitted in
  **words and in row** - see §10. Their text fields, lists and headings are still the desk's, because
  a field grows with its font and making one grow is a change to that page rather than to a thumb.
- The palette is the only screen surface resized. The top bar's **row** is fitted now too, and re-fitted
  when the glass changes shape (§4.2); the presentation panel is still unchanged.
- The **foot strip speaks a desk's language** on a phone. The ground view's line was the first one fixed -
  `HINTS_GROUND_ON_A_FINGER`, chosen by the same `shows_touch_controls` that decides whether the thumb pad
  is built at all - because a phone in a garden has no keys *and* no mouse, and the two gestures it does
  have were nowhere on the screen. The rest of the strip still needs a phone's vocabulary: `HINTS_2D` names
  a wheel and W A S D, and `hand_keys` names Enter and Escape, where a phone has `touch_command`'s pinch
  and two-finger pan and the palette's own `Finish` and `Close` buttons to end a shape.
- No tablet has been held: the ten-inch reading above is the desk doing the tablet's arithmetic with a
  tablet's density, which is what `tablet_demo` exists for.

## 6. Where the device run actually stands

An arm64 debug APK is built (`build/landscaping-planner-debug.apk`, about 52 MB,
`ca.storm.landscapingplanner`, landscape, targetSdk 36, **no permissions requested**), installed on the
SM-A166W over adb, and driven on it. On the glass it reads:

- **450 dots to the inch**, 2340 by 1080, Android 16, so the logical canvas is 1444 px wide;
- the **menu bar folds** to eleven titles and a **More** menu, the whole row 1388 px inside 1444;
- the **palette is whole** - `Drawing (0)` and every button inside the panel, whose row of edit buttons
  re-flows to as many columns as the panel has room for - two at a thumb's type size;
- the **palette takes 29% of the landscape canvas** rather than 56%, a tool to a row and every label
  inside its cell (section 4.1);
- the **system picker opens** with `typ=*/*`; it opened as `text/plain` before, which greyed out the very
  `.survey` the door exists for, and the APK still asks for no permissions;
- the **ground view walks** in first person and **turns when the right half of the screen is dragged**.

Still open, and stated rather than assumed: whether a picked file comes back as a path `FileAccess` can
read - the return trip recreates the activity, the frame comes back byte-identical and no import appears -
the left-half stick walking, and any reading at all from a real tablet or a Linux machine.

## 7. The camera, on the glass

The field survey's camera was built and then measured on the SM-A166W, and the measurement moved
the design twice:

* The APK request is no longer nothing. It asks for **one** permission - `android.permission.CAMERA`
  - and nothing else: no storage, no network, no location. A camera is gated by Android, so a program
  that takes photographs cannot be the program that asks for nothing; what it *can* be is a program
  that asks for exactly one thing.
* The device offers **23 formats** and the engine will not start a feed until one is chosen. The
  chosen one here is 1920 x 1440 `YUV_420_888`, and a photograph taken through it is about 250 KB.

The run that proved it, on the glass: Site > Record what is on site... > Take a photo... raised
Android's own permission question; allowing it showed the back camera; the shutter kept a photograph
in the app's own storage under `files/field_photos/`, and pulling that file out with `adb exec-out run-as`
and opening it showed the machine the phone was pointed at, with its text legible.

Two things about the photograph are the engine's rather than this program's, and are stated rather
than hidden: the picture comes back with a strong colour cast on this device, and it is whatever the
compatibility renderer's YUV conversion makes of the frame. Nothing in this program guesses at a
correction for it; a photograph taken outdoors in daylight will show the cast for what it is.

**The front door, on the glass.** The launch page was driven on the same device. It stands; its two
choices are drawn at the size of a thumb; and *Take a photograph* opens the camera straight from it
with no drawing open at all - which is the whole point of having the door. Its Close button fell off
the bottom edge at the first size it declared (520 by 320): the shared chrome grows every button to
5.5 mm on a phone, four grown buttons plus their sentences want more room than a desk's worth of
content does, and the window does not grow past the size the page declares. The door now declares
520 by 540. **The page layout check cannot catch that class of fault** - it measures at a desk, on
purpose, which is what keeps it measuring the pages this project designed - so a page whose slack is
too small for grown buttons is found only on a phone, by looking.

## 8. Being held: landscape, portrait, and a camera the phone does not turn for you

`window/handheld/orientation` was **4**, which is not `SCREEN_SENSOR` (that is 6) but
`SCREEN_SENSOR_LANDSCAPE` - a request that pins the activity to landscape. So the window did *not*
follow the device, and a phone held upright showed the whole program on its side. It is **6** now, and
the same build comes up landscape in one run and portrait in another with nothing changed but the way
the phone was lying. The seven values are worth stating once, because 4 and 6 look alike:
`SCREEN_LANDSCAPE` 0, `SCREEN_PORTRAIT` 1, `SCREEN_REVERSE_LANDSCAPE` 2, `SCREEN_REVERSE_PORTRAIT` 3,
`SCREEN_SENSOR_LANDSCAPE` 4, `SCREEN_SENSOR_PORTRAIT` 5, `SCREEN_SENSOR` 6.

**The two canvases.** Landscape is 1444 by 666 logical pixels; portrait is 1185 by 2567. Both follow
from the window's own arithmetic - `stretch/mode` `canvas_items` with `aspect` `expand` takes the smaller
of the two axis scales (1.2 landscape, 0.675 portrait), and `PhoneHud`'s `UI_SCALE` of 1.35 rides on top,
so one logical pixel is 1.62 physical across a short side and 0.911 the other way. Measured, not derived:
the front door declares 520 by 540 and drew 472 physical pixels wide in portrait, and 472 / 520 = 0.911.

**Driving either shape from a desk.** `adb shell settings put system accelerometer_rotation 0` followed
by `user_rotation 0` (portrait) or `1` (landscape) does turn this app - a landscape frame under
`user_rotation 1`, and then a byte-identical portrait frame back at `0`. It did *not* work while the app
was pinned to landscape, which is where an earlier reading of "adb cannot fake the rotation" came from: it
was the lock refusing, not the platform. Restore with `accelerometer_rotation 1`.

**What the HUD does when the canvas turns.** The docked panels are anchored and re-lay-out by
themselves, and the menu bar folds: 6 titles and a **More** in portrait, 11 and a **More** in landscape,
with its second row wrapping when the titles and the view buttons will not share one. Palette,
presentation panel, hints, compass and scale bar all stay on the screen in both shapes.

**A page is put back when the room changes shape under it.** `PageChrome.show_centred` dispatches
to `Window.popup_centered_clamped`, which is a position and not an anchor: a page opened while the
canvas is 666 tall and then left open through a turn to 2567 tall was stranded where it was, near
the top. Seen on the glass. The doorway is what made it matter - the front door follows the phone,
so a page *is* up through a turn - and two things answer it. `PageChrome.placed_again` reads the room
again and places the page by the *same* arithmetic `show_centred` opened it with, so the two cannot
drift apart, from the floor the page **declares** rather than the one it was left: its `min_size`
holds last time's clamp, and a page brought down to 630 could never grow back to the 720 it asked
for. And the HUD walks the pages that are up on the viewport's `size_changed`, because that is the
one node that knows which pages there are - `pages_in_windows()` plus the front door, which answers
its own Escape and is deliberately not in that list. Nothing else is asked for again: the keyboard is
not taken a second time and no button is made big for a finger a second time, because a page somebody
is already using has already answered both of those questions.

**And the palette is wide.** It takes 55% of the landscape canvas and **68% of the portrait one** -
794 logical pixels of 1444 and 1185. That is the phone pass's own doing, not the orientation change:
`PhoneHud.size_for_a_finger` grows the palette buttons and `columns_that_fit` sets them three across, and
the panel is a `PanelContainer` that widens to hold them. On a phone in portrait that leaves a third of
the screen for the drawing. A cap on the column width is the obvious answer and has not been written.

**The camera still has to be turned by hand.** A sensor is bolted to the phone's body, so a picture
arrives on its side whenever the phone is; `scripts/held_orientation.gd` (`HeldOrientation`) is the
app's knowledge of that, as pure statics, and `CameraWindow` pushes the quarter turn and the cover fit
into the viewfinder's shader from `DisplayServer.screen_get_orientation()`. The picture's proportions
have to be kept by the material rather than by the stretch mode, because a rectangle cannot fit the shape
a picture has *after* it has been turned - which is what `CameraCapture.turned_size` and `cover_scale`
are for. The photograph follows for free: it is a grab of the page.

**A page's own title bar is drawn above the page.** Godot draws an embedded `Window`'s title bar
itself, and it draws it *above* the rectangle the window reports as its position and size, while
`popup_centered_clamped` centres the contents alone. So a page lost the top of its own title bar as
soon as its floor came within twice the bar's height (36 px on this theme) of the room - and on the
four pages that declare 850 pixels on a 900-pixel desk that was 11 pixels of it, which
`tools/page_chrome_probe.tscn` showed: the figures page opened at `position.y` 25 with its title
text drawn from -11. The camera page is the same fault at full size, and is why a phone read it as
"the page does not fit": its 720 came down to the 666 a phone has, which put the *whole* bar - the
word "Camera" and the close cross - above the top of the screen. Nothing measurable was wrong:
`size` read 880 by 666, `position` read (282, 0), a centred page on a canvas it exactly matched, and
the layout fitted. The fix is in the one place a page is put on a screen: `PageChrome.content_room`
takes the bar's height out of the room before the floor is clamped, and `show_centred` moves the page
down by half of it - which is what centres the window rather than its contents. Measured after: the
camera page opened 880 by 630 at position (282, 36), its whole self exactly the canvas, with the bar
from the top of the frame, and the figures page 850 tall at (210, 43) with all 36 pixels of its bar.

**But the top of that screen is the HUD's own bar, and a page reaching it drew over the menu titles.**
The bar is the scene's own furniture - `TopBar` is anchored 12 to 62 pixels down, and a phone's own
chrome makes it taller - and a page whose title bar was placed at 7 on a desk, or above the top of the
screen on a phone, covered it: the figures page's 36-pixel bar landed straight on the menu titles, and
it was the **ground** view, where nothing else is up at the top, that made it plain. A page cannot have
the room *and* the strip the bar occupies, so the strip is stated once, by the HUD, and every page lands
below it. `PageChrome.reserved_above` is set from the bar's own *rectangle*, in the pass that has just
sized the chrome for the device - read off the bar rather than the offset the scene gives it, because a
phone's bar is not the desk's: measured, 61 pixels tall with its foot at 70 against the desk's 50 and
62 in a landscape room, and 562 in a narrow portrait one, where the chrome folds. It is stated whether
or not the bar is on screen, because a page that moved when the bar appeared would be worse than one
simply placed low; and a page already up when that pass runs - the front door, which is shown as the HUD
starts - is put back through the same door a change of the room's shape uses, so that "every page lands
below the bar" is true of every page rather than of most of them. `content_room` takes the strip out of
the room and `_place` moves the page down by half of it, exactly as the page's own bar is accounted for;
a page shown with no HUD - every test - finds nought there and lands where it always did.

**Measured after, on a 1600 by 900 desk:** the figures page opens **1180 by 802** - the room less the
bar's 62 and its own 36 - at **(210, 98)**, so its title bar stands from 62 to 98 and the menu titles
above it are clear; and the front door, which had already landed when the strip was stated, is put back
at 229 rather than the 198 it first landed at. **On the SM-A166W, held upright:** the room is 1185 by
2567 and the chrome folds to **562**, so the camera page - the one page that asks for the whole room -
opens at **(0, 598)**, 1185 by 1969, with its own bar standing from 562 to 598: the bar's own foot, and
not a pixel over it. The price is that a page as tall as the room reaches the strip and its own bar less
far, and the ten pages that declare more than a screen already scroll their length, so a page brought
down shorter than its contents still shows its own last row.

**And a page that has outgrown its room says so.** It was silent before, and silently wrong: a page whose
bottom had been cut looked exactly like a page that had ended. The sentence stands in the page's own title bar -
the one strip of a page that a scroll cannot take away, where a caption put inside the contents would be
scrolled out of sight by the very thing it warns about. `PageLayout.words_for_a_page_that_scrolls` words it,
because that module owns the measurement `PageChrome.scroll_if_it_does_not_fit` has just made.

**And it says what is true of the page now, not what was true once.** The wrapper is made once and left
standing, because it does no harm once it is there - but the title is written on every landing, so a page
wrapped for a phone and landed again on a desk comes out saying its own name and nothing more. The first
version added the sentence once and left it, and `hud_layout_check` printed it as a lie: the front door of a
1600 x 900 desk announced that it was taller than the screen while it stood whole in the middle of one.
`PageLayout.the_title_itself` takes the sentence off again, and that pair is what makes writing it on every
landing idempotent. A page that fits says nothing extra, so a desk's titles are exactly the titles they were -
and the same device measured both ways: with the pair in place the front door of the A16W's own block reads
`"Landscaping Planner"`, where the page fills the room it was given rather than overflowing it.

**Still owed.** The direction of that quarter turn was chosen clockwise and has not been seen on a phone
held upright; it is one number in `HeldOrientation.quarter_turns` if it is the wrong way.

## 9. Which way up the board is asked to be

The board opens **wide** and a person may say otherwise - which is the three answers of
`scripts/orientation_choice.gd` (`OrientationChoice`): `LANDSCAPE`, `PORTRAIT`, `FOLLOW`. The
default is landscape because a plan is drawn along a wide screen, and because that is what the
program has always opened at; a person who has never touched this gets exactly what they got
before there was a choice. The three are reached at **View > Screen orientation**, as the same
kind of set as the three views above them.

| answer | what the window is asked for | what it means on the glass |
| --- | --- | --- |
| Landscape (the default) | `SCREEN_LANDSCAPE` | wide, however the phone is held |
| Portrait | `SCREEN_PORTRAIT` | upright, however the phone is held |
| Follow the phone | `SCREEN_SENSOR` | turns with the device |

**The arithmetic is in one file and the asking is in one place.** `reading_for` turns a hold into
a `DisplayServer` reading and nothing else in the program turns one into the other, because the
seven readings include 4 (`SCREEN_SENSOR_LANDSCAPE`) and 6 (`SCREEN_SENSOR`) and asking for the
wrong one pins a window to landscape while every sentence about it says it follows the phone -
which is the fault §8 records. `ViewController._ready` asks beside `PhoneHud.apply` (the
same node, the same reason: the window is nobody else's to set) and the menu handler
applies the board's answer again through the same door when a person changes it. A choice is kept in
`user://orientation.json` through a temporary file and a rename, and read back at startup: never
having chosen and having chosen the default are the same answer, and a file that cannot be read
is a board that has not been told rather than a fault to report. The parse is `JSON.new().parse`
rather than `JSON.parse_string`, which prints an engine error for every file it cannot read and
so fails a test run over a corrupt file nobody was asked about.

**The doorway follows the phone; the board keeps its own answer.** The front door and the page it
leads to are not a board - one is a door with two choices on it, the other is the list of ways a
drawing can begin - so neither is pinned wide. `OrientationChoice.DOORWAY` is the follow-the-phone
hold under the name of the thing it is for, and `for_the_window(doorway_is_up, kept)` is the whole
rule in one function. The state is handed in rather than worked out there, because whether the
doorway is up is `StartChoices.should_show`'s answer and not this file's to know: `ViewController`
asks it at startup and the HUD asks again whenever the doorway comes or goes, which are the only two
moments it can change. Asking once at a launch is deliberate - a window asked for landscape and then
for the sensor in the same breath is a phone that turns twice where a person sees it turn once. It is
not a fourth entry on the menu: a window asked to follow the phone already answers it, so a person who
has chosen that sees no change at all when the doorway comes and goes.
**On a desk the three are shown switched off.** A desktop's window cannot be asked to change
which way up it is, so `can_turn` takes the platform's answer as an argument (`OS.has_feature`
("mobile")` where it is asked for real) and the entries carry `enabled_when = &"can_turn"`. An
entry that looks pressable and is not is the thing this program spends the most effort avoiding,
and a switched-off entry that names what is missing is the honest way to say it.

**Verified on the SM-A166W, three ways in one run:** the build came up landscape with the phone
lying exactly as it had when the previous build came up portrait (byte-identical to the earlier
landscape capture); the drawing board came up behind the front door in landscape; and forcing the
display upright mid-run with `accelerometer_rotation 0` and `user_rotation 0` left the frame
**byte-identical**, so the window is genuinely requesting landscape rather than merely happening
to be that way. The suite is 3,925.

**And verified again on the R5CYA269Q8P, in one process (pid 24,957, never restarted).** With the
phone lying portrait, the build came up at **1080 by 2340 with the front door upright and centred**
and its title bar drawn from the top of the frame - where the same build before the doorway rule came
up wide. The room was then changed *under the open door*, with `wm size 2340x1080`: the door was
**re-centred in the new canvas** with its bar flush to the top, which is `placed_again` and the HUD's
`size_changed` hook doing the work rather than a second `_ready` (the pid proves that, and so does the
absence of a second menu build). `wm size reset` brought it back **byte-identical** to the launch
capture, 83811 bytes both times. Taking a way in then took the board back: the display reported
`rotation 1` at 2340 by 1080, and the drawing board came up landscape with the new drawing on it. The
camera page that appeared in one earlier capture was a stale instance rather than a fault - a clean
force-stop and start shows the front door alone, twice over. `dumpsys display` is worth reading
carefully for this: `mBaseDisplayInfo` reports the *unrotated* size and `rotation 0` whatever the
phone is doing, so the picture and `mOverrideDisplayInfo` are the readings that mean anything. A
`input tap` missed two buttons that `input keyevent 61` then `66` reached, which is the same
unreliability §8 records for the touch injection. The suite is 4,052.

**The window says what it was asked for, and that is the only way to see the request.** Two lines of
the program's own device report, read with `adb logcat | grep ORIENT`, in the same spirit as the menu
bar's line: a phone showing a wide page in a hand that is holding it upright looks exactly like a
phone that asked for landscape, so which of the two happened cannot be seen on the glass. The view
controller prints one at the start of every run - `ORIENT start: path='' dirty=false doorway=true
asks=follow reading=6 can_turn=true` - and the HUD one whenever the doorway comes or goes -
`ORIENT doorway: up=false asks=landscape`. The *reading* is printed too, because the 4-versus-6 fault
this section opens with is exactly a reading nobody looked at. Verified with them in place on the
R5CYA269Q8P: the launch printed `asks=follow reading=6 can_turn=true` and three `doorway: up=true
asks=follow` as the door stood up and handed over to the begin page, then `up=false asks=landscape`
when the last doorway page went away - and the WindowManager log immediately after it names the same
request in Android's own words, `rotationForOrientation(orient=SCREEN_ORIENTATION_LANDSCAPE (0))`,
against the 2340 by 1080 the board then drew. `SCREEN_SENSOR` appears there as
`SCREEN_ORIENTATION_FULL_USER (13)`, which is what a following window leaves behind, and the whole
launch stayed at 1080 by 2340. That report is also what settled a two-second landscape blink seen
once, before it existed: every ask is now accounted for in the log, none of them asked for landscape
at that moment, and the phone's auto-rotate was on - so the blink was the device's own sensor while
it was being picked up, which is what following the phone *means* rather than a fault in it.

## 10. A menu's row, and the reader's own word size

Two things a thumb meets were still a desk's, and both were settled by measuring rather than by reading.

**A menu's row is not its font.** A page's pickers are fitted when the page *opens*
(`PageChrome._size_the_menus_for_a_finger`, through `PhoneHud.size_a_windows_words_for_a_finger`), which
is why a page nobody has opened reports its menus at the desk's 16 px while a page that is up reports 47:
the same menu, before and after. What a thumb hits is the **row**, and a row is the font's own line plus
the separation the theme puts between items - so measured at the phone's own scale, the fitted menu came
to **44 px against the 51 px a button gets**. The menus were the smallest thing on a page to hit, which is
the very thing the fitting above exists to stop. `PhoneHud._raise_the_row_to_a_thumb` now puts the slack
into the separation and only ever **raises** it: a menu already drawing a thumb's row is left exactly as
the theme drew it, and a menu shown twice is not handed a taller row twice.

The instrument is worth recording, because the obvious one lies. Copying a menu's font size onto a
`PopupMenu` of one's own and reading `get_contents_minimum_size` answers **27 px for a menu drawn at 16
and 27 px again for one drawn at 47** - a font-size override does not move a fresh menu's contents size,
so that reading was the default theme's row both times. What held was a **rendered** menu:
`tools/phone_gui_probe.tscn` opens a page, pops its picker up, and divides the menu's own height among its
items less the panel stylebox's frame. It reports `open page` and `never opened` side by side, which is the
only reading that can tell the two apart.

**The reading size is stated here because the platform will not state one.** Android hands every app the
reader's own text-size setting, in `sp`; Godot exposes no reading of it - the screen queries are a size, a
density and two scale factors, and none of them is a font scale - so a person who needs larger words was
being given none. `scripts/reading_size.gd` (`ReadingSize`) is that choice: three answers (Standard, Large,
Largest), each a factor on the sizes `PhoneHud` states, kept in `user://reading-size.json` the way the
board's orientation is kept, and reached at **View > Reading size**.

The words **and the rows that hold them** move together, because a row is what a thumb hits and a control
cannot be shorter than the words inside it; and nothing under 1.0 is either offered or accepted, because
every size in `PhoneHud` is a floor - what a thumb can hit, what an eye can read at arm's length - rather
than a preference. `Hud._menu_set_reading_size` hands the factor to `PhoneHud` and fits the board again,
and any page already open with it: a page fitted twice is the same page drawn bigger rather than a page
grown twice, because a page's words are grown from the size the page laid them out at.

**A desk is untouched by it.** Nothing is fitted on a computer, so the three entries carry the `finger`
need and are shown switched off there - the same honesty the three orientation choices have on a machine
whose window cannot turn. An entry that is not offered beats one that does nothing when it is pressed.


## 11. A window's class, its shape, and the hinge nobody can see (`WindowClass`, `WindowPosture`)

Android has two more ideas about a device than this program first had, and these are the two files that
state them - each written as far as it can honestly be written and no further.

**Size is a table rather than a diagonal** (`WindowClass`). Whether the whole canvas is drawn up used to be
a screen's long side compared against seven inches, which is the right answer bought with the wrong unit. A
dp is 1/160 inch, the unit Android states a size in, and Android's five window size classes are compact
under 600, medium under 840, expanded under 1200, large under 1600, and extra-large above. **The class is
taken from the window's *shorter* side**, and that is the correction: the phone this program is aimed at is
832 dp across held sideways - a *medium* window by width, not a phone at all - and it is its 384 dp of
height that has no room. Asking the wider side would have answered that a phone has room it does not have.
So `zooming_here` asks `WindowClass.is_small` now, Material's own breakpoints are asserted in
`tests/test_window_class.gd`, and a window nobody could measure has **no class** rather than the smallest
one, because a number that does not exist is not an answer about a window. `tablet_demo` prints the class a
ten-inch tablet would be - expanded - beside the answer it already printed.

**A fold cannot be read** (`WindowPosture`). Android's third idea is posture: a foldable standing
half-open on a table wants the controls in the half nearest the hands, and one folded like a book wants a
page kept clear of the crease. Both of those want the fold itself, and `DisplayServer`'s whole vocabulary
about a screen - its size, its density, its scale, its orientation, its usable rectangle and whether it
has a touchscreen - holds no fold, no hinge and no posture. So what is named here is the **shape of the
window the fold leaves behind**: standing when it is as tall as it is wide or taller, lying along when it
is wider than it is tall. That is the one part of the posture question that is not a guess, the shape is
read from the room alone so it can be reported anywhere, and the guard is deliberately a *negative* one -
`tests/test_window_posture.gd` fails if an answer claiming a fold is ever added. Keeping a paragraph clear
of a crease needs the crease's position, and a page narrowed to sit in the left half of a *standing* window
would be narrowed wrongly on every phone and every tablet held upright, which is a wrong answer of the kind
this project spends its effort avoiding; so nothing is done about it and this paragraph is the record of
why. The shape is reported where a device already is - `HudProbe.device_lines` prints `shape=standing`
beside the density - so a driver can at least read which way up the window is.

## 12. What a press looks like, and what a control that cannot be pressed looks like

Two answers a thumb has no other way of being told, since a finger has no hover to light a control up
before it lands. `scripts/touch_style.gd` builds one `Theme` and hands it to the two carriers a control
can reach: the HUD's own `Root` control, from `Hud._ready`, and every page, from `PageChrome._land`,
where the page lands - the one place a page is shown.

**Two carriers, because a `CanvasLayer` stops a theme lookup.** A theme is found by walking up from a
control to the first ancestor that has one, and a theme put on the tree's root - where this first went -
reaches nothing inside this HUD, because the HUD *is* a `CanvasLayer`. Measured: a `Button` under
`root > CanvasLayer > Control` answers the engine's own default, while the same theme worn by the
`Control` inside the layer answers this program's.

**Every box is the engine's own box for that state, recoloured, and nothing else.** Content margins,
border widths and expand margins are *layout* here - `PageLayout` reads them as a page's padding, the
room arithmetic subtracts them and the audit measures against them - so a recolouring cannot move a fit.
A fill is free; a border is a size, and that is why a press carries no border.

**A press is stated under both `pressed` and `hover_pressed`, with one box.** A finger always hovers - a
touch arrives as a pointer that stays - so a held button, and a toggle that is on, are drawn in the
engine's *press-while-hovered* state; and the engine states **nothing at all** for a `Button`'s
`hover_pressed`, so a lookup for it lands on a box that draws no centre. Measured on the SM-A166W: with
only `pressed` stated, the palette's tool-in-hand drew this program's border around **no fill at all**,
with the panel showing through it.

**Measured on the glass, after the fix**: the held Line tool read `#6e7580` - the stated fill, byte for
byte - where the untouched button beside it read `#272828`, and the palette's panel behind them
`#3a3e3f`. A control that cannot be pressed is stated with its fill pulled down to `#0f0f0f` and its
words dimmed, and that half was measured on the glass too: on the Billing page, whose buttons are dead
until a job is chosen, "Start billing it" read `#0f0f0f` - the stated fill - with its words at
`#777777`, where a live control on the same background read `#2e2e2e`. The desk is unchanged:
the audit still reads `TopBar row 1540.0 of 1576.0 -> FITS`, the palette column fits, and all 34 pages
fit the size they declare.

## 13. Reading the probe back off a phone

A log is a ring, and a session is not. `adb logcat` holds a rolling buffer, so a phone session long enough to be worth reading has usually scrolled past the block that mattered - and once it has gone it has gone. Every block `HudProbe.publish` speaks is therefore also written to `user://probe.log`, out of the one door that publishes anything: `publish` says it, `HudProbe.record` keeps it, and the file holds the very words that were printed, so a line pulled off the device and a line read out of the log cannot come to disagree about a number.

**Pulling it off the device.**

```
adb exec-out run-as ca.storm.landscapingplanner cat files/probe.log
```

That route works because the build is debuggable, which is the same condition as `HudProbe.on()`: a release build carries the code and never runs it, and writes no file either.

**It gives up its oldest lines rather than filling the phone.** Past `HudProbe.LOG_LIMIT` (1 MB) the file keeps the newest `LOG_KEEP` (500 KB). The cut is made at a line break and never inside one, so a block is never half a block, and the rewrite goes through `user://probe.log.writing` and is renamed into place - the same rule every other written file here follows, so an interrupted trim leaves the log it had rather than half of the one it was making.

### 13.1 The phone's own room on a desk, so its layout is desk work

Every figure this document states about a phone was, until now, only obtainable by building an APK,
installing it and looking at the device. `tools/phone_screen.tscn` answers the same questions on the
desk: it states the A16W through the doors the program already has - `PhoneHud.force_density`,
`PhoneHud.force_display` and `TouchInput.force`, none of them new - hangs `main.tscn` inside a
`SubViewport`, and prints the program's own block. Measured 2026-11-18, the run and the device agree
line for line: room `viewport=(1185, 2567) native=(1080, 2340)`, strip 247 px, insets `room l=0 t=110`
over `display l=0 t=100`, kept foot `42 px of the display, 46 of the room`, and the palette's own
rectangles identical to the pixel (`Move / J` at `screen (26, 1979) .. (169, 2050) 144x71`). With
`--shot` it writes a picture of the room's canvas at 1185 by 2567 - and `--door` leaves the front door
standing, for looking at that - and the picture set beside a capture taken off the phone is the same
screen element for element: the same bar, the same palette in the same order, and the foot line
wrapping at the same three points.

Three things are worth knowing before reading its block.

**The room comes from the window, and the scale from the same one.** A `Window` is what makes
`canvas_scale` answer the phone's 0.91, and the fitting is sized by it. A `Window` made at runtime
starts with canvas scaling switched off, so the project's own `content_scale_size`, mode and aspect are
handed on from the root window rather than copied, and the room that follows is the device's 1185 by
2567. A `Window` is also *unreadable* - an embedded one is composited into its parent, so its texture
comes back one flat colour - which is why the program hangs inside a `SubViewport` instead: a
`SubViewportContainer` with `stretch` gives it exactly the window's visible rectangle, and what is then
read is the canvas, at the room's own pixels rather than the glass's.

**A desk cannot be the glass, so three lines are the desk's.** `InView` compares a control with the
root viewport's rectangle **deliberately** - that is the rule that found the phone's own view buttons
drawn off the glass - and the finger floor is converted through the same room. On a phone the root
window *is* the glass; on a desk it is the desk, so `offscreen`, `page-edge` and `small` report this
window's numbers rather than the device's (a floor of 144 where the device states 107, which is
1600/1185 of it). The run says so rather than dropping those lines, and the device's own block is the
arbiter for them: it reports none of the three.

**A page in a `Window` answers for itself.** The program says it in its own comment - a focused window
takes the keyboard into its own viewport, so the HUD never sees an Escape meant for one - so the tool
hands the event to the page the HUD itself would reach first (`Hud.page_in_front`), and to the
program's own viewport when the board is what is up. The event pushed is the one `draft_cancel` is
bound to rather than a key chosen by the tool, and the focus is given up first: a focused control
swallows the key before `_unhandled_input` sees it at all.

**Both ways up are stated, from the device's own numbers.** `--lying` states the phone on its side, and standing
is what silence means. Each shape's glass and usable rectangle come from the one table, read off the A16W's own
block rather than derived - lying is 2340 by 1080 with the same 100 px turned to the left - and the *room* is
deliberately not stated, because it is the program's own arithmetic: a lying window with the project's own
stretch yields the 1444 by 666 with `scale=1.62` that the device itself reports, so both attitudes are reproduced
from the display alone. A `--word` that is not one of the tool's verbs is refused by name, because a typo would
otherwise state the standing glass, answer every question with it, and say nothing about having done it.

## 14. The rules this follows, and the one it breaks

The numbers in this document are mostly not this project's invention, and writing them down here is so
that the next reader does not have to derive them again. Three come from Android and Material, and each
was **read off the source** rather than remembered - a rule a person reads in a document and the rule a
phone enforces have been known to differ, which is why the device is asked as well as the guide.

**A touch target is 48 by 48 dp.** Android's own accessibility guidance asks that "each interactive UI
element have a focusable area, or touch target size, of at least 48dpx48dp". A dp is 1/160 inch, so on
this phone's measured 450 dpi that is **7.6 mm, or 135 px** - and this program states `TOUCH_MM` **5.5**,
which is 97 px. That is a *judgement and not an oversight*, and `PhoneHud`'s own comment carries the
reason: at 48 dp a row is 135 px of a 349-pixel palette, twelve screens of scrolling for one list of
tools. 5.5 mm is the floor of a comfortable thumb, the palette scrolls, and the number can be raised in
that one place without touching a layout. The probe's `small` line enforces *this* number, so a control
below Material's floor is deliberately not called a fault.

**Text is 4.5:1 against its background, and 3:1 when it is large.** The same guidance asks for at least
4.5:1 below 18sp and 3:1 at or above it, and `scripts/contrast.gd` carries exactly those two numbers as
`LEAST` and `LEAST_LARGE`. The module *is* the rule rather than a restatement of it, and the probe asks
it page by page.

**Android 15 enforces edge-to-edge, and this is the one rule the program breaks.** From Android's
behaviour changes for apps targeting API 35: "Apps are edge-to-edge by default ... content draws behind
the system navigation bar unless insets are applied ... you must handle insets." This build reports
`targetSdk=36` - read off the phone, since the preset states no target at all - and the room it is given
is the whole screen, so it **is** edge-to-edge and it applies **the display cutout only**.
`DisplayServer.get_display_safe_area` is the cutout and nothing more, and the one other door,
`screen_get_usable_rect`, answers the whole screen on this Android. So the navigation bar's 42 px along
the foot is given ground by no page and no control, and doing so needs the phone's own `WindowInsets`
over JNI - an Android plugin, and a custom Gradle build to carry it, neither of which this project has.
It is written here rather than fixed because it is a **compliance gap and not a nicety**, and a gap
nobody can see is the kind that gets forgotten.

**And the window's own size class** is section 11's business: Android's five breakpoints, taken from the
window's shorter side, held by `tests/test_window_class.gd`.

Where the two were read from, for whoever needs to check them rather than remember them:
[Make apps more accessible](https://developer.android.com/guide/topics/ui/accessibility/apps) for the
touch target and the contrast ratios, and
[About Android 15 behaviour changes](https://developer.android.com/about/versions/15/behavior-changes-15)
for the edge-to-edge enforcement. `tests/test_phone_target.gd` holds the numbers quoted above to the
modules that own them, so a floor moved in one place cannot leave this section describing another.
