/*
 * 模板自带的最小 GDExtension —— 把主窗口从任务栏上真的藏起来（以及再叫回来）。
 *
 * ============================ 为什么需要这个文件 ============================
 *
 * 「关窗后只剩托盘图标、任务栏上不留按钮」这件事，Godot 自己的 API 做不到：
 *
 *   1. `Window::set_visible()` 对**没有父节点**的窗口直接
 *      `ERR_FAIL_NULL_MSG(get_parent(), "Can't change visibility of main window.")`
 *      （scene/main/window.cpp）。主窗口就是 `get_tree().root`，没有父节点，
 *      所以 `hide()` 必然失败并在控制台留一行红色 ERROR。
 *   2. `DisplayServer` 没有任何 hide 类接口，最接近的只有 `window_set_mode(MINIMIZED)`。
 *   3. Windows 后端给主窗口**恒定**加 `WS_EX_APPWINDOW`（= 必须出现在任务栏），
 *      只有窗口带外部父 HWND 时才跳过 —— 那是编辑器把游戏内嵌进编辑器的路径，
 *      运行期拿不到（display_server_windows.cpp 的 `_get_window_style`）。
 *   4. `WINDOW_FLAG_POPUP` 明确拒绝主窗口（"Main window can't be popup."）。
 *
 * 于是只剩一条路：拿 `DisplayServer.window_get_native_handle()` 给出的 HWND，
 * 绕过引擎直接调 Win32 的 `ShowWindow`。GDScript 调不了 Win32，所以需要这一层。
 *
 * ======================= 为什么是手写 C 而不是 godot-cpp =======================
 *
 * 本文件只包两个函数。为一个 `ShowWindow` 拉一整套 godot-cpp（几百 MB 的仓库 +
 * 一次长编译）不划算：这里直接 include Godot 的 `gdextension_interface.h`
 * （已在本目录 vendored 一份），用 C 写完整套注册流程。
 * 代价是这份代码与 Godot 的 ABI **版本绑定** —— 升级引擎版本时要照着新版头文件核对。
 * 本工程固定 4.7.2，所以没问题；真要升级，先跑 `tools/self_check.gd` 里的那条探针。
 *
 * ============================== 踩过的坑（务必看） ==============================
 *
 * `GDExtensionPropertyInfo.class_name` **不能给 NULL**。头文件里它是个指针，
 * 看上去「没有类」就该填 NULL，但 Godot 侧的 `PropertyInfo(const GDExtensionPropertyInfo &)`
 * 是无条件解引用的：
 *
 *     class_name = *reinterpret_cast<const StringName *>(pinfo.class_name);
 *
 * 给 NULL 就是一次空指针解引用 —— 表现为**加载扩展时整个进程直接 signal 11 崩溃**，
 * 而且崩在 Godot 自己的代码里、堆栈没有符号，非常难查。
 * 正确的做法是传一个**空的 StringName**（见 empty_class_name_sn）。
 * 同一个坑 `hint_string` 也有（它要的是空 `String`，不是 NULL）。
 *
 * ============================== 暴露给 GDScript ==============================
 *
 *   NativeWindow.hide_window(hwnd: int)          → ShowWindow(hwnd, SW_HIDE)
 *   NativeWindow.show_window(hwnd: int)          → ShowWindow(hwnd, SW_SHOW) + SetForegroundWindow
 *   NativeWindow.is_supported() -> bool          → 恒为 true（这个库只可能编在 Windows 上）
 *   NativeWindow.is_window_visible(hwnd) -> bool → IsWindowVisible（给自检断言用）
 *
 * 四个都是**静态方法**（`GDEXTENSION_METHOD_FLAG_STATIC`）。GDScript 侧请用
 * `ClassDB.class_call_static(&"NativeWindow", &"hide_window", hwnd)` 这种**动态**写法调，
 * 不要在业务脚本里直接写类名 —— 那样 .dll 一旦缺失，整个脚本会编译不过。
 */

#include "gdextension_interface.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define GDE_EXPORT __declspec(dllexport)
#else
#define GDE_EXPORT __attribute__((visibility("default")))
#endif

