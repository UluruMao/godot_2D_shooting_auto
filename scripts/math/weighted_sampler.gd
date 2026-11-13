class_name WeightedSampler
extends RefCounted
## O(n) categorical sampling. Invalid/zero weights are ineligible.

static func index_at(weights: PackedFloat64Array, unit_roll: float) -> int:
	if not is_finite(unit_roll) or unit_roll < 0.0 or unit_roll >= 1.0:
		return -1
	# Scale first to avoid overflow when summing very large finite weights.
	var largest := 0.0
	for weight in weights:
		if is_finite(weight) and weight > largest:
			largest = weight
	if largest <= 0.0:
		return -1
	var total := 0.0
	for weight in weights:
		if is_finite(weight) and weight > 0.0:
			total += weight / largest
	var threshold := unit_roll * total
	var last := -1
	for i in weights.size():
		if not is_finite(weights[i]) or weights[i] <= 0.0:
			continue
		last = i
		threshold -= weights[i] / largest
		if threshold < 0.0:
			return i
	return last

static func pick(weights: PackedFloat64Array, rng: RandomNumberGenerator) -> int:
	# randf() can include its upper endpoint; clamp to the last valid quantile.
	return index_at(weights, minf(rng.randf(), 0.9999999999999999))
