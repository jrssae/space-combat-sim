"""The Babylon 5 station generator (M7-T04, D72): its two pieces and their frames, the Cobra arms on the drum, the drum clearing the
frame through a whole turn, the proportions against the measurements (and against the reference STL when it is present), the
budgets, the output contract on a small bake and determinism."""

from __future__ import annotations

import json
import math
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import babylon5_station as station
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.context import BuildContext
from tools.procgen.core.detail_layer import detail_tile
from tools.procgen.core.geometry import Mesh
from tools.procgen.core.glb import read_glb
from tools.procgen.core.image import read_png
from tools.procgen.core.sampling import sample_mesh
from tools.procgen.parts import station as st
from tools.procgen.parts import station_detail as sd

REPO_ROOT = Path(__file__).resolve().parents[3]
STL = REPO_ROOT / "references" / "EA Babylon 5 Station.stl"
SMALL = (1024, 1024, 64)  # drum, frame and detail tile in px: the tests' bake (the doors' small parts need room for their charts)
# The defence grid's mounts (D75, approved 2026-11-13), station frame: name, piece, position.
MOUNTS = [
    ("L1", "drum", (-41, 292, 690)), ("L2", "drum", (41, 292, 690)), ("L3", "drum", (292, 41, 690)), ("L4", "drum", (292, -41, 690)),
    ("L5", "drum", (41, -292, 690)), ("L6", "drum", (-41, -292, 690)), ("L7", "drum", (-292, -41, 690)), ("L8", "drum", (-292, 41, 690)),
    ("L9", "frame", (0, 507, 1500)), ("L10", "frame", (0, 537, 2650)), ("L11", "frame", (0, 537, 4500)), ("L12", "frame", (0, 472, 5650)),
    ("H1", "frame", (-45, 375, 515)), ("H2", "frame", (45, 375, 515)),
    ("I1", "drum", (0, 324, 800)), ("I2", "drum", (324, 0, 800)), ("I3", "drum", (0, -324, 800)), ("I4", "drum", (-324, 0, 800)),
    ("I5", "frame", (0, 438, 520)), ("I6", "frame", (40, 459, 1500)), ("I7", "frame", (-40, 537, 2650)), ("I8", "frame", (40, 537, 4500)),
    ("I9", "frame", (-40, 472, 5650)),
]


def _mesh(parts) -> Mesh:
    return Mesh.concatenate(p.mesh for p in parts)


def _in_station_frame(points: np.ndarray, shift: np.ndarray) -> np.ndarray:
    return np.asarray(points) + shift


