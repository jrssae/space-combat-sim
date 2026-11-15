"""``cargo_pod_craft`` (M7-T33): the output contract, the 6 m size, the frame (jaws forward, -Z), both texture sets, the metal finish,
outward faces, the hardpoints T34 carries cargo by, the collision and determinism. Built twice on the default seed."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import cargo_pod_craft as pod
from tools.procgen.core import collision as col
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.core.glb import GlbJoint, GlbPrimitive, glb_bytes, read_glb
from tools.procgen.core.image import read_png
from tools.procgen.core.obj import read_obj
from tools.procgen.styles import REQUIRED_ROLES
from tools.procgen.styles.cargo_pod_craft import CARGO_POD_CRAFT

TRIANGLE_BUDGET = 4000  # a small craft seen in numbers round the cargo bay


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signed_volume(mesh: Mesh) -> float:
    a, b, c = mesh.corners()
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)


class CargoPodCraftTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        cls.out_a = pod.build(BuildContext(cls.dir_a, seed=42))
        cls.out_b = pod.build(BuildContext(cls.dir_b, seed=42))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / pod.HARDPOINTS_NAME).read_text(encoding="utf-8"))
        cls.obj = read_obj(cls.dir_a / pod.OBJ_NAME)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    # --- registry, files, manifest ----------------------------------------------------------
    def test_registered_under_its_id(self) -> None:
        self.assertIs(ASSETS["cargo_pod_craft"], pod.build)

    def test_all_files_are_written_and_listed(self) -> None:
        names = sorted(p.name for p in self.dir_a.iterdir())
        maps = [f"cargo_pod_craft_{k}{s}.png{ext}" for k in ("albedo", "normal", "orm") for s in ("", "_low") for ext in ("", ".import")]
        maps += [f"cargo_pod_craft_emissive.png{ext}" for ext in ("", ".import")]
        self.assertEqual(names, sorted(["hardpoints.json", "manifest.json", "cargo_pod_craft.glb", "cargo_pod_craft.mtl",
                                        "cargo_pod_craft.obj", *maps]))
        self.assertEqual(sorted(p.name for p in self.out_a.files), names)
        self.assertEqual(self.out_a.warnings, ())
        self.assertEqual(self.manifest["files"], {"obj": "cargo_pod_craft.obj", "mesh": "cargo_pod_craft.glb", "hardpoints": "hardpoints.json"})

    def test_manifest_names_the_textured_mesh_and_both_texture_sets(self) -> None:
        self.assertEqual((self.manifest["asset_id"], self.manifest["frame"], self.manifest["seed"]), ("cargo_pod_craft", "godot", 42))
        mesh = self.manifest["mesh"]
        self.assertEqual(mesh["file"], "cargo_pod_craft.glb")
        self.assertEqual(self.out_a.triangle_count, mesh["triangles"])
        self.assertEqual(mesh["lods"], [], "Godot's importer builds the levels of detail")
        for surface in mesh["surfaces"]:
            low = surface["detail"]["low"]
            self.assertEqual(low, {k: f"cargo_pod_craft_{k}_low.png" for k in ("albedo", "normal", "orm")})

    def test_the_low_set_is_the_same_size_with_less_detail(self) -> None:
        for key in ("albedo", "normal"):
            high = read_png(self.dir_a / f"cargo_pod_craft_{key}.png")[..., :3].astype(float)
            low = read_png(self.dir_a / f"cargo_pod_craft_{key}_low.png")[..., :3].astype(float)
            self.assertEqual(high.shape, low.shape, key)
            self.assertGreater(float(np.abs(high - low).mean()), 0.05, f"{key}: the low set drops the fine seams and plating")
            # Fine detail is high-frequency: the full set varies more from texel to texel.
            self.assertGreater(float(np.abs(np.diff(high, axis=1)).mean()), float(np.abs(np.diff(low, axis=1)).mean()), key)

    # --- size, frame and budget -------------------------------------------------------------
    def test_six_metres_long_at_the_references_proportions(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], 6.0, delta=0.02)
        self.assertAlmostEqual(dims["width"], 3.28, delta=0.33)
        self.assertAlmostEqual(dims["height"], 2.07, delta=0.21)
        self.assertLessEqual(self.out_a.triangle_count, TRIANGLE_BUDGET)
        self.assertGreater(self.out_a.triangle_count, 800)

    def test_the_manifest_box_bounds_the_obj_and_is_centred(self) -> None:
        lo, hi = self.obj.vertices.min(axis=0), self.obj.vertices.max(axis=0)
        np.testing.assert_allclose(lo, self.manifest["aabb_min"], atol=1e-4)
        np.testing.assert_allclose(hi, self.manifest["aabb_max"], atol=1e-4)
        np.testing.assert_allclose(lo + hi, 0.0, atol=1e-6)

    def test_the_jaws_lead_and_the_cab_trails(self) -> None:
        v = self.obj.vertices
        front = v[v[:, 2] < v[:, 2].min() + 0.3]
        self.assertGreater(float(np.abs(front[:, 0]).min()), 1.0, "only the hands reach the front, out at the arms")
        rear = v[v[:, 2] > v[:, 2].max() - 0.3]
        self.assertLess(float(np.abs(rear[:, 0]).max()), 1.2, "the stern is the cab's")

    def test_every_closed_piece_faces_outward(self) -> None:
        pieces = {**pod.cab_meshes(CARGO_POD_CRAFT), **pod.arm_meshes(CARGO_POD_CRAFT)}
        for name in ("engine", "arm_root_r", "arm_r", "reach_r", "wrist_r", "jaw_up_r", "jaw_lo_r"):
            self.assertGreater(signed_volume(pieces[name]), 0.0, name)
        fore = pod.faceted_loft([pod.hex_ring(s) for s in pod.FORE_SECTIONS], [CARGO_POD_CRAFT.material("hull")] * 6)
        self.assertGreater(signed_volume(fore), 0.0)
        for mesh in pod.stern_meshes(CARGO_POD_CRAFT):  # open at the cabin: each face still looks away from its piece's middle
            n, c = mesh.face_normals(), mesh.face_centroids()
            self.assertTrue(np.all(np.einsum("ij,ij->i", n, c - c.mean(axis=0)) > 0.0))

    def test_left_and_right_mirror(self) -> None:
        v = self.obj.vertices
        np.testing.assert_allclose(np.sort(v[:, 0]), np.sort(-v[:, 0]), atol=1e-6)

    # --- the finish ------------------------------------------------------------------------
    def test_the_style_has_every_role_and_is_metal(self) -> None:
        for role in REQUIRED_ROLES:
            self.assertIn(role, CARGO_POD_CRAFT.materials)
        for role in ("hull", "hull_panel", "hull_dark", "clamp"):
            self.assertGreaterEqual(CARGO_POD_CRAFT.material(role).metallic, 0.5, role)
        blue = CARGO_POD_CRAFT.material("hull").albedo
        self.assertGreater(blue[2], 2.0 * blue[0], "the cab is Earth Alliance blue")

    def test_the_orm_map_carries_the_metal(self) -> None:
        orm = read_png(self.dir_a / "cargo_pod_craft_orm.png")[..., :3].astype(float) / 255.0
        metal = orm[..., 2]
        self.assertGreater(float(np.percentile(metal, 75)), 0.4)

    # --- hardpoints and collision ------------------------------------------------------------
    def test_the_hands_grip_ahead_of_the_cab_side_by_side(self) -> None:
        grips = {g["name"]: np.array(g["position"]) for g in self.hp["grips"]}
        self.assertEqual(set(grips), {"grip_l", "grip_r"})
        np.testing.assert_allclose(grips["grip_l"], grips["grip_r"] * np.array([-1.0, 1.0, 1.0]), atol=1e-6)
        self.assertAlmostEqual(float(grips["grip_r"][0] - grips["grip_l"][0]), self.hp["cargo_hold"]["span_m"], places=3)
        hold = np.array(self.hp["cargo_hold"]["position"])
        self.assertAlmostEqual(float(hold[2]), float(self.manifest["aabb_min"][2]), places=3, msg="a held block starts at the jaws' tips")
        self.assertLess(float(grips["grip_r"][2]), float(self.obj.vertices[np.abs(self.obj.vertices[:, 0]) < 0.5][:, 2].min()))
        self.assertEqual(self.hp["cargo_hold"]["forward"], [0.0, 0.0, -1.0])

    def test_thrusters_point_out_and_pair_up(self) -> None:
        main = self.hp["main_thruster"]
        self.assertEqual(main["exhaust"], [0.0, 0.0, 1.0])
        self.assertGreater(main["position"][2], 2.5)
        names = {r["name"] for r in self.hp["rcs"]}
        for r in self.hp["rcs"]:
            if r["name"].startswith("r_"):
                self.assertIn("l_" + r["name"][2:], names)
            self.assertAlmostEqual(float(np.linalg.norm(r["exhaust"])), 1.0, places=5)
            self.assertTrue(r["tags"] or r["exhaust"][2] != 0.0, r["name"])
        self.assertEqual(len(self.hp["rcs"]), 10)

    def test_nav_lights_port_red_side_left(self) -> None:
        lights = self.hp["nav_lights"]
        self.assertLess(lights["port"][0], 0.0)
        self.assertGreater(lights["starboard"][0], 0.0)
        self.assertGreater(lights["top"][1], 0.9)

    def test_collision_covers_the_mesh_within_the_budget(self) -> None:
        section = self.manifest["collision"]
        self.assertEqual([p["name"] for p in section["pieces"]], ["craft"])
        shapes = col.shapes_from_entry(section["pieces"][0])
        self.assertLessEqual(len(shapes), col.MAX_SHAPES_PER_PIECE)
        triangles = self.obj.vertices[self.obj.faces]
        fit = col.coverage(triangles, shapes, 0.05)
        self.assertLess(fit.max_gap_m, 0.1, f"a render surface outside every shape at {fit.gap_at}")
        self.assertLess(fit.max_excess_m, 0.3, fit.excess_shape)
        kinds = {c["type"] for c in self.hp["collision"]}
        self.assertLessEqual(kinds, {"box", "capsule"}, "the hit volumes are boxes and capsules")

    # --- the moving arms -------------------------------------------------------------------------
    def test_the_glb_is_skinned_with_one_surface(self) -> None:
        glb = read_glb(self.dir_a / "cargo_pod_craft.glb")
        names = [n["name"] for n in glb.doc["nodes"]]
        self.assertEqual(names[1:], ["root", "reach_r", "wrist_r", "jaw_up_r", "jaw_lo_r", "reach_l", "wrist_l", "jaw_up_l", "jaw_lo_l"])
        self.assertEqual(glb.doc["nodes"][0]["skin"], 0)
        self.assertEqual(len(glb.doc["meshes"][0]["primitives"]), 1, "the arms add no draw call")
        joints = glb.primitives[0].joints
        self.assertEqual(set(np.unique(joints)), set(range(9)))

    def test_each_moving_part_rides_its_joint(self) -> None:
        glb = read_glb(self.dir_a / "cargo_pod_craft.glb")
        prim = glb.primitives[0]
        bones = {b["name"]: np.array(b["position"]) for b in self.manifest["rig"]["bones"]}
        for side in ("r", "l"):
            k = [b["name"] for b in self.manifest["rig"]["bones"]].index(f"jaw_up_{side}")
            jaw = prim.positions[prim.joints == k]
            self.assertLess(float(np.abs(jaw[:, 0] - bones[f"jaw_up_{side}"][0]).max()), 0.2, "the upper jaw's vertices sit round its joint")
            self.assertGreater(float(jaw[:, 1].min()), bones[f"wrist_{side}"][1] - 0.1, "and above the gap")
        fixed_arm = prim.positions[(prim.joints == 0) & (np.abs(prim.positions[:, 0]) > 1.05)]
        self.assertGreater(float(fixed_arm[:, 2].min()), float(bones["reach_r"][2]) - 0.05, "nothing of the arms ahead of the outer barrels is fixed")

    def test_the_rig_names_its_joints_ranges_and_rest(self) -> None:
        rig = self.manifest["rig"]
        self.assertEqual(rig["rest"], {"extend": 0.0, "wrist_deg": 0.0, "jaw_open": 1.0})
        self.assertGreater(rig["extend_m"], 0.5)
        names = [b["name"] for b in rig["bones"]]
        for b in rig["bones"]:
            self.assertLess(b["parent"], names.index(b["name"]))
        for g in self.hp["grips"]:
            self.assertIn(g["bone"], names)

    def test_the_inner_barrels_hide_inside_the_outer_ones_at_rest(self) -> None:
        arm = pod.arm_meshes(CARGO_POD_CRAFT)
        reach, outer = arm["reach_r"].bounds(), arm["arm_r"].bounds()
        self.assertGreater(float(reach[1][2]), pod.OUTER_BARREL[0] + pod.EXTEND_M - 0.01, "long enough to reach out a whole travel")
        self.assertLess(float(reach[1][2]), float(outer[1][2]), "and still inside the outer barrels at rest")

    def test_glb_skin_round_trip(self) -> None:
        prim = GlbPrimitive(np.eye(3), np.eye(3), np.zeros((3, 2)), [0, 1, 2], "m", joints=[0, 1, 1])
        data = glb_bytes([prim], "m", [GlbJoint("a", -1, (0.0, 0.0, 0.0)), GlbJoint("b", 0, (1.0, 2.0, 3.0))])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "m.glb"
            path.write_bytes(data)
            glb = read_glb(path)
        self.assertEqual(list(glb.primitives[0].joints), [0, 1, 1])
        self.assertEqual(glb.doc["nodes"][2]["translation"], [1.0, 2.0, 3.0])
        self.assertEqual(glb.doc["skins"][0]["joints"], [1, 2])
        with self.assertRaises(ValueError):
            glb_bytes([GlbPrimitive(np.eye(3), np.eye(3), np.zeros((3, 2)), [0, 1, 2], "m")], "m", [GlbJoint("a", -1, (0.0, 0.0, 0.0))])

    # --- determinism -------------------------------------------------------------------------
    def test_the_same_seed_builds_the_same_files(self) -> None:
        for path in sorted(self.dir_a.iterdir()):
            self.assertEqual(sha256(path), sha256(self.dir_b / path.name), path.name)


if __name__ == "__main__":
    unittest.main()
