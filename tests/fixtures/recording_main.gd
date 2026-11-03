extends Node3D
## Stands in for Main in flow tests (M5-T09): remembers what `Game` handed the scene it built, so a test can check that a retry
## played the same scenario and seed without paying for the real Main.

var scenario_path: String = ""
var scenario_seed: int = -1
