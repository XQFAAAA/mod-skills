---
name: "wwmi-format-condition-converter"
description: "将 WWMI mod.ini 中基于 filter_index 浮点值的纹理槽条件（if ps-tX == 83.xxx）改写为基于 DXGI format 枚举的精确条件（if ps-tX->format == 77），并删除 match_format + filter_index 模糊匹配块。前提：自定义贴图与原槽位绑定格式相同，无需提供原槽位格式。当需要把 mod 的纹理识别从模糊匹配改为精确格式匹配时使用。"
---

# WWMI 纹理条件 format 化转换指南

把 WWMI mod.ini 中 `if ps-tX == <filter_index 浮点值>` 的运行时条件改写为 `if ps-tX->format == <DXGI 枚举值>`，使纹理识别不再依赖 filter_index 模糊匹配（可进一步删除对应模糊匹配块）。

## 何时使用

- 用户要求把 `ps-tX == 83.666751` 这类浮点值条件改为 `ps-tX->format == 77` 这类格式条件
- 用户要求删除 `match_format + filter_index` 的纹理模糊匹配 `[TextureOverrideComponent*]` 块
- mod.ini 中已有 Test 参考写法 `if ps-t0->format == 71 && ...`，需要按同样方式改写其余条件

## 核心前提

**自定义贴图资源（if 块内引用的替换 .dds）与目标槽位（ps-tX）原本绑定的游戏贴图格式相同。**

因此无需提供/查询原槽位格式：直接以 if 块内赋给该槽位的自定义贴图 `.dds` 格式，作为该槽位的判定格式。若自定义贴图格式与原槽位格式不一致，本转换不适用（格式条件将无法命中）。

## 转换流程

1. **定位所有条件**：找出 mod.ini 中所有 `if ps-tX == <浮点值>`（含嵌套 `if`）。
2. **槽位↔资源映射**：把条件中被检查的每个 `ps-tX` 对应到 if 块内赋给**同一槽位**的 `ref Resource...` 资源。
   - 例：`ps-t1 = ref ResourceTextureHair_D` → ps-t1 的格式取 `ResourceTextureHair_D` 对应 .dds 的格式。
   - 若 if 块同时给多个槽位赋资源、但只检查部分槽位：仅被检查的槽位按它**自己的**资源确定格式（其他未检查槽位不影响条件）。
3. **查资源定义**：找到 `[ResourceTextureXxx]` 节 → `filename = Textures/Xxx.dds`，得到 .dds 文件路径。
4. **texdiag 查看格式**：`texdiag info Textures/Xxx.dds`，读取输出中的 `format =` 行。
   - 若无 texdiag：`winget install Microsoft.DirectXTex.Texdiag` 安装后重试。
5. **格式 → DXGI 枚举值**：按「DXGI 枚举参考」把格式名映射为数值。
6. **改写条件**：把 `ps-tX == 83.xxx` 替换为 `ps-tX->format == <枚举值>`，其余 `&&` 结构与末尾 `&& 1` 保持不变；**不要改动 if 块内的资源赋值逻辑**。
7. **删除模糊匹配块（必须）**：删除所有 `[TextureOverrideComponent*]` 且带 `match_format + filter_index` 的节（形如 `match_priority = 100` 的纹理格式匹配块）。这些块与新的 format 条件功能重复，转换后必须移除。删除前先 `grep match_format` 确认仅存在于待删除的纹理节中。

## 示例（Xuanling-Bianka 实战）

改前：
```ini
if ps-t0 == 83.666751 && ps-t1 == 83.666755 && ps-t2 == 83.66567156825666 && ps-t5 == 83.666755 && 1
    ps-t0 = ref ResourceTextureBianka_FTM_FF0080
    ps-t1 = ref ResourceTextureBianka_Bang_D2
    ps-t2 = ref ResourceTextureBianka_Bang_HN
    ps-t5 = ref ResourceTextureBianka_Bang_HM
endif
```

改后（各槽位格式来自其替换贴图 texdiag 结果）：
```ini
if ps-t0->format == 77 && ps-t1->format == 99 && ps-t2->format == 87 && ps-t5->format == 98 && 1
    ps-t0 = ref ResourceTextureBianka_FTM_FF0080
    ps-t1 = ref ResourceTextureBianka_Bang_D2
    ps-t2 = ref ResourceTextureBianka_Bang_HN
    ps-t5 = ref ResourceTextureBianka_Bang_HM
endif
```

依据：Bianka_FTM_FF0080.dds=BC3_UNORM(77)，Bianka_Bang_D2.dds=BC7_UNORM_SRGB(99)，Bianka_Bang_HN.dds=B8G8R8A8_UNORM(87)，Bianka_Bang_HM.dds=BC7_UNORM(98)。

嵌套 if 同理（Component1 头发）：
```ini
if ps-t6->format == 98
    ps-t6 = ref ResourceTextureBianka_Hair_Light
endif
if ps-t7->format == 98
    ps-t6 = ref ResourceTextureBianka_Hair_VFX
    ps-t7 = ref ResourceTextureBianka_Hair_Light
endif
```

## DXGI 枚举参考（完整 DXGI_FORMAT，直接使用，无需再查网页）

```
typedef enum DXGI_FORMAT {
 DXGI_FORMAT_UNKNOWN = 0,
 DXGI_FORMAT_R32G32B32A32_TYPELESS = 1,
 DXGI_FORMAT_R32G32B32A32_FLOAT = 2,
 DXGI_FORMAT_R32G32B32A32_UINT = 3,
 DXGI_FORMAT_R32G32B32A32_SINT = 4,
 DXGI_FORMAT_R32G32B32_TYPELESS = 5,
 DXGI_FORMAT_R32G32B32_FLOAT = 6,
 DXGI_FORMAT_R32G32B32_UINT = 7,
 DXGI_FORMAT_R32G32B32_SINT = 8,
 DXGI_FORMAT_R16G16B16A16_TYPELESS = 9,
 DXGI_FORMAT_R16G16B16A16_FLOAT = 10,
 DXGI_FORMAT_R16G16B16A16_UNORM = 11,
 DXGI_FORMAT_R16G16B16A16_UINT = 12,
 DXGI_FORMAT_R16G16B16A16_SNORM = 13,
 DXGI_FORMAT_R16G16B16A16_SINT = 14,
 DXGI_FORMAT_R32G32_TYPELESS = 15,
 DXGI_FORMAT_R32G32_FLOAT = 16,
 DXGI_FORMAT_R32G32_UINT = 17,
 DXGI_FORMAT_R32G32_SINT = 18,
 DXGI_FORMAT_R32G8X24_TYPELESS = 19,
 DXGI_FORMAT_D32_FLOAT_S8X24_UINT = 20,
 DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS = 21,
 DXGI_FORMAT_X32_TYPELESS_G8X24_UINT = 22,
 DXGI_FORMAT_R10G10B10A2_TYPELESS = 23,
 DXGI_FORMAT_R10G10B10A2_UNORM = 24,
 DXGI_FORMAT_R10G10B10A2_UINT = 25,
 DXGI_FORMAT_R11G11B10_FLOAT = 26,
 DXGI_FORMAT_R8G8B8A8_TYPELESS = 27,
 DXGI_FORMAT_R8G8B8A8_UNORM = 28,
 DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 29,
 DXGI_FORMAT_R8G8B8A8_UINT = 30,
 DXGI_FORMAT_R8G8B8A8_SNORM = 31,
 DXGI_FORMAT_R8G8B8A8_SINT = 32,
 DXGI_FORMAT_R16G16_TYPELESS = 33,
 DXGI_FORMAT_R16G16_FLOAT = 34,
 DXGI_FORMAT_R16G16_UNORM = 35,
 DXGI_FORMAT_R16G16_UINT = 36,
 DXGI_FORMAT_R16G16_SNORM = 37,
 DXGI_FORMAT_R16G16_SINT = 38,
 DXGI_FORMAT_R32_TYPELESS = 39,
 DXGI_FORMAT_D32_FLOAT = 40,
 DXGI_FORMAT_R32_FLOAT = 41,
 DXGI_FORMAT_R32_UINT = 42,
 DXGI_FORMAT_R32_SINT = 43,
 DXGI_FORMAT_R24G8_TYPELESS = 44,
 DXGI_FORMAT_D24_UNORM_S8_UINT = 45,
 DXGI_FORMAT_R24_UNORM_X8_TYPELESS = 46,
 DXGI_FORMAT_X24_TYPELESS_G8_UINT = 47,
 DXGI_FORMAT_R8G8_TYPELESS = 48,
 DXGI_FORMAT_R8G8_UNORM = 49,
 DXGI_FORMAT_R8G8_UINT = 50,
 DXGI_FORMAT_R8G8_SNORM = 51,
 DXGI_FORMAT_R8G8_SINT = 52,
 DXGI_FORMAT_R16_TYPELESS = 53,
 DXGI_FORMAT_R16_FLOAT = 54,
 DXGI_FORMAT_D16_UNORM = 55,
 DXGI_FORMAT_R16_UNORM = 56,
 DXGI_FORMAT_R16_UINT = 57,
 DXGI_FORMAT_R16_SNORM = 58,
 DXGI_FORMAT_R16_SINT = 59,
 DXGI_FORMAT_R8_TYPELESS = 60,
 DXGI_FORMAT_R8_UNORM = 61,
 DXGI_FORMAT_R8_UINT = 62,
 DXGI_FORMAT_R8_SNORM = 63,
 DXGI_FORMAT_R8_SINT = 64,
 DXGI_FORMAT_A8_UNORM = 65,
 DXGI_FORMAT_R1_UNORM = 66,
 DXGI_FORMAT_R9G9B9E5_SHAREDEXP = 67,
 DXGI_FORMAT_R8G8_B8G8_UNORM = 68,
 DXGI_FORMAT_G8R8_G8B8_UNORM = 69,
 DXGI_FORMAT_BC1_TYPELESS = 70,
 DXGI_FORMAT_BC1_UNORM = 71,
 DXGI_FORMAT_BC1_UNORM_SRGB = 72,
 DXGI_FORMAT_BC2_TYPELESS = 73,
 DXGI_FORMAT_BC2_UNORM = 74,
 DXGI_FORMAT_BC2_UNORM_SRGB = 75,
 DXGI_FORMAT_BC3_TYPELESS = 76,
 DXGI_FORMAT_BC3_UNORM = 77,
 DXGI_FORMAT_BC3_UNORM_SRGB = 78,
 DXGI_FORMAT_BC4_TYPELESS = 79,
 DXGI_FORMAT_BC4_UNORM = 80,
 DXGI_FORMAT_BC4_SNORM = 81,
 DXGI_FORMAT_BC5_TYPELESS = 82,
 DXGI_FORMAT_BC5_UNORM = 83,
 DXGI_FORMAT_BC5_SNORM = 84,
 DXGI_FORMAT_B5G6R5_UNORM = 85,
 DXGI_FORMAT_B5G5R5A1_UNORM = 86,
 DXGI_FORMAT_B8G8R8A8_UNORM = 87,
 DXGI_FORMAT_B8G8R8X8_UNORM = 88,
 DXGI_FORMAT_R10G10B10_XR_BIAS_A2_UNORM = 89,
 DXGI_FORMAT_B8G8R8A8_TYPELESS = 90,
 DXGI_FORMAT_B8G8R8A8_UNORM_SRGB = 91,
 DXGI_FORMAT_B8G8R8X8_TYPELESS = 92,
 DXGI_FORMAT_B8G8R8X8_UNORM_SRGB = 93,
 DXGI_FORMAT_BC6H_TYPELESS = 94,
 DXGI_FORMAT_BC6H_UF16 = 95,
 DXGI_FORMAT_BC6H_SF16 = 96,
 DXGI_FORMAT_BC7_TYPELESS = 97,
 DXGI_FORMAT_BC7_UNORM = 98,
 DXGI_FORMAT_BC7_UNORM_SRGB = 99,
 DXGI_FORMAT_AYUV = 100,
 DXGI_FORMAT_Y410 = 101,
 DXGI_FORMAT_Y416 = 102,
 DXGI_FORMAT_NV12 = 103,
 DXGI_FORMAT_P010 = 104,
 DXGI_FORMAT_P016 = 105,
 DXGI_FORMAT_420_OPAQUE = 106,
 DXGI_FORMAT_YUY2 = 107,
 DXGI_FORMAT_Y210 = 108,
 DXGI_FORMAT_Y216 = 109,
 DXGI_FORMAT_NV11 = 110,
 DXGI_FORMAT_AI44 = 111,
 DXGI_FORMAT_IA44 = 112,
 DXGI_FORMAT_P8 = 113,
 DXGI_FORMAT_A8P8 = 114,
 DXGI_FORMAT_B4G4R4A4_UNORM = 115,
 DXGI_FORMAT_P208 = 130,
 DXGI_FORMAT_V208 = 131,
 DXGI_FORMAT_V408 = 132,
 DXGI_FORMAT_SAMPLER_FEEDBACK_MIN_MIP_OPAQUE = 189,
 DXGI_FORMAT_SAMPLER_FEEDBACK_MIP_REGION_USED_OPAQUE = 190,
 DXGI_FORMAT_A4B4G4R4_UNORM = 191,
 DXGI_FORMAT_FORCE_UINT = 0xffffffff
} ;
```

