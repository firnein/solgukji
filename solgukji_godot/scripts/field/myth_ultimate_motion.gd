extends RefCounted
## Caster choreography for myth ultimates, layered over the existing figure atlas.
## Profile: motion, travel, rise, lean, beats, recovery time.

enum Motion { SWEEP, ROAR, CHARGE, SHOT, COMMAND, INVOKE, EMBER, RESTORE, DECOY, AMBUSH, FIRE_WAVE, CRESCENT, WHIRLWIND }

const PROFILES := {
	"c177": [Motion.CRESCENT, 1.18, 0.62, 0.88, 1, 0.92], # Cheongryong crescent slash
	"c178": [Motion.ROAR, 0.04, 0.20, 0.28, 2, 0.74], # Changban roar
	"c179": [Motion.CHARGE, 0.42, 0.11, 0.34, 1, 0.55], # Lone rider rescue
	"c180": [Motion.CHARGE, 0.35, 0.18, 0.30, 2, 0.66], # Young conqueror's rush
	"c181": [Motion.WHIRLWIND, 0.92, 0.83, 0.95, 3, 1.02], # Peerless whirlwind
	"c182": [Motion.CHARGE, 0.50, 0.06, 0.42, 1, 0.46], # Zhang Liao's breakthrough
	"c183": [Motion.EMBER, 0.14, 0.25, 0.36, 2, 0.78], # Luoyang conflagration
	"c184": [Motion.SHOT, 0.21, 0.11, 0.28, 3, 0.73], # Gale bow
	"c185": [Motion.SHOT, 0.28, 0.16, 0.35, 2, 0.63], # Twin halberds
	"c186": [Motion.COMMAND, 0.12, 0.17, 0.22, 1, 0.72], # Banner of Jiangdong
	"c187": [Motion.INVOKE, 0.05, 0.28, 0.24, 2, 0.84], # Eight formations
	"c188": [Motion.DECOY, 0.10, 0.16, 0.19, 3, 0.83], # Ten victories
	"c189": [Motion.EMBER, 0.13, 0.18, 0.23, 3, 0.82], # Yiling fire trail
	"c190": [Motion.RESTORE, 0.08, 0.19, 0.15, 1, 0.87], # Banner of benevolence
	"c191": [Motion.COMMAND, 0.07, 0.12, 0.15, 2, 0.76], # Counsel of a kingmaker
	"c192": [Motion.INVOKE, 0.09, 0.34, 0.33, 1, 0.88], # Yellow Heaven
	"c193": [Motion.RESTORE, 0.05, 0.15, 0.24, 5, 0.95], # Five animal frolics
	"c194": [Motion.COMMAND, 0.18, 0.21, 0.29, 2, 0.70], # Hero of troubled times
	"c195": [Motion.FIRE_WAVE, 1.02, 0.92, 0.72, 1, 1.18], # Red Cliffs fire wave
	"c196": [Motion.DECOY, 0.12, 0.20, 0.32, 2, 0.94], # Chain stratagem
	"c197": [Motion.AMBUSH, 0.35, 0.13, 0.37, 2, 0.65], # Hundred riders
	"c198": [Motion.AMBUSH, 0.29, 0.06, 0.23, 1, 0.82], # White-clad river crossing
	"c199": [Motion.AMBUSH, 0.47, 0.24, 0.43, 1, 0.57], # Ziwu valley ambush
	"s03": [Motion.ROAR, 0.19, 0.23, 0.37, 1, 0.60], # Xiahou Dun's defiance
	"s10": [Motion.COMMAND, 0.04, 0.11, 0.12, 1, 0.84], # Master Water Mirror's recommendation
	"s13": [Motion.DECOY, 0.22, 0.24, 0.35, 3, 0.79], # Disappearing orange
	"s17": [Motion.AMBUSH, 0.12, 0.19, 0.24, 2, 0.82], # Resolve at White Gate
	"L50": [Motion.DECOY, 0.08, 0.09, 0.37, 1, 0.76], # Wolf glance
	"L51": [Motion.SWEEP, 0.46, 0.18, 0.50, 2, 0.66], # 호치 허저 —— 불멸 맹공을 크게
	"L52": [Motion.SHOT, 0.30, 0.11, 0.28, 2, 0.74], # 노익장 황충 —— 백보천양
	"L53": [Motion.INVOKE, 0.09, 0.27, 0.32, 2, 0.84], # 오두미천사 장로 —— 오두미도
}

