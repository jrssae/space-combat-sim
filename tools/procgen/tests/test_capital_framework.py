"""The capital framework's section model (M10-T05, D12.1; ``core/capital.py``), on a three-module hull: the checks a spec must
pass, the port twins, each section's collision inside the budget, and the hardpoint lists."""

from __future__ import annotations

import dataclasses
import unittest

import numpy as np

from tools.procgen.core import capital as cap
from tools.procgen.core import collision as col
from tools.procgen.parts import capital as cp
from tools.procgen.parts import capital_engines as engines
from tools.procgen.parts import capital_fittings as fittings
from tools.procgen.parts import capital_hull as hull
from tools.procgen.parts import capital_weapons as weapons
from tools.procgen.styles.capital import FRAMEWORK_GREY, Seamless

STYLE = FRAMEWORK_GREY.style


def small_spec(**changes: object) -> cap.CapitalSpec:
    """A hull, a turret on it and an engine on each quarter: sections ``core`` (a reactor) and ``engine_r`` with its twin."""
    body = hull.hull_section("body", (hull.Station(0.0, 10.0, 6.0, 2.0), hull.Station(60.0, 10.0, 6.0, 2.0)), STYLE).in_section("core")
    turret = weapons.turret_mount("turret", 4.0, STYLE).mounted((0.0, 6.0, 20.0)).in_section("core")
    engine = engines.engine_block("engine_r", (6.0, 6.0, 12.0), (1, 1), STYLE, share=0.5).translated((8.0, 0.0, 52.0))
    spec = cap.CapitalSpec(
        asset_id="small", generator_version=1, ship_class="cruiser",
        modules=(body, turret, engine.in_section("engine_r").on_side(cp.RIGHT)),
        sections=(cap.Section("core", "reactor", 0.6, 1.0e12), cap.Section("engine_r", "engine", 0.2)),
        style=FRAMEWORK_GREY, bridge=cap.Pose((0.0, 6.0, 5.0)),
    )
    return dataclasses.replace(spec, **changes)


