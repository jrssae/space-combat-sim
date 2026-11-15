extends Node
## Photographs the Babylon 5 station for the maintainer's look sheet (M7-T04): the game's main scene with the station at its
## place, the drum held still so the Cobra arms stay where the shots expect them, the key star turned to light the hull from over
## the camera's shoulder; one shot per view (`VIEWS`: 50 m off a Cobra bay and off the docking aperture, 200 m off a band, 1 km,
## then 10 and 100 km by `far view`). Each shot saves its frame and prints the `render` provider's numbers. Before the game loads,
## the station's two pieces are loaded alone to read what their maps take on the GPU (the card's VRAM before and after, and the
## textures' own bytes).
##
## Arguments after `--`: out=<dir> settle=<frames>. Run by scripts/station_sheet.sh on the real renderer.

const SYSFS_VRAM: String = "/sys/class/drm/card1/device/mem_info_vram_used"
## Each view: a name, then the camera and its aim in the station frame of docs/assets-station.md (z aft from the bow tip, x to
## starboard, y up) and the field of view; or a `far` distance in km for `far view station`.
## A view with `glint` [point, normal] in the station frame turns the key star so its mirror image off that surface meets the camera:
## the sun's specular highlight across the plating (metal, not plastic).
const VIEWS: Array[Dictionary] = [
	{"name": "bay_50m", "at": Vector3(300.0, -55.0, 1085.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0},
	{"name": "bay_glint_50m", "at": Vector3(292.0, 22.0, 1110.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0,
			"glint": [Vector3(243.0, 0.0, 1170.0), Vector3(1.0, 0.0, 0.0)]},
	{"name": "bay_head_60m", "at": Vector3(345.0, 45.0, 615.0), "aim": Vector3(300.0, 0.0, 720.0), "fov": 62.0},
	{"name": "bay_doors_50m", "at": Vector3(287.0, 16.0, 1118.0), "aim": Vector3(239.0, 0.0, 1160.0), "fov": 62.0},
	{"name": "aperture_50m", "at": Vector3(40.0, -45.0, 420.0), "aim": Vector3(0.0, 0.0, 495.0), "fov": 62.0},
	{"name": "aperture_150m", "at": Vector3(150.0, -110.0, 340.0), "aim": Vector3(0.0, 0.0, 500.0), "fov": 60.0},
	{"name": "band_200m", "at": Vector3(560.0, -300.0, 1860.0), "aim": Vector3(0.0, 0.0, 2150.0), "fov": 60.0},
	{"name": "band_glint_50m", "at": Vector3(395.0, 240.0, 1990.0), "aim": Vector3(361.0, 208.0, 2040.0), "fov": 62.0,
			"glint": [Vector3(361.0, 208.0, 2060.0), Vector3(0.866, 0.5, 0.0)]},
	{"name": "grazing_1km", "at": Vector3(760.0, 330.0, 600.0), "aim": Vector3(0.0, 120.0, 3200.0), "fov": 50.0,
			"glint": [Vector3(295.0, 295.0, 2600.0), Vector3(0.707, 0.707, 0.0)]},
	{"name": "1km", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0},
	{"name": "10km", "far": 10.0},
	{"name": "100km", "far": 100.0},
]
## M7-T25's `t25` (the main docking bay rebuilt to the STL with an 80 m mouth: bow on, three-quarter, the mouth close and inside, the
## doors open onto the black void, the lower hatch, the ring), `t25tunnel` (the mouth close up: its red-lit grey plating) and
## `t32` (the cargo bay in the same metal: outside its throat, inside looking in and out), `t25seq` (live: a civilian docks through the opening doors, then
## one undocks; each frame taken when the traffic reaches a stage). M7-T19's sets (`views=<set>`): `t19` the cost views (from a Cobra bay, the aperture, 1 km, 10 km, 1 000 km), `fly` a pass along
## the station's underside about 200 m off the hull from the bow to the reactor (section joins and levels of detail), `doors` the
## Cobra-bay doors close up (the near-only props); M7-T05's `t05` (the docking bay), `cargo`, `strip` and `markers` (every hardpoint
## as a ball); M7-T21's `t21` (the creased arm and the roofed cargo bay); M7-T22's `t22` (the spine and command section). The
## default set is T04's look sheet.
const VIEW_SETS: Dictionary = {
	# M7-T18's final A/B sheet: today (the lights off) and the lights as approved, from a Cobra bay, the bow's docking ring, the Cobra
	# arms, 1 km and 10 km, and the night side (the key star off).
	"t18final": [
		{"name": "bay_50m_today", "at": Vector3(300.0, -55.0, 1085.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0, "lights": "off"},
		{"name": "bay_50m_new", "at": Vector3(300.0, -55.0, 1085.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0, "lights": "on"},
		{"name": "bow_today", "at": Vector3(330.0, 70.0, 130.0), "aim": Vector3(0.0, 10.0, 500.0), "fov": 45.0, "lights": "off"},
		{"name": "bow_new", "at": Vector3(330.0, 70.0, 130.0), "aim": Vector3(0.0, 10.0, 500.0), "fov": 45.0, "lights": "on"},
		{"name": "arms_today", "at": Vector3(640.0, -120.0, 1180.0), "aim": Vector3(0.0, 0.0, 1060.0), "fov": 62.0, "lights": "off"},
		{"name": "arms_new", "at": Vector3(640.0, -120.0, 1180.0), "aim": Vector3(0.0, 0.0, 1060.0), "fov": 62.0, "lights": "on"},
		{"name": "1km_today", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0, "lights": "off"},
		{"name": "1km_new", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0, "lights": "on"},
		{"name": "10km_today", "far": 10.0, "lights": "off"},
		{"name": "10km_new", "far": 10.0, "lights": "on"},
		{"name": "night_arms_today", "at": Vector3(640.0, -120.0, 1180.0), "aim": Vector3(0.0, 0.0, 1060.0), "fov": 62.0, "lights": "off",
				"night": true},
		{"name": "night_arms_new", "at": Vector3(640.0, -120.0, 1180.0), "aim": Vector3(0.0, 0.0, 1060.0), "fov": 62.0, "lights": "on",
				"night": true},
		{"name": "night_1km_today", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0, "lights": "off",
				"night": true},
		{"name": "night_1km_new", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0, "lights": "on",
				"night": true},
	],
	"t19": [
		{"name": "bay_50m", "at": Vector3(300.0, -55.0, 1085.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0},
		{"name": "aperture_50m", "at": Vector3(40.0, -45.0, 420.0), "aim": Vector3(0.0, 0.0, 495.0), "fov": 62.0},
		{"name": "1km", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0},
		{"name": "10km", "far": 10.0},
		{"name": "1000km", "far": 1000.0},
	],
	"doors": [
		{"name": "bay_doors_50m", "at": Vector3(287.0, 16.0, 1118.0), "aim": Vector3(239.0, 0.0, 1160.0), "fov": 62.0},
		{"name": "bay_doors_20m", "at": Vector3(262.0, 4.0, 1140.0), "aim": Vector3(239.0, 0.0, 1160.0), "fov": 62.0},
		{"name": "bay_doors_300m", "at": Vector3(520.0, -120.0, 1000.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 50.0},
	],
	# M7-T05: the docking bay beside the maintainer's six references (bow on, the mouth from the side and close, the tunnel looking
	# in, the inner airlock, the lower hatch), lit from aft where the light would flood the tunnel; then every hardpoint as a marker.
	"t05": [
		{"name": "bay_bow_on", "at": Vector3(0.0, 10.0, -170.0), "aim": Vector3(0.0, 0.0, 470.0), "fov": 38.0},
		{"name": "bay_bow_on_lit_aft", "at": Vector3(0.0, 10.0, -170.0), "aim": Vector3(0.0, 0.0, 470.0), "fov": 38.0, "sun": "aft"},
		{"name": "bay_mouth_side", "at": Vector3(-115.0, 25.0, 370.0), "aim": Vector3(0.0, -5.0, 462.0), "fov": 55.0},
		{"name": "bay_mouth_close", "at": Vector3(18.0, 8.0, 392.0), "aim": Vector3(0.0, 0.0, 470.0), "fov": 62.0, "sun": "aft"},
		{"name": "bay_tunnel_in", "at": Vector3(0.0, 4.0, 470.0), "aim": Vector3(0.0, 0.0, 640.0), "fov": 72.0, "sun": "aft"},
		{"name": "bay_airlock", "at": Vector3(0.0, 0.0, 598.0), "aim": Vector3(0.0, 0.0, 640.0), "fov": 72.0, "sun": "aft"},
		{"name": "bay_lower_hatch", "at": Vector3(70.0, -190.0, 330.0), "aim": Vector3(0.0, -70.0, 468.0), "fov": 55.0},
	],
	# M7-T05 phase B: the cargo bay (zero-gravity) between the forks, and a strip at 50 m round the places Q2 asks to hold up close
	# (a door swung open to show the launch hall, the doors closed, the command section's windows and compartments).
	"cargo": [
		{"name": "cargo_bay_high", "at": Vector3(95.0, 470.0, 340.0), "aim": Vector3(0.0, 335.0, 455.0), "fov": 58.0},
		{"name": "cargo_bay_slot", "at": Vector3(18.0, 372.0, 250.0), "aim": Vector3(0.0, 345.0, 460.0), "fov": 60.0, "sun": "aft"},
		{"name": "cargo_bay_hold", "at": Vector3(260.0, 520.0, -900.0), "aim": Vector3(0.0, 340.0, 200.0), "fov": 50.0},
	],
	"strip": [
		{"name": "strip_door_open_45m", "at": Vector3(38.0, 272.0, 1050.0), "aim": Vector3(0.0, 232.0, 1102.0), "fov": 62.0,
				"open_door": 3},
		{"name": "strip_hall_through_door", "at": Vector3(4.0, 262.0, 1085.0), "aim": Vector3(0.0, 212.0, 1101.5), "fov": 72.0,
				"open_door": 3},
		{"name": "strip_doors_50m", "at": Vector3(-48.0, 282.0, 1030.0), "aim": Vector3(0.0, 238.0, 1105.0), "fov": 62.0},
		{"name": "strip_windows_50m", "at": Vector3(215.0, 432.0, 820.0), "aim": Vector3(165.0, 424.0, 870.0), "fov": 62.0},
		{"name": "strip_compartment_50m", "at": Vector3(45.0, 500.0, 735.0), "aim": Vector3(0.0, 452.0, 780.0), "fov": 62.0},
		{"name": "strip_main_docking_bay_50m", "at": Vector3(30.0, 15.0, 400.0), "aim": Vector3(0.0, 0.0, 465.0), "fov": 62.0},
		{"name": "strip_cargo_bay_50m", "at": Vector3(14.0, 350.0, 375.0), "aim": Vector3(0.0, 340.0, 460.0), "fov": 62.0},
	],
	# M7-T21: the Cobra arm's creased section and its door strip between the creases, a door open onto the halls, and the roofed
	# cargo bay from outside and looking in down its throat.
	"t21": [
		{"name": "arm_doors_50m", "at": Vector3(-48.0, 282.0, 1030.0), "aim": Vector3(0.0, 238.0, 1105.0), "fov": 62.0},
		{"name": "arm_side", "at": Vector3(95.0, 270.0, 1060.0), "aim": Vector3(10.0, 228.0, 1120.0), "fov": 55.0},
		{"name": "arm_door_open_45m", "at": Vector3(38.0, 272.0, 1050.0), "aim": Vector3(0.0, 232.0, 1102.0), "fov": 62.0,
				"open_door": 3},
		{"name": "arm_halls_through_door", "at": Vector3(4.0, 262.0, 1085.0), "aim": Vector3(0.0, 212.0, 1101.5), "fov": 72.0,
				"open_door": 3},
		{"name": "cargo_bay_outside", "at": Vector3(120.0, 450.0, 250.0), "aim": Vector3(0.0, 340.0, 440.0), "fov": 55.0},
		{"name": "cargo_bay_throat", "at": Vector3(10.0, 352.0, 300.0), "aim": Vector3(0.0, 340.0, 470.0), "fov": 58.0, "sun": "aft"},
		{"name": "cargo_bay_inside", "at": Vector3(0.0, 345.0, 425.0), "aim": Vector3(-20.0, 334.0, 485.0), "fov": 78.0, "sun": "aft"},
	],
	# M7-T22: the spine and the command section rebuilt to the STL's sections, at 50 m and 1 km, and the bow's prongs.
	"t22": [
		{"name": "command_beam_50m", "at": Vector3(165.0, 478.0, 1085.0), "aim": Vector3(127.0, 430.0, 1140.0), "fov": 62.0},
		{"name": "command_dome_50m", "at": Vector3(45.0, 492.0, 1050.0), "aim": Vector3(0.0, 440.0, 1115.0), "fov": 62.0},
		{"name": "command_body_50m", "at": Vector3(170.0, 395.0, 760.0), "aim": Vector3(105.0, 385.0, 820.0), "fov": 62.0},
		{"name": "command_under_200m", "at": Vector3(260.0, 250.0, 980.0), "aim": Vector3(60.0, 360.0, 1130.0), "fov": 55.0},
		{"name": "command_1km", "at": Vector3(850.0, 760.0, 350.0), "aim": Vector3(0.0, 400.0, 1100.0), "fov": 50.0},
		{"name": "bow_50m", "at": Vector3(150.0, 372.0, 140.0), "aim": Vector3(95.0, 335.0, 210.0), "fov": 62.0},
		{"name": "bow_300m", "at": Vector3(330.0, 470.0, -200.0), "aim": Vector3(80.0, 335.0, 280.0), "fov": 55.0},
		{"name": "spine_deck_50m", "at": Vector3(170.0, 500.0, 1450.0), "aim": Vector3(90.0, 470.0, 1520.0), "fov": 62.0},
		{"name": "spine_radiator_50m", "at": Vector3(190.0, 560.0, 1945.0), "aim": Vector3(110.0, 500.0, 2000.0), "fov": 62.0},
		{"name": "spine_green_zone_50m", "at": Vector3(215.0, 470.0, 2600.0), "aim": Vector3(125.0, 420.0, 2660.0), "fov": 62.0},
		{"name": "spine_cargo_300m", "at": Vector3(520.0, 700.0, 3200.0), "aim": Vector3(0.0, 470.0, 3450.0), "fov": 55.0},
		{"name": "spine_1km", "at": Vector3(900.0, 950.0, 1700.0), "aim": Vector3(0.0, 420.0, 2900.0), "fov": 50.0},
		{"name": "spine_aft_1km", "at": Vector3(900.0, 950.0, 4400.0), "aim": Vector3(0.0, 400.0, 5500.0), "fov": 50.0},
		{"name": "spine_hub_50m", "at": Vector3(190.0, 520.0, 5600.0), "aim": Vector3(100.0, 450.0, 5670.0), "fov": 62.0},
	],
	"t25": [
		{"name": "bay_bow_on", "at": Vector3(0.0, 12.0, -260.0), "aim": Vector3(0.0, 0.0, 480.0), "fov": 42.0},
		{"name": "bay_bow_on_lit_aft", "at": Vector3(0.0, 12.0, -260.0), "aim": Vector3(0.0, 0.0, 480.0), "fov": 42.0, "sun": "aft"},
		{"name": "bay_three_quarter", "at": Vector3(-170.0, 70.0, 260.0), "aim": Vector3(0.0, 0.0, 490.0), "fov": 55.0},
		{"name": "bay_mouth_close", "at": Vector3(28.0, 10.0, 405.0), "aim": Vector3(0.0, 0.0, 505.0), "fov": 62.0, "sun": "aft"},
		{"name": "bay_mouth_in", "at": Vector3(0.0, 4.0, 470.0), "aim": Vector3(0.0, 0.0, 552.0), "fov": 72.0, "sun": "aft"},
		{"name": "bay_doors_open", "at": Vector3(0.0, 4.0, 470.0), "aim": Vector3(0.0, 0.0, 552.0), "fov": 72.0, "sun": "aft",
				"airlock": "open"},
		{"name": "bay_lower_hatch", "at": Vector3(70.0, -190.0, 330.0), "aim": Vector3(0.0, -75.0, 485.0), "fov": 55.0},
		{"name": "bay_ring_side", "at": Vector3(190.0, -70.0, 400.0), "aim": Vector3(0.0, 0.0, 500.0), "fov": 55.0},
	],
	# The mouth from outside, then close up (the show's red-lit grey plating, the doors closed): approaching it, half way down it,
	# and at the inner doors.
	"t25tunnel": [
		{"name": "tunnel_mouth_outside", "at": Vector3(75.0, 32.0, 270.0), "aim": Vector3(0.0, 0.0, 500.0), "fov": 45.0},
		{"name": "tunnel_approach", "at": Vector3(14.0, 7.0, 395.0), "aim": Vector3(0.0, 0.0, 530.0), "fov": 62.0},
		{"name": "tunnel_mid", "at": Vector3(8.0, 4.0, 512.0), "aim": Vector3(-6.0, 0.0, 553.0), "fov": 74.0},
		{"name": "tunnel_doors", "at": Vector3(5.0, 3.0, 538.0), "aim": Vector3(0.0, 0.0, 553.0), "fov": 78.0},
		{"name": "tunnel_mid_looking_out", "at": Vector3(-6.0, 3.0, 535.0), "aim": Vector3(6.0, 0.0, 470.0), "fov": 74.0},
	],
	# M7-T32: the cargo bay in the docking bay's red-lit grey metal: outside its throat down the slot, inside looking in, inside
	# looking out.
	"t32": [
		{"name": "cargo_outside_mouth", "at": Vector3(22.0, 356.0, 300.0), "aim": Vector3(0.0, 340.0, 470.0), "fov": 55.0},
		{"name": "cargo_inside_looking_in", "at": Vector3(18.0, 346.0, 446.0), "aim": Vector3(-40.0, 333.0, 489.0), "fov": 80.0},
		{"name": "cargo_inside_looking_out", "at": Vector3(-30.0, 347.0, 486.0), "aim": Vector3(8.0, 338.0, 410.0), "fov": 80.0},
	],
	# M7-T24: the station's surfaces at the views a player sees them fullscreen: the launch cinematics' outside shots (up the arm
	# toward the sphere, out across the drum), the Cobra bay and its arm's head, the docking sphere and its bay, a band, the spine over
	# the sphere, 1 km (and grazing), 10 km. Shot once per texture set (`detail=low|high`).
	"t24": [
		{"name": "launch_up_the_arm", "at": Vector3(268.0, -24.0, 1190.0), "aim": Vector3(236.0, 40.0, 760.0), "fov": 60.0},
		{"name": "launch_across_drum", "at": Vector3(300.0, 40.0, 1150.0), "aim": Vector3(120.0, 250.0, 1600.0), "fov": 60.0},
		{"name": "bay_50m", "at": Vector3(300.0, -55.0, 1085.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0},
		{"name": "bay_head_60m", "at": Vector3(345.0, 45.0, 615.0), "aim": Vector3(300.0, 0.0, 720.0), "fov": 62.0},
		{"name": "sphere_80m", "at": Vector3(150.0, -300.0, 640.0), "aim": Vector3(60.0, -240.0, 760.0), "fov": 62.0},
		{"name": "aperture_150m", "at": Vector3(150.0, -110.0, 340.0), "aim": Vector3(0.0, 0.0, 500.0), "fov": 60.0},
		{"name": "band_200m", "at": Vector3(560.0, -300.0, 1860.0), "aim": Vector3(0.0, 0.0, 2150.0), "fov": 60.0},
		{"name": "spine_100m", "at": Vector3(150.0, 520.0, 900.0), "aim": Vector3(0.0, 420.0, 1100.0), "fov": 60.0},
		{"name": "grazing_1km", "at": Vector3(760.0, 330.0, 600.0), "aim": Vector3(0.0, 120.0, 3200.0), "fov": 50.0},
		{"name": "1km", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0},
		{"name": "10km", "far": 10.0},
	],
	# M7-T24's final A/B sheet: the launch cinematics' outside views, a Cobra bay, the main docking bay, the cargo bay, the main body's
	# windows from below, 1 km and 10 km.
	"t24final": [
		{"name": "launch_up_the_arm", "at": Vector3(300.0, -70.0, 1240.0), "aim": Vector3(250.0, 50.0, 820.0), "fov": 60.0},
		{"name": "launch_across_drum", "at": Vector3(300.0, 40.0, 1150.0), "aim": Vector3(120.0, 250.0, 1600.0), "fov": 60.0},
		{"name": "bay_50m", "at": Vector3(300.0, -55.0, 1085.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0},
		{"name": "docking_bay_150m", "at": Vector3(150.0, -110.0, 340.0), "aim": Vector3(0.0, 0.0, 500.0), "fov": 60.0},
		{"name": "cargo_outside_mouth", "at": Vector3(22.0, 356.0, 300.0), "aim": Vector3(0.0, 340.0, 470.0), "fov": 55.0},
		{"name": "drum_below_behind", "at": Vector3(-1100.0, -1250.0, 4600.0), "aim": Vector3(0.0, 0.0, 2300.0), "fov": 50.0,
				"up": Vector3(0.0, -1.0, 0.0)},
		{"name": "1km", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0},
		{"name": "10km", "far": 10.0},
	],
	# M7-T24's drum pattern: its full length from below and behind looking forward (the angle of the maintainer's "station from
	# below"), the same from about 2 km three-quarter, and the green zone close from below.
	"t24drum": [
		{"name": "drum_below_behind", "at": Vector3(-1100.0, -1250.0, 4600.0), "aim": Vector3(0.0, 0.0, 2300.0), "fov": 50.0,
				"up": Vector3(0.0, -1.0, 0.0)},
		{"name": "drum_2km", "at": Vector3(300.0, -1800.0, 1800.0), "aim": Vector3(0.0, 0.0, 3200.0), "fov": 65.0},
		{"name": "drum_below_close", "at": Vector3(-260.0, -700.0, 4350.0), "aim": Vector3(0.0, -200.0, 3400.0), "fov": 50.0},
		{"name": "green_150m", "at": Vector3(150.0, -470.0, 2950.0), "aim": Vector3(0.0, -334.0, 3150.0), "fov": 60.0},
		{"name": "green_1km", "at": Vector3(950.0, -520.0, 3300.0), "aim": Vector3(0.0, -60.0, 3600.0), "fov": 50.0},
		{"name": "green_3km", "at": Vector3(2700.0, -1300.0, 3000.0), "aim": Vector3(0.0, 0.0, 3500.0), "fov": 40.0},
		{"name": "vane_400m", "at": Vector3(950.0, -700.0, 4500.0), "aim": Vector3(535.0, -800.0, 4805.0), "fov": 55.0},
		{"name": "aft_1km", "at": Vector3(900.0, -500.0, 6700.0), "aim": Vector3(0.0, 0.0, 6200.0), "fov": 60.0},
	],
	# M7-T24's second checkpoint: the drum, sphere and spine from the side at the angle of the maintainer's "station side, purple and
	# grey", the sphere from its side and close, the spine from above.
	"t24side": [
		{"name": "side_main", "at": Vector3(2100.0, 650.0, 500.0), "aim": Vector3(0.0, 60.0, 2300.0), "fov": 45.0},
		{"name": "sphere_side", "at": Vector3(950.0, 260.0, 380.0), "aim": Vector3(0.0, 0.0, 760.0), "fov": 50.0},
		{"name": "spine_600m", "at": Vector3(650.0, 800.0, 700.0), "aim": Vector3(0.0, 420.0, 1350.0), "fov": 55.0},
		{"name": "grid_arm_head", "at": Vector3(430.0, 130.0, 610.0), "aim": Vector3(300.0, 0.0, 745.0), "fov": 50.0},
		{"name": "sphere_below_ahead", "at": Vector3(560.0, -640.0, 180.0), "aim": Vector3(0.0, -80.0, 660.0), "fov": 45.0},
		{"name": "collar_panel_close", "at": Vector3(-58.0, -282.0, 552.0), "aim": Vector3(-41.4, -208.0, 606.0), "fov": 50.0},
		{"name": "grid_bow_quarter", "at": Vector3(-420.0, 330.0, 250.0), "aim": Vector3(0.0, 60.0, 760.0), "fov": 60.0},
	],
	# Live (the drum turning, the traffic flying): a civilian docks and one undocks, seen from beside the lane outside the mouth.
	"t25seq": [
		{"name": "seq_1_approach", "live": true, "run": "traffic dock near", "depth_ge": -260.0},
		{"name": "seq_2_doors_open", "live": true, "depth_ge": -75.0},
		{"name": "seq_3_entering", "live": true, "depth_ge": 0.0},
		{"name": "seq_4_inside_closing", "live": true, "doors_closing_le": 0.5},
		{"name": "seq_5_docked_shut", "live": true, "docked": true},
		{"name": "seq_6_undock_opening", "live": true, "run": "traffic undock", "doors_opening_ge": 0.6},
		{"name": "seq_7_emerging", "live": true, "depth_le": -40.0},
		{"name": "seq_8_out_shut", "live": true, "doors_shut_after": true},
	],
	"markers": [
		{"name": "markers_side", "at": Vector3(-3600.0, 1300.0, 3200.0), "aim": Vector3(0.0, 0.0, 3500.0), "fov": 62.0, "markers": 40.0},
		{"name": "markers_aft", "at": Vector3(-1700.0, 1000.0, 6900.0), "aim": Vector3(0.0, 100.0, 5000.0), "fov": 62.0, "markers": 28.0},
		{"name": "markers_bow_above", "at": Vector3(950.0, 1250.0, 150.0), "aim": Vector3(0.0, 250.0, 1000.0), "fov": 55.0, "markers": 14.0},
		{"name": "markers_bow_below", "at": Vector3(1000.0, -1100.0, 300.0), "aim": Vector3(0.0, -50.0, 1050.0), "fov": 58.0,
				"markers": 14.0},
		{"name": "markers_bow_front", "at": Vector3(380.0, 230.0, -420.0), "aim": Vector3(0.0, 120.0, 520.0), "fov": 55.0, "markers": 9.0},
	],
	"fly": [
		{"name": "fly_01_bow", "at": Vector3(60.0, -540.0, 200.0), "aim": Vector3(0.0, 0.0, 900.0), "fov": 62.0},
		{"name": "fly_02_sphere", "at": Vector3(60.0, -560.0, 800.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 62.0},
		{"name": "fly_03_waist", "at": Vector3(60.0, -540.0, 1300.0), "aim": Vector3(0.0, 0.0, 2000.0), "fov": 62.0},
		{"name": "fly_04_ring", "at": Vector3(60.0, -620.0, 1750.0), "aim": Vector3(0.0, 0.0, 2500.0), "fov": 62.0},
		{"name": "fly_05_green", "at": Vector3(60.0, -540.0, 2600.0), "aim": Vector3(0.0, 0.0, 3300.0), "fov": 62.0},
		{"name": "fly_06_green", "at": Vector3(60.0, -545.0, 3500.0), "aim": Vector3(0.0, 0.0, 4200.0), "fov": 62.0},
		{"name": "fly_07_green", "at": Vector3(60.0, -540.0, 4300.0), "aim": Vector3(0.0, 0.0, 5000.0), "fov": 62.0},
		{"name": "fly_08_aft_band", "at": Vector3(60.0, -620.0, 5000.0), "aim": Vector3(0.0, 0.0, 5700.0), "fov": 62.0},
		{"name": "fly_09_hub", "at": Vector3(60.0, -550.0, 5650.0), "aim": Vector3(0.0, 0.0, 6350.0), "fov": 62.0},
		{"name": "fly_10_truss", "at": Vector3(60.0, -320.0, 6500.0), "aim": Vector3(0.0, 0.0, 7200.0), "fov": 62.0},
		{"name": "fly_11_shaft", "at": Vector3(60.0, -330.0, 7250.0), "aim": Vector3(0.0, 0.0, 7900.0), "fov": 62.0},
		{"name": "fly_12_reactor", "at": Vector3(60.0, -380.0, 7800.0), "aim": Vector3(0.0, 0.0, 8100.0), "fov": 62.0},
	],
}
const LIT_LIGHT: Vector3 = Vector3(0.3, -0.35, -1.0)  # camera frame: over the camera's left shoulder, as the look sheets
## The marker colours (M7-T05), by what a hardpoint is: the grid's kinds as T02's sheet drew them, then the rest.
const MARKER_COLOURS: Dictionary = {
	"light_pulse": Color("#FF8C1A"), "heavy_cannon": Color("#E02020"), "interceptor": Color("#20C8F0"),
	"bay_release": Color("#FFE040"), "bay_rail": Color("#A08020"), "approach": Color("#FF40FF"),
	"cargo_hold": Color("#00E0A0"), "cargo_path": Color("#B0FFE8"), "cargo_bay": Color("#E0281A"), "main_docking_bay": Color("#FF2A1A"),
	"beacon": Color("#FF60C0"), "running": Color("#FFFFFF"), "ring": Color("#C0C0FF"), "bay": Color("#FFA860"),
	"aperture": Color("#FF2A1A"), "tour": Color("#40FF60"),
}

var main: Main
var options: Dictionary = {"out": "user://", "settle": "90", "views": "", "detail": ""}
var _views: Array = VIEWS
var _index: int = -1
var _frame: int = 0
var _station: Station = null
var _origin_z: float = 4000.0
var _timed_us: int = 0  # when the timed frames of this shot began
var _markers: Array[Dictionary] = []  # each marker node and its size against the view's marker radius
const TIMED_FRAMES: int = 60  # the last frames before each capture, timed for a steady frame rate
## The live sequence (`t25seq`): where its camera stands, the time scale it runs at, and the most frames a stage may wait.
const LIVE_SHOT: Dictionary = {"at": Vector3(150.0, 55.0, 150.0), "aim": Vector3(0.0, 0.0, 470.0), "fov": 48.0}
const LIVE_SPEED: float = 4.0
const LIVE_LIMIT_FRAMES: int = 6000
var _live: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	_views = VIEW_SETS.get(String(options["views"]), VIEWS)
	if not String(options["detail"]).is_empty():  # the texture set to shoot (M7-T24), before any map loads
		Settings.set_value(&"texture_detail", StringName(options["detail"]))
	await _measure_maps()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	get_tree().root.add_child.call_deferred(main)
	get_tree().set_deferred(&"current_scene", main)
	main.ready.connect(_start.call_deferred, CONNECT_ONE_SHOT)


# What the station's maps take: the card's VRAM before and after the two pieces load (textures upload on load), and the bytes of
# every map as imported (compressed, with mipmaps).
func _measure_maps() -> void:
	var before: int = _vram_bytes()
	var manifest: Dictionary = MeshAssets.read_manifest(StationStandin.ASSET_ID)
	var dir: String = ShipSpec.ASSET_ROOT.path_join(StationStandin.ASSET_ID)
	var held: Array[Mesh] = []
	var bytes: int = 0
	var seen: Dictionary = {}
	# Loaded by path, so the sheet also runs on a build from before the station hull material (a before-and-after copy).
	var hull_path: String = "res://src/rendering/station_hull_material.gd"
	var hull: GDScript = load(hull_path) as GDScript if ResourceLoader.exists(hull_path) else null
	for piece: String in ["drum", "frame"]:
		var entry: Dictionary = (manifest.get("pieces", {}) as Dictionary).get(piece, {})
		held.append(MeshAssets.load_textured(dir, entry.get("mesh", {})))
		for surface: Dictionary in (entry.get("mesh", {}) as Dictionary).get("surfaces", []):
			var files: Array = [surface.get("albedo"), surface.get("normal"), surface.get("orm"), surface.get("emissive")]
			var detail: Dictionary = surface.get("world_detail", {})
			if hull != null and hull.wants(surface):  # the station hull's maps in the set in use (M7-T24)
				files = []
				for key: String in hull.ATLAS_KEYS + hull.TILE_KEYS:
					files.append(hull.map_file(surface, key))
				files.append(surface.get("emissive"))
			else:
				files += [detail.get("albedo"), detail.get("normal")]
			for file: Variant in files:
				if file == null or seen.has(file):
					continue
				seen[file] = true
				var texture: Texture2D = load(dir.path_join(String(file))) as Texture2D
				if texture != null:
					var image: Image = texture.get_image()
					bytes += image.get_data().size()
					print("[station_sheet] map %s: %dx%d format %d mipmaps %s, %.1f MB" % [file, image.get_width(), image.get_height(),
							image.get_format(), image.has_mipmaps(), image.get_data().size() / 1048576.0])
	await get_tree().process_frame
	await get_tree().process_frame
	var after: int = _vram_bytes()
	print("[station_sheet] maps %.1f MB as imported; card VRAM %.1f -> %.1f MB (+%.1f MB) loading both pieces" % [bytes / 1048576.0,
			before / 1048576.0, after / 1048576.0, (after - before) / 1048576.0])
	held.clear()


func _vram_bytes() -> int:
	var file: FileAccess = FileAccess.open(SYSFS_VRAM, FileAccess.READ)
	return int(file.get_line().strip_edges()) if file != null else -1  # sysfs gives no length, so a line, not the whole text


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "flare off", "fps off"]:
		_run(line)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	if main.overlay != null:
		main.overlay.visible = false
	main.ship.visible = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if main.far_props.station == null:
		_run("far station")
	_station = main.far_props.station
	if _station == null:
		print("[station_sheet] the station is not generated")
		get_tree().quit(1)
		return
	_origin_z = float((MeshAssets.read_manifest(StationStandin.ASSET_ID).get("centroid_offset", [0.0, 0.0, 4000.0]) as Array)[2])
	_station.set_spinning(false)  # the arms stay where the shots expect them
	_station.set_drum_angle(0.0)
	_station.set_process(false)
	if String(options["views"]) == "markers":
		_build_markers()
	if main.space_environment != null:
		main.space_environment.hold_key_star(true)
	get_tree().process_frame.connect(_on_frame)
	_next()


func _run(line: String) -> void:
	for result: ConsoleResult in DebugConsole.registry.execute(line):
		if not result.ok:
			print("[station_sheet] console error on '%s': %s" % [line, "; ".join(result.lines)])


# The station frame's point as an offset in the station node's own frame (the asset's origin sits `_origin_z` aft of the bow).
func _local(p: Vector3) -> Array[float]:
	return [p.x, p.y, p.z - _origin_z]


func _next() -> void:
	_index += 1
	_frame = 0
	if _index >= _views.size():
		get_tree().quit(0)
		return
	var view: Dictionary = _views[_index]
	for marker: Dictionary in _markers:
		(marker["node"] as Node3D).scale = Vector3.ONE * float(marker["size"]) * float(view.get("markers", 1.0))
	if view.has("lights"):  # M7-T18's A/B: the station's exterior lights off (today) or on
		_run("station_lights %s" % view["lights"])
	_open_door(int(view.get("open_door", 0)))
	_set_airlock(String(view.get("airlock", "")))
	if bool(view.get("live", false)):
		_go_live(view)
		return
	if view.has("far"):
		_run("far view station %s" % view["far"])
		return
	var key: Dictionary = {"position": {"actor": "station", "offset": _local(view["at"])},
			"look_at": {"actor": "station", "offset": _local(view["aim"])}, "fov": view["fov"]}
	if view.has("up"):  # a view rolled to match a reference's framing (M7-T24)
		var up: Vector3 = view["up"]
		key["up"] = {"actor": "station", "direction": [up.x, up.y, up.z]}
	var made: Dictionary = CinematicShot.from_dict(StringName(view["name"]), {"keys": [key.merged({"t": 0.0}), key.merged({"t": 3600.0})]})
	main.camera_rig.play_shot(made["shot"], _pose, _origin_to_local)


# The main docking bay's doors held open or shut for a static view (M7-T25), at once; "" leaves them to the traffic.
func _set_airlock(how: String) -> void:
	var lock: StationAirlock = _station.airlock if is_instance_valid(_station) else null
	if lock == null or _live:
		return
	lock.doors.mode = {"open": AirlockDoors.Mode.OPEN, "shut": AirlockDoors.Mode.SHUT}.get(how, AirlockDoors.Mode.AUTO)
	lock.doors.fraction = 1.0 if how == "open" else 0.0
	lock.leaves.set_offset(lock.open_m * lock.doors.fraction)


# The live sequence's stage: the station turning and the traffic flying at `LIVE_SPEED`, the camera beside the lane.
func _go_live(view: Dictionary) -> void:
	if not _live:
		_live = true
		_station.set_spinning(true)
		_station.set_process(true)
		Engine.physics_ticks_per_second = roundi(60.0 * LIVE_SPEED)
		Engine.time_scale = LIVE_SPEED
		Engine.max_physics_steps_per_frame = maxi(Engine.max_physics_steps_per_frame, roundi(LIVE_SPEED))
		var key: Dictionary = {"position": {"actor": "station", "offset": _local(LIVE_SHOT["at"])},
				"look_at": {"actor": "station", "offset": _local(LIVE_SHOT["aim"])}, "fov": LIVE_SHOT["fov"]}
		var made: Dictionary = CinematicShot.from_dict(&"t25seq", {"keys": [key.merged({"t": 0.0}), key.merged({"t": 36000.0})]})
		main.camera_rig.play_shot(made["shot"], _pose, _origin_to_local)
	if view.has("run"):
		_run(String(view["run"]))


# Whether a live stage has come: the traffic's last ship this deep past the doors' plane (or this far out), the doors this far
# open or shut, or the docked ship gone behind shut doors.
func _live_ready(view: Dictionary) -> bool:
	var lock: StationAirlock = _station.airlock
	var c: Combatant = main.traffic.last_ship() if main.traffic != null else null
	var depth: float = NAN
	if c != null and is_instance_valid(c.ship) and c.ship.is_inside_tree():
		depth = lock.depth_of(_station.to_local(c.ship.global_position))
	if view.has("depth_ge"):
		return not is_nan(depth) and depth >= float(view["depth_ge"])
	if view.has("depth_le"):
		return not is_nan(depth) and depth <= float(view["depth_le"])
	if view.has("doors_closing_le"):
		return not lock.doors.wants_open() and lock.doors.fraction <= float(view["doors_closing_le"])
	if view.has("doors_opening_ge"):
		return lock.doors.wants_open() and lock.doors.fraction >= float(view["doors_opening_ge"])
	if view.has("docked"):
		return main.traffic.docked_count > 0 and lock.doors.is_shut()
	if view.has("doors_shut_after"):
		return lock.doors.is_shut() and not is_nan(depth) and depth < -100.0
	return true


func _pose(actor: String) -> Variant:
	return _station.global_transform if actor == "station" and is_instance_valid(_station) else null


func _origin_to_local(offset: PackedFloat64Array) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], main.world.origin.system_id))


func _light_from_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var star: DirectionalLight3D = main.space_environment.key_star if main.space_environment != null else null
	if camera == null or star == null:
		return
	var direction: Vector3 = (camera.global_basis * LIT_LIGHT).normalized()
	var view: Dictionary = _views[_index]
	star.visible = not bool(view.get("night", false))  # the night side: no sun, the station's own lights only
	if view.get("sun", "") == "aft":
		# Sunlight from astern grazes the bay's walls and misses its frames, so the red they give off is what shows (no light here
		# casts shadows, so a sun ahead would light the tunnel's depths).
		direction = (_station.global_basis * Vector3(0.15, -0.2, -1.0)).normalized()
	if view.has("glint"):
		# Light that leaves the surface toward the camera: the mirror of the camera's direction about the surface's normal.
		var glint: Array = view["glint"]
		var at: Vector3 = glint[0]
		var point: Vector3 = _station.to_global(Vector3(at.x, at.y, at.z - _origin_z))
		var normal: Vector3 = (_station.global_basis * (glint[1] as Vector3)).normalized()
		var to_camera: Vector3 = (camera.global_position - point).normalized()
		direction = -(2.0 * normal.dot(to_camera) * normal - to_camera).normalized()
	var up: Vector3 = camera.global_basis.y if absf(direction.dot(camera.global_basis.y)) < 0.99 else camera.global_basis.x
	star.global_transform = Transform3D(Basis.looking_at(direction, up), star.global_position)


func _on_frame() -> void:
	if _index < 0 or _index >= _views.size():
		return
	_light_from_camera()
	if _live:
		_frame += 1
		if _live_ready(_views[_index]) or _frame >= LIVE_LIMIT_FRAMES:
			_capture(String(_views[_index]["name"]), Engine.get_frames_per_second())
			_next()
		return
	_station.drum_pivot.basis = Basis.IDENTITY  # held at rest every frame: the arms stay where the shots expect them
	_frame += 1
	if _frame == int(options["settle"]) - TIMED_FRAMES:
		_timed_us = Time.get_ticks_usec()
	if _frame < int(options["settle"]):
		return
	_capture(String(_views[_index]["name"]), TIMED_FRAMES / maxf((Time.get_ticks_usec() - _timed_us) / 1e6, 1e-6))
	_next()


# Saves the frame as the view `name` and prints the `render` provider's numbers.
func _capture(name: String, steady_fps: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	print("[station_sheet] %s: camera %s at %s, station at %s" % [name, camera.get_path() if camera != null else "none",
			camera.global_position if camera != null else Vector3.ZERO, _station.global_position])
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/station_%s.png" % [options["out"], name]
	image.save_png(path)
	var stats: Array[String] = []
	for key: String in ["renderer", "fps", "draw_calls", "triangles", "vram_mb", "gpu_ms"]:
		stats.append("%s=%s" % [key, str(DebugConsole.registry.read("render.%s" % key).get("value", "?"))])
	stats.append("light_slots=%s" % str(DebugConsole.registry.read("lights.active").get("value", "?")))
	print("[station_sheet] %s: %s steady_fps=%.0f card_vram_mb=%.0f station_meshes_shown=%d -> %s" % [name, " ".join(stats), steady_fps,
			_vram_bytes() / 1048576.0, _shown(_station), path])


# Swings door `number`'s two leaves open on every arm (0 closes them all), each about its hinge on its outer edge, as a launch would.
func _open_door(number: int) -> void:
	const OPEN_RAD: float = 1.75
	const HINGE_X: float = 9.6
	for node: MultiMeshInstance3D in _station.drum_piece.prop_nodes():
		var name: String = String(node.name)
		if not name.begins_with("PropsDoorLeaf") and not name.begins_with("Props_DoorLeaf"):
			continue
		if not node.has_meta("closed"):
			var closed: Array[Transform3D] = []
			for k: int in node.multimesh.instance_count:
				closed.append(node.multimesh.get_instance_transform(k))
			node.set_meta("closed", closed)
		var right: bool = name.ends_with("R")
		var open: bool = name.trim_suffix("R").trim_suffix("L").ends_with(str(number))
		var hinge := Vector3(HINGE_X if right else -HINGE_X, 0.0, 0.0)
		var turn := Basis(Vector3.BACK, (-OPEN_RAD if right else OPEN_RAD) if open else 0.0)
		var swing := Transform3D(turn, hinge - turn * hinge)
		var closed_list: Array = node.get_meta("closed")
		for k: int in node.multimesh.instance_count:
			node.multimesh.set_instance_transform(k, (closed_list[k] as Transform3D) * swing)


# Every hardpoint as a small unlit ball on the piece that carries it, coloured by kind (M7-T05's marker sheet).
func _build_markers() -> void:
	var hp: StationHardpoints = StationHardpoints.from_manifest(MeshAssets.read_manifest(StationStandin.ASSET_ID))
	if not hp.valid:
		print("[station_sheet] hardpoints: %s" % hp.error)
		return
	for m: Dictionary in hp.grid_mounts:
		_marker(m["body"], m["position"], m["kind"], 1.0)
	for b: Dictionary in hp.cobra_bays:
		_marker(b["body"], b["rail_start"], "bay_rail", 0.4)
	for p: Vector3 in hp.main_docking_bay["main_docking_bay_path"]:
		_marker(hp.main_docking_bay["body"], p, "approach", 0.8)
	for p: Vector3 in hp.cargo_bay["cargo_bay_path"]:
		_marker(hp.cargo_bay["body"], p, "cargo_path", 0.8)
	_marker(hp.cargo_bay["body"], hp.cargo_bay["cargo_bay_hold"], "cargo_hold", 1.4)
	for b: Dictionary in hp.cobra_bays:
		_marker(b["body"], b["release"], "bay_release", 0.4)
	for light: Dictionary in hp.lights:
		_marker(light["body"], light["position"], light["kind"], 0.5)
	for t: Dictionary in hp.tour_points:
		_marker(t["body"], t["position"], "tour", 1.0)
	print("[station_sheet] markers: %d mounts, %d bays, %d lights, %d tour points" % [hp.grid_mounts.size(), hp.cobra_bays.size(),
			hp.lights.size(), hp.tour_points.size()])


func _marker(body: String, at: Vector3, kind: String, size: float) -> void:
	var node := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = MARKER_COLOURS.get(kind, Color.WHITE)
	ball.material = material
	node.mesh = ball
	node.position = at
	(_station.drum_pivot if body == StationHardpoints.DRUM else _station as Node3D).add_child(node)
	_markers.append({"node": node, "size": size})


# The station's meshes drawn now (sections, props, the dot), for the cost readout.
func _shown(node: Node) -> int:
	var count: int = 1 if node is GeometryInstance3D and (node as GeometryInstance3D).is_visible_in_tree() else 0
	for child: Node in node.get_children():
		count += _shown(child)
	return count