# Alternate grades of the same commander share the gesture, with smaller movement.
const IMMORTAL_VARIANTS := {
	"L02": "c178", "s02": "s03", "s01": "c177", "L05": "c179",
	"c156": "c182", "c158": "c183", "L38": "c181", "L08": "c180",
	"c162": "c185", "c163": "c186", "c161": "c184", "c164": "c197",
	"c165": "c198", "c166": "c199", "c169": "c195", "c168": "c189",
	"L12": "c187", "s07": "c190", "c172": "c191", "s14": "c192",
	"c175": "L50", "L17": "c194", "L49": "s17",
}

const IMMORTAL_PROFILES := {
	"s05": [Motion.CHARGE, 0.49, 0.08, 0.33, 1, 0.55], # Xu Huang breaks the encirclement
	"c153": [Motion.SWEEP, 0.40, 0.16, 0.46, 2, 0.61], # Xu Chu's ferocious assault
	"c155": [Motion.CHARGE, 0.59, 0.13, 0.40, 2, 0.60], # Ma Chao leads the Xiliang cavalry
	"c159": [Motion.COMMAND, 0.14, 0.19, 0.24, 2, 0.72], # Yuan Shao rallies the army
	"c160": [Motion.SHOT, 0.28, 0.09, 0.24, 1, 0.70], # Huang Zhong's single precise shot
	"c170": [Motion.INVOKE, 0.18, 0.23, 0.27, 3, 0.78], # Jiang Wei's northern expeditions
	"s08": [Motion.AMBUSH, 0.24, 0.16, 0.22, 1, 0.76], # Fa Zheng's Dingjun plan
	"c173": [Motion.INVOKE, 0.08, 0.23, 0.29, 2, 0.77], # Zhang Lu invokes the Five Pecks
}

static func _profile(card: String) -> Array:
	var source: String = IMMORTAL_VARIANTS.get(card, card)
	return PROFILES.get(source, IMMORTAL_PROFILES.get(card, []))

const INACTIVE := Vector4(0.0, 0.0, 0.0, -1.0)

## X is the forward offset in soldier heights, Y is the rise, Z is lean, W is the atlas pose.
static func sample(card: String, phase: String, age: float, life: float) -> Vector4:
	var motion := _sample_ultimate(card, phase, age, life)
	if motion.w >= 0.0:
		if phase == "impact":
			var prep := _sample_ultimate(card, "charge", 0.549, 0.55)
			var release := smoothstep(0.0, minf(0.16, life * 0.3), age)
			motion = Vector4(
				lerpf(prep.x, motion.x, release),
				lerpf(prep.y, motion.y, release),
				lerpf(prep.z, motion.z, release),
				prep.w if release < 0.4 else motion.w)
		elif phase == "dash":
			var blend := smoothstep(0.0, 0.10, age) * (1.0 - smoothstep(maxf(0.1, life - 0.16), life, age))
			motion = Vector4(motion.x * blend, motion.y * blend, motion.z * blend, motion.w)
	if motion.w >= 0.0 and (IMMORTAL_VARIANTS.has(card) or IMMORTAL_PROFILES.has(card)):
		return Vector4(motion.x * 0.72, motion.y * 0.72, motion.z * 0.78, motion.w)
	return motion


