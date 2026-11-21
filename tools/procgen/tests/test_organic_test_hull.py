"""``organic_test_hull`` (M10-T06, D12.2): the organic part library's whole output on its test hull: one seamless body
cut into sections, limbs and petals, the class budget, both texture sets of a hull with no drawn layout, the sheen on its
surfaces, collision that covers it section by section, hardpoints, determinism, and the plated (hex) look.

The expected numbers are typed in from the generator's docstring and docs/assets-capital.md, not read from the generator.
"""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS
from tools.procgen.assets import organic_test_hull as oth
from tools.procgen.core import collision as col
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import over_budget
from tools.procgen.core.context import BuildContext
from tools.procgen.core.image import read_png
from tools.procgen.core.isosurface import edge_faults
from tools.procgen.core.obj import read_obj
from tools.procgen.parts import capital as cp
from tools.procgen.styles import organic as looks
from tools.procgen.tests.budget_table import read_budgets
from tools.procgen.tests.mesh_checks import MAP_KEYS, assert_model_mesh, glb_triangles

ID = "organic_test_hull"
# A coarse build keeps the tests quick: the shape is checked, not its finish.
TEST_OPTIONS = {"atlas_px": 512, "spacing": 3.0, "cell_m": 2.5, "body_triangles": 8000}
SECTIONS = ("head", "core", "tail", "petals", "claw_r", "claw_l", "legs_r", "legs_l")
KINDS = {"head": "bridge", "core": "reactor", "tail": "engine", "petals": "structure", "claw_r": "structure", "claw_l": "structure",
         "legs_r": "structure", "legs_l": "structure"}
