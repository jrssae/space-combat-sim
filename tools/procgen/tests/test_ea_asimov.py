"""``ea_asimov`` (M10-T53, Q84, Q86, Q87): the Asimov-class liner on the capital framework. Files and pieces, size, the sections and
the habitat band's turning piece, an unarmed loadout, the open hexagonal mouth, the halves the mining variant will part, collision
coverage, the class budget, the look (the patch skin, no seam lines), the band liveries and bars, the forward bowl, and each
part's sections against the reference STL (CLAUDE.md, "STL fidelity"; the face's planes exempted by Q95), and stage 2's docking
collars with a crew shuttle swept onto each (as M10-T70 sweeps the craft through Babylon 5's bay) and its shuttle bay (Q96): the
hall inside the fixed core the band turns round, on the interior layer, with both shuttles swept down their lanes into their berths.

The expected numbers are typed in from docs/assets-capital.md, data/capitals/loadouts.json and the generator's docstring.
"""

from __future__ import annotations

import itertools
import json
import math
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.assets import ASSETS, BUILD_ALONE
from tools.procgen.assets import ea_asimov as ea
from tools.procgen.core import capital as cap
from tools.procgen.core import loadout
from tools.procgen.core import manifest as manifest_io
from tools.procgen.core.budgets import over_budget, texture_mb, low_set_mb
from tools.procgen.core.context import BuildContext
from tools.procgen.core.geometry import Mesh
from tools.procgen.core.seams import Plates
from tools.procgen.parts import capital as cp
from tools.procgen.parts import ea_asimov as asi
from tools.procgen.parts import ea_asimov_fidelity as fid
from tools.procgen.parts import ea_hyperion as hy
from tools.procgen.styles import ea_asimov as st
from tools.procgen.tests import bay_interiors
from tools.procgen.tests import convex_gap as cg
from tools.procgen.tests import test_ea_craft_bay_clearance as bay
from tools.procgen.tests.budget_table import read_budgets
from tools.refview.sections import PASS_IOU, section_score

ROOT = Path(__file__).resolve().parents[3]
SHUTTLE = ROOT / "assets" / "generated" / "ea_shuttle" / "hardpoints.json"  # the crew shuttle as built (its stern hatch, Q84)
DOCK_GAP_M = 0.3  # data/capitals/ship_docks.json, gap_m
CRAFT_DIR = ROOT / "assets" / "generated"
REST_GAP_M = 0.05  # CarrierDock.DOCK_GAP_M: a berthed craft's belly over the deck
KESTREL_FOLD = tuple(hy.SHUTTLE_POSES["ea_atmo_shuttle"]["fold_joint_m"])  # its wings turn up about these roots (Q73)
DECK_SHAPES = ("cap_bay_low", "core_bay_low")  # the bay's deck: a berthed craft stands on it
SWEEP_OUT_M, SWEEP_STEP_M = 150.0, 1.0  # a lane is swept from the berth to clear of the bowl
OFF_LANE = [(dx, dy, roll) for dx in (-0.75, 0.75) for dy in (-0.75, 0.75) for roll in (-2.0, 2.0)]
STL = ROOT / "references" / "EA Asimov liner 600m.stl"
NAMES = ROOT / "data" / "ships" / "names.json"
TEST_OPTIONS = {"atlas_px": 512, "detail_px": 128}
LENGTH, SPAN, HEIGHT = 600.0, 347.4, 347.4
SECTIONS = ("bridge", "spine", "face", "habitat", "sphere_aft", "reactor", "engine_r", "engine_l")


def _shape_points(shape: dict) -> np.ndarray:
    """Points whose convex hull holds a collision shape: a hull's own, a box's corners, and for a capsule the corners of a
    cube round each end's sphere (a little outside it, which keeps the check on the safe side)."""
    if shape["type"] == "hull":
        return np.array(shape["points"])
    basis = np.array([shape["basis"]["x"], shape["basis"]["y"], shape["basis"]["z"]]).T
    centre = np.array(shape["position"])
    signs = np.array(list(itertools.product((-1.0, 1.0), repeat=3)))
    if shape["type"] == "box":
        return centre + (signs * (np.array(shape["size"]) / 2.0)) @ basis.T
    if shape["type"] == "capsule":
        along = basis[:, "xyz".index(shape["axis"])] * (shape["height"] / 2.0 - shape["radius"])
        return np.concatenate([centre + end + signs * shape["radius"] for end in (along, -along)])
    raise AssertionError(f"{shape['name']}: {shape['type']} is not handled")