/* ---------------------------------------------------------------- 不透明对象的存放
 *
 * 4.7 的接口头把这些类型定义成 `void *`（`GDExtensionStringNamePtr` 之类），
 * **头文件里看不出真实对象有多大** —— 那件事只有 godot-cpp 知道。
 * 所以这里自己开一块足够大的、8 字节对齐的存放区。
 *
 * 实测尺寸（Godot 4.x）：`String` / `StringName` 各 8 字节（内部是一个 `_Data*`），
 * `Variant` 24 字节。这里统一给 32 字节 —— 多要一点是无害的（Godot 只写它自己那部分），
 * 关键是**对齐**要对，这几个类型都要求 8。
 */
typedef union {
	uint64_t _align;
	uint8_t _bytes[32];
} gde_storage;

enum { SLOT_HIDE = 0, SLOT_SHOW = 1, SLOT_SUPPORTED = 2, SLOT_VISIBLE = 3, SLOT_COUNT = 4 };

static gde_storage class_name_sn;
static gde_storage parent_class_sn;
static gde_storage empty_class_name_sn;      /* 见文件头「踩过的坑」 */
static gde_storage method_name_sn[SLOT_COUNT];
static gde_storage arg_name_sn;
static gde_storage ret_name_sn;
static gde_storage hint_string_str;

/* ---------------------------------------------------------------- 从 Godot 借来的接口 */
static GDExtensionInterfaceStringNameNewWithUtf8Chars fn_string_name_new;
static GDExtensionInterfaceStringNewWithUtf8Chars fn_string_new;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 fn_register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod fn_register_method;
static GDExtensionInterfaceGetVariantToTypeConstructor fn_get_to_type_ctor;
static GDExtensionVariantFromTypeConstructorFunc fn_from_type_ctor_bool;

static GDExtensionClassLibraryPtr library_ptr;

/* ---------------------------------------------------------------- 参数 / 返回值转换 */

/* Variant → int64。接口里没有「直接读 int」的调用，得先拿一个转换函数。 */
static int64_t variant_to_int64(GDExtensionVariantPtr v) {
	int64_t out = 0;
	GDExtensionTypeFromVariantConstructorFunc ctor =
			fn_get_to_type_ctor(GDEXTENSION_VARIANT_TYPE_INT);
	if (ctor != NULL) {
		ctor(&out, v);
	}
	return out;
}

/* ---------------------------------------------------------------- 两个干活的方法
 *
 * 每个方法都给两个版本：Variant 版（GDScript 调用走这条）和 ptrcall 版
 * （引擎内部走这条）。**两个都要给** —— 只给 Variant 版的话，某些调用路径会因为
 * ptrcall 不可用而失败；只给 ptrcall 版则会丢掉 GDScript 的动态调用。
 */

static void call_hide(void *ud, GDExtensionClassInstancePtr inst,
		const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
		GDExtensionVariantPtr ret, GDExtensionCallError *err) {
	(void)ud; (void)inst; (void)ret;
	if (argc < 1) {
		if (err != NULL) {
			err->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		}
		return;
	}
	int64_t hwnd = variant_to_int64((GDExtensionVariantPtr)args[0]);
#ifdef _WIN32
	ShowWindow((HWND)(intptr_t)hwnd, SW_HIDE);
#else
	(void)hwnd;
#endif
}

static void ptrcall_hide(void *ud, GDExtensionClassInstancePtr inst,
		const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	(void)ud; (void)inst; (void)ret;
#ifdef _WIN32
	ShowWindow((HWND)(intptr_t)(*(const int64_t *)args[0]), SW_HIDE);
#else
	(void)args;
#endif
}

static void call_show(void *ud, GDExtensionClassInstancePtr inst,
		const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
		GDExtensionVariantPtr ret, GDExtensionCallError *err) {
	(void)ud; (void)inst; (void)ret;
	if (argc < 1) {
		if (err != NULL) {
			err->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		}
		return;
	}
	int64_t hwnd = variant_to_int64((GDExtensionVariantPtr)args[0]);
#ifdef _WIN32
	ShowWindow((HWND)(intptr_t)hwnd, SW_SHOW);
	/* 用户是从托盘点回来的，补一次置前，免得窗口出现在底下没被注意到 */
	SetForegroundWindow((HWND)(intptr_t)hwnd);
#else
	(void)hwnd;
#endif
}

static void ptrcall_show(void *ud, GDExtensionClassInstancePtr inst,
		const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	(void)ud; (void)inst; (void)ret;
#ifdef _WIN32
	HWND h = (HWND)(intptr_t)(*(const int64_t *)args[0]);
	ShowWindow(h, SW_SHOW);
	SetForegroundWindow(h);
#else
	(void)args;
#endif
}

