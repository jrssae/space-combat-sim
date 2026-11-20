# Ship catalogue

Generated from `data/ships/catalogue.json`, each type's `ShipSpec` and its generated manifest and hardpoints by
`ShipCatalogDoc` (M10-T61). Do not edit by hand: after a change run `scripts/gen_assets.sh` (if a hull changed) and
`scripts/gen_ship_catalog.sh`. `tests/unit/test_ship_catalog_doc.gd` fails while this page is stale.

Adding a hull: one entry in the catalogue (keys in `src/game/ship_catalog_data.gd`) and one `ShipSpec` `.tres` in
`assets/ships/`. Scenarios name ships by `id`; never rename one (recordings and saved careers hold them).

## Hulls

| id | faction | role | size L x W x H (m) | hull points | weapons | jump capable | carries fighters |
|---|---|---|---|---|---|---|---|
| `starfury_aurora` | earth_alliance | fighter | 9.8 x 15.4 x 7.5 | 300 | fixed `pulse_cannon_ef` | no | no |
| `starfury_ally` | earth_alliance | fighter | 9.8 x 15.4 x 7.5 | 300 | fixed `pulse_cannon_ef` | no | no |
| `raider_fighter` | raiders | fighter | 7.4 x 16.0 x 1.5 | 60 | fixed `raider_plasma` | no | no |
| `saturn_3_freighter` | earth_alliance | civilian | 96.8 x 94.9 x 35.8 | 640 | none | no | no |
| `saturn_4_transport` | earth_alliance | civilian | 158.5 x 106.2 x 25.2 | 540 | none | no | no |
| `saturn_4_tanker` | earth_alliance | civilian | 158.5 x 50.5 x 31.6 | 440 | none | no | no |
| `saturn_8_transport` | earth_alliance | civilian | 258.5 x 106.2 x 24.7 | 715 | none | no | no |
| `saturn_8_tanker` | earth_alliance | civilian | 258.5 x 51.3 x 31.3 | 380 | none | no | no |
| `skylark_transport` | earth_alliance | civilian | 60.0 x 40.2 x 10.2 | 440 | none | no | no |
| `narn_transport` | narn | civilian | 70.0 x 46.0 x 18.0 | 340 | none | no | no |
| `centauri_brezebel` | centauri | civilian | 60.0 x 39.1 x 25.2 | 300 | none | no | no |
| `brakiri_bokmai` | brakiri | civilian | 79.9 x 31.6 x 30.9 | 330 | turrets `turret_light_brakiri` | no | no |
| `raider_strike_carrier` | raiders | capital (strike_carrier) | 112.0 x 85.5 x 84.3 | 10000 | none | yes | yes (18 cradles) |

## What other code reads from each entry

`pooled`: `ShipPool` builds it by type. `docking`: `tunnel` (the main docking bay) or `cargo_bay`. `look_sheet`: what
`sheet <asset>` parks. `name`: the target preview's class line. `callsign`: a civilian's radio name.

| id | spec | ai_profile | pooled | docking | look_sheet | name | callsign |
|---|---|---|---|---|---|---|---|
| `starfury_aurora` | `res://assets/ships/starfury_aurora.tres` | - | yes | - | - | Aurora Starfury | - |
| `starfury_ally` | `res://assets/ships/starfury_ally.tres` | ally_starfury | yes | - | pool | - | - |
| `raider_fighter` | `res://assets/ships/raider_delta_v.tres` | raider | yes | - | pool | Delta-V raider | - |
| `saturn_3_freighter` | `res://assets/ships/saturn_3_freighter.tres` | civilian | yes | cargo_bay | pool | Saturn 3 freighter | SATURN |
| `saturn_4_transport` | `res://assets/ships/saturn_4_transport.tres` | civilian | yes | cargo_bay | pool | Saturn 4 transport | SATURN |
| `saturn_4_tanker` | `res://assets/ships/saturn_4_tanker.tres` | civilian | yes | cargo_bay | pool | Saturn 4 tanker | SATURN |
| `saturn_8_transport` | `res://assets/ships/saturn_8_transport.tres` | civilian | yes | cargo_bay | pool | Saturn 8 transport | SATURN |
| `saturn_8_tanker` | `res://assets/ships/saturn_8_tanker.tres` | civilian | yes | cargo_bay | pool | Saturn 8 tanker | SATURN |
| `skylark_transport` | `res://assets/ships/skylark_transport.tres` | civilian | yes | tunnel | pool | Skylark transport | SKYLARK |
| `narn_transport` | `res://assets/ships/narn_transport.tres` | civilian | yes | tunnel | pool | Narn transport | NARN |
| `centauri_brezebel` | `res://assets/ships/centauri_brezebel.tres` | civilian | yes | tunnel | pool | Brezebel transport | BREZEBEL |
| `brakiri_bokmai` | `res://assets/ships/brakiri_bokmai.tres` | civilian | yes | - | pool | Bokmai hauler | BOKMAI |
| `raider_strike_carrier` | `res://assets/ships/raider_strike_carrier.tres` | - | no | - | hull | - | - |