class CapitalFrameworkTests(unittest.TestCase):
    def test_a_sound_spec_has_no_problems(self) -> None:
        self.assertEqual(cap.problems(small_spec()), [])

    def test_starboard_sections_and_modules_get_port_twins(self) -> None:
        spec = small_spec()
        self.assertEqual([s.name for s in cap.all_sections(spec)], ["core", "engine_r", "engine_l"])
        self.assertEqual([(m.name, m.section) for m in cap.all_modules(spec)],
                         [("body", "core"), ("turret", "core"), ("engine_r", "engine_r"), ("engine_l", "engine_l")])
        self.assertAlmostEqual(sum(s.hull_share for s in cap.all_sections(spec)), 1.0)
        twin = cap.Section("pod_r", "fuel", 0.1, 5.0, joint=(4.0, 1.0, 2.0)).twin()
        self.assertEqual((twin.name, twin.joint, twin.blast_energy_j), ("pod_l", (-4.0, 1.0, 2.0), 5.0))

    def test_each_broken_rule_is_named(self) -> None:
        spec = small_spec()
        core, engine = spec.sections
        body, turret, eng = spec.modules
        cases = {
            "unknown kind": dict(sections=(dataclasses.replace(core, kind="galley"), engine)),
            "add up to": dict(sections=(dataclasses.replace(core, hull_share=0.5), engine)),
            "needs a blast energy": dict(sections=(dataclasses.replace(core, blast_energy_j=0.0), engine)),
            "only reactor, magazine and fuel": dict(sections=(core, dataclasses.replace(engine, blast_energy_j=1.0))),
            "unknown piece": dict(sections=(core, dataclasses.replace(engine, piece="ring"))),
            "above zero": dict(sections=(dataclasses.replace(core, hull_share=0.0), dataclasses.replace(engine, hull_share=0.5))),
            "unknown section": dict(modules=(body, turret.in_section("keel"), eng)),
            "has no module": dict(sections=(dataclasses.replace(core, hull_share=0.5), engine, cap.Section("spare", "structure", 0.1))),
            "module names must be unique": dict(modules=(body, turret, eng, turret)),
            "hardpoint names must be unique": dict(modules=(body, turret, eng, weapons.turret_mount("turret", 2.0, STYLE).in_section("core"))),
            "thrust shares": dict(modules=(body, turret)),
            "ends in _r": dict(modules=(body, turret.on_side(cp.RIGHT), eng)),
            "section names must be unique": dict(sections=(core, engine, dataclasses.replace(engine, hull_share=1e-9))),
            "needs a spin": dict(pieces=(cap.PieceSpec(), cap.PieceSpec("ring", 512))),
            "does not spin": dict(pieces=(cap.PieceSpec(spin_rad_s=0.1),)),
            "include 'hull'": dict(pieces=(cap.PieceSpec("body"),)),
        }
        for words, change in cases.items():
            if words == "thrust shares":  # one engine alone gives half the thrust
                change = dict(modules=(body, turret, eng.on_side(cp.CENTRE).in_section("core")), sections=(dataclasses.replace(core, hull_share=1.0),))
            found = cap.problems(small_spec(**change))
            self.assertTrue(any(words in p for p in found), f"{words!r} not in {found}")

    def test_a_broken_spec_is_not_built(self) -> None:
        from pathlib import Path
        from tools.procgen.core.context import BuildContext

        spec = small_spec(sections=(cap.Section("core", "reactor", 0.9, 1.0), cap.Section("engine_r", "engine", 0.2)))
        with self.assertRaisesRegex(ValueError, "small: the sections' hull shares add up to 1.3"):
            cap.build(spec, BuildContext(Path("unused"), seed=1))

    def test_each_section_gets_its_modules_shapes_inside_the_budget(self) -> None:
        spec = small_spec()
        shapes = cap.section_shapes(cap.all_modules(spec), cap.all_sections(spec), col.Budget(max_shapes=64))
        self.assertEqual(list(shapes), ["core", "engine_r", "engine_l"])
        self.assertEqual({s.name for s in shapes["core"]}, {"body_00", "turret", "turret_guns"})
        self.assertEqual({s.name for s in shapes["engine_l"]}, {"engine_l", "engine_l_bell"})
        tight = cap.section_shapes(cap.all_modules(spec), cap.all_sections(spec), col.Budget(max_shapes=2))
        self.assertTrue(all(len(group) <= 2 for group in tight.values()), "merged down to the budget")
        centre = np.array([[0.0, 0.0, 30.0]])
        self.assertEqual(float(col.gaps(tight["core"], centre).max()), 0.0, "the merged shapes still hold the hull")

    def test_the_skin_dresses_hull_and_fittings_and_leaves_bare_parts(self) -> None:
        mast = fittings.antenna("mast", 5.0, STYLE).mounted((0.0, 6.0, 40.0)).in_section("core")
        spec = small_spec(modules=(*small_spec().modules, mast))
        by_name = {m.name: m for m in cap.dressed(spec, 42)}
        self.assertTrue(by_name["body"].part.seams and by_name["turret"].part.seams)
        self.assertFalse(by_name["mast"].part.seams, "an antenna is bare")
        self.assertNotEqual(by_name["body"].part.seams.features(), by_name["turret"].part.seams.features())
        bare = cap.dressed(dataclasses.replace(spec, style=dataclasses.replace(FRAMEWORK_GREY, skin=Seamless())), 42)
        self.assertFalse(any(m.part.seams for m in bare), "a seamless skin draws no seams (Q46)")

    def test_hardpoints_are_listed_by_kind_in_the_body_frame(self) -> None:
        spec = small_spec()
        offset = np.array([0.0, 1.0, 30.0])
        lists = cap.hardpoint_lists(cap.all_modules(spec), offset)
        self.assertEqual({k: [e["name"] for e in v] for k, v in lists.items()},
                         {"weapons": ["turret"], "bays": [], "engines": ["engine_r", "engine_l"], "lights": []})
        turret = lists["weapons"][0]
        self.assertEqual((turret["kind"], turret["section"], turret["forward"], turret["up"]), ("turret", "core", [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]))
        module = spec.modules[1]
        np.testing.assert_allclose(turret["position"], module.hardpoints[0].position - offset, atol=1e-5)
        right, left = lists["engines"]
        self.assertEqual((right["thrust"], right["exhaust"], right["share"]), ([0.0, 0.0, -1.0], [0.0, 0.0, 1.0], 0.5))
        self.assertEqual(left["position"], [-right["position"][0], right["position"][1], right["position"][2]])
        self.assertEqual((right["section"], left["section"]), ("engine_r", "engine_l"))

    def test_the_sample_spacing_follows_the_length(self) -> None:
        self.assertEqual([cap.default_spacing(length) for length in (60.0, 300.0, 600.0, 3000.0)], [0.5, 1.0, 2.0, 4.0])


if __name__ == "__main__":
    unittest.main()
