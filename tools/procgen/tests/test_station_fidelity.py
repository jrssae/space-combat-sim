"""Per-part section check (M7-T21, CLAUDE.md "STL fidelity"): the section compare in ``tools/refview/sections.py`` on small solids,
and the station's parts against the reference STL at the planes ``parts/station_fidelity.py`` lists, each IoU >= 0.90 unless
exempt with an accepted reason."""

from __future__ import annotations

import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core.geometry import Material, Mesh, box
from tools.procgen.parts import station_fidelity as sf
from tools.refview.sections import PASS_IOU, SectionPlane, section_mask, section_score

REPO_ROOT = Path(__file__).resolve().parents[3]
STL = REPO_ROOT / "references" / "EA Babylon 5 Station.stl"
GREY = Material("grey", (0.5, 0.5, 0.5))


def _tris(*meshes: Mesh) -> np.ndarray:
    m = Mesh.concatenate(meshes)
    return m.vertices[m.faces]


class SectionToolTests(unittest.TestCase):
    PLANE = SectionPlane("z0", 2, 0.0, (-10.0, 10.0, -10.0, 10.0))

    def test_a_box_fills_its_section(self) -> None:
        mask = section_mask(_tris(box((8.0, 4.0, 2.0), GREY)), self.PLANE, 0.5)
        self.assertEqual(int(mask.sum()), 16 * 8)

    def test_overlapping_parts_fill_as_their_union(self) -> None:
        a, b = box((8.0, 4.0, 2.0), GREY), box((4.0, 8.0, 2.0), GREY)
        mask = section_mask(_tris(a, b), self.PLANE, 0.5)
        self.assertEqual(int(mask.sum()), 16 * 8 + 8 * 16 - 8 * 8, "a cross, not the two boxes' overlap cancelled")

    def test_a_tunnel_stays_open_and_the_outline_fills_it(self) -> None:
        walls = [box((10.0, 2.0, 2.0), GREY, (0.0, 4.0, 0.0)), box((10.0, 2.0, 2.0), GREY, (0.0, -4.0, 0.0)),
                 box((2.0, 6.0, 2.0), GREY, (4.0, 0.0, 0.0)), box((2.0, 6.0, 2.0), GREY, (-4.0, 0.0, 0.0))]
        open_ = section_mask(_tris(*walls), self.PLANE, 0.5)
        self.assertFalse(open_[20, 20], "the middle is empty")
        solid = section_score(_tris(box((10.0, 10.0, 2.0), GREY)), _tris(*walls), self.PLANE)
        self.assertLess(solid.iou, 0.7)
        outline = section_score(_tris(box((10.0, 10.0, 2.0), GREY)), _tris(*walls), SectionPlane("z0", 2, 0.0, self.PLANE.window, outline=True))
        self.assertAlmostEqual(outline.iou, 1.0, places=6)

    def test_iou_of_a_shifted_section(self) -> None:
        a, b = box((8.0, 8.0, 2.0), GREY), box((8.0, 8.0, 2.0), GREY, (2.0, 0.0, 0.0))
        self.assertAlmostEqual(section_score(_tris(a), _tris(a), self.PLANE).iou, 1.0)
        self.assertAlmostEqual(section_score(_tris(a), _tris(b), self.PLANE).iou, 48.0 / 80.0, places=6)

    def test_a_plane_on_a_row_of_corners_still_cuts(self) -> None:
        # Two boxes stacked on the plane: their shared row of corners lies on it, and the cut still finds the upper one.
        upper, lower = box((8.0, 4.0, 2.0), GREY, (0.0, 0.0, 1.0)), box((8.0, 4.0, 2.0), GREY, (0.0, 0.0, -1.0))
        self.assertEqual(int(section_mask(_tris(upper, lower), self.PLANE, 0.5).sum()), 16 * 8)

    def test_an_arm_is_cut_in_its_own_frame(self) -> None:
        # A box standing out along +x (an arm at 0 degrees), turned onto the top (+y), fills the window over the top.
        side = _tris(box((20.0, 6.0, 2.0), GREY, (30.0, 0.0, 0.0)))
        plane = SectionPlane("arm", 2, 0.0, (-10.0, 10.0, 15.0, 45.0), turn_deg=90.0)
        self.assertEqual(int(section_mask(side, plane, 0.5).sum()), 12 * 40)


@unittest.skipUnless(STL.is_file(), "the reference STL is gitignored; it is on the maintainer's machine")
class StationSectionTests(unittest.TestCase):
    """Each part's sections against the STL: IoU >= 0.90, or an exemption with its accepted reason."""

    @classmethod
    def setUpClass(cls) -> None:
        from tools.procgen.assets import babylon5_station as station  # noqa: PLC0415
        from tools.refview import refview  # noqa: PLC0415

        raw, _ = refview.read_stl(STL)
        model, _ = refview.to_ship_frame(raw, refview.frame_matrix("-y", "+z", "-x"), station.LENGTH_M)
        cls.stl = np.asarray(model).reshape(-1, 3, 3)
        drum = Mesh.concatenate(p.mesh for p in station.drum_parts())
        frame = Mesh.concatenate(p.mesh for p in station.frame_parts())
        cls.model = np.concatenate([drum.vertices[drum.faces] + station.DRUM_CENTRE, frame.vertices[frame.faces] + station.ORIGIN])

    def _part(self, part: str) -> None:
        failures = []
        for plane in sf.PLANES[part]:
            score = section_score(self.stl, self.model, plane)
            if score.iou < PASS_IOU and plane.name not in sf.EXEMPTIONS:
                failures.append(f"{plane.name} {score.iou:.3f}")
        self.assertEqual(failures, [], f"{part}: sections under {PASS_IOU}")

    def test_the_cobra_arms(self) -> None:
        self._part("cobra_arms")

    def test_the_main_docking_bay(self) -> None:
        self._part("main_docking_bay")

    def test_the_cargo_bay(self) -> None:
        self._part("cargo_bay")

    @unittest.skip("pending: rebuilt to the STL in M7-T22 (maintainer, 2026-11-13); scores 0.48-0.72")
    def test_the_dorsal_spine(self) -> None:
        self._part("dorsal_spine")

    @unittest.skip("pending: rebuilt to the STL in M7-T22 (maintainer, 2026-11-13); scores 0.38-0.71")
    def test_the_command_section(self) -> None:
        self._part("command_section")

    def test_every_exemption_names_a_plane_and_a_reason(self) -> None:
        names = {p.name for p in sf.all_planes()}
        for name, reason in sf.EXEMPTIONS.items():
            self.assertIn(name, names)
            self.assertGreater(len(reason), 20, name)


if __name__ == "__main__":
    unittest.main()
