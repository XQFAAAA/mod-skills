---
name: wwmi-merged-instance-converter
description: 将 WWMI 旧版 Merged 骨架 mod 升级为 Merged Instance 多实例新版 mod（含 13 项 ini 变更，基于 $instance_id + PoolInstanceID 池 + PoolMergeStatus 池 + TextureOverrideMeshDataCB 方案，RW 骨架池带 pool_allocate_slot_on_missing 与资源模板），并按 BlendBufferrR8-R16.py 由 Blend.buf + BlendRemapVertexVG.buf 生成 Blend_R16.buf。当需要把旧版 mod 转成支持同屏多实例/16 位骨骼索引的新版 mod 时使用。
---

# WWMI Merged Instance 转换指南

把一个使用 **Merged（合并）骨架**的旧版 WWMI mod 升级为 **Merged Instance（多实例合并骨架）** 新版 mod，并生成配套的 16 位混合缓冲 `Blend_R16.buf`。

## 何时使用

当用户要求把旧版 mod（仅支持同屏 1 个 mod 对象、blend 使用 8 位索引）转换为新版（支持同一对象多个实例、骨骼/顶点组索引突破 256 限制使用 16 位）时使用。

参考对照文件（均已复制到本 skill 的 `references/` 文件夹，Test 对象 = 8 组件、实例数=4）：
- 旧版：`references/mod.bak`（Merged 模式）
- 新版：`references/mod.ini`（Merged Instance，`$instance_id` + `PoolMergeStatus` 方案）
- 转换脚本：`references/BlendBufferrR8-R16.py`
- 缓冲样本：`references/Blend.buf`、`references/BlendRemapVertexVG.buf`（输入）→ `references/Blend_R16.buf`（输出）

## 背景

- 旧版 mod.ini 使用单份骨架缓冲 `ResourceMergedSkeleton` / `ResourceExtraMergedSkeleton`，同屏出现多个同对象实例时会互相覆盖。
- 新版通过 **Pool（资源池）+ `$instance_id`（实例 ID）** 为每个实例分配独立骨架合并槽位，并改用 16 位 blend 数据（`Blend_R16.buf`）支持超过 256 的 VG/骨骼索引。
- 实例 ID 的获取：`[TextureOverrideMeshDataCB]`（通用 hash `358d62cb`）把 MeshDataCB 标记为 `3380.7777`；在每个组件绘制处理开头，从 vs-cb2/vs-cb3（若等于 3380.7777）把 `@vs-cb2`/`@vs-cb3`（当前绑定 CB 的地址，不同实例不同）写入通用变量 `$instance_id`。
- 实例 ID 的存储：每个实例首次合并时把 `$instance_id` 注册进 **`[PoolInstanceID]` 池**（`$PoolInstanceID[槽位号] = $instance_id`），帧末按 `$PoolInstanceID[0..N-1]` 遍历各实例传递骨骼矩阵，不再使用逐实例 `$instance_id_{N}` 变量。
- RW 骨架池 `[PoolMergedSkeletonRW]` / `[PoolExtraMergedSkeletonRW]` 带 **`pool_allocate_slot_on_missing = 1` 与资源模板**（`type`/`format`/`array`/`bind_flags`）：访问缺失槽位时自动分配槽位并按模板创建 RWBuffer，命令列表无需手动初始化槽位、无需逐实例 RWBuffer 资源引用。
- 合并状态不再按实例展开成 N 个变量，而是每组件一个 **`PoolMergeStatus_{C}` 池**（按 `$instance_id` 索引），配合 `pool_variable_default_value = 0`，天然支持任意实例数。

## 变量约定

- `N`：实例数量，实例编号 `0 .. N-1`（Test 参考中 N=4）
- `C`：组件数量，组件编号 `0 .. C-1`（Test 参考中 C=8）
- `$instance_id`：当前绘制调用的实例 ID（通用变量，从标记的 MeshDataCB 捕获，供 CommandListMergeSkeleton / OverrideSharedResources / PoolMergeStatus 索引使用）
- `$PoolInstanceID[S]`：`[PoolInstanceID]` 池的第 S 号槽位，存放注册到骨架池槽位 S 的实例 ID（首次合并 Regular 段写入；帧末用 `$PoolInstanceID[0..N-1]` 选择各实例的 Pool 槽位）
- `$PoolMergeStatus_{C}[$instance_id]`：组件 C 在当前实例的骨架合并状态（0=未合并 / 1=仅常规 / 2=常规+特殊）
- `$merge_status_id`：通用输入/输出变量，供 CommandListMergeSkeleton 使用