贴图类常用值速查：R8_UNORM=61、BC1(70/71/72)、BC2(73/74/75)、BC3(76/77/78)、BC4(79/80/81)、BC5(82/83/84)、B8G8R8A8(87/90/91)、BC6H(94/95/96)、BC7(97/98/99)、B4G4R4A4=115、A4B4G4R4=191。

## 注意事项

- 不同组件（Component）可能引用不同贴图但条件浮点值相同：各自按其资源的实际格式转换，格式相同才能复用同一数值。
- `filter_index` 属于 WWMI 核心回调的节（如 `[TextureOverrideMarkBoneDataCB]`、`[TextureOverrideMeshDataCB]`）**不能删除**，它们是骨架/网格数据合并的必需标记。
- 删除模糊匹配块前先 grep 确认 `match_format` 仅存在于待删除的纹理节中。
- `ps-tX->format` 返回当前绑定纹理的 DXGI 格式枚举值，与 `ps-tX == 浮点值` 的 filter_index 比较语义不同，改写后需在游戏中验证能正常命中。

## 检查清单

- [ ] 所有 `if ps-tX == <浮点值>` 已改写为 `if ps-tX->format == <枚举值>`（含嵌套 if）
- [ ] 每个格式值均来自 if 块内引用资源的 texdiag 结果，未臆测
- [ ] if 块内资源赋值逻辑未改动
- [ ] 模糊匹配块（match_format + filter_index）已全部删除，grep `match_format` 无残留，且未误删核心回调
- [ ] 修改前先备份 mod.ini（如复制为 mod.bak）
