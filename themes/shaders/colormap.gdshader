shader_type canvas_item;
render_mode unshaded;

// 伪彩着色器：把「单通道强度纹理」按色标（colormap）着色。
//
// 为什么这么画：强度图每个像素只有一个标量（光强）。把「标量 → 颜色」交给 GPU 之后，
// 「换配色」「调显示范围」「调伽马」都只是改 uniform —— 不用重算、不用重新上传数据。
// 纹理用 FORMAT_RF（32 位浮点单通道）：原样存光强，不做量化，动态范围再大也不失真。
//
// 实测坑（Godot 4.7 + gl_compatibility）：
//   1) canvas_item 的 fragment 里，COLOR **已经乘过纹理采样**了。
//      所以着色时写 `COLOR = vec4(c, 1.0);` 就行；再写 `* COLOR` 会把整幅图压暗
//      （这正是最初「图像一片黑/一片红」的原因）。
//   2) 纹理用 NEAREST 采样：一是保证逐格显示（和 pcolormesh 的方格一致），
//      二是浮点纹理的线性过滤在部分老 GPU/虚拟机上要额外扩展。
//
// 由 IntensityMap 使用：
//   TEXTURE  —— 强度纹理（TextureRect.texture，FORMAT_RF）
//   colormap —— 一维色标纹理（Colormaps.texture()，与色标条共用同一张，保证两边一致）
//   vmin/vmax —— 显示范围（原始强度单位），用于自动量程 / 增益调节
//   gamma    —— 伽马（>1 提亮暗部细节，看弱条纹常用）

uniform sampler2D colormap : filter_linear, repeat_disable;
uniform float vmin = 0.0;
uniform float vmax = 1.0;
uniform float gamma : hint_range(0.1, 4.0) = 1.0;

void fragment() {
	float raw = texture(TEXTURE, UV).r;
	float t = clamp((raw - vmin) / max(vmax - vmin, 1e-30), 0.0, 1.0);
	if (gamma != 1.0) {
		t = pow(t, gamma);
	}
	vec3 c = texture(colormap, vec2(t, 0.5)).rgb;
	COLOR = vec4(c, 1.0);
}