## 转换流程（含备份前置步骤）

按以下顺序执行：

1. **备份旧版 ini（前置步骤）**
   - 若目标 `mod.ini` 存在且内容仍为旧版（Merged），先将其复制为 `mod.bak` 作备份，再执行后续改写，避免旧版内容丢失。
   - 若 `mod.bak` 已存在，则直接覆盖（以本次备份为准）或保留时间戳副本。
2. **生成 16 位混合缓冲**
   - 依据 `references/BlendBufferrR8-R16.py`，由 `Meshes/Blend.buf` + `Meshes/BlendRemapVertexVG.buf` 生成 `Meshes/Blend_R16.buf`（详见「二、Blend_R16.buf 生成」）。
3. **改写 ini**
   - 按下方「一、INI 变更」的 13 项逐条把旧版内容改写为 Merged Instance 新版。
4. **写入 mod.ini**
   - 将新版内容写入 `mod.ini`。
5. **验证**
   - 对照「三、检查清单」逐项检查，确认转换正确。

---

## 一、INI 变更（旧版 Merged → 新版 Merged Instance）

### 1. Constants：合并状态改用 PoolMergeStatus_{C} 池

旧版（每组件一个普通变量）：
```
global $merge_status_id_0 = 0
...
global $merge_status_id_7 = 0
```

新版：**移除**上述 `$merge_status_id_{C}` 变量，改为每组件一个池（按 `$instance_id` 索引）：
```
[PoolMergeStatus_0]
pool_size = 4
pool_index_type = fifo
pool_variable_default_value = 0

[PoolMergeStatus_1]
pool_size = 4
pool_index_type = fifo
pool_variable_default_value = 0
...
```
（共 C 个池，`pool_size` = 实例数 N，`pool_variable_default_value = 0` 使未记录的实例默认为 0 = 未合并。）

保留通用输入/输出变量：
```
global $merge_status_id = 0
```

**重要 — [Constants] 内变量顺序**：`global persist $draw_*` 开关块（`; Swap vars aka toggles defaults` / `; Per-object state vars` 注释 + 各 `global persist $draw_component{C} = 1`）**必须保留在原位**（紧跟在 `global $merge_status_id = 0` 之后），新加的 `$instance_id`、`[PoolInstanceID]` 池与 `[PoolMergeStatus_{C}]` 池统一插在开关块**之后**。参考（Test 对象）顺序：
```
global $merge_status_id = 0
; Swap vars aka toggles defaults
; Per-object state vars
global persist $draw_component0 = 1
...
global persist $draw_component7 = 1
global $instance_id = 0

[PoolInstanceID]
pool_size = 4
pool_index_type = fifo
pool_variable_default_value = 0

[PoolMergeStatus_0]
...
[PoolMergeStatus_7]
```

### 2. Constants：新增通用实例 ID 变量与 [PoolInstanceID] 池

插入位置：`[Constants]` 内 `global persist $draw_*` 开关块**之后**、`[PoolMergeStatus_{C}]` 池**之前**（见第 1 项的顺序说明）。
```
global $instance_id = 0

[PoolInstanceID]
pool_size = 4
pool_index_type = fifo
pool_variable_default_value = 0
```
（`$instance_id` 为当前绘制实例 ID；`[PoolInstanceID]` 池按骨架池槽位号存储各实例 ID，`pool_size` = 实例数 N。**不再需要**逐实例 `$instance_id_{0..N-1}` 变量。）

### 3. 新增 [TextureOverrideMeshDataCB] 标记

在 `[TextureOverrideMarkBoneDataCB]` 之后新增（hash `358d62cb` 为 WuWa 通用 MeshDataCB hash）：
```
[TextureOverrideMeshDataCB]
hash = 358d62cb
match_priority = 0
filter_index = 3380.7777
```
作用：把 MeshDataCB 标记为 `3380.7777`，后续可通过 `vs-cb2 == 3380.7777` / `vs-cb3 == 3380.7777` 判断当前绘制调用是否携带该 CB。