LENGTH, SPAN, HEIGHT = 300.0, 180.0, 97.6
CUTS = (108.0, 212.0)  # where the body's skin passes from the head to the core and from the core to the tail


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class OrganicTestHullTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b, cls.dir_hex = root / "a", root / "b", root / "hex"
        cls.out_a = oth.build(BuildContext(cls.dir_a, seed=42, options=TEST_OPTIONS))
        cls.out_b = oth.build(BuildContext(cls.dir_b, seed=42, options=TEST_OPTIONS))
        cls.out_hex = oth.build(BuildContext(cls.dir_hex, seed=42, options={**TEST_OPTIONS, "look": "hex", "detail_px": 128}))
        cls.manifest = manifest_io.read_manifest(cls.dir_a)
        cls.hp = json.loads((cls.dir_a / "hardpoints.json").read_text(encoding="utf-8"))
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.sections = {s["name"]: s for s in cls.manifest["sections"]}
        cls.shapes = {entry["name"]: col.shapes_from_entry(entry) for entry in cls.manifest["collision"]["pieces"]}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def chunk_triangles(self, name: str) -> np.ndarray:
        """A section's chunk mesh, back in place in the generator's frame."""
        chunk = next(c for c in self.hp["chunks"] if c["name"] == name)
        return glb_triangles(self.dir_a / chunk["mesh"]) + np.array(chunk["offset"]) + self.offset

    # --- files, budget, texture sets -----------------------------------------------------------------------------------
    def test_registered_built_and_within_the_cruiser_budget(self) -> None:
        self.assertIs(ASSETS[ID], oth.build)
        self.assertEqual(self.out_a.warnings, (), "the collision covers the hull")
        self.assertEqual({p.name for p in self.out_a.files}, {p.name for p in self.dir_a.iterdir()})
        manifest_io.validate_manifest(self.manifest)
        assert_model_mesh(self, self.dir_a, self.manifest["mesh"], f"{ID}.obj", "hull")
        budget = self.manifest["budget"]
        self.assertEqual(budget["class"], "cruiser")
        row = read_budgets()["cruiser"]
        self.assertEqual(over_budget("cruiser", oth.BODY_TRIANGLES + budget["triangles"] - TEST_OPTIONS["body_triangles"], 0.0, 0.0), [],
                         "with its body at full size the hull is inside the class's triangles")
        self.assertLessEqual(oth.ATLAS_PX, row.atlas_px, "and its one atlas is the class's size")
        self.assertEqual(list(self.manifest["pieces"]), ["hull"])

    def test_dimensions_and_the_bow_forward(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH, delta=1.0)
        self.assertAlmostEqual(dims["span"], SPAN, delta=1.0)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=1.5)
        v = read_obj(self.dir_a / f"{ID}.obj").vertices + self.offset
        self.assertAlmostEqual(float(v[:, 2].min()), 0.0, delta=1.0, msg="the claws' tips at the bow")
        self.assertAlmostEqual(float(v[:, 2].max()), LENGTH, delta=0.01, msg="the tendrils' tips at the stern")
        self.assertAlmostEqual(float(v[:, 0].max()), -float(v[:, 0].min()), delta=0.5, msg="as wide to port as to starboard")

    def test_a_seamless_hull_still_has_its_low_set_a_mip_level_down(self) -> None:
        surface = self.manifest["mesh"]["surfaces"][0]
        self.assertEqual(self.manifest["skin"], "seamless")
        self.assertNotIn("world_detail", surface, "no plating tile on a seamless skin (Q46)")
        self.assertEqual(set(surface["detail"]["low"]), set(MAP_KEYS))
        for key in MAP_KEYS:
            low = surface["detail"]["low"][key]
            self.assertTrue((self.dir_a / (low + ".import")).is_file(), key)
            self.assertEqual((read_png(self.dir_a / surface[key]).shape[0], read_png(self.dir_a / low).shape[0]), (512, 256), key)
        normal = read_png(self.dir_a / surface["normal"])
        self.assertLessEqual(int(np.ptp(normal.reshape(-1, normal.shape[-1]), axis=0).max()), 2, "no seam or panel line is drawn: the normal map is flat")

    def test_the_surface_wears_the_looks_sheen(self) -> None:
        surface = self.manifest["mesh"]["surfaces"][0]
        self.assertEqual(surface["sheen"], looks.organic("vorlon").surface["sheen"])
        self.assertGreater(surface["sheen"]["glow_energy"], 0.0)
        self.assertEqual((surface["sheen"]["variant_share"], surface["sheen"]["variant_all"]), (0.2, 0.0), "a fifth of its ships red-based")

    # --- one skin, cut into sections -----------------------------------------------------------------------------------
    def test_the_body_is_one_closed_skin_shared_out_by_the_head_core_and_tail(self) -> None:
        modules = {m.name: m for m in oth.modules(looks.organic("vorlon").style, 42, 2.5, 8000)}
        body = [modules[name].part.mesh for name in ("head", "core", "tail")]
        points = np.concatenate([m.vertices for m in body])
        _, index = np.unique(points, axis=0, return_inverse=True)
        faces, base = [], 0
        for mesh in body:
            faces.append(index.reshape(-1)[mesh.faces + base])
            base += mesh.vertex_count
        self.assertEqual(edge_faults(np.concatenate(faces)), 0, "watertight, with one outside")
        self.assertLessEqual(sum(m.face_count for m in body), 8000)
        for name in ("claw_r", "leg_0_r", "leg_2_r", "tendril_top", "tendril_r", "petal_top", "petal_r"):
            self.assertEqual(edge_faults(modules[name].part.mesh.faces), 0, f"{name} is closed too")
        self.assertEqual({m.side for m in modules.values() if m.name.endswith("_r")}, {cp.RIGHT})

    def test_the_sections_are_named_kinded_and_share_out_the_hull_points(self) -> None:
        self.assertEqual(tuple(self.sections), SECTIONS)
        self.assertEqual({name: s["kind"] for name, s in self.sections.items()}, KINDS)
        self.assertAlmostEqual(sum(s["hull_share"] for s in self.sections.values()), 1.0, places=9)
        self.assertGreater(self.sections["core"]["blast_energy_j"], 0.0, "the reactor is the explosive section")
        self.assertEqual([s["name"] for s in self.manifest["sections"] if "blast_energy_j" in s], ["core"])

    def test_the_chunks_cover_the_hull_and_the_body_is_cut_where_it_says(self) -> None:
        self.assertEqual([c["name"] for c in self.hp["chunks"]], list(SECTIONS))
        chunks = {name: self.chunk_triangles(name) for name in SECTIONS}
        self.assertEqual(sum(len(t) for t in chunks.values()), self.manifest["mesh"]["triangles"], "every triangle is in one section's chunk")
        whole = glb_triangles(self.dir_a / f"{ID}.glb") + self.offset
        middles = np.concatenate([t.mean(axis=1) for t in chunks.values()])
        self.assertLess(float(col.nearest_distance(middles, whole.mean(axis=1), 0.5).max()), 1e-3, "and the chunks are the hull")
        # The head's skin ends at the first cut, the tail's starts at the second (a triangle's width of saw-tooth either way).
        petals_and_claws = 131.0  # the petals' hinges and the claws' roots are behind the head's cut, in their own sections
        self.assertLess(float(chunks["head"].mean(axis=1)[:, 2].max()), CUTS[0] + 0.01)
        self.assertGreater(float(chunks["core"].mean(axis=1)[:, 2].min()), CUTS[0] - 0.01)
        self.assertLess(float(chunks["core"].mean(axis=1)[:, 2].max()), CUTS[1] + 0.01)
        self.assertGreater(float(chunks["tail"].mean(axis=1)[:, 2].min()), CUTS[1] - 0.01)
        self.assertLess(float(chunks["petals"][..., 2].max()), petals_and_claws)
        self.assertTrue(np.all(chunks["legs_r"][..., 0] > 0.0) and np.all(chunks["legs_l"][..., 0] < 0.0))

    # --- collision -----------------------------------------------------------------------------------------------------
    def test_every_section_has_convex_collision_inside_the_budget(self) -> None:
        self.assertEqual(tuple(self.shapes), SECTIONS)
        for name, shapes in self.shapes.items():
            self.assertEqual(len(shapes), self.sections[name]["shapes"], name)
            self.assertLessEqual(len(shapes), self.manifest["collision"]["max_shapes"], name)
            self.assertTrue(all(s.kind == col.HULL and len(s.points) <= 32 for s in shapes), name)
        self.assertLessEqual(sum(len(s) for s in self.shapes.values()), 110, "about a hundred shapes for the whole hull")
        self.assertEqual(len(self.shapes["legs_r"]), len(self.shapes["legs_l"]))

    def test_the_collision_covers_the_skin_and_stays_close_to_it(self) -> None:
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))
        self.assertLessEqual(cover["tolerance_m"], 4.0)
        self.assertLessEqual(cover["reach_m"], 8.0)
        for name in SECTIONS:
            skin = self.chunk_triangles(name).reshape(-1, 3) - self.offset
            self.assertLess(float(col.gaps(self.shapes[name], skin).max()), 4.5, f"{name}: its own shapes hold its own skin")
        between_legs = np.array([[70.0, -30.0, 150.0]]) - self.offset  # open space under a leg's arch
        self.assertGreater(float(col.gaps([s for group in self.shapes.values() for s in group], between_legs)[0]), 4.0)

    # --- hardpoints ----------------------------------------------------------------------------------------------------
    def test_the_beam_and_the_engine_are_on_their_sections(self) -> None:
        self.assertEqual([(w["name"], w["kind"], w["section"]) for w in self.hp["weapons"]], [("beam", "beam", "head")])
        self.assertEqual([(e["name"], e["section"], e["share"]) for e in self.hp["engines"]], [("engine", "tail", 1.0)])
        self.assertEqual(self.sections["head"]["hardpoints"], ["beam"])
        self.assertEqual(self.sections["tail"]["hardpoints"], ["engine"])
        np.testing.assert_allclose(np.array(self.hp["engines"][0]["position"]) + self.offset, [0.0, 0.0, 266.0], atol=1e-4)
        self.assertEqual(self.hp["engines"][0]["thrust"], [0.0, 0.0, -1.0])
        self.assertIn("jump_point", self.hp)
        self.assertIn("placeholder", self.manifest["notes"][0])

    # --- determinism, the plated look ----------------------------------------------------------------------------------
    def test_two_builds_are_the_same_files(self) -> None:
        names = sorted(p.name for p in self.dir_a.iterdir())
        self.assertEqual(names, sorted(p.name for p in self.dir_b.iterdir()))
        for name in names:
            self.assertEqual(sha256(self.dir_a / name), sha256(self.dir_b / name), name)

    def test_the_hex_look_is_the_same_shape_plated_with_its_tile_and_its_own_sheen(self) -> None:
        self.assertEqual(self.out_hex.warnings, ())
        manifest = manifest_io.read_manifest(self.dir_hex)
        self.assertEqual(manifest["skin"], "hex_grid")
        self.assertEqual(manifest["budget"]["triangles"], self.manifest["budget"]["triangles"])
        surface = manifest["mesh"]["surfaces"][0]
        self.assertEqual(surface["sheen"], looks.organic("hex").surface["sheen"])
        self.assertEqual(surface["world_detail"]["tile_m"], 16.0)
        self.assertTrue((self.dir_hex / surface["world_detail"]["albedo"]).is_file())
        normal = read_png(self.dir_hex / surface["normal"])
        self.assertGreater(int(np.ptp(normal.reshape(-1, normal.shape[-1]), axis=0).max()), 20, "the hexagons' seams are drawn (Q47)")
        high, low = read_png(self.dir_hex / surface["albedo"]), read_png(self.dir_hex / surface["detail"]["low"]["albedo"])
        self.assertEqual((high.shape[0], low.shape[0]), (512, 256))
        np.testing.assert_allclose(glb_triangles(self.dir_hex / f"{ID}.glb"), glb_triangles(self.dir_a / f"{ID}.glb"), atol=1e-6)


if __name__ == "__main__":
    unittest.main()