static func _sample_ultimate(card: String, phase: String, age: float, life: float) -> Vector4:
	var profile := _profile(card)
	if age < 0.0 or age >= life:
		return INACTIVE
	if profile.is_empty():
		profile = [Motion.SWEEP, 0.38, 0.18, 0.34, 1, 0.7]
	var motion: int = profile[0]
	var travel: float = profile[1]
	var rise: float = profile[2]
	var lean: float = profile[3]
	var beats: float = profile[4]
	if phase == "charge":
		if motion == Motion.WHIRLWIND:
			var coil := smoothstep(0.0, life * 0.88, age)
			return Vector4(-0.46 * coil, -0.19 * coil, -0.82 * coil, 1.0)
		if motion == Motion.CRESCENT:
			var windup := smoothstep(0.0, life * 0.78, age)
			return Vector4(-0.62 * windup, 0.27 * windup, -0.67 * windup, 1.0)
		if motion == Motion.FIRE_WAVE:
			var draw_back := smoothstep(0.0, life * 0.68, age)
			var brace := smoothstep(life * 0.48, life, age)
			return Vector4(-0.65 * draw_back, 0.5 * brace, -0.52 * draw_back, 1.0)
		var p := smoothstep(0.0, maxf(0.01, life * 0.76), age)
		var retreat := motion in [Motion.SWEEP, Motion.CHARGE, Motion.SHOT, Motion.AMBUSH]
		return Vector4(-travel * 0.55 * p if retreat else 0.0, rise * 0.38 * p,
			-lean * 0.58 * p, 1.0 if p > 0.06 else 0.0)
	if phase == "dash":
		var bounce := pow(absf(sin(age * (15.0 + beats * 2.0))), 2.0)
		return Vector4(travel * 0.36, rise * bounce, lean * 0.70, 2.0)
	var duration := minf(life, float(profile[5]))
	if phase != "impact" or age >= duration:
		return INACTIVE
	var t := age / duration
	var settle := 1.0 - smoothstep(0.58, 1.0, t)
	var pulse := sin(PI * beats * t)
	var lift := absf(pulse)
	var strike := (0.45 + 0.55 * smoothstep(0.0, 0.16, t)) * settle
	var pose := 1.0 if t > 0.76 else 2.0
	match motion:
		Motion.SWEEP:
			return Vector4(travel * strike, rise * lift * settle, lean * pulse * settle, pose)
		Motion.ROAR:
			return Vector4(travel * lift * settle, rise * strike, -lean * strike, pose)
		Motion.CHARGE:
			return Vector4(travel * strike, rise * lift * settle, lean * strike, pose)
		Motion.SHOT:
			var recoil := strike if beats <= 1.0 else lift * settle
			return Vector4(-travel * recoil, rise * recoil, -lean * recoil, 1.0 if recoil < 0.26 else pose)
		Motion.COMMAND:
			return Vector4(travel * strike, rise * lift * settle, lean * strike * 0.45, pose)
		Motion.INVOKE:
			return Vector4(-travel * strike, rise * strike, -lean * pulse * settle, pose)
		Motion.EMBER:
			return Vector4(travel * lift * settle, rise * strike, lean * pulse * settle, pose)
		Motion.WHIRLWIND:
			var swing := sin(TAU * beats * t)
			var leap := sin(PI * smoothstep(0.0, 0.78, t))
			return Vector4(travel * (0.55 + 0.38 * swing) * strike,
				rise * leap, lean * swing * settle, 2.0 if swing > -0.40 and t < 0.82 else 1.0)
		Motion.CRESCENT:
			var follow := 1.0 - smoothstep(0.20, 0.88, t)
			var arc := sin(PI * smoothstep(0.0, 0.63, t))
			return Vector4(travel * follow, rise * arc, lean * follow - 0.14 * arc, pose)
		Motion.FIRE_WAVE:
			var release := 1.0 - smoothstep(0.24, 0.92, t)
			var arc := sin(PI * smoothstep(0.0, 0.68, t))
			return Vector4(travel * release, rise * arc, lean * release - 0.22 * arc, pose)
		Motion.RESTORE:
			return Vector4(0.0, rise * lift * settle, -lean * strike, pose)
		Motion.DECOY:
			return Vector4(-travel * lift * settle, rise * strike, lean * pulse * settle, pose)
		Motion.AMBUSH:
			var pounce := pow(lift, 0.55) * settle
			return Vector4(travel * pounce, rise * pounce, lean * pounce, pose)
	return INACTIVE



