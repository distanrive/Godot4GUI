class_name Colormaps
extends RefCounted
## 色标（colormap）注册表——把标量强度映射成颜色，供伪彩图 `IntensityMap` 与色标条使用。
##
## 默认色标 `rainbow` 与 matplotlib 的 `cmap='rainbow'` **完全一致**：
##     R = clamp(|2t - 0.5|, 0, 1)      G = sin(π·t)      B = cos(π·t/2)
## （已与原版逐点数值比对，256 级上误差 < 1e-7），因此 Godot 端可以直接复刻
## matplotlib 出图的观感，后端不必依赖 matplotlib —— 详见 `docs/plotting-alternatives.md`。
##
## 想统一换配色：优先给控件设 `colormap` 名；要新增/改配方就只改本文件，
## 不要在控件里写死颜色。色标条、伪彩图、图例全部走这里，因此天然一致。
##
## 用法：
##   Colormaps.texture("rainbow")      # -> GradientTexture1D（带缓存），供着色器采样
##   Colormaps.gradient("rainbow")     # -> Gradient 资源
##   Colormaps.sample("rainbow", 0.5)  # -> Color（CPU 端取色，画图例/测试用）

## 默认色标名（取值见 `ThemePalette.CMAP_DEFAULT`，改样式只改令牌文件）。
const DEFAULT := ThemePalette.CMAP_DEFAULT

## 色标采样级数：与 matplotlib 的默认 LUT 级数一致（256），误差不可见。
const SAMPLES := 256

## matplotlib `jet` 的分段定义（分段线性，采样后与原版一致）。
const _JET := {
	"r": [[0.0, 0.0], [0.35, 0.0], [0.66, 1.0], [0.89, 1.0], [1.0, 0.5]],
	"g": [[0.0, 0.0], [0.125, 0.0], [0.375, 1.0], [0.64, 1.0], [0.91, 0.0], [1.0, 0.0]],
	"b": [[0.0, 0.5], [0.11, 1.0], [0.34, 1.0], [0.65, 0.0], [1.0, 0.0]],
}

static var _gradients: Dictionary = {}
static var _textures: Dictionary = {}


## 全部可用的色标名（下拉框/循环切换用）。
static func names() -> PackedStringArray:
	return PackedStringArray(["rainbow", "jet", "gray"])


## 取色标在 t∈[0,1] 处的颜色。
static func sample(name: String, t: float) -> Color:
	var x := clampf(t, 0.0, 1.0)
	match name:
		"jet":
			return Color(_seg(x, _JET["r"]), _seg(x, _JET["g"]), _seg(x, _JET["b"]))
		"gray":
			return Color(x, x, x)
		_:
			# matplotlib rainbow：R 分段线性（>0.75 被钳到 1），G/B 为正弦/余弦
			return Color(
				clampf(absf(2.0 * x - 0.5), 0.0, 1.0),
				sin(PI * x),
				cos(PI * x * 0.5))


## 取色标对应的 Gradient（带缓存，可反复取用）。
static func gradient(name: String) -> Gradient:
	name = _resolve(name)
	if _gradients.has(name):
		return _gradients[name]

	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	offsets.resize(SAMPLES)
	colors.resize(SAMPLES)
	for i in SAMPLES:
		var t := float(i) / float(SAMPLES - 1)
		offsets[i] = t
		colors[i] = sample(name, t)

	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	g.offsets = offsets
	g.colors = colors
	_gradients[name] = g
	return g


## 取色标对应的 1D 纹理（带缓存）；伪彩图着色器与色标条都用它，保证两边一致。
static func texture(name: String) -> GradientTexture1D:
	name = _resolve(name)
	if _textures.has(name):
		return _textures[name]

	var tex := GradientTexture1D.new()
	tex.gradient = gradient(name)
	tex.width = SAMPLES
	tex.use_hdr = false
	_textures[name] = tex
	return tex


## 名字不存在时回退到默认色标，避免控件因拼错而变黑。
static func _resolve(name: String) -> String:
	return name if names().has(name) else DEFAULT


## 分段线性查表：table 为 [[x0, y0], [x1, y1], ...]，x 升序。
static func _seg(t: float, table: Array) -> float:
	if t <= float(table[0][0]):
		return float(table[0][1])
	var last: Array = table[table.size() - 1]
	if t >= float(last[0]):
		return float(last[1])
	for i in range(table.size() - 1):
		var a: Array = table[i]
		var b: Array = table[i + 1]
		var x0 := float(a[0])
		var x1 := float(b[0])
		if t <= x1:
			var w := (t - x0) / maxf(x1 - x0, 1e-9)
			return lerpf(float(a[1]), float(b[1]), w)
	return float(last[1])