class StationShapeTests(unittest.TestCase):
    """The geometry, without baking a texture."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.drum_parts, cls.frame_parts = station.drum_parts(), station.frame_parts()
        cls.drum, cls.frame = _mesh(cls.drum_parts), _mesh(cls.frame_parts)
        rng = np.random.default_rng(5)
        cls.drum_pts = sample_mesh(cls.drum, 3.0, rng, smooth=False).positions + station.DRUM_CENTRE  # station frame
        cls.frame_pts = sample_mesh(cls.frame, 3.0, rng, smooth=False).positions + station.ORIGIN

    def test_two_pieces_with_the_frame_and_drum_parts_where_the_references_put_them(self) -> None:
        drum = {p.name for p in self.drum_parts}
        frame = {p.name for p in self.frame_parts}
        self.assertTrue({"sphere", "fwd_body", "fwd_band", "green", "aft_band", "arms", "rims"} <= drum)
        self.assertTrue({"bow", "spine", "cargo", "dome", "hub", "fins", "booms", "vanes", "truss", "aft"} <= frame)
        self.assertFalse(drum & frame)

    def test_the_drums_frame_sits_on_the_long_axis(self) -> None:
        lo, hi = self.drum.bounds()
        np.testing.assert_allclose(0.5 * (lo + hi)[:2], [0.0, 0.0], atol=1.0, err_msg="centred on its axis, so it turns in place")
        self.assertEqual(station.drum_pivot()[:2], [0.0, 0.0])
        self.assertAlmostEqual(station.drum_pivot()[2], float(station.DRUM_CENTRE[2] - station.ORIGIN[2]))
        self.assertLess(abs(0.5 * (lo[2] + hi[2])), 30.0, "the drum's frame is near its middle")

    def test_the_station_is_8_km_long_and_as_wide_and_high_as_the_measurements(self) -> None:
        pts = np.concatenate([self.drum_pts, self.frame_pts])
        size = pts.max(axis=0) - pts.min(axis=0)
        np.testing.assert_allclose(size, [1111.0, 3006.0, 8000.0], rtol=0.01)  # docs/assets-station.md, "Overall size"
        self.assertAlmostEqual(float(pts[:, 2].min()), 0.0, delta=1.0, msg="the bow tip at z 0")

    def test_four_cobra_arms_turn_with_the_drum_at_right_angles(self) -> None:
        heads = self.drum_pts[(self.drum_pts[:, 2] > 760.0) & (self.drum_pts[:, 2] < 840.0)]
        r = np.hypot(heads[:, 0], heads[:, 1])
        tips = heads[r > 300.0]
        turn = np.degrees(np.arctan2(tips[:, 1], tips[:, 0])) % 360.0
        for angle in st.ARM_ANGLES_DEG:
            near = np.abs((turn - angle + 180.0) % 360.0 - 180.0) < 20.0
            self.assertGreater(int(near.sum()), 10, f"an arm's head stands at {angle} degrees")
        self.assertEqual(int((np.abs((turn[:, None] - np.array(st.ARM_ANGLES_DEG)[None, :] + 180.0) % 360.0 - 180.0).min(axis=1)
                              > 20.0).sum()), 0, "nothing else stands that far out there")
        frame_there = self.frame_pts[(self.frame_pts[:, 2] > 620.0) & (self.frame_pts[:, 2] < 1420.0)]
        frame_turn = np.degrees(np.arctan2(frame_there[:, 1], frame_there[:, 0])) % 360.0
        for angle in (0.0, 180.0, 270.0):  # the frame stands only over the top arm (the spine), never beside or below the drum
            near = np.abs((frame_turn - angle + 180.0) % 360.0 - 180.0) < 30.0
            self.assertEqual(int(near.sum()), 0, f"frame beside the arm at {angle} degrees")

    def test_the_drum_clears_the_frame_through_a_whole_turn(self) -> None:
        # Turned through 360 degrees the drum sweeps the solid of revolution of its farthest point at each station along the axis;
        # every frame point near the drum must stay outside that solid with room to spare (the spine 9 m over the bands, Q9).
        bin_m = 2.0
        z, r = self.drum_pts[:, 2], np.hypot(self.drum_pts[:, 0], self.drum_pts[:, 1])
        z0 = z.min() - 100.0
        bins = int((z.max() + 100.0 - z0) / bin_m) + 1
        reach = np.full(bins, -np.inf)
        np.maximum.at(reach, ((z - z0) / bin_m).astype(int), r)
        centres = z0 + (np.arange(bins) + 0.5) * bin_m
        fz, fr = self.frame_pts[:, 2], np.hypot(self.frame_pts[:, 0], self.frame_pts[:, 1])
        best = np.full(len(fz), np.inf)
        for k in np.flatnonzero(np.isfinite(reach)):
            dz = np.abs(fz - centres[k])
            near = dz < 60.0
            gap = np.hypot(np.maximum(dz[near] - 0.5 * bin_m, 0.0), np.maximum(fr[near] - reach[k], 0.0))
            best[near] = np.minimum(best[near], gap)
        worst = int(np.argmin(best))
        self.assertGreater(float(best[worst]), 5.0, f"the frame at {self.frame_pts[worst].round(1)} touches the turning drum")
        # And at a few turns, nothing of the drum passes through the spine's underside over the bands.
        for turn in np.radians([0.0, 22.5, 45.0, 67.5, 90.0]):
            c, s = math.cos(turn), math.sin(turn)
            p = self.drum_pts @ np.array([[c, s, 0.0], [-s, c, 0.0], [0.0, 0.0, 1.0]])
            under = (np.abs(p[:, 0]) < 85.0) & (p[:, 2] > 1800.0) & (p[:, 2] < 2290.0)
            self.assertLess(float(p[under, 1].max()), 428.0 - 5.0)

    def test_each_cobra_arm_has_six_framed_lit_clamped_doors_over_an_open_hall(self) -> None:
        from tools.procgen.parts import station_props as sp  # noqa: PLC0415

        top = st.ARM_HATCH[4]
        floor = top - st.DOOR_DEPTH
        centres = st.launch_door_centres()
        cx, (dx, dz) = st.LAUNCH_STRIP_X, st.LAUNCH_DOOR_HALF
        self.assertEqual(len(centres), 6, "six doors an arm (the maintainer's arm model)")
        # One Starfury (15.4 m across its claws, 9.8 m long, span across the arm) drops through with 2 m or more to spare round it.
        self.assertGreaterEqual(dx - 7.7, 2.0)
        self.assertGreaterEqual(dz - 4.9, 2.0)
        self.assertGreater(centres[1] - centres[0] - 2.0 * dz, 3.0, "a bar between doors")
        hx0, hx1, hz0, hz1 = st.LAUNCH_HALL
        self.assertTrue(hx0 < cx - dx and cx + dx < hx1 and hz0 < centres[0] - dz and centres[-1] + dz < hz1, "the hall under the strip")
        self.assertLess(hx1, st.ARM_HATCH[2], "the strip keeps to the face, not the whole 94 m")
        for angle in st.ARM_ANGLES_DEG:
            a = math.radians(angle)
            # The arm's own +x (built on top, turned by its angle less 90 degrees).
            out, across = np.array([math.cos(a), math.sin(a), 0.0]), np.array([math.sin(a), -math.cos(a), 0.0])
            r, x, z = self.drum_pts @ out, self.drum_pts @ across, self.drum_pts[:, 2]
            in_door = (np.abs(x - cx) < dx - 1.5) & (r > st.HALL_CEILING_R - 20.0)
            for c in centres:
                door = in_door & (np.abs(z - c) < dz - 1.5)
                self.assertAlmostEqual(float(r[door].max()), st.HALL_CEILING_R, delta=0.6, msg="open to the hall's ceiling")
            between = (np.abs(x - cx) < dx - 1.5) & (np.abs(z - 0.5 * (centres[0] + centres[1])) < 1.0) & (r > 200.0)
            self.assertAlmostEqual(float(r[between].max()), top, delta=0.5, msg="the deck's bar stands between doors")
            beside = (np.abs(x + 25.0) < 5.0) & (np.abs(z - centres[2]) < 5.0) & (r > 200.0)
            self.assertAlmostEqual(float(r[beside].max()), top, delta=0.5, msg="the rest of the face is deck")
        lights = {p.name: p for p in self.drum_parts}["bay_lights"].mesh
        self.assertEqual(lights.face_count, 4 * 6 * 4 * 12, "a lit strip along each edge of every door")
        self.assertTrue(all(m.emissive_strength > 0.0 for m in lights.materials))
        self.assertNotIn("clamps", {p.name for p in self.drum_parts}, "the clamps are near-only props (M7-T19)")
        groups = {g.kind: g for g in sp.groups("waist", station.DRUM_CENTRE)}
        self.assertEqual(len(groups["clamp"].transforms), 4 * 6, "a clamp beside every door")
        self.assertEqual(sp.clamp().face_count, 3 * 12, "a post, an arm and a red cap")
        leaves = [k for k in groups if k.startswith("door_leaf_")]
        self.assertEqual(len(leaves), 12, "two leaves a door number, each its own kind (its half of the number)")
        self.assertTrue(all(len(groups[k].transforms) == 4 for k in leaves), "one of each on every arm")
        self.assertEqual(len(groups["gantry"].transforms), 24, "a gantry over every door in its hall")
        # M7-T09's hangar keeps T04's seven-door names until T20 refits it.
        self.assertEqual((st.COBRA_DOORS, st.DOOR_HALF, len(st.door_centres())), (7, (32.0, 14.0), 7))

    def test_every_closed_shape_faces_outward(self) -> None:
        for part in self.drum_parts + self.frame_parts:
            self.assertGreater(st.signed_volume(part.mesh), 0.0, part.name)

    def test_the_grid_mounts_have_a_surface_under_them_on_their_piece(self) -> None:
        # D75's mounts are T05's to build; here they must sit on (within a few metres of) the piece that carries them.
        for name, piece, at in MOUNTS:
            pts = self.drum_pts if piece == "drum" else self.frame_pts
            gap = float(np.linalg.norm(pts - np.asarray(at, dtype=float), axis=1).min())
            self.assertLess(gap, 25.0, f"{name} ({piece}) is {gap:.1f} m from its surface")

    def test_budgets(self) -> None:
        self.assertLessEqual(self.drum.face_count, 40_000)
        self.assertLessEqual(self.frame.face_count, 40_000)
        self.assertEqual((station.DRUM_ATLAS_PX, station.FRAME_ATLAS_PX, station.DETAIL_PX), (4096, 4096, 1024))

    @unittest.skipUnless(STL.is_file(), "the reference STL is gitignored; it is on the maintainer's machine")
    def test_the_90_percent_rule_against_the_reference(self) -> None:
        from tools.refview import compare, refview  # noqa: PLC0415 - needs Pillow and the reference

        raw, _ = refview.read_stl(STL)
        model, _ = refview.to_ship_frame(raw, refview.frame_matrix("-y", "+z", "-x"), station.LENGTH_M)
        whole = station.whole_station()
        result = compare.compare_shapes(model, whole.vertices[whole.faces] + station.ORIGIN, station.LENGTH_M)
        failures = compare.judge({n: v.iou for n, v in result.views.items()}, result.ratios)
        self.assertEqual(failures, [])


class DetailTileTests(unittest.TestCase):
    def test_the_tile_wraps_and_blends_lightly_on_a_plates_face(self) -> None:
        maps = detail_tile(1024, 16.0, seed=3)
        albedo, normal = maps["albedo"].astype(int), maps["normal"].astype(int)
        self.assertEqual(albedo.shape, (1024, 1024, 4))
        self.assertEqual(normal.shape, (1024, 1024, 3))
        # Seamless: the first and last rows and columns differ no more than any neighbouring pair inside.
        inner = np.abs(np.diff(albedo[..., 3], axis=0)).mean()
        self.assertLessEqual(np.abs(albedo[0, :, 3] - albedo[-1, :, 3]).mean(), 3.0 * inner + 1.0)
        self.assertLessEqual(np.abs(albedo[:, 0, 3] - albedo[:, -1, 3]).mean(), 3.0 * inner + 1.0)
        alpha = albedo[..., 3] / 255.0
        self.assertAlmostEqual(float(np.median(alpha)), 0.35, delta=0.02, msg="a plate's face takes a third of the tile")
        self.assertGreater(float((alpha > 0.6).mean()), 0.02, "the seams take most of it")
        self.assertTrue(np.array_equal(detail_tile(1024, 16.0, seed=3)["albedo"], maps["albedo"]))
        with self.assertRaises(ValueError):
            detail_tile(256, 15.0)


def _bake(name: str, px: int = 1024) -> tuple[np.ndarray, dict[str, np.ndarray]]:
    """One shape's maps baked alone at about the full build's texel: its covered texels' sRGB albedo, and every map."""
    from tools.procgen.core.textured_mesh import atlas_of  # noqa: PLC0415
    from tools.procgen.core.textures import bake_maps  # noqa: PLC0415

    parts = {p.name: p for p in station.drum_parts() + station.frame_parts()}
    atlas = atlas_of([parts[name]], atlas_px=px, texel_m=1.0, style=station.STYLE, grid=False)
    maps = bake_maps(atlas, station.STYLE, seed=1, occlusion=False)
    maps["filled"] = atlas.buffers.filled
    return maps["albedo"][atlas.buffers.filled].astype(float), maps


def _blue(a: np.ndarray, margin: float) -> np.ndarray:
    return (a[:, 2] > a[:, 0] + margin) & (a[:, 2] > a[:, 1] + margin)


class PaintTests(unittest.TestCase):
    def test_the_bands_and_green_zone_wear_blue_violet_blocks_on_grey(self) -> None:
        for name, lo, hi in (("fwd_band", 0.25, 0.6), ("green", 0.25, 0.6), ("sphere", 0.3, 0.6)):
            albedo, _ = _bake(name)
            share = float(_blue(albedo, 12.0).mean())
            self.assertTrue(lo < share < hi, f"{name}: blue-violet on {share:.0%} of it")

    def test_the_vanes_are_deep_blue_in_a_grey_frame_and_the_cargo_red(self) -> None:
        vanes, _ = _bake("vanes", 2048)
        self.assertGreater(float(_blue(vanes, 20.0).mean()), 0.5)
        grey = np.abs(vanes[:, 0] - vanes[:, 2]) < 6.0
        self.assertGreater(float(grey.mean()), 0.1, "the frame round each blade")
        cargo, _ = _bake("cargo", 512)
        red = (cargo[:, 0] > cargo[:, 1] + 20.0) & (cargo[:, 0] > cargo[:, 2] + 20.0)
        self.assertGreater(float(red.mean()), 0.8)

    def test_the_cobra_arms_carry_red_trim(self) -> None:
        arms, _ = _bake("arms")
        red = (arms[:, 0] > arms[:, 1] + 20.0) & (arms[:, 0] > arms[:, 2] + 20.0) & (arms[:, 1] < arms[:, 0] * 0.7)
        rust = (arms[:, 0] > arms[:, 2] + 12.0) & (arms[:, 1] > arms[:, 2]) & (arms[:, 1] > arms[:, 0] * 0.55)
        self.assertGreater(float(red.mean()), 0.01, "the doors' red border, the arm's trim and the red cross")
        self.assertLess(float(rust.mean()), 0.01, "the doors are their leaves (props) now; the hall under them is dark")


