class_name FeatureEdges
extends RefCounted
## The lines worth drawing of a hull (architecture §18.20, M5-T43), pure: its creases (edges whose two faces meet at more than
## `CREASE_DEG`), its open borders and any edge more than two faces share, as pairs of points for a `PRIMITIVE_LINES` mesh. A
## plain triangle wireframe draws the diagonal of every flat panel and turns a hull into noise. Vertices at the same place
## count as one, so a UV seam or a hard-normal split is no border. Edges come in the order the triangles first name them.
## `FeatureEdgeJob` does the work, here in one go.

## Faces meeting at more than this are a crease, degrees.
const CREASE_DEG: float = 25.0
## Vertices nearer than about this are one, m.
const WELD_M: float = 0.001


## The feature edges of a triangle list, as line pairs (a0, b0, a1, b1, ...). With no `indices` every three vertices are a
## triangle.
static func build(vertices: PackedVector3Array, indices: PackedInt32Array = PackedInt32Array(),
		crease_deg: float = CREASE_DEG, weld_m: float = WELD_M) -> PackedVector3Array:
	var job := FeatureEdgeJob.new(vertices, indices, crease_deg, weld_m)
	job.step()
	return job.lines()


## The feature edges of every triangle surface of `mesh` together (seams between surfaces weld too).
static func from_mesh(mesh: Mesh, crease_deg: float = CREASE_DEG, weld_m: float = WELD_M) -> PackedVector3Array:
	var job: FeatureEdgeJob = FeatureEdgeJob.for_mesh(mesh, crease_deg, weld_m)
	job.step()
	return job.lines()


## A mesh of the lines, with no surface when there are none.
static func line_mesh(lines: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if lines.size() < 2:
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh
