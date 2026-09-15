"""Rayleigh-Sommerfeld 衍射模拟（逐距离流式输出）。

来源：近代光学基础作业脚本 `Rayleigh-Sommerfeld-assignment1.py`
（原文件保持原样、未做任何修改；本文件是**复制到本项目后的改写版**）。

改写点只有一个：原脚本是「先把 1000 个 z 全算完，再交给 matplotlib 画一张图」，
本模块改成「每算出一个 z 就产出一列数据」，于是 Godot 前端可以边算边画、
逐个距离刷新图像（见 `docs/plotting-alternatives.md`）。

物理与数值与原脚本完全一致：
  * 同一套屏函数（直径 D 的圆孔，孔内 U0 = 1）；
  * 同一个 Rayleigh-Sommerfeld 卷积核 g(z)；
  * 同一条 FFT 链路（ifftshift → fft2 → 频域相乘 → ifft2 → fftshift → 取 x=0 一行）；
  * 同一组默认参数（λ=0.5 μm、D=10 μm、L=100 μm、N=1000、z 从 0.1 μm 到 100 μm 步长 dx）。

归一化：原脚本在最后除以全矩阵最大值，这里改为**前端按「目前为止的最大值」在线归一化**
（最大值是着色器的一个 uniform），全部算完后得到的图像与原脚本逐像素一致。
"""

from __future__ import annotations

import ast
import json
import math
import os
from dataclasses import dataclass
from typing import Iterator

import numpy as np
from scipy.fft import fft2, ifft2, ifftshift, fftshift

__all__ = ["Config", "Simulation", "load_params", "PARAM_ALIASES"]

# 参数文件里的名字 -> 本模块的规范名（大小写不敏感，兼容原作业脚本的 lamda / D / L / N）
PARAM_ALIASES = {
    "lamda": "lamda",
    "lambda_": "lamda",
    "wavelength": "lamda",
    "d": "diameter",
    "diameter": "diameter",
    "l": "width",
    "width": "width",
    "n": "samples",
    "samples": "samples",
    "z_min": "z_min",
    "z_start": "z_min",
    "z_max": "z_max",
    "z_stop": "z_max",
    "z_stride": "z_stride",
    "ym": "y_window",          # 作业脚本里画图用的显示窗口 ±ym
    "y_window": "y_window",
    "y_max": "y_window",
}