/* is_supported()：这个库只可能编在 Windows 上，所以恒真。
 * 留着它是为了让 GDScript 侧有个「先探一下再调」的写法。 */
static void call_is_supported(void *ud, GDExtensionClassInstancePtr inst,
		const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
		GDExtensionVariantPtr ret, GDExtensionCallError *err) {
	(void)ud; (void)inst; (void)args; (void)argc; (void)err;
	GDExtensionBool yes = 1;
	if (fn_from_type_ctor_bool != NULL) {
		fn_from_type_ctor_bool(ret, &yes);
	}
}

static void ptrcall_is_supported(void *ud, GDExtensionClassInstancePtr inst,
		const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	(void)ud; (void)inst; (void)args;
	*(GDExtensionBool *)ret = 1;
}

/* is_window_visible(hwnd) -> bool：包的是 Win32 的 `IsWindowVisible`。
 *
 * 它唯一的用途是**让自检能断言「隐藏真的生效了」** —— 否则「隐藏成功」这件事
 * 在自动化测试里完全不可观测（GDScript 看不到窗口系统）。 */
static void call_is_visible(void *ud, GDExtensionClassInstancePtr inst,
		const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
		GDExtensionVariantPtr ret, GDExtensionCallError *err) {
	(void)ud; (void)inst; (void)argc; (void)err;
	GDExtensionBool visible = 0;
#ifdef _WIN32
	int64_t hwnd = variant_to_int64((GDExtensionVariantPtr)args[0]);
	visible = IsWindowVisible((HWND)(intptr_t)hwnd) ? 1 : 0;
#else
	(void)args;
#endif
	if (fn_from_type_ctor_bool != NULL) {
		fn_from_type_ctor_bool(ret, &visible);
	}
}

static void ptrcall_is_visible(void *ud, GDExtensionClassInstancePtr inst,
		const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	(void)ud; (void)inst;
	GDExtensionBool visible = 0;
#ifdef _WIN32
	visible = IsWindowVisible((HWND)(intptr_t)(*(const int64_t *)args[0])) ? 1 : 0;
#else
	(void)args;
#endif
	*(GDExtensionBool *)ret = visible;
}

/* ---------------------------------------------------------------- 注册 */

static void make_string_name(gde_storage *dest, const char *text) {
	fn_string_name_new((GDExtensionUninitializedStringNamePtr)dest, text);
}

/* 填一个 PropertyInfo。`class_name`/`hint_string` 必须指向**有效对象**，不能是 NULL
 * （见文件头的「踩过的坑」）。 */
static void fill_property(GDExtensionPropertyInfo *p, GDExtensionVariantType type,
		GDExtensionStringNamePtr name) {
	memset(p, 0, sizeof(*p));
	p->type = type;
	p->name = name;
	p->class_name = (GDExtensionStringNamePtr)&empty_class_name_sn;
	p->hint = 0;                                              /* PROPERTY_HINT_NONE */
	p->hint_string = (GDExtensionStringPtr)&hint_string_str;
	p->usage = 6;                                             /* STORAGE | EDITOR */
}

/* 把方法挂到类上。kind：0 = (int) -> void，1 = () -> bool，2 = (int) -> bool。 */
static void register_method(const char *name, int slot, int kind,
		GDExtensionClassMethodCall call, GDExtensionClassMethodPtrCall ptrcall) {
	GDExtensionPropertyInfo args[1];
	GDExtensionPropertyInfo ret_info;
	GDExtensionClassMethodArgumentMetadata meta[1];
	GDExtensionClassMethodInfo info;

	make_string_name(&method_name_sn[slot], name);

	memset(&info, 0, sizeof(info));
	info.name = (GDExtensionStringNamePtr)&method_name_sn[slot];
	info.call_func = call;
	info.ptrcall_func = ptrcall;
	info.method_flags = GDEXTENSION_METHOD_FLAG_STATIC | GDEXTENSION_METHOD_FLAGS_DEFAULT;

	if (kind == 0 || kind == 2) {
		fill_property(&args[0], GDEXTENSION_VARIANT_TYPE_INT,
				(GDExtensionStringNamePtr)&arg_name_sn);
		meta[0] = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
		info.argument_count = 1;
		info.arguments_info = args;
		info.arguments_metadata = meta;
	} else {
		info.argument_count = 0;
	}

	if (kind == 0) {
		info.has_return_value = 0;
	} else {
		fill_property(&ret_info, GDEXTENSION_VARIANT_TYPE_BOOL,
				(GDExtensionStringNamePtr)&ret_name_sn);
		info.has_return_value = 1;
		info.return_value_info = &ret_info;
		info.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	}

	fn_register_method(library_ptr, (GDExtensionConstStringNamePtr)&class_name_sn, &info);
}

