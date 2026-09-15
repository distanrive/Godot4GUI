class_name Fmt
extends RefCounted
## 数字格式化小工具。
##
## 为什么需要它：GDScript 的 `%` 运算符只认 %d/%f/%s/%x/%o/%c/%%，
## **不支持 C 的 %e / %g**（写了会运行时报 "unsupported format character"），
## 而工控界面又常要按有效数字/科学计数法显示（光强能到 1e28）。
## 所以：科学计数法与「几位有效数字」在这里自己拼，全局统一口径。
##
## 用法：
##   Fmt.num(0.5)        # "0.5"
##   Fmt.num(123456.0)   # "1.23e5"
##   Fmt.num(1.0e28)     # "1.00e28"

## 按有效数字输出：数量级过大/过小时自动转科学计数法，并去掉多余的 0。
static func num(v: float, sig := 3) -> String:
	if is_nan(v):
		return "—"
	if is_inf(v):
		return "+∞" if v > 0.0 else "-∞"
	var a := absf(v)
	if a == 0.0:
		return "0"
	sig = clampi(sig, 1, 9)
	var exp := int(floor(log(a) / log(10.0)))
	if exp >= 5 or exp <= -4:
		return sci(v, sig)
	# 定点：小数位数 = 有效数字位数 - 整数部分位数
	var decimals := clampi(sig - 1 - exp, 0, 9)
	var s := String.num(v, decimals)
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s


## 科学计数法，如 "1.23e-05"（指数不加前导 0，读起来更短）。
static func sci(v: float, sig := 3) -> String:
	if v == 0.0 or not is_finite(v):
		return "0"
	var a := absf(v)
	var exp := int(floor(log(a) / log(10.0)))
	var mant := v / pow(10.0, exp)
	# 四舍五入后可能进位成 10.0（如 9.99e5 → 1.00e6），归一一下
	var rounded := float(String.num(mant, maxi(sig - 1, 0)))
	if absf(rounded) >= 10.0:
		mant /= 10.0
		exp += 1
	return "%se%d" % [String.num(mant, maxi(sig - 1, 0)), exp]


## 转成界面上的「显示单位」数值 + 单位后缀（默认 1e6，即 m → μm）。
static func scaled(v: float, scale := 1.0e6, sig := 3) -> String:
	return num(v * scale, sig)
