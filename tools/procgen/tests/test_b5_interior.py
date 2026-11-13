"""The Cobra-bay interior (M7-T09, D77): the hall matching the arm outside, the seven racks over the doors, each Starfury held
by its clamp without touching anything else, the lights within the rig's slots, the metal paints, the budgets, the output contract
on a small bake and determinism."""

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
from tools.procgen.parts import station as st
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
        cls.racks = interior.racks()
        cls.fighter = _fighter()

    def test_three_racks_under_each_of_the_arms_seven_doors(self) -> None:
        self.assertEqual(len(self.racks), st.COBRA_DOORS * len(cb.SLOT_X))
        arm = cb.to_arm()
        basis, origin = np.asarray(arm["basis"]), np.asarray(arm["origin"])
        door_z = st.door_centres()
        for rack in self.racks:
            p = basis @ np.asarray(rack["position"]) + origin
            np.testing.assert_allclose(rack["position_arm"], p, atol=1e-4)
            self.assertAlmostEqual(p[2], door_z[rack["door"] - 1], places=4, msg="each rack over its door, as the arm outside has them")
            self.assertLess(p[1], cb.DOOR_FLOOR_R, "inside the arm, toward the axis from the doors")
            self.assertEqual(rack["id"], f"door{rack['door']}_slot{rack['slot']}")
        self.assertEqual([r["number"] for r in self.racks], list(range(1, 22)), "Alpha 1 to 21")
        self.assertEqual(len({r["id"] for r in self.racks}), 21)

    def test_every_fighter_drops_through_its_door_to_its_release_point(self) -> None:
        lo, hi = self.fighter.bounds()
        z0, z1, _, _, outer_r = st.ARM_HATCH
        for rack in self.racks:
            x, _, z = rack["position"]
            rx, ry, rz = rack["release"]
            self.assertEqual((rx, rz), (x, z), "straight down, radially out")
            self.assertLess(ry, -cb.WELL_DEPTH, "below the door")
            self.assertGreater(rack["release_arm"][1], outer_r, "outside the arm's frame round the doors")
            self.assertLess(abs(x) + float(hi[0]), cb.LEAF_OUT, "the whole fighter between the leaves' outer edges")
        gap = cb.SLOT_X[1] - cb.SLOT_X[0] - 2.0 * float(hi[0])
        self.assertGreater(gap, 3.0, "neighbours clear of each other's pods")

    def test_the_hall_fits_inside_the_arm(self) -> None:
        z0, z1, half_w, inner_r, outer_r = st.ARM_HATCH
        self.assertLessEqual(cb.HALF_W + 1.0, half_w, "the side walls inside the arm's flanks")
        self.assertGreaterEqual(cb.DOOR_FLOOR_R - (cb.HEIGHT + 1.0), inner_r, "the ceiling below the arm's inner skin")
        self.assertLessEqual(2.0 * cb.END_Z + 3.0, z1 - z0, "the end walls inside the hatch section")
        self.assertAlmostEqual(cb.PITCH_M * st.COBRA_DOORS, st.DOOR_ROW[1] - st.DOOR_ROW[0])

    def test_one_bay_tiles_the_hall(self) -> None:
        lo, hi = Mesh.concatenate(self.bay.values()).bounds()
        self.assertAlmostEqual(float(lo[2]), -cb.HALF_PITCH, places=5)
        self.assertAlmostEqual(float(hi[2]), cb.HALF_PITCH, places=5)
        np.testing.assert_allclose(np.diff(cb.bay_centres()), cb.PITCH_M)

    def test_the_fighter_hangs_over_its_door_clear_of_the_floor(self) -> None:
        lo, hi = self.fighter.bounds()
        self.assertAlmostEqual(float(lo[1]), cb.FURY_LOW_Y, delta=0.05)
        self.assertGreater(cb.HANG_Y + float(lo[1]), 4.0, "its lowest pod well above the closed leaves")
        self.assertLess(float(hi[0]), cb.DOOR_X, "it drops through its door")
        self.assertLess(float(hi[2] - lo[2]), 2.0 * cb.DOOR_Z)

    def test_each_clamp_holds_its_fighter_and_nothing_else_touches_it(self) -> None:
        sampled = sample_mesh(self.fighter, 0.06, np.random.default_rng(1), smooth=False).positions
        parts = {name: sample_mesh(self.bay[name], 0.06, np.random.default_rng(2), smooth=False).positions
                 for name in CLAMP_PARTS + PAD_PARTS + ("bridge", "columns", "leaves", "work_lamps", "beacons", "lattice")}
        for x in cb.SLOT_X:
            fighter = sampled + [x, cb.HANG_Y, 0.0]
            f_lo, f_hi = fighter.min(axis=0) - 0.5, fighter.max(axis=0) + 0.5
            for name, pts in parts.items():
                near = pts[np.all((pts > f_lo) & (pts < f_hi), axis=1)]
                if len(near) == 0:
                    self.assertNotIn(name, PAD_PARTS, f"slot at x {x}: its pads")
                    continue
                gap = _min_distance(near, fighter)
                if name in PAD_PARTS:
                    self.assertLess(gap, 0.12, f"slot at x {x}: the pads rest on the fuselage's back and the upper pods")
                else:
                    self.assertGreater(gap, 0.04, f"slot at x {x}: {name} keeps clear (the pads sit between)")

    def test_the_camera_rail_runs_clear_of_the_racks_and_the_columns(self) -> None:
        _, hi = self.fighter.bounds()
        rail = cb.CAMERA_RAIL
        self.assertGreater(rail["x"] - (max(cb.SLOT_X) + float(hi[0])), 2.0, "beside the outer fighters")
        self.assertLess(rail["x"], cb.WORK_LAMP[0] - 2.0, "short of the columns and their lamps")

    def test_the_envelope_constants_match_the_starfury(self) -> None:
        v = sample_mesh(self.fighter, 0.04, np.random.default_rng(3), smooth=False).positions
        spine = v[(np.abs(v[:, 0]) < 0.55) & (v[:, 2] > cb.PAD_Z[0]) & (v[:, 2] < cb.PAD_Z[1])]
        self.assertAlmostEqual(float(spine[:, 1].max()), cb.FURY_TOP_Y, delta=0.05)
        px, top, pz = cb.FURY_POD
        pod = v[(np.abs(v[:, 0] - px) < 0.3) & (np.abs(v[:, 2] - pz) < 0.3) & (v[:, 1] > 0.0)]
        self.assertAlmostEqual(float(pod[:, 1].max()), top, delta=0.08)

    def test_lights_fit_the_rigs_slots(self) -> None:
        lights = interior.lights()
        self.assertEqual(len(lights), LIGHT_SLOTS, "one per bay: every emitter always has a slot, none ever swaps")
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
        self.assertEqual(len(m["pieces"]["bay"]["instances"]), 7)
        self.assertEqual(len(m["racks"]), 21)
        self.assertEqual(m["launch"]["slots_per_door"], 3)
        self.assertTrue({"id", "door", "slot", "release", "release_arm"} <= set(m["racks"][0]))
        self.assertEqual(m["fighter"], "starfury_aurora")
        self.assertEqual(len(m["lights"]), LIGHT_SLOTS)
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
        self.assertEqual(json.loads(text)["racks"][0]["position"][1], cb.HANG_Y)


if __name__ == "__main__":
    unittest.main()