/* 类实例的构造 / 析构。我们的方法全是静态的、用不到实例，但
 * `GDExtensionClassCreationInfo6` 要求给（除非声明成 virtual 类）。
 * 给一对最朴素的实现：万一有人在 GDScript 里 `NativeWindow.new()` 也不会崩。 */
static GDExtensionObjectPtr create_instance(void *ud, GDExtensionBool notify_postinitialize) {
	(void)ud;
	(void)notify_postinitialize;
	return (GDExtensionObjectPtr)malloc(1);
}

static void free_instance(void *ud, GDExtensionClassInstancePtr inst) {
	(void)ud;
	free((void *)inst);
}

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE) {
		return;
	}

	/* 注册时要用到的几个名字，先造好 —— 它们要活到扩展卸载为止，
	 * 所以放在 static 存放区里、不释放。 */
	make_string_name(&class_name_sn, "NativeWindow");
	make_string_name(&parent_class_sn, "Object");
	make_string_name(&empty_class_name_sn, "");
	make_string_name(&arg_name_sn, "hwnd");
	make_string_name(&ret_name_sn, "supported");
	fn_string_new((GDExtensionUninitializedStringPtr)&hint_string_str, "");

	GDExtensionClassCreationInfo6 info;
	memset(&info, 0, sizeof(info));
	info.is_exposed = 1;
	info.create_instance_func = create_instance;
	info.free_instance_func = free_instance;
	fn_register_class(library_ptr,
			(GDExtensionConstStringNamePtr)&class_name_sn,
			(GDExtensionConstStringNamePtr)&parent_class_sn, &info);

	register_method("hide_window", SLOT_HIDE, 0, call_hide, ptrcall_hide);
	register_method("show_window", SLOT_SHOW, 0, call_show, ptrcall_show);
	register_method("is_supported", SLOT_SUPPORTED, 1, call_is_supported, ptrcall_is_supported);
	register_method("is_window_visible", SLOT_VISIBLE, 2,
			call_is_visible, ptrcall_is_visible);
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	(void)level;
}

/* ---------------------------------------------------------------- 入口 */

GDE_EXPORT GDExtensionBool godot4gui_native_window_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	library_ptr = p_library;

	/* 取接口函数。名字必须与 gdextension_interface.h 里的 `@name` 一字不差。
	 * 任何一个取不到都直接返回 0 —— 让 Godot 报「扩展加载失败」，
	 * 比带着空函数指针跑下去、在某个随机时刻崩掉要好查得多。 */
	GDExtensionInterfaceFunctionPtr p;

#define LOAD(var, name) \
	do { \
		p = p_get_proc_address(name); \
		if (p == NULL) { \
			return 0; \
		} \
		var = (void *)p; \
	} while (0)

	LOAD(fn_string_name_new, "string_name_new_with_utf8_chars");
	LOAD(fn_string_new, "string_new_with_utf8_chars");
	LOAD(fn_register_class, "classdb_register_extension_class6");
	LOAD(fn_register_method, "classdb_register_extension_class_method");
	LOAD(fn_get_to_type_ctor, "get_variant_to_type_constructor");
#undef LOAD

	p = p_get_proc_address("get_variant_from_type_constructor");
	if (p == NULL) {
		return 0;
	}
	{
		typedef GDExtensionVariantFromTypeConstructorFunc (*get_from_ctor_t)(GDExtensionVariantType);
		fn_from_type_ctor_bool = ((get_from_ctor_t)p)(GDEXTENSION_VARIANT_TYPE_BOOL);
		if (fn_from_type_ctor_bool == NULL) {
			return 0;
		}
	}

	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = NULL;
	r_initialization->initialize = initialize;
	r_initialization->deinitialize = deinitialize;
	return 1;
}