### 4. 每个组件捕获 $instance_id

在 `TextureOverrideComponent{C}` 的 `if $mod_enabled` 之后、pool 初始化之前加入：
```
if vs-cb2 == 3380.7777
    $instance_id = @vs-cb2
elif vs-cb3 == 3380.7777
    $instance_id = @vs-cb3
endif
```
作用：把当前 drawcall 的实例 ID 记录到通用 `$instance_id`。
原因：到 Present 帧末执行骨骼矩阵传递时，已经拿不到之前 drawcall 的 vs-cb2/vs-cb3，必须提前记录。`@vs-cb2`/`@vs-cb3` 是当前绑定 CB 的资源地址，不同实例的 CB 地址不同，可唯一标识实例。

### 5. 帧末重置合并状态

`CommandListUpdateMergedSkeleton` 中重置每个组件的合并状态池（每组件一行）：
```
PoolMergeStatus_0[*] = 0
PoolMergeStatus_1[*] = 0
...
```
`[*]` 表示将该池所有槽位重置为默认值 0。

### 6. 帧末按实例传递骨骼矩阵

旧版：
```
ResourceMergedSkeleton = copy ResourceMergedSkeletonRW
ResourceExtraMergedSkeleton = copy ResourceExtraMergedSkeletonRW
```

新版（基底 copy 保留；先全部 Merged、再全部 Extra；索引一律用 `$PoolInstanceID[N]`，N = 0 .. 实例数-1）：
```
ResourceMergedSkeleton = copy ResourceMergedSkeletonRW
ResourceExtraMergedSkeleton = copy ResourceExtraMergedSkeletonRW
PoolMergedSkeleton[$PoolInstanceID[0]] = copy PoolMergedSkeletonRW[$PoolInstanceID[0]]
PoolMergedSkeleton[$PoolInstanceID[1]] = copy PoolMergedSkeletonRW[$PoolInstanceID[1]]
...
PoolExtraMergedSkeleton[$PoolInstanceID[0]] = copy PoolExtraMergedSkeletonRW[$PoolInstanceID[0]]
PoolExtraMergedSkeleton[$PoolInstanceID[1]] = copy PoolExtraMergedSkeletonRW[$PoolInstanceID[1]]
...
```

### 7. CommandListMergeSkeleton：槽位自动分配，无逐实例分支

旧版直接写入单一 `ResourceMergedSkeletonRW` / `ResourceExtraMergedSkeletonRW`。

新版 RW 骨架池带 `pool_allocate_slot_on_missing = 1` 与资源模板（见第 10 项），访问缺失槽位时自动分配槽位并按模板创建 RWBuffer，因此**无需** `#Pool...RW[$instance_id] == -1` 初始化块，也**无需**按槽位号 0..N-1 展开的 if/elif 分支和 `ResourceMergedSkeletonRW{N}` 逐实例缓冲引用（Regular 骨架部分）：
```
if $merge_status_id == 0
    if vs-cb4 == 3381.7777
        cs-cb8 = ref vs-cb4
        $PoolInstanceID[#PoolMergedSkeletonRW[$instance_id]] = $instance_id
        cs-u6 = PoolMergedSkeletonRW[$instance_id]
        $\WWMIv1\custom_mesh_scale = 1.00
        run = CustomShader\WWMIv1\SkeletonMerger
        $merge_status_id = 1
    endif
endif
```
- `#PoolMergedSkeletonRW[$instance_id]` 返回该实例在 RW 池中分配到的槽位号；用它作下标把 `$instance_id` 注册进 `[PoolInstanceID]` 池（仅在 Regular 段注册一次，Extra 段不注册）。
- `cs-u6 = PoolMergedSkeletonRW[$instance_id]` 直接把该实例的池槽位 RWBuffer 交给 SkeletonMerger。

Special（Extra）骨架部分同理，但不重复注册 PoolInstanceID，判定条件 `vs-cb4 == 3381.7777 && vs-cb3 == 3381.7777`：
```
if $merge_status_id == 1
    if vs-cb4 == 3381.7777 && vs-cb3 == 3381.7777
        cs-cb8 = ref vs-cb3
        cs-u6 = PoolExtraMergedSkeletonRW[$instance_id]
        $\WWMIv1\custom_mesh_scale = 1.00
        run = CustomShader\WWMIv1\SkeletonMerger
        $merge_status_id = 2
    endif
endif
```

### 8. CommandListOverrideSharedResources：vb4 改 16 位 + 按实例绑定骨架

旧版：`vb4 = ResourceBlendBuffer`；`vs-cb4 = ref ResourceMergedSkeleton`（含 blend remap 分支）。

新版：
```
vb4 = ResourceBlendBuffer_R16
vb4->ElementFormat(ATTRIBUTE, 3) = R16G16B16A16_UINT
vb4->ElementFormat(ATTRIBUTE, 14) = R16G16B16A16_UINT
vb4->ElementFormat(ATTRIBUTE, 4) = R16G16B16A16_UNORM
vb4->ElementFormat(ATTRIBUTE, 15) = R16G16B16A16_UNORM
vb4->ElementOffset(ATTRIBUTE, 3) = 0
vb4->ElementOffset(ATTRIBUTE, 14) = 8
vb4->ElementOffset(ATTRIBUTE, 4) = 16
vb4->ElementOffset(ATTRIBUTE, 15) = 24
if vs-cb4 == 3381.7777
    vs-cb4 = ref PoolMergedSkeleton[$instance_id]
    if vs-cb3 == 3381.7777
        vs-cb3 = ref PoolExtraMergedSkeleton[$instance_id]
    endif
elif vs-cb3 == 3381.7777
    vs-cb3 = ref PoolMergedSkeleton[$instance_id]
endif
```

### 9. TextureOverrideComponent{C}：每个实例只进一次合并

在捕获 `$instance_id`（见第 4 项）之后，直接使用单个合并状态块（槽位由 `pool_allocate_slot_on_missing = 1` 自动分配，**无需** `#PoolMergedSkeletonRW[$instance_id] == -1` 初始化块，也无需逐实例枚举）：
```
if $PoolMergeStatus_{C}[$instance_id] != 2
    $\WWMIv1\vg_offset = <该组件vg_offset>
    $\WWMIv1\vg_count = <该组件vg_count>
    $merge_status_id = $PoolMergeStatus_{C}[$instance_id]
    run = CommandListMergeSkeleton
    $PoolMergeStatus_{C}[$instance_id] = $merge_status_id
endif
```

各组件内原有的 `$draw_component{C}` 开关判断、drawindexed 调用、纹理替换与特效（如 RabbitFX）逻辑**保持不变**，仅替换骨架合并部分与绘制判断条件。

### 10. 资源池声明（随实例数增加；RW 池带自动分配与资源模板）

```
[PoolMergedSkeleton]
pool_size = 4
pool_index_type = fifo
pool_lazy_initialization = 0

[PoolExtraMergedSkeleton]
pool_size = 4
pool_index_type = fifo
pool_lazy_initialization = 0

[PoolMergedSkeletonRW]
pool_size = 4
pool_index_type = fifo
pool_lazy_initialization = 0
pool_allocate_slot_on_missing = 1
type = RWBuffer
format = R32G32B32A32_FLOAT
array = 1536
bind_flags = shader_resource unordered_access

[PoolExtraMergedSkeletonRW]
pool_size = 4
pool_index_type = fifo
pool_lazy_initialization = 0
pool_allocate_slot_on_missing = 1
type = RWBuffer
format = R32G32B32A32_FLOAT
array = 1536
bind_flags = shader_resource unordered_access
```
（`pool_size` = 实例数 N。两个 RW 池**必须**带 `pool_allocate_slot_on_missing = 1` 和资源模板 `type`/`format`/`array`/`bind_flags`：访问缺失槽位时自动分配槽位，并按模板创建 RWBuffer 供 `cs-u6 = Pool...RW[$instance_id]` 使用。）

基底 `[ResourceMergedSkeletonRW]` / `[ResourceExtraMergedSkeletonRW]` 保留并 `array = 1536`（帧末基底 copy 与 ShapeKey 回调仍引用 `ResourceMergedSkeleton`）。