## Ordinary skills wind up into the real hit delay and use a shorter recovery than ultimates.
static func sample_skill(card: String, style: String, kind: String, age: float, delay: float) -> Vector4:
	var profile := _profile(card)
	var weight := 0.9
	if not profile.is_empty():
		weight = 0.72 + float(profile[1]) * 0.36 + float(profile[3]) * 0.24
	var windup := maxf(0.05, delay)
	const RELEASE := 0.10
	const RECOVERY := 0.38
	var brace := Vector3(-0.21, 0.08, -0.17) * weight
	if age < 0.0 or age >= windup + RELEASE + RECOVERY:
		return INACTIVE
	if age < windup:
		var t := smoothstep(0.0, windup, age)
		return Vector4(brace.x * t, brace.y * t, brace.z * t, 1.0 if t > 0.18 else 0.0)
	var elapsed := age - windup
	if elapsed < RELEASE:
		var t := smoothstep(0.0, RELEASE, elapsed)
		var attack := _skill_release(style, kind, 0.0, weight)
		return Vector4(lerpf(brace.x, attack.x, t), lerpf(brace.y, attack.y, t),
			lerpf(brace.z, attack.z, t), 1.0 if t < 0.42 else 2.0)
	return _skill_release(style, kind, (elapsed - RELEASE) / RECOVERY, weight)


static func _skill_release(style: String, kind: String, t: float, weight: float) -> Vector4:
	var snap := (1.0 - smoothstep(0.12, 1.0, t)) * weight
	var lift := sin(PI * t) * weight
	var pose := 2.0 if t < 0.76 else 0.0
	match style:
		"charge", "pierce":
			return Vector4(0.62 * snap, 0.13 * lift, 0.30 * snap, pose)
		"arrows":
			return Vector4(-0.23 * snap, 0.12 * lift, -0.22 * snap, pose)
		"shadow":
			return Vector4(0.48 * snap, -0.16 * lift, 0.31 * snap, pose)
		"slash":
			return Vector4(0.29 * snap, 0.19 * lift, 0.34 * snap, pose)
		"heal":
			return Vector4(0.0, 0.27 * lift, -0.14 * snap, pose)
	if kind == "phys":
		return Vector4(0.31 * snap, 0.16 * lift, 0.25 * snap, pose)
	return Vector4(0.13 * snap, 0.24 * lift, 0.21 * snap, pose)

## Q uses a short, distinct release gesture based on the actual skill style.
static func sample_q(style: String, kind: String, age: float, delay: float) -> Vector4:
	var travel := 0.32
	var rise := 0.18
	var lean := 0.36
	match style:
		"pierce", "charge", "dash":
			travel = 0.78
		"arrows", "arrow", "volley":
			travel = -0.34
			lean = -0.32
		"heal", "guard", "aura", "buff":
			travel = 0.0
			rise = 0.34
			lean = -0.16
		"shadow", "steal":
			travel = 0.52
			rise = -0.19
		_:
			if kind == "int":
				travel = 0.11
				rise = 0.38
	var windup := maxf(0.05, delay)
	const RELEASE := 0.12
	const RECOVERY := 0.38
	if age < 0.0 or age >= windup + RELEASE + RECOVERY:
		return INACTIVE
	var rest := Vector3.ZERO
	var brace := Vector3(-absf(travel) * 0.35, -0.08, -lean * 0.55)
	var strike := Vector3(travel, rise, lean)
	var offset: Vector3
	var pose: float
	if age < windup:
		var t := smoothstep(0.0, windup, age)
		offset = rest.lerp(brace, t)
		pose = 1.0 if t > 0.18 else 0.0
	elif age < windup + RELEASE:
		var t := smoothstep(0.0, RELEASE, age - windup)
		offset = brace.lerp(strike, t)
		pose = 2.0 if t > 0.42 else 1.0
	else:
		var t := smoothstep(0.0, RECOVERY, age - windup - RELEASE)
		offset = strike.lerp(rest, t)
		pose = 0.0 if t > 0.85 else 2.0
	return Vector4(offset.x, offset.y, offset.z, pose)
