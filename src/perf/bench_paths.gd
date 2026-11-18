class_name BenchPaths
extends RefCounted
## Where the benchmark's reports live (M8-T14, roadmap L15): the project's `reports/` folder in a dev run, where the bench
## scripts look for them, and the user's data folder in an exported build, whose `res://` is a read-only pack.

const PROJECT_ROOT: String = "res://reports"
const USER_ROOT: String = "user://reports"
const PROBE_NAME: String = ".bench_write_probe"

# The project folder's answer, asked once a run: -1 not asked yet, else 0 or 1.
static var _project_writable: int = -1


## `path` itself, unless it lies in the project's reports folder and that takes no files: then the same place in the user's
## folder. `project_writable` (a Callable returning bool) answers for the project; tests pass their own.
static func resolve(path: String, project_writable: Callable = Callable()) -> String:
	if path != PROJECT_ROOT and not path.begins_with(PROJECT_ROOT + "/"):
		return path
	var writable: bool = bool(project_writable.call()) if project_writable.is_valid() else project_reports_writable()
	return path if writable else USER_ROOT + path.substr(PROJECT_ROOT.length())


## Whether the project's reports folder takes files. Not in an export, and not in a read-only install.
static func project_reports_writable() -> bool:
	if _project_writable < 0:
		_project_writable = int(folder_writable(ProjectSettings.globalize_path(PROJECT_ROOT)))
	return _project_writable == 1


## Whether files can be written into `absolute`, made if missing. A path that is not absolute has no folder behind it: an
## export's `res://` comes out that way.
static func folder_writable(absolute: String) -> bool:
	if not absolute.is_absolute_path():
		return false
	DirAccess.make_dir_recursive_absolute(absolute)
	var probe_path: String = absolute.path_join(PROBE_NAME)
	var probe := FileAccess.open(probe_path, FileAccess.WRITE)
	if probe == null:
		return false
	probe.close()
	DirAccess.remove_absolute(probe_path)
	return true