并为每个实例新增骨架缓冲（每实例各两份；新方案下命令列表已不引用这些逐实例缓冲，保留仅为与参考文件一致，可按需省略）：
```
[ResourceMergedSkeleton0]
[ResourceMergedSkeletonRW0]
type = RWBuffer
format = R32G32B32A32_FLOAT
array = 1536

[ResourceExtraMergedSkeleton0]
[ResourceExtraMergedSkeletonRW0]
type = RWBuffer
format = R32G32B32A32_FLOAT
array = 1536
...
```

### 11. 绘制判断条件变更

旧版：`if ResourceMergedSkeleton !== null`
新版：`if #PoolMergedSkeleton[$instance_id] !== -1`

### 12. 删除压缩骨骼相关代码

因为索引/权重已突破 1 字节（256 个）限制，取消压缩骨骼索引和压缩骨骼矩阵的代码：
- `[Present]` 中删除 `run = CommandListInitializeBlendRemaps`，**保留** `run = CommandListProcessToggles` 与 `run = CommandListUpdateMergedSkeleton`（`[CommandListProcessToggles]` 节本身保持不变）
- 注释/删除 `CommandListInitializeBlendRemaps`（blend remap 初始化）
- 注释/删除 `CommandListRemapMergedSkeleton`（SkeletonRemapper 骨骼重映射）
- 删除 `ResourceBlendBufferNoStride`、`ResourceRemappedBlendBufferRW`、`ResourceRemappedSkeletonRW`、`ResourceExtraRemappedSkeletonRW` 等重映射资源
- 删除各组件节中的 `ResourceBlendBufferOverride` / `ResourceRemappedSkeletonComponent{C}` 绑定
- `BlendRemapVertexVG.buf` / `BlendRemapForward.buf` / `BlendRemapReverse.buf` 的资源声明可保留（不再参与计算）

### 13. 新增资源 [ResourceBlendBuffer_R16]

```
[ResourceBlendBuffer_R16]
type = Buffer
format = DXGI_FORMAT_R16_UINT
stride = 32
filename = Meshes/Blend_R16.buf
```

---

## 二、Blend_R16.buf 生成（依据 BlendBufferrR8-R16.py）

### 输入
- `Blend.buf`：16 字节/顶点 = 4×R8G8B8A8（8 个 8 位骨骼索引 + 8 个 8 位骨骼权重）
  - [0:4] 索引0-3（R8G8B8A8_UINT）
  - [4:8] 索引4-7（R8G8B8A8_UINT）
  - [8:12] 权重0-3（R8G8B8A8_UNORM）
  - [12:16] 权重4-7（R8G8B8A8_UNORM）
- `BlendRemapVertexVG.buf`：16 字节/顶点 = 2×R16G16B16A16（8 个 16 位 VG id）

### 输出
`Blend_R16.buf` 32 字节/顶点：
- [0:8] R16G16B16A16_UINT — 索引0-3（来自 BlendRemapVertexVG）
- [8:16] R16G16B16A16_UINT — 索引4-7（来自 BlendRemapVertexVG）
- [16:24] R16G16B16A16_UNORM — 权重0-3（Blend 权重 × 257）
- [24:32] R16G16B16A16_UNORM — 权重4-7（Blend 权重 × 257）

### 算法步骤
1. 校验两个文件分别按 16 字节/顶点对齐，且顶点数一致。
2. 8 位索引零扩展为 16 位（`struct.unpack('<4B')` → 直接作为 16 位整数）。
3. 8 位 UNORM 权重位复制为 16 位：`x * 257`（保持浮点值不变：x/255 == x*257/65535）。
4. 将每个顶点前 16 字节（索引部分）用 BlendRemapVertexVG.buf 的 16 位 VG id 覆盖。

### Python 实现（与脚本一致）
```python
import struct

BYTES_PER_VERTEX_BLEND_IN = 16
BYTES_PER_VERTEX_BLEND_OUT = 32
BYTES_PER_VERTEX_VG = 16

with open('Blend.buf', 'rb') as f:
    blend_data = f.read()
with open('BlendRemapVertexVG.buf', 'rb') as f:
    vg_data = f.read()

VERTEX_COUNT = len(blend_data) // BYTES_PER_VERTEX_BLEND_IN
assert len(blend_data) % BYTES_PER_VERTEX_BLEND_IN == 0
assert len(vg_data) % BYTES_PER_VERTEX_VG == 0
assert VERTEX_COUNT == len(vg_data) // BYTES_PER_VERTEX_VG

# 步骤1：R8 -> R16
out = bytearray()
for i in range(VERTEX_COUNT):
    v = blend_data[i * 16 : (i + 1) * 16]
    uint1 = struct.unpack('<4B', v[0:4])        # 索引0-3
    uint2 = struct.unpack('<4B', v[4:8])        # 索引4-7
    unorm1 = tuple(x * 257 for x in v[8:12])    # 权重0-3
    unorm2 = tuple(x * 257 for x in v[12:16])   # 权重4-7
    out += struct.pack('<4H4H4H4H', *uint1, *uint2, *unorm1, *unorm2)

with open('Blend_R16.buf', 'wb') as f:
    f.write(out)

# 步骤2：用 BlendRemapVertexVG.buf 覆盖索引部分（原地修改）
with open('Blend_R16.buf', 'r+b') as f:
    r16 = bytearray(f.read())
    for i in range(VERTEX_COUNT):
        start = i * BYTES_PER_VERTEX_BLEND_OUT
        r16[start : start + BYTES_PER_VERTEX_VG] = vg_data[i * BYTES_PER_VERTEX_VG : (i + 1) * BYTES_PER_VERTEX_VG]
    f.seek(0)
    f.write(r16)
```

---

## 三、检查清单

- [ ] Constants 中存在 `[PoolMergeStatus_{C}]` 池（每组件一个，`pool_size = 实例数`，`pool_variable_default_value = 0`），且无逐实例 `$merge_status_id_{C}_{N}` 变量
- [ ] `[Constants]` 中 `global persist $draw_*` 开关块保留在原位（`$merge_status_id` 之后、`$instance_id`/池之前），`[Present]` 保留 `run = CommandListProcessToggles`
- [ ] 存在通用 `$instance_id` 变量 + `[PoolInstanceID]` 池（`pool_size = 实例数`，`pool_index_type = fifo`，`pool_variable_default_value = 0`），且无逐实例 `$instance_id_{0..N-1}` 变量
- [ ] 存在 `[TextureOverrideMeshDataCB]`（hash = 358d62cb，filter_index = 3380.7777）
- [ ] 每个 `TextureOverrideComponent{C}` 都有 `$instance_id` 捕获块（vs-cb2/vs-cb3 == 3380.7777）
- [ ] 帧末 `CommandListUpdateMergedSkeleton` 用 `PoolMergeStatus_{C}[*] = 0` 重置，并按 `$PoolInstanceID[0..N-1]` 索引 copy Pool 骨架（先 Merged 后 Extra）
- [ ] `CommandListMergeSkeleton` 主合并段含注册行 `$PoolInstanceID[#PoolMergedSkeletonRW[$instance_id]] = $instance_id` 与 `cs-u6 = PoolMergedSkeletonRW[$instance_id]`（Extra 段不注册，用 `PoolExtraMergedSkeletonRW[$instance_id]`），无逐实例 if/elif 分支
- [ ] 每个 `TextureOverrideComponent{C}` 有单个 `$PoolMergeStatus_{C}[$instance_id]` 合并块，且无 pool 槽位初始化代码
- [ ] 绘制条件为 `if #PoolMergedSkeleton[$instance_id] !== -1`
- [ ] vb4 使用 `ResourceBlendBuffer_R16` 并带 4 条 ElementFormat + 4 条 ElementOffset
- [ ] 4 个骨架 Pool 资源 `pool_size = 实例数`
- [ ] `[PoolMergedSkeletonRW]` / `[PoolExtraMergedSkeletonRW]` 带 `pool_allocate_slot_on_missing = 1` 和资源模板（`type = RWBuffer`、`format = R32G32B32A32_FLOAT`、`array = 1536`、`bind_flags = shader_resource unordered_access`）
- [ ] （可选）逐实例 `ResourceMergedSkeletonRW{N}` / `ResourceExtraMergedSkeletonRW{N}` 缓冲——命令列表已不引用，可按需省略或删除
- [ ] blend remap / 压缩骨骼相关代码已移除
- [ ] `Meshes/Blend_R16.buf` 已生成，且 `Blend.buf` 与 `BlendRemapVertexVG.buf` 顶点数一致
