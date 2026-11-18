class_name StationSpin
extends RefCounted
## The station's drum turn (M7-T06, D74, Q9): an angle from the system's clock, so the drum stands at the same angle in every
## run at the same system time and a seek (M9's warp) lands it there too. Pure.

## The drum's spin, rad/s about the station's +Z (the manifest's `spin_rad_s`, 0.148).
var rate_rad_s: float = 0.0


func _init(p_rate_rad_s: float = 0.0) -> void:
	rate_rad_s = p_rate_rad_s


## The drum's turn at system time `time_s` (seconds), 0 to TAU.
func angle_at(time_s: float) -> float:
	return fposmod(rate_rad_s * time_s, TAU)


## How fast the drum's skin moves `radius_m` from its axis, m/s.
func surface_speed(radius_m: float) -> float:
	return absf(rate_rad_s) * radius_m