def _polygon_gap(p: np.ndarray, q: np.ndarray) -> float:
    """The least distance between two convex outlines (counter-clockwise); negative when they overlap."""
    def inside(pt: np.ndarray, poly: np.ndarray) -> bool:
        a, b = poly, np.roll(poly, -1, 0)
        return bool((((b[:, 0] - a[:, 0]) * (pt[1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (pt[0] - a[:, 0])) >= 0.0).all())

    apart = np.maximum(p.min(0) - q.max(0), q.min(0) - p.max(0)).max()
    if apart > 40.0:
        return float(apart)  # far apart: their boxes' gap is no more than theirs, and enough to say so
    gap = min(float(bay.seg_dist(p, q, np.roll(q, -1, 0)).min()), float(bay.seg_dist(q, p, np.roll(p, -1, 0)).min()))
    overlap = bay.crossing(p, q) or any(inside(v, q) for v in p) or any(inside(v, p) for v in q)
    return -gap if overlap else gap


class AsimovBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls._tmp.name) / "ea_asimov"
        cls.out = ea.build(BuildContext(cls.dir, seed=42, options=TEST_OPTIONS))
        cls.manifest = manifest_io.read_manifest(cls.dir)
        cls.hp = json.loads((cls.dir / "hardpoints.json").read_text(encoding="utf-8"))
        cls.offset = np.array(cls.manifest["centroid_offset"])
        cls.sections = {s["name"]: s for s in cls.manifest["sections"]}

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_registered_built_alone_and_covered(self) -> None:
        self.assertIs(ASSETS["ea_asimov"], ea.build)
        self.assertIn("ea_asimov", BUILD_ALONE, "two 4 096 px atlases: built alone")
        self.assertEqual(self.out.warnings, (), "the collision covers the hull")
        manifest_io.validate_manifest(self.manifest)
        cover = self.manifest["collision"]["coverage"]
        self.assertEqual((cover["covered"], cover["within_reach"]), (1.0, 1.0))

    def test_size(self) -> None:
        dims = self.manifest["dimensions_m"]
        self.assertAlmostEqual(dims["length"], LENGTH, delta=0.005 * LENGTH)
        self.assertAlmostEqual(dims["span"], SPAN, delta=0.01 * SPAN)
        self.assertAlmostEqual(dims["height"], HEIGHT, delta=0.01 * HEIGHT)

    def test_the_sections_and_the_turning_band(self) -> None:
        self.assertEqual(tuple(self.sections), SECTIONS)
        self.assertAlmostEqual(sum(s["hull_share"] for s in self.sections.values()), 1.0, places=9)
        self.assertGreater(self.sections["reactor"]["blast_energy_j"], 0.0)
        pieces = self.manifest["pieces"]
        self.assertEqual(list(pieces), ["hull", "band"])
        self.assertEqual(pieces["band"]["sections"], ["habitat"])
        np.testing.assert_allclose(np.array(pieces["band"]["pivot"]) + self.offset, asi.BAND_PIVOT, atol=1e-3)
        self.assertEqual(pieces["band"]["axis"], [0.0, 0.0, 1.0])
        self.assertAlmostEqual(pieces["band"]["spin_rad_s"], ea.BAND_SPIN_RAD_S)

    def test_unarmed_with_four_engines_and_its_lights(self) -> None:
        self.assertEqual(loadout.problems(self.hp, loadout.read(), "ea_asimov"), [])
        self.assertEqual(self.hp["weapons"], [])
        self.assertEqual(loadout.read()["hulls"]["ea_asimov"]["launches"], {"ea_shuttle": 1, "ea_atmo_shuttle": 1}, "its two shuttles (Q84)")
        self.assertEqual(len(self.hp["engines"]), 4)
        self.assertAlmostEqual(sum(e["share"] for e in self.hp["engines"]), 1.0)
        roles = sorted(light["role"] for light in self.hp["lights"])
        self.assertEqual(roles, ["bay", "beacon", "beacon", "port", "starboard", "top"])

    # --- the shuttle bay (Q84, Q96) --------------------------------------------------------------------------------------
    def test_the_shuttle_bay_is_a_lit_hall_with_a_door_and_two_berths(self) -> None:
        (b,) = self.hp["bays"]
        self.assertEqual((b["name"], b["kind"], b["section"]), (asi.BAY_NAME, cp.BAY, "face"))
        self.assertEqual((b["forward"], b["up"]), ([0.0, 0.0, -1.0], [0.0, 1.0, 0.0]), "it opens forward, into the bowl")
        self.assertEqual((b["mouth_m"], b["depth_m"]), ([70.0, 23.2], 70.0), "the hall runs 70 m straight back (Q96)")
        self.assertEqual(b["aperture_m"], [45.0, 27.0], "behind the hexagonal mouth")
        self.assertEqual((b["capacity"], b["berths"], b["berth_craft"]), (2, 2, ["ea_shuttle", "ea_atmo_shuttle"]), "a crew shuttle and a Kestrel (Q84)")
        self.assertTrue(b["visitors"], "craft that are not the liner's own may berth in it")
        hall = bay_interiors.halls(self.hp)[0]
        front = float((hall.centre + hall.axes[2] * hall.half[2] + self.offset)[2])
        self.assertAlmostEqual(front, asi.HEX_BACK_Z, places=3, msg="the hall begins behind the mouth's frame")
        self.assertAlmostEqual(float((hall.centre - hall.axes[1] * hall.half[1] + self.offset)[1]), asi.BAY_DECK_Y, places=3)
        (door,) = self.hp["doors"]
        self.assertEqual(door["name"], f"{asi.BAY_NAME}_door")
        self.assertGreaterEqual(door["size_m"][0], 45.0)
        self.assertGreaterEqual(door["size_m"][1], 27.0)
        at = np.array(door["position"]) + self.offset
        self.assertTrue(asi.BOWL_FLOOR_Z < at[2] < asi.HEX_BACK_Z, "the shutter runs inside the mouth's frame")
        np.testing.assert_allclose(at[:2], np.array(asi.HEX).mean(axis=0), atol=1e-3)
        (lamp,) = [light for light in self.hp["lights"] if light["role"] == "bay"]
        self.assertEqual(lamp["name"], f"{asi.BAY_NAME}_light", "the door lights the hall as it opens")
        self.assertTrue(bay_interiors.halls(self.hp)[0].name == asi.BAY_NAME)

    def test_the_bay_hall_is_on_the_interior_layer(self) -> None:
        """Q68: the sun's light stays out of the hall; its walls, deck, back and the wall round the mouth are lit by its lamp."""
        bay_interiors.check(self, self.dir, self.manifest, self.hp, 1)
        self.assertGreaterEqual(self.manifest["pieces"]["hull"]["mesh"]["interior_triangles"], 40, "and its front wall round the mouth")

    def test_the_band_turns_round_a_fixed_core_clear_of_the_bay(self) -> None:
        """Q96: the habitat band's collision is a ring as far back as the bay reaches; the hall lies inside the core with room
        to spare whichever way the band has turned."""
        shapes = {entry["name"]: entry for entry in self.manifest["collision"]["pieces"]}
        pivot = np.array(self.manifest["pieces"]["band"]["pivot"]) + self.offset
        inner = asi.CORE_R * math.cos(math.pi / asi.CORE_SIDES)  # the nearest the ring's flat inner faces come to the axis
        ring = 0
        for shape in shapes["habitat"]["shapes"]:
            pts = _shape_points(shape) + pivot
            if pts[:, 2].min() < asi.CORE_END_Z - 0.01 and float(np.hypot(pts[:, 0], pts[:, 1]).max()) > asi.CORE_R + 1.0:
                ring += 1 if shape["name"].startswith("band_fore_") else 0  # the others are the clamps on the skin
                self.assertGreaterEqual(float(np.hypot(pts[:, 0], pts[:, 1]).min()), asi.CORE_R - 1e-3, f"{shape['name']} stays off the core")
        self.assertEqual(ring, 2 * asi.CORE_SIDES, "two steps of sectors round the core")
        half, top = 0.5 * asi.BAY_SIZE[0], asi.BAY_DECK_Y + asi.BAY_SIZE[1]
        far = max(math.hypot(half, y) for y in (asi.BAY_DECK_Y, top))
        self.assertGreaterEqual(inner - far, 3.0, "the hall's far corners to the turning ring")
        self.assertGreaterEqual(asi.CORE_END_Z - (asi.HEX_BACK_Z + asi.BAY_DEPTH), 10.0, "and its back wall to the band's solid part")
        self.assertEqual(shapes["habitat"]["piece"], "band")
        self.assertEqual(shapes["face"]["piece"], "hull", "the core and the hall do not turn")
        core = [s for s in shapes["face"]["shapes"] if s["name"].startswith("core_")]
        self.assertEqual(len(core), 5, "the core round the hall and its solid end")

    def _berths(self) -> list[tuple[str, np.ndarray, np.ndarray]]:
        """The bay's berths as the game reads them (``BayBerths``): the craft, its point on the deck and its lane's way out."""
        (b,) = self.hp["bays"]
        forward, up = np.array(b["forward"]), np.array(b["up"])
        right = np.cross(forward, up)
        sill = np.array(b["exit"]) - up * (b["mouth_m"][1] / 3.0)
        out = []
        for craft, deg, run in zip(b["berth_craft"], b["berth_fan_deg"], b["berth_run_m"], strict=True):
            way = forward * math.cos(math.radians(deg)) + right * math.sin(math.radians(deg))
            out.append((craft, sill - way * run, way))
        return out

    def _liner(self) -> cg.Body:
        """Every collision shape of the liner but the bay's deck, in the body's frame."""
        if not hasattr(type(self), "_body"):
            names, sets = [], []
            for entry in self.manifest["collision"]["pieces"]:
                at = np.zeros(3) if entry["piece"] == cap.HULL_PIECE else np.array(self.manifest["pieces"][entry["piece"]]["pivot"])
                for shape in entry["shapes"]:
                    if shape["name"] not in DECK_SHAPES:
                        names.append(shape["name"])
                        sets.append(_shape_points(shape) + at)
            type(self)._body = cg.Body(names, sets)
        return type(self)._body

    @staticmethod
    def _craft(craft: str) -> tuple[cg.Body, np.ndarray]:
        """A shuttle as it flies into a bay (the Kestrel's wings folded) and the point of it that rests on the deck."""
        body = cg.craft_body(CRAFT_DIR / craft / "hardpoints.json", KESTREL_FOLD if craft == "ea_atmo_shuttle" else None)
        box = json.loads((CRAFT_DIR / craft / "manifest.json").read_text(encoding="utf-8"))
        lo, hi = np.array(box["aabb_min"]), np.array(box["aabb_max"])
        return body, np.array([0.5 * (lo[0] + hi[0]), lo[1] - REST_GAP_M, 0.5 * (lo[2] + hi[2])])

    @staticmethod
    def _on_lane(body: cg.Body, rest: np.ndarray, deck: np.ndarray, way: np.ndarray, out_m: float = 0.0, off: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> cg.Body:
        """The craft ``out_m`` out of its berth along its lane, nose out, set ``off`` (m across, m up, degrees of roll) from it."""
        axes = cg.nose_along(way)
        return body.moved(cg.rolled(axes, off[2]), deck - axes @ rest + way * out_m + axes @ np.array([off[0], off[1], 0.0]))

    def _lane_gap(self, craft: str, deck: np.ndarray, way: np.ndarray, others: cg.Body, off: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> tuple[float, str]:
        """The least gap from the craft to ``others`` anywhere on its lane, from its berth out past the bowl."""
        body, rest = self._craft(craft)
        ends = [self._on_lane(body, rest, deck, way, t, off).bounds() for t in (0.0, SWEEP_OUT_M)]
        near = others.near(np.min([e[0] for e in ends], axis=0) - 15.0, np.max([e[1] for e in ends], axis=0) + 15.0)
        return min((cg.gap(self._on_lane(body, rest, deck, way, t, off), near) for t in np.arange(0.0, SWEEP_OUT_M + 0.5, SWEEP_STEP_M)),
                   key=lambda found: found[0])

    def _need_craft(self) -> None:
        for craft in asi.BAY_CRAFT:
            if not (CRAFT_DIR / craft / "hardpoints.json").exists():
                self.skipTest(f"{craft} is not built")

    def test_both_shuttles_fly_their_lanes_through_the_mouth_into_their_berths(self) -> None:
        """As M10-T70 sweeps Babylon 5's bay: each craft's collision, swept down its own lane from outside the bowl to its
        berth, stays clear of the mouth's frame, the hall and the rest of the hull, also when it is off its lane."""
        self._need_craft()
        for craft, deck, way in self._berths():
            body, rest = self._craft(craft)
            berthed = self._on_lane(body, rest, deck, way)
            self.assertGreaterEqual(float(berthed.corners[..., 1].min()), float(deck[1]) - 0.25, f"{craft} stands on the deck (its boxes a hand larger than its skin)")
            centred, where = self._lane_gap(craft, deck, way, self._liner())
            self.assertGreaterEqual(centred, 2.5, f"{craft} on its lane ({where})")
            worst = min(self._lane_gap(craft, deck, way, self._liner(), off)[0] for off in OFF_LANE)
            self.assertGreaterEqual(worst, 1.0, f"{craft} off by 0.75 m and 2 degrees of roll")

    def test_the_two_berths_and_the_collars_leave_each_other_room(self) -> None:
        """A craft flies in or out past the other in its berth, and past crew shuttles mated on the collars."""
        self._need_craft()
        berths = self._berths()
        placed = {craft: self._on_lane(*self._craft(craft), deck, way) for craft, deck, way in berths}
        crew, kestrel = (placed[c] for c in asi.BAY_CRAFT)
        self.assertGreaterEqual(cg.gap(crew, kestrel)[0], 8.0, "side by side in their berths")
        shuttle, _ = self._craft("ea_shuttle")
        hatch = np.array(json.loads(SHUTTLE.read_text(encoding="utf-8"))["docking_ports"][0]["position"])
        mated = [shuttle.moved(np.eye(3), np.array(p["position"]) + np.array(p["out"]) * DOCK_GAP_M - hatch) for p in self.hp["docking_ports"]]
        for (craft, deck, way), other in zip(berths, (kestrel, crew), strict=True):
            passing, where = self._lane_gap(craft, deck, way, other)
            self.assertGreaterEqual(passing, 2.5, f"{craft} past the other berth ({where})")
            for port, body in zip(self.hp["docking_ports"], mated, strict=True):
                self.assertGreaterEqual(self._lane_gap(craft, deck, way, body)[0], 3.0, f"{craft} past a shuttle on {port['name']}")

    def test_four_docking_collars_on_the_lower_teeth_face_forward(self) -> None:
        ports = {p["name"]: p for p in self.hp["docking_ports"]}
        self.assertEqual(sorted(ports), ["collar_lower_l", "collar_lower_r", "collar_upper_l", "collar_upper_r"])
        pivot = np.array(self.hp["rotors"][0]["pivot"])  # the sphere's centre, on the axis
        for name, port in ports.items():
            at = np.array(port["position"]) - pivot
            self.assertEqual((port["out"], port["up"], port["section"]), ([0.0, 0.0, -1.0], [0.0, 1.0, 0.0], "face"), name)
            self.assertAlmostEqual(float(np.hypot(at[0], at[1])), 67.5, delta=0.01, msg=f"{name} on its tooth's tip")
            self.assertAlmostEqual(float(at[2]), asi.POD_Z[0] - asi.COLLAR_REACH - asi.SPHERE_Z, delta=0.01, msg=f"{name} stands ahead of its tooth")
            self.assertLess(at[1], -30.0, f"{name} below the spine")
            twin = ports[cp.left_name(name) if name.endswith("_r") else name[:-2] + "_r"]
            self.assertEqual([-twin["position"][0], *twin["position"][1:]], port["position"], f"{name} has its twin")
        self.assertNotIn("habitat", {p["section"] for p in ports.values()}, "none on the turning band")

    def _lane_gaps(self, port: dict, dx: float = 0.0, dy: float = 0.0, roll_deg: float = 0.0) -> tuple[float, float]:
        """A crew shuttle mated on ``port`` by its stern hatch and swept out along the collar's axis: the least gap (m) from its
        collision boxes to the collar's own shape and to every other shape of the liner. A shape counts when it reaches
        ahead of the box's stern end (the sweep runs forward from there); the gap is taken in the plane across the lane."""
        shuttle = json.loads(SHUTTLE.read_text(encoding="utf-8"))
        (hatch,) = shuttle["docking_ports"]
        origin = np.array(port["position"]) + np.array(port["out"]) * DOCK_GAP_M - np.array(hatch["position"])
        r = math.radians(roll_deg)
        turn = np.array([[math.cos(r), -math.sin(r)], [math.sin(r), math.cos(r)]])
        own, rest = math.inf, math.inf
        for box, c in zip(bay.box_shadows(SHUTTLE), shuttle["collision"], strict=True):
            basis = np.array([c["basis"]["x"], c["basis"]["y"], c["basis"]["z"]]).T
            reach = 0.5 * c["height"] if c["type"] == "capsule" else float(np.abs(basis[2] * (np.array(c["size"]) / 2.0)).sum())
            stern = origin[2] + c["position"][2] + reach
            shadow = bay.hull2d(box @ turn.T + origin[:2] + [dx, dy])
            for name, bow, outline in self._hull_outlines():
                if bow > stern:
                    continue
                gap = _polygon_gap(shadow, outline)
                if name.startswith(port["name"]):
                    own = min(own, gap)
                else:
                    rest = min(rest, gap)
        return own, rest

    def _hull_outlines(self) -> list[tuple[str, float, np.ndarray]]:
        """Every collision shape of the liner seen from ahead: its name, its foremost z and its outline."""
        if not hasattr(type(self), "_outlines"):
            points = [(s["name"], _shape_points(s)) for p in self.manifest["collision"]["pieces"] for s in p["shapes"]]
            type(self)._outlines = [(name, float(pts[:, 2].min()), bay.hull2d(pts[:, :2])) for name, pts in points]
        return type(self)._outlines

    def test_a_crew_shuttle_backs_onto_each_collar_clear_of_the_hull(self) -> None:
        if not SHUTTLE.exists():
            self.skipTest("ea_shuttle is not built")
        for port in self.hp["docking_ports"]:
            own, rest = self._lane_gaps(port)
            self.assertGreaterEqual(own, 1.0, f"{port['name']}: the lock's rim to the shuttle's stern flaps, centred")
            self.assertGreaterEqual(rest, 8.0, f"{port['name']}: the lane to the rest of the hull, centred")
            worst = [self._lane_gaps(port, dx, dy, roll) for dx in (-0.75, 0.0, 0.75) for dy in (-0.75, 0.0, 0.75) for roll in (-2.0, 0.0, 2.0)]
            self.assertGreaterEqual(min(w[0] for w in worst), 0.25, f"{port['name']}: the lock, off by 0.75 m and 2 degrees of roll")
            self.assertGreaterEqual(min(w[1] for w in worst), 7.0, f"{port['name']}: the hull, off by 0.75 m and 2 degrees of roll")

    def test_shuttles_on_neighbouring_collars_keep_apart(self) -> None:
        if not SHUTTLE.exists():
            self.skipTest("ea_shuttle is not built")
        hatch = np.array(json.loads(SHUTTLE.read_text(encoding="utf-8"))["docking_ports"][0]["position"])
        outline = bay.hull2d(np.concatenate(bay.box_shadows(SHUTTLE)))
        ports = self.hp["docking_ports"]
        for i, a in enumerate(ports):
            for b in ports[i + 1:]:
                gap = _polygon_gap(outline + (np.array(a["position"]) - hatch)[:2], outline + (np.array(b["position"]) - hatch)[:2])
                self.assertGreaterEqual(gap, 8.0, f"{a['name']} and {b['name']}")

    def test_the_hull_is_inside_the_capital_budget(self) -> None:
        budget = self.manifest["budget"]
        self.assertEqual(budget["class"], "capital")
        row = read_budgets()["capital"]
        self.assertLessEqual(budget["triangles"], row.triangles)
        self.assertEqual([p.atlas_px for p in ea.PIECES], [4096, 4096])
        self.assertEqual(over_budget("capital", budget["triangles"], texture_mb([4096, 4096], 1024), low_set_mb([4096, 4096], 1024)), [])

    def test_every_opaque_surface_carries_the_band_liveries(self) -> None:
        for piece in self.manifest["pieces"].values():
            for surface in piece["mesh"]["surfaces"]:
                if not surface["blend"]:
                    self.assertEqual(surface["band_tint"], st.band_tint())

    def test_only_the_band_carries_the_bars(self) -> None:
        """The game's shader draws a ship's bars where ``band_bars`` says, in the band's own frame (Q95): no atlas a count."""
        pieces = self.manifest["pieces"]
        for surface in pieces["band"]["mesh"]["surfaces"]:
            if not surface["blend"]:
                self.assertEqual(surface["band_bars"], st.band_bars())
        self.assertFalse(any("band_bars" in surface for surface in pieces["hull"]["mesh"]["surfaces"]))
        bars = st.band_bars()
        self.assertAlmostEqual(bars["radius_m"], asi.SPHERE_R)
        self.assertEqual(bars["span_m"], [st.PATTERN.ring_end_z - asi.SPHERE_Z, asi.AFT_SEAM_Z - asi.SEAM_WIDTH - asi.SPHERE_Z])
        self.assertEqual(st.band_tint()["bar_counts"], [6, 8])


class AsimovSpecTests(unittest.TestCase):
    def test_the_spec_has_no_problems(self) -> None:
        self.assertEqual(cap.problems(ea.spec()), [])

    def test_only_the_liner_variant_so_far(self) -> None:
        self.assertEqual(ea.VARIANTS, ("liner",))
        with self.assertRaises(ValueError):
            ea.modules(variant="mining")

    def test_the_band_is_two_halves_split_at_the_equator(self) -> None:
        """T56's mining transport parts its sphere there: each half its own closed part."""
        band = [m for m in ea.modules() if m.section == "habitat" and m.name in ("band_fore", "band_aft")]
        self.assertEqual(sorted(m.name for m in band), ["band_aft", "band_fore"])
        lo, hi = ({m.name: m.part.mesh.bounds()[k][2] for m in band} for k in (0, 1))
        self.assertAlmostEqual(hi["band_fore"], asi.SPHERE_Z, places=6)
        self.assertAlmostEqual(lo["band_aft"], asi.SPHERE_Z, places=6)

    def test_the_hexagonal_mouth_is_open(self) -> None:
        """Nothing stands in the mouth from the bow back to the bay's back wall."""
        hex_pts = np.array(asi.HEX)
        centre = hex_pts.mean(axis=0)
        mesh = Mesh.concatenate([m.part.mesh for m in cp.with_twins(ea.modules())])
        tris = mesh.vertices[mesh.faces]
        ray = np.array([centre[0], centre[1]])
        hit_z = []
        def cross(u: np.ndarray, v: np.ndarray) -> float:
            return float(u[0] * v[1] - u[1] * v[0])

        for t in tris:
            a, b, c = t[:, :2]
            d = cross(b - a, c - a)
            if abs(d) < 1e-9:
                continue
            w1, w2 = cross(ray - a, c - a) / d, cross(b - a, ray - a) / d
            if w1 >= 0.0 and w2 >= 0.0 and w1 + w2 <= 1.0:
                hit_z.append(float(t[0, 2] + w1 * (t[1, 2] - t[0, 2]) + w2 * (t[2, 2] - t[0, 2])))
        self.assertAlmostEqual(min(hit_z), asi.HEX_BACK_Z + asi.BAY_DEPTH, places=3, msg="the first surface down the mouth's axis is the hall's back wall")

    def test_the_forward_face_is_a_deep_bowl_with_the_mouth_in_its_floor(self) -> None:
        """Q95: the show's cavity. The bowl narrows terrace by terrace to a floor wide enough for the mouth, and its collision
        leaves it open: no shape of the face reaches into it past the ribs' depth."""
        self.assertGreaterEqual(asi.BOWL_FLOOR_Z - asi.COLLAR[0], 35.0, "deep, not the reference's shallow disc")
        radii = [r for _, top, foot in asi.BOWL for r in (top, foot)]
        self.assertEqual(radii, sorted(radii, reverse=True))
        self.assertGreater(radii[-1], max(float(np.hypot(*p)) for p in asi.HEX), "the floor holds the whole mouth")
        self.assertLess(asi.HEX_BACK_Z, asi.FORE_SEAM_Z, "the mouth ends ahead of the turning band")
        cap_module = next(m for m in ea.modules() if m.name == "forward_cap")
        ends = [t[0] for t in asi.BOWL[1:]] + [asi.BOWL_FLOOR_Z]
        for (z0, top, foot), z1 in zip(asi.BOWL, ends, strict=True):
            for shape in (q for q in cap_module.shapes if q.name.startswith("cap_bowl")):
                pts = np.asarray(shape.points)
                inside = pts[(pts[:, 2] > z0 + 0.01) & (pts[:, 2] < z1 - 0.01)]
                if len(inside):
                    self.assertGreater(float(np.hypot(inside[:, 0], inside[:, 1]).min()), foot - asi.RIB_DEPTH, shape.name)

    def test_the_skin_is_patches_without_seams(self) -> None:
        layout = st.SKIN.hull_layout((0.0, 0.0, 0.0), (1.0, 1.0, 1.0), 7)
        for feature in (f for _, _, group in layout.groups for f in group):
            with self.subTest(feature=type(feature).__name__):
                self.assertTrue(feature.dark == 0.0, "no seam lines")
                if isinstance(feature, Plates) and feature.scatter == 0.0:
                    self.assertEqual(feature.depth, 0.0, "no grooves round the plates")
        self.assertIsNone(st.SKIN.detail_tile(64, 7))

    def test_the_paint_is_the_shows_layout(self) -> None:
        """Q95: a band-coloured ring round the forward face behind a white rim, about as wide as a bar; behind it white skin that
        turns with the band (its bars are the game's), window rows on the band standing clear of both bar counts."""
        cap_mesh = next(m for m in ea.modules() if m.name == "forward_cap").part.mesh
        names = [m.name for m in cap_mesh.materials]
        z = cap_mesh.vertices[cap_mesh.faces][:, :, 2].mean(axis=1)
        on_sphere = np.linalg.norm(cap_mesh.vertices[cap_mesh.faces].mean(axis=1) - np.array([0.0, 0.0, asi.SPHERE_Z]), axis=1) > asi.SPHERE_R - 1.0
        stripe = np.array([names[k].endswith("_stripe") for k in cap_mesh.face_material])
        self.assertTrue(stripe[on_sphere & (z > st.PATTERN.ring_z)].all(), "the ring")
        self.assertFalse(stripe[z < st.PATTERN.ring_z].any(), "the white rim and the grey collar inside it")
        self.assertAlmostEqual(float(cap_mesh.vertices[:, 2][np.linalg.norm(cap_mesh.vertices - np.array([0.0, 0.0, asi.SPHERE_Z]), axis=1)
                                                             > asi.SPHERE_R - 0.01].max()), st.PATTERN.ring_end_z, places=6, msg="the ring ends the cap's skin")
        polar = [math.acos((asi.SPHERE_Z - z) / asi.SPHERE_R) for z in (st.PATTERN.ring_z, st.PATTERN.ring_end_z)]
        self.assertAlmostEqual(asi.SPHERE_R * (polar[1] - polar[0]), 2.0 * st.PATTERN.bar_half_m, delta=2.0, msg="the ring is a bar wide")
        lead = next(m for m in ea.modules() if m.name == "band_lead")
        self.assertEqual(lead.section, "habitat", "the skin behind the ring turns with the band, so the bars meet the ring")
        lo, hi = lead.part.mesh.bounds()
        self.assertAlmostEqual(float(lo[2]), st.PATTERN.ring_end_z, places=6)
        self.assertAlmostEqual(float(hi[2]), asi.FORE_SEAM_Z, places=6)
        for m in ea.modules():
            if m.name in ("band_fore", "band_aft", "band_lead"):
                self.assertFalse(any(mat.name.endswith("_stripe") for mat in m.part.mesh.materials), "no bars baked")
            if m.name.endswith("_windows") and m.name.startswith("band_"):
                v = m.part.mesh.vertices
                deg = np.degrees(np.arctan2(v[:, 1], v[:, 0]))
                for count in st.PATTERN.bar_counts:
                    sector = 360.0 / count
                    off = np.abs((deg + 0.5 * sector) % sector - 0.5 * sector)
                    self.assertGreater(float((np.radians(off) * np.hypot(v[:, 0], v[:, 1])).min()), st.PATTERN.bar_half_m, f"{m.name}, {count} bars")

    def test_the_liveries(self) -> None:
        self.assertGreaterEqual(len(st.LIVERIES), 4, "the show's green and at least three more (Q86)")
        self.assertEqual(st.LIVERIES[0].key, "green", "the show's green is the default")
        self.assertEqual(len({lv.band for lv in st.LIVERIES}), len(st.LIVERIES))
        tint = st.band_tint()
        self.assertEqual(tint["liveries"][0], "green")
        self.assertEqual(len(tint["colours"]), len(st.LIVERIES))
        self.assertEqual(st.PAINT["stripe"], st.LIVERIES[0].band, "baked in the default green")
        names = json.loads(NAMES.read_text(encoding="utf-8"))["names"][st.NAMES_TYPE]
        self.assertEqual(names[0], "Asimov")
        self.assertEqual(names[1], "Callisto")  # the show's other liner, the one name that is no author (Q88)
        self.assertGreaterEqual(len(names), 15)


@unittest.skipUnless(STL.is_file(), "the reference STL is gitignored; it is on the maintainer's machine")
class AsimovSectionTests(unittest.TestCase):
    """The silhouettes and each part's sections against the STL: IoU >= 0.90."""

    @classmethod
    def setUpClass(cls) -> None:
        from tools.refview import refview  # noqa: PLC0415

        raw, _ = refview.read_stl(STL)
        axes = fid.REFERENCE_MAPPING
        model, _ = refview.to_ship_frame(raw, refview.frame_matrix(axes["right"], axes["up"], axes["aft"]), LENGTH)
        cls.stl = np.asarray(model).reshape(-1, 3, 3)
        mesh = Mesh.concatenate([m.part.mesh for m in cp.with_twins(ea.modules())])
        cls.model = mesh.vertices[mesh.faces]

    def test_every_part_passes(self) -> None:
        for part, planes in fid.PLANES.items():
            with self.subTest(part=part):
                failures = [f"{p.name} {s.iou:.3f}" for p in planes if (s := section_score(self.stl, self.model, p)).iou < PASS_IOU
                            and p.name not in fid.EXEMPT]
                self.assertEqual(failures, [], f"{part}: sections under {PASS_IOU}")

    def test_only_the_forward_face_is_exempt(self) -> None:
        """Q95: the show's bowl replaces the reference's shallow face; nothing else may miss, and the mouth holds in the floor."""
        face = {p.name for part in ("forward_face", "hex_mouth") for p in fid.PLANES[part]}
        self.assertLessEqual(set(fid.EXEMPT), face)
        self.assertNotIn("mouth_z215", fid.EXEMPT)
        for reason in fid.EXEMPT.values():
            self.assertIn("Q95", reason)

    def test_the_silhouettes(self) -> None:
        from tools.refview.compare import compare_shapes, judge  # noqa: PLC0415

        result = compare_shapes(self.stl, self.model, LENGTH)
        self.assertEqual(judge({k: v.iou for k, v in result.views.items()}, result.ratios), [])


if __name__ == "__main__":
    unittest.main()