class MetalTests(unittest.TestCase):
    """Metal, not plastic (the maintainer, 2026-11-13): painted metal on the plating, bare metal on the trim and machinery, the
    roughness varied plate to plate, dirt rougher and duller."""

    def test_the_materials_are_painted_or_bare_metal(self) -> None:
        from tools.procgen.styles.earth_alliance_station import BARE_METAL, SCHEME  # noqa: PLC0415

        for role, (_, _, metallic, roughness) in SCHEME.items():
            if role == "window":
                continue
            if role in BARE_METAL:
                self.assertGreaterEqual(metallic, 0.75, role)
                self.assertLessEqual(roughness, 0.4, role)
            else:
                self.assertTrue(0.35 <= metallic <= 0.6, f"{role}: painted metal, metallic {metallic}")
                self.assertTrue(0.3 <= roughness <= 0.7, f"{role}: neither wet nor matte, roughness {roughness}")

    def test_the_baked_roughness_varies_across_the_plating_and_the_metal_reads_as_metal(self) -> None:
        _, band = _bake("fwd_band")
        orm = band["orm"][band["filled"]].astype(float) / 255.0
        rough, metal = orm[:, 1], orm[:, 2]
        self.assertTrue(0.3 < float(np.median(rough)) < 0.65, "satin, not wet and not matte")
        self.assertGreater(float(np.percentile(rough, 90) - np.percentile(rough, 10)), 0.12, "plate to plate and with the dirt")
        self.assertTrue(0.25 < float(np.median(metal)) < 0.6, "painted metal")
        from tools.procgen.core import textures  # noqa: PLC0415

        if hasattr(textures, "metal_finish"):  # dirt duller than clean paint comes with M7-T16's finish, shared by the station's style
            self.assertGreater(float(np.percentile(metal, 90) - np.percentile(metal, 10)), 0.05, "dirt is duller than clean paint")
        _, truss = _bake("truss", 512)
        bare = truss["orm"][truss["filled"]].astype(float) / 255.0
        self.assertGreater(float(np.median(bare[:, 2])), 0.6, "bare metal on the truss")
        self.assertLess(float(np.median(bare[:, 1])), float(np.median(rough)), "and smoother than the paint")


