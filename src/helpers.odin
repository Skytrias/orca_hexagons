package src

import "core:math"
import oc "core:sys/orca"

exp_interpolate :: proc(cur: ^f32, nxt, dt, rate: f32) {
	cur^ += (nxt - cur^) * (1 - math.pow_f32(rate, dt))
}
