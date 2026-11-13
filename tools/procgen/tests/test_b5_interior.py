"""The Cobra-bay interior (M7-T09, M7-T20; D77): the hall fitted to the arm's launch hall (the station's ``hardpoints.cobra_arm``),
the six racked fighters over the doors and the second row of six where T05's hardpoints put them, each Starfury held by its clamp
without touching anything else, the lights within the rig's slots, the metal paints, the budgets, the output contract on a small
bake and determinism."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import b5_interior as interior
from tools.procgen.assets import starfury_aurora as fury
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.core.sampling import sample_mesh
from tools.procgen.parts import cobra_bay as cb
from tools.procgen.parts import station_hardpoints as sh
from tools.procgen.styles.cobra_bay import COBRA_BAY, SCHEME

SMALL = (1024, 512, 256, 64)  # bay, ends, signs and detail tile in px: the tests' bake (the bay's 1 500 charts need 1 024)
LIGHT_SLOTS = 7  # LightPicker.SLOT_COUNT: the rig's omni slots (the 8th light is the key light)
CLAMP_PARTS = ("drop_arm", "clamp_arms", "hoses")
PAD_PARTS = ("pads",)


def _fighter() -> Mesh:
    """The real Starfury's hull in its rendered frame, sampled coarsely (its outline does not depend on the spacing)."""
    placed, _ = fury.centre(fury.build_parts(fury.DEFAULT_SPEC, fury.STYLE, BuildContext(Path("unused"), seed=42), 0.2, 0.2))
    return Mesh.concatenate(p.part.mesh for p in placed)


def _min_distance(a: np.ndarray, b: np.ndarray) -> float:
    best = np.inf
    for k in range(0, len(a), 400):
        d = np.linalg.norm(a[k:k + 400, None, :] - b[None, :, :], axis=2)
        best = min(best, float(d.min()))
    return best