class WindowTests(unittest.TestCase):
    def test_the_bands_and_the_command_section_have_rows_of_lit_windows(self) -> None:
        # Baked part by part at about a metre a texel (the full build's), since the tests' small bake has no room for a window.
        for name in ("fwd_band", "spine"):
            lit = _bake(name)[1]["emissive"].max(axis=2) > 60
            self.assertGreater(int(lit.sum()), 200, f"{name}: windows glow")
            self.assertLess(float(lit.mean()), 0.05, f"{name}: in rows, not all over")


class StationBuildTests(unittest.TestCase):
    """A small bake (the atlases at a few hundred px) for the contract, the paint and determinism."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        root = Path(cls._tmp.name)
        cls.dir_a, cls.dir_b = root / "a", root / "b"
        station.build_at(BuildContext(cls.dir_a, seed=42), *SMALL)
        station.build_at(BuildContext(cls.dir_b, seed=42), *SMALL)
        cls.manifest = manifest_io.read_manifest(cls.dir_a)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_the_output_contract(self) -> None:
        manifest_io.validate_manifest(self.manifest)
        self.assertEqual(self.manifest["asset_id"], "babylon5_station")
        self.assertEqual(self.manifest["centroid_offset"], [0.0, 0.0, 4000.0])
        pieces = self.manifest["pieces"]
        self.assertEqual(set(pieces), {"drum", "frame"})
        for name, piece in pieces.items():
            section = piece["mesh"]
            manifest_io.validate_mesh_section(section)
            self.assertEqual(section["file"], f"babylon5_station_{name}.glb")
            positions = np.concatenate([p.positions for p in read_glb(self.dir_a / section["file"]).primitives])
            np.testing.assert_allclose(positions.min(axis=0), piece["aabb_min"], atol=1e-2)
            for surface in section["surfaces"]:
                for key in ("albedo", "normal", "orm", "emissive"):
                    self.assertTrue((self.dir_a / surface[key]).is_file(), surface[key])
                detail = surface["world_detail"]
                self.assertEqual(detail["tile_m"], 16.0)
                for key in ("albedo", "normal"):
                    self.assertTrue((self.dir_a / detail[key]).is_file())
                    self.assertTrue((self.dir_a / (detail[key] + ".import")).is_file())
        drum = pieces["drum"]
        self.assertEqual(drum["axis"], [0.0, 0.0, 1.0])
        self.assertEqual(drum["pivot"], station.drum_pivot())
        self.assertAlmostEqual(drum["spin_rad_s"], 0.148)
        self.assertEqual(self.manifest["length_m"], 8000.0)
        far = self.manifest["far"]
        self.assertLess(far["areas_m2"][2], far["areas_m2"][0], "end on it is smaller than from the side")

    def test_the_drums_surface_glows_where_its_windows_are(self) -> None:
        surface = self.manifest["pieces"]["drum"]["mesh"]["surfaces"][0]
        self.assertGreater(surface["emissive_strength"], 0.0, "Q10")

    def test_the_bow_is_at_minus_z_with_the_aperture_and_the_reactor_at_plus_z(self) -> None:
        # The game's frame (the glbs as written, the drum moved to its pivot): the bow tip and the docking aperture at -Z, the
        # reactor at +Z (the maintainer read the aperture shot as the reactor's end, M7-T04 fix round).
        pieces = self.manifest["pieces"]
        drum = np.concatenate([p.positions for p in read_glb(self.dir_a / pieces["drum"]["mesh"]["file"]).primitives])
        drum = drum + np.asarray(pieces["drum"]["pivot"])
        frame = np.concatenate([p.positions for p in read_glb(self.dir_a / pieces["frame"]["mesh"]["file"]).primitives])
        origin = self.manifest["centroid_offset"][2]
        self.assertAlmostEqual(float(frame[:, 2].min()), -origin, delta=1.0, msg="the bow tip at -Z")
        self.assertAlmostEqual(float(frame[:, 2].max()), 8000.0 - origin, delta=1.0, msg="the reactor's aft face at +Z")
        front = drum[drum[:, 2] < drum[:, 2].min() + 40.0]  # the drum's foremost 40 m: the docking bay (M7-T05)
        mouth_front = sd.BLOCK[2] - sd.GRILLE[2]  # the grilles on the block round the mouth
        self.assertAlmostEqual(float(drum[:, 2].min()), mouth_front - origin, delta=1.0, msg="the docking bay's block is the drum's front")
        self.assertLess(float(np.hypot(front[:, 0], front[:, 1]).max()), math.hypot(sd.HOUSING[0], sd.HOUSING[1]) + 1.0,
                        "the cross housing inside the frame's ring")
        reactor = frame[frame[:, 2] > 7700.0 - origin]
        self.assertLess(float(np.hypot(reactor[:, 0], reactor[:, 1]).max()), 175.0, "the reactor, not a docking ring")
        ring = frame[(frame[:, 2] > st.RING_FRAME[0] - origin - 1.0) & (frame[:, 2] < st.RING_FRAME[1] - origin + 1.0)]
        self.assertGreater(len(ring), 0, "the aperture's ring stands at the bow end of the frame")

    def test_deterministic(self) -> None:
        names = sorted(p.name for p in self.dir_a.iterdir())
        self.assertEqual(names, sorted(p.name for p in self.dir_b.iterdir()))
        for name in names:
            self.assertEqual((self.dir_a / name).read_bytes(), (self.dir_b / name).read_bytes(), name)
        json.loads((self.dir_a / "manifest.json").read_text())


if __name__ == "__main__":
    unittest.main()