@dataclass
class Config:
    """仿真参数（默认值 = 作业脚本里的原参数）。"""

    lamda: float = 0.5e-6      # 波长 (m)
    diameter: float = 10e-6    # 小孔直径 (m)
    width: float = 100e-6      # 模拟区域大小 (m)，需 L > 4D
    samples: int = 1000        # 采样点数 N
    z_min: float = 0.1e-6      # 起始距离 (m)
    z_max: float = 100e-6      # 终止距离 (m)
    z_stride: int = 1          # z 步进（1 = 每算一个 z 出一列，与原脚本一致）
    y_window: float = 10e-6    # 送往前端显示的 y 窗口 ±y_window（原脚本画图用的 ym）

    def __post_init__(self) -> None:
        self.samples = int(max(32, min(int(self.samples), 4096)))
        self.z_stride = int(max(1, int(self.z_stride)))
        self.lamda = float(self.lamda)
        self.diameter = float(self.diameter)
        self.width = float(self.width)
        self.z_min = float(self.z_min)
        self.z_max = float(self.z_max)
        self.y_window = float(self.y_window)
        if self.z_max < self.z_min:
            self.z_min, self.z_max = self.z_max, self.z_min
        if self.y_window <= 0.0:
            self.y_window = self.width / 2.0
        self._z_values = None

    @property
    def dx(self) -> float:
        """采样间隔（与原脚本 dx = L / N 相同）。"""
        return self.width / self.samples

    @property
    def wave_number(self) -> float:
        """波数 k = 2π/λ。"""
        return 2.0 * math.pi / self.lamda

    @property
    def z_values(self) -> np.ndarray:
        """参与计算的 z 序列（原脚本为 arange(z_min, z_max + dx, dx)，这里再按 z_stride 抽稀）。"""
        if self._z_values is None:
            dx = self.dx
            full = np.arange(self.z_min, self.z_max + dx, dx)
            self._z_values = full[:: self.z_stride]
        return self._z_values

    def as_dict(self) -> dict:
        return {
            "lamda": self.lamda,
            "diameter": self.diameter,
            "width": self.width,
            "samples": self.samples,
            "z_min": self.z_min,
            "z_max": self.z_max,
            "z_stride": self.z_stride,
            "y_window": self.y_window,
            "dx": self.dx,
            "columns": int(len(self.z_values)),
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Config":
        """按别名表从任意字典构造（缺项用默认值）。"""
        kwargs = {}
        for key, value in data.items():
            name = PARAM_ALIASES.get(str(key).strip().lower())
            if name is not None:
                kwargs[name] = value
        return cls(**kwargs)


class Simulation:
    """按作业脚本的数值方案，逐列产出 Z-Y 光强（一列 = 一个 z 处沿 y 的强度剖面）。"""

    def __init__(self, config: Config | None = None):
        self.cfg = config or Config()
        n = self.cfg.samples
        dx = self.cfg.dx

        # 生成衍射屏坐标网格（与作业脚本逐行对应）
        axis = (np.arange(n) - n // 2) * dx      # 从 -N/2·dx 到 (N/2-1)·dx
        x, y = np.meshgrid(axis, axis)
        self._x = x
        self._y = y

        # 画图窗口 |y| <= ym（原脚本的 ym），只把窗口内的数据发给前端显示
        mask = np.abs(axis) <= self.cfg.y_window
        idx = np.flatnonzero(mask)
        if idx.size == 0:                        # 窗口比采样间隔还小，退化为中心一行
            idx = np.array([n // 2])
        self._slice = slice(int(idx[0]), int(idx[-1]) + 1)
        self.y_values = axis[self._slice]

        # 屏函数：半径 D/2 内为 1，其余为 0
        r0 = np.sqrt(x ** 2 + y ** 2)
        u0 = np.where(r0 < self.cfg.diameter / 2.0,
                      np.complex128(1.0), np.complex128(0.0))

        # U0 的傅里叶变换是循环不变量：原脚本每步重算一次，这里提到循环外（结果逐位相同）
        self._u0_fft = fft2(ifftshift(u0))
        self._k = self.cfg.wave_number
        self._z_values = self.cfg.z_values

    # ---- 对外属性 ----
    @property
    def columns(self) -> int:
        return int(len(self._z_values))

    @property
    def rows(self) -> int:
        """送往前端的每列行数（= 画图窗口内的采样点数）。"""
        return int(self.y_values.size)

    @property
    def z_values(self) -> np.ndarray:
        return self._z_values

    # ---- 计算 ----
    def kernel(self, z: float) -> np.ndarray:
        """Rayleigh-Sommerfeld 卷积核 g(z)（与作业脚本 calculate_g 相同）。"""
        r = np.sqrt(self._x ** 2 + self._y ** 2 + z ** 2)
        with np.errstate(divide="ignore", invalid="ignore"):
            term = (-1.0 / (2.0 * np.pi)) * (z / r ** 3) \
                * (1j * self._k * r - 1.0) * np.exp(1j * self._k * r)
        return np.nan_to_num(term)

    def column(self, index: int) -> tuple[float, np.ndarray, float]:
        """算出第 index 个 z 处的光强剖面。

        返回 (z, 窗口内的强度数组, 整行峰值)：
        第三个值用于「按目前为止的全局最大值在线归一化」，它取自**整行**（与原脚本
        `numpy.max(intensity_yz)` 一致），而不是只看窗口，否则量程会偏小。
        """
        if index < 0 or index >= self.columns:
            raise IndexError(f"z 序号越界：{index} / {self.columns}")
        z = float(self._z_values[index])
        g_fft = fft2(ifftshift(self.kernel(z)))
        uz = fftshift(ifft2(g_fft * self._u0_fft))
        intensity = np.abs(uz) ** 2
        # x = 0（即第 N//2 行）处的光强分布
        row = intensity[self.cfg.samples // 2, :]
        return z, row[self._slice], float(row.max())

    def __iter__(self) -> Iterator[tuple[int, float, np.ndarray, float]]:
        for i in range(self.columns):
            z, row, peak = self.column(i)
            yield i, z, row, peak


# ---------------------------------------------------------------- 参数文件

def load_params(path: str) -> dict:
    """从参数文件读取仿真参数。

    支持两种格式：
      * `.json` —— 直接读字典；
      * `.py`   —— 用 `ast` **只解析模块级字面量常量**（不执行文件），
                   因此可以直接把作业脚本 `Rayleigh-Sommerfeld-assignment1.py`
                   拖进来，自动取出其中的 lamda / D / L / N 等参数。

    返回：规范化后的参数字典（只含文件里确实写了的项），附带 `"source"` 与 `"found"`。
    """
    if not path:
        raise ValueError("未指定参数文件路径")
    if not os.path.isfile(path):
        raise FileNotFoundError(f"文件不存在：{path}")

    ext = os.path.splitext(path)[1].lower()
    if ext == ".json":
        with open(path, "r", encoding="utf-8") as fh:
            raw = json.load(fh)
        if not isinstance(raw, dict):
            raise ValueError("JSON 参数文件的根节点必须是对象（字典）")
        found = {}
        for key, value in raw.items():
            name = PARAM_ALIASES.get(str(key).strip().lower())
            if name is not None:
                found[name] = value
    elif ext in (".py", ".pyw"):
        found = _read_python_constants(path)
    else:
        raise ValueError(f"不支持的参数文件类型：{ext}（请用 .json 或 .py）")

    if not found:
        raise ValueError(
            "文件里没有找到可识别的参数（支持 lamda/wavelength、D/diameter、"
            "L/width、N/samples、z_min/z_max/z_stride）")

    found["source"] = os.path.abspath(path)
    return found


def _read_python_constants(path: str) -> dict:
    """解析 .py 里的模块级字面量赋值（不导入、不执行，避免副作用）。"""
    with open(path, "r", encoding="utf-8") as fh:
        tree = ast.parse(fh.read(), filename=path)

    found: dict = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        if len(node.targets) != 1 or not isinstance(node.targets[0], ast.Name):
            continue
        name = PARAM_ALIASES.get(node.targets[0].id.strip().lower())
        if name is None:
            continue
        try:
            value = ast.literal_eval(node.value)     # 只认字面量，L / N 这类算式会被跳过
        except (ValueError, SyntaxError):
            continue
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            found[name] = value
    return found