class HallShapeTests(unittest.TestCase):
    """The geometry, without baking a texture."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.bay = {p.name: p.mesh for p in interior.bay_parts()}
        cls.fighters = interior.fighters()
        cls.fighter = _fighter()
        alpha = [b for b in sh.cobra_bays(sh.Frames(np.zeros(3), np.zeros(3))) if b["wing"] == "alpha"]
        cls.bays = {b["door_number"]: b for b in alpha}  # the top arm's, in its own frame (the station frame, the arm unturned)

    def test_twelve_alpha_fighters_six_a_wave_one_per_door(self) -> None:
        self.assertEqual(len(self.fighters), 2 * cb.BAYS)
        self.assertEqual(cb.BAYS, 6)
        for wave in (1, 2):
            row = [f for f in self.fighters if f["wave"] == wave]
            self.assertEqual(sorted(f["door"] for f in row), list(range(1, 7)), f"wave {wave}: one per door")
        for f in self.fighters:
            self.assertEqual(f["wing"], "alpha", "the hangar is Alpha's, the top arm")
            self.assertEqual(f["id"], f"alpha_{f['door']}_{f['wave']}")
            self.assertEqual(f["bay"], f"cobra_bay_alpha_{f['door']}")
        self.assertEqual(sorted(f["number"] for f in self.fighters), list(range(1, 13)), "Alpha 1 to 12")

    def test_the_fighters_are_where_the_stations_hardpoints_put_them(self) -> None:
        arm = cb.to_arm()
        basis, origin = np.asarray(arm["basis"]), np.asarray(arm["origin"])
        for f in self.fighters:
            bay = self.bays[f["door"]]
            np.testing.assert_allclose(f["position_arm"], basis @ np.asarray(f["position"]) + origin, atol=1e-4)
            np.testing.assert_allclose(f["release_arm"], bay["release"], atol=1e-3, err_msg="released where T05's bay releases")
            if f["wave"] == 1:
                np.testing.assert_allclose(f["position_arm"], bay["rail_start"], atol=1e-3, err_msg="on the rack over its door")
            else:
                np.testing.assert_allclose(f["position_arm"], bay["staging"], atol=1e-3, err_msg="at T05's staging point")
                np.testing.assert_allclose(f["staging_path_arm"], bay["staging_path"], atol=1e-3, err_msg="T05's path onto the rack")

    def test_the_hall_is_the_arms_launch_halls(self) -> None:
        arm = cb.to_arm()
        basis, origin = np.asarray(arm["basis"]), np.asarray(arm["origin"])

        def mapped(half_w: float, y0: float, y1: float) -> np.ndarray:
            corners = np.array([[sx * half_w, y, sz * cb.END_Z] for sx in (-1, 1) for y in (y0, y1) for sz in (-1, 1)])
            return corners @ basis.T + origin

        upper, lower = cb.ARM["hall"], cb.ARM.get("lower_hall") or cb.ARM["hall"]
        up = mapped(cb.HALF_W, 0.0, cb.UP_H)
        np.testing.assert_allclose(sorted({round(v, 4) for v in up[:, 0]}), upper["x"])
        np.testing.assert_allclose(sorted({round(v, 4) for v in up[:, 2]}), upper["z"])
        np.testing.assert_allclose(sorted({round(v, 4) for v in up[:, 1]}), [upper["ceiling_r"], upper["floor_r"]])
        low = mapped(cb.LOW_W, cb.UP_H, cb.HEIGHT)
        np.testing.assert_allclose(sorted({round(v, 4) for v in low[:, 0]}), lower["x"])
        self.assertAlmostEqual(float(low[:, 1].min()), lower["ceiling_r"])
        door_z = [float(z) for _, z in cb.ARM["centres"]]
        np.testing.assert_allclose(np.asarray(cb.bay_centres()) + origin[2], door_z)
        self.assertAlmostEqual(origin[0] - cb.RACK_X, cb.ARM["strip_x"], msg="the racks over the door strip")

    def test_every_fighter_drops_through_its_door(self) -> None:
        lo, hi = self.fighter.bounds()
        for f in self.fighters:
            rx, ry, rz = f["release"]
            self.assertEqual((rx, rz), (cb.RACK_X, f["position"][2]), "straight down from the rack, radially out")
            self.assertLess(ry, -cb.WELL_DEPTH, "below the door")
        self.assertLess(float(hi[0]), cb.LEAF_OUT, "between the leaves' outer edges")
        self.assertLess(float(hi[2]), cb.LEAF_HALF_Z)
        self.assertGreater(cb.PITCH_M - float(hi[2] - lo[2]), 5.0, "neighbours along the hall clear")
        # The second row: inside the lower hall, clear of its floor (the ledge) and of the racked row it crosses over.
        self.assertLess(abs(cb.STAGE_X) + float(hi[0]), cb.LOW_W - 2.5, "clear of the lower hall's wall and its cabinets")
        if cb.TWO_LEVELS:
            self.assertGreater(cb.STAGE_Y + float(lo[1]), cb.UP_H + 0.5, "above the ledge")
            self.assertGreater(abs(cb.STAGE_X) - float(hi[0]), cb.HALF_W, "beside the upper hall, over the ledge")
        self.assertGreater(cb.STAGE_Y + float(lo[1]) - (cb.HANG_Y + float(hi[1])), 2.0, "it crosses over the racked row")

    def test_one_bay_tiles_the_row_and_the_ends_fill_the_hall(self) -> None:
        lo, hi = Mesh.concatenate(self.bay.values()).bounds()
        self.assertAlmostEqual(float(lo[2]), -cb.HALF_PITCH, places=5)
        self.assertAlmostEqual(float(hi[2]), cb.HALF_PITCH, places=5)
        np.testing.assert_allclose(np.diff(cb.bay_centres()), cb.PITCH_M)
        ends = Mesh.concatenate(p.mesh for p in interior.end_parts())
        self.assertGreaterEqual(float(ends.bounds()[1][2]), cb.END_Z)
        self.assertLessEqual(float(ends.vertices[:, 2][ends.vertices[:, 2] > 0].min()), cb.ROW_HALF + 1e-6)

    def test_the_fighter_hangs_over_its_door_clear_of_the_floor(self) -> None:
        lo, hi = self.fighter.bounds()
        self.assertAlmostEqual(float(lo[1]), cb.FURY_LOW_Y, delta=0.05)
        self.assertGreater(cb.HANG_Y + float(lo[1]), 4.0, "its lowest pod well above the closed leaves")

    def test_each_clamp_holds_its_fighter_and_nothing_else_touches_it(self) -> None:
        sampled = sample_mesh(self.fighter, 0.06, np.random.default_rng(1), smooth=False).positions
        parts = {name: sample_mesh(self.bay[name], 0.06, np.random.default_rng(2), smooth=False).positions
                 for name in CLAMP_PARTS + PAD_PARTS + ("bridge", "rails", "leaves", "work_lamps", "beacons", "lattice", "cabinets",
                                                       "catwalk", "railing", "pipes", "canisters", "ledge", "wall")
                 if name in self.bay}
        for x, y in ((cb.RACK_X, cb.HANG_Y), (cb.STAGE_X, cb.STAGE_Y)):
            fighter = sampled + [x, y, 0.0]
            f_lo, f_hi = fighter.min(axis=0) - 0.5, fighter.max(axis=0) + 0.5
            for name, pts in parts.items():
                near = pts[np.all((pts > f_lo) & (pts < f_hi), axis=1)]
                if len(near) == 0:
                    self.assertNotIn(name, PAD_PARTS, f"fighter at x {x}: its pads")
                    continue
                gap = _min_distance(near, fighter)
                if name in PAD_PARTS:
                    self.assertLess(gap, 0.12, f"fighter at x {x}: the pads rest on the fuselage's back and the upper pods")
                else:
                    self.assertGreater(gap, 0.04, f"fighter at x {x}: {name} keeps clear (the pads sit between)")

    def test_the_second_row_crosses_onto_the_racks_clear_of_the_hall(self) -> None:
        # The staged fighter's sweep along its path, against everything that does not travel with it (its own trolley and clamp do;
        # the rack's arms and pads are where the sweep ends, holding it).
        fighter = sample_mesh(self.fighter, 0.25, np.random.default_rng(4), smooth=False).positions
        fixed = ("leaves", "ledge", "railing", "lattice", "work_lamps", "rails", "bridge", "pipes", "catwalk", "cabinets", "wall",
                 "canisters", "pilasters", "portal", "beams", "floods", "wall_lamps")
        pts = np.concatenate([sample_mesh(self.bay[n], 0.25, np.random.default_rng(5), smooth=False).positions for n in fixed if n in self.bay])
        rack_arms = sample_mesh(self.bay["drop_arm"], 0.25, np.random.default_rng(6), smooth=False).positions
        pts = np.concatenate([pts, rack_arms[np.abs(rack_arms[:, 0] - cb.STAGE_X) > 2.5]])
        path = [np.asarray(p, dtype=float) for p in self.fighters[6]["staging_path"]]
        path = [p - [0.0, 0.0, p[2]] for p in path]  # the bay's own frame: its door at z 0
        for a, b in zip(path[:-1], path[1:], strict=True):
            steps = max(2, int(np.linalg.norm(b - a)))
            for t in np.linspace(0.0, 1.0, steps + 1):
                if (b is path[-1]) and t > 0.9:
                    continue  # settling onto the rack's pads
                at = a + t * (b - a)
                swept = fighter + at
                lo, hi = swept.min(axis=0) - 0.5, swept.max(axis=0) + 0.5
                near = pts[np.all((pts > lo) & (pts < hi), axis=1)]
                if len(near):
                    self.assertGreater(_min_distance(near, swept), 0.2, f"the second row's crossing at {at.round(1)}")

    def test_the_camera_rail_runs_beside_the_racks_clear_of_them_and_the_walls(self) -> None:
        _, hi = self.fighter.bounds()
        x = cb.CAMERA_RAIL["x"]
        self.assertGreater(abs(x - cb.RACK_X) - float(hi[0]), 2.0, "clear of the racked fighters")
        self.assertLess(abs(x), cb.HALF_W - 3.5, "clear of the upper hall's walls, their cabinets and catwalks")
        self.assertLess((x - cb.RACK_X) * (cb.STAGE_X - cb.RACK_X), 0.0, "on the far side from the second row")
        self.assertGreater(cb.CAMERA_RAIL["z_from"], -cb.END_Z)
        self.assertLess(cb.CAMERA_RAIL["z_to"], cb.END_Z)
        for name, view in cb.camera_views().items():
            at = np.asarray(view["at"])
            self.assertLess(abs(at[0]), cb.LOW_W, name)
            self.assertLess(abs(at[2]), cb.END_Z, name)
            self.assertTrue(0.0 < at[1] < cb.HEIGHT, name)
            if at[1] < cb.UP_H:
                self.assertLess(abs(at[0]), cb.HALF_W, f"{name}: in the upper hall")

    def test_the_envelope_constants_match_the_starfury(self) -> None:
        v = sample_mesh(self.fighter, 0.04, np.random.default_rng(3), smooth=False).positions
        spine = v[(np.abs(v[:, 0]) < 0.55) & (v[:, 2] > cb.PAD_Z[0]) & (v[:, 2] < cb.PAD_Z[1])]
        self.assertAlmostEqual(float(spine[:, 1].max()), cb.FURY_TOP_Y, delta=0.05)
        px, top, pz = cb.FURY_POD
        pod = v[(np.abs(v[:, 0] - px) < 0.3) & (np.abs(v[:, 2] - pz) < 0.3) & (v[:, 1] > 0.0)]
        self.assertAlmostEqual(float(pod[:, 1].max()), top, delta=0.08)
        mid = top - cb.FURY_POD_R
        side = v[(np.abs(v[:, 1] - mid) < 0.3) & (np.abs(v[:, 2] - pz) < 0.3) & (v[:, 0] > 0.0)]
        self.assertAlmostEqual(float(side[:, 0].max()), px + cb.FURY_POD_R, delta=0.08, msg="the pod's outboard side")

    def test_lights_fit_the_rigs_slots(self) -> None:
        lights = interior.lights()
        self.assertEqual(len(lights), cb.BAYS, "one per bay")
        self.assertLessEqual(len(lights), LIGHT_SLOTS, "every emitter always has a slot, none ever swaps")
        for light in lights:
            x, y, _ = light["position"]
            self.assertLess(abs(x), cb.HALF_W)
            self.assertLess(0.0, y)
            self.assertLess(y, cb.HEIGHT)

    def test_paints_are_metal_not_plastic(self) -> None:
        for role, (_, _, metallic, roughness) in SCHEME.items():
            if role != "rubber":
                self.assertGreaterEqual(metallic, 0.4, role)
                self.assertLessEqual(roughness, 0.7, role)
        self.assertIn("metal_finish", COBRA_BAY.extra)
        self.assertGreater(SCHEME["machinery"][2], SCHEME["wall"][2], "bare steel more metallic than paint")

    def test_triangle_budgets(self) -> None:
        for name, parts in (("bay", interior.bay_parts()), ("ends", interior.end_parts()), ("signs", interior.sign_parts())):
            faces = sum(p.mesh.face_count for p in parts)
            self.assertLessEqual(faces, interior.MAX_TRIANGLES[name], name)

    def test_no_faces_hide_in_the_walls(self) -> None:
        mesh = Mesh.concatenate(self.bay.values())
        n, c = mesh.face_normals(), mesh.face_centroids()
        backs = (n[:, 1] > 0.9) & (c[:, 1] > cb.HEIGHT - 1e-3)
        self.assertFalse(backs.any(), "no texels on the ceiling's back")


class HallBuildTests(unittest.TestCase):
    """A small bake: the files and the manifest the scene reads, and the same bytes twice."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.out_a = interior.build_at(BuildContext(root / "a", seed=42), *SMALL)
        cls.out_b = interior.build_at(BuildContext(root / "b", seed=42), *SMALL)
        cls.manifest = manifest_io.read_manifest(root / "a")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_the_manifest_carries_what_the_backdrop_reads(self) -> None:
        m = self.manifest
        self.assertEqual(m["asset_id"], "b5_interior")
        self.assertEqual(set(m["pieces"]), {"bay", "ends", "signs"})
        self.assertEqual(len(m["pieces"]["bay"]["instances"]), 6)
        self.assertEqual(len(m["fighters"]), 12)
        self.assertEqual((m["launch"]["wing"], m["launch"]["waves"], m["launch"]["wave_gap_s"]), ("alpha", 2, 10.0))
        self.assertTrue({"id", "wing", "door", "wave", "release", "release_arm"} <= set(m["fighters"][0]))
        self.assertEqual(m["fighter"], "starfury_aurora")
        self.assertEqual(len(m["lights"]), 6)
        self.assertIn("rail", m["camera"])
        self.assertIn("basis", m["to_arm"])
        for name in ("bay", "ends"):
            for surface in m["pieces"][name]["mesh"]["surfaces"]:
                self.assertEqual(surface["world_detail"]["tile_m"], interior.DETAIL_TILE_M)
        for name, entry in m["pieces"].items():
            mesh = entry["mesh"]
            self.assertTrue((self.out_a.out_dir / mesh["file"]).is_file(), name)
            for surface in mesh["surfaces"]:
                for key in ("albedo", "normal", "orm", "emissive"):
                    self.assertTrue((self.out_a.out_dir / surface[key]).is_file())
        self.assertGreater(m["pieces"]["bay"]["mesh"]["surfaces"][0]["emissive_strength"], 0.0, "the hall glows")
        self.assertTrue({"deck", "machinery", "work_light"} <= set(m["materials"]))

    def test_the_same_seed_writes_the_same_bytes(self) -> None:
        names_a = sorted(p.name for p in self.out_a.files)
        names_b = sorted(p.name for p in self.out_b.files)
        self.assertEqual(names_a, names_b)
        for name in names_a:
            self.assertEqual((self.out_a.out_dir / name).read_bytes(), (self.out_b.out_dir / name).read_bytes(), name)

    def test_the_manifest_is_plain_json(self) -> None:
        text = (self.out_a.out_dir / "manifest.json").read_text(encoding="utf-8")
        self.assertEqual(json.loads(text)["fighters"][0]["position"][1], cb.HANG_Y)


if __name__ == "__main__":
    unittest.main()
