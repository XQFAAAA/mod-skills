---
name: "wwmi-accessory-delay"
description: "给定配件/饰品的 vb0 hash 与延迟帧数，生成 WWMI 延迟显示 ini：用 Pool 按 FRAME_NUMBER 保存 vs-cb3/vs-cb4 骨骼矩阵，handling = skip 后改绑 N 帧前的矩阵 drawindexed 重画，使饰品延迟显示（N=1 时与合并骨骼人物的一帧延迟对齐）。当用户要求让某配件/饰品延迟显示、延迟 N 帧、生成或修改 accessory delay / delay.ini 时使用。"
---

# WWMI 配件饰品延迟显示生成指南

输入饰品 vb0 hash + 延迟帧数，生成可直接放入 `WWMI/Mods/` 的独立 ini：Pool 以 `FRAME_NUMBER` 为索引每帧保存饰品的骨骼矩阵常量缓冲（vs-cb4/vs-cb3），命中后 `handling = skip` 并改绑 N 帧前保存的矩阵 `drawindexed = auto` 重画，实现饰品延迟 N 帧显示。

## 何时使用

- 用户要求"让某配件/饰品延迟显示 / 延迟 N 帧"
- 用户要求让饰品与人物（合并骨骼 mod）的一帧延迟对齐（N = 1）
- 用户给出 delay.ini 模板，要求套用到新的模型 hash 或修改延迟帧数

## 原理

- WWMI 合并骨骼 mod 要收集全部矩阵后到下帧使用 → 人物整体延迟 1 帧；配件饰品没有这个延迟，盯帧可见 1 帧错位。
- 饰品 draw 时把当前绑定的骨骼矩阵 CB 复制进 Pool（按帧号索引）；重画时改绑 `FRAME_NUMBER - N` 帧的矩阵 → 视觉延迟 N 帧。
- 槽位无有效数据（前 N 帧预热期 / 已过期）时 `#Pool[$index] == -1`，不 skip 不重画，正常绘制。

## 输入

| 参数 | 必填 | 说明 |
|------|------|------|
| hash | 是 | 目标饰品 **vb0 hash**（8 位 hex，如 `e04b517b`）。来源：开启日志后 `d3d11_log.txt` 的 DrawIndexed 行 `vb0 hash = xxxxxxxx`，或 hunting 模式查看；通过装备/隐藏该饰品对照定位其 draw |
| 延迟帧数 N | 否 | 默认 60；与人物合并骨骼延迟对齐用 1 |
| 输出路径 | 否 | 默认建议 `WWMI\Mods\AccessoryDelay\AccessoryDelay_<hash>.ini`（`d3dx.ini` 的 `include_recursive = Mods` 会自动加载） |

## 使用脚本（推荐）

`scripts/generate_delay_ini.ps1` 封装校验 hash → 计算 Pool 参数 → 生成 ini（UTF-8 BOM + CRLF）的完整流程：

```powershell
# 生成（默认延迟 60 帧）
powershell -ExecutionPolicy Bypass -File f:\AI\mod-skills\wwmi-accessory-delay\scripts\generate_delay_ini.ps1 `
  -Hash    e04b517b `
  -Delay   60 `
  -OutFile "f:\Mod\3Dmigoto Game\XXMI-Launcher-Portable-v1.8.7\WWMI\Mods\AccessoryDelay\AccessoryDelay_e04b517b.ini"

# 仅预览不写盘：省略 -OutFile 或加 -Preview
# 覆盖已存在文件：加 -Force；自定义 namespace：-Namespace "Mods\xxx"
```

## 生成模板（脚本输出结构）

```ini
; WWMI 配件饰品延迟显示
; vb0 hash: <hash>    延迟: <N> 帧

namespace = Mods\AccessoryDelay_<hash>

[Constants]
global $accessory_status = 0

[PoolAccessoryVSCB4]
pool_size = <按 N 查表>
pool_index_type = fifo
pool_expiration_timeout_frames = <按 N 查表>
pool_expiration_refresh_on_read = 1

[PoolAccessoryVSCB3]
pool_size = <按 N 查表>
pool_index_type = fifo
pool_expiration_timeout_frames = <按 N 查表>
pool_expiration_refresh_on_read = 1

[Present]
$accessory_status = 0

[TextureOverride_Accessory]
hash = <hash>
if $accessory_status != 2
    if $accessory_status == 0
        if vs-cb4 == 3381.7777
            PoolAccessoryVSCB4[FRAME_NUMBER] = copy vs-cb4
            $accessory_status = 1
        endif
    endif
    if $accessory_status == 1
        if vs-cb4 == 3381.7777 && vs-cb3 == 3381.7777
            PoolAccessoryVSCB3[FRAME_NUMBER] = copy vs-cb3
            $accessory_status = 2
        endif
    endif
endif

local $index = FRAME_NUMBER - <N>

if #PoolAccessoryVSCB4[$index] != -1

    handling = skip

    if vs-cb4 == 3381.7777
        vs-cb4 = ref PoolAccessoryVSCB4[$index]
        if vs-cb3 == 3381.7777
            vs-cb3 = ref PoolAccessoryVSCB3[$index]
        endif
    elif vs-cb3 == 3381.7777
        vs-cb3 = ref PoolAccessoryVSCB4[$index]
    endif

    drawindexed = auto

endif
```

## Pool 参数按延迟帧数 N

| N | pool_size | pool_expiration_timeout_frames | pool_expiration_refresh_on_read |
|---|-----------|--------------------------------|---------------------------------|
| 1 | 2 | 省略 | 省略 |
| >1 | ≥ 2N 的最小 2 的幂（60 → 128） | 2N（60 → 120） | 1 |

- 过期机制（N>1）：饰品长时间不可见后旧矩阵失效，重新出现时不会闪回旧姿势；预热期（出现后的前 N 帧）槽位为空 → 正常显示，之后延迟自动生效。

## 关键点

- `hash = <vb0 hash>`：目标饰品的 vb0 hash，不要填 IB/ps hash。
- `3381.7777` **不可改动**：WWMI-Tool 导出 mod 中 `[TextureOverrideMarkBoneDataCB]` 的 `filter_index` 标记（骨骼矩阵 CB 的社区约定值）。`vs-cb4 == 3381.7777` 判断当前绑定 cb4 是否为骨骼矩阵缓冲。
  - **前提**：已安装至少一个带该标记的 wwmi-tool mod，否则条件永不命中、延迟不生效。若没有，需在 ini 中自行补充该标记节。
- `$accessory_status` 状态机：每帧该饰品有多个 draw，只需复制一次，避免重复 copy；`[Present]` 每帧重置为 0。
- 两段捕获：先 cb4（仅要求 vs-cb4 命中），再 cb3（要求 cb3 与 cb4 **同时**命中）→ 应对部分特效 draw 只有 cb3 有矩阵的情况。
- 重画分支：cb4 命中 → cb4/cb3 均替换；仅 cb3 命中（特效 draw）→ 用保存的 CB4 矩阵替换 cb3（其角色对应模型的 vs-cb4）。
- `FRAME_NUMBER`：当前帧号（Present 调用定义帧边界）。

## 多饰品共存

- 每个饰品独立一个 ini，`namespace = Mods\AccessoryDelay_<hash>` → 变量（`$accessory_status`）与 Pool 节随 namespace 隔离，互不冲突，无需改名。
- 多个 ini 各自的 `[Present]` 会全部执行，无需合并。
- **同一 hash 只能有一个延迟节**：若替换现有实现（如 `Mods\New Folder\delay.ini` 已延迟 `e04b517b`），先删除/禁用旧节，否则同帧双重 skip + 重画会导致重复绘制。

## 注意事项

- 生成文件编码为 UTF-8 BOM + CRLF，不要用会改变编码/换行的编辑方式保存。
- 脚本默认拒绝覆盖已存在文件（-Force 才覆盖）；手改生成文件前先备份。
- 建议延迟 ≤ 120 帧（2 秒 @60fps），过大无意义且 Pool 占用增大（脚本超限会警告）。
- 验证：游戏内观察饰品是否滞后 N 帧；`-Delay 1` 时饰品应与人物动作完全同步；调试时可临时调大 N（如 30/60）肉眼确认后再回调。
- 若延迟后饰品特效异常，检查对应特效 draw 的 cb3/cb4 命中分支（仅 cb3 的 draw 走 elif 分支）。

## 检查清单

- [ ] hash 为该饰品 vb0 hash（8 位 hex），非 IB/ps hash
- [ ] 延迟帧数确认（1 = 对齐人物合并骨骼，N = 自定义）
- [ ] 已安装带 `[TextureOverrideMarkBoneDataCB]` `filter_index = 3381.7777` 标记的 wwmi-tool mod
- [ ] 同一 hash 没有其他延迟节残留（如旧 delay.ini）
- [ ] 文件位于 WWMI/Mods/ 下，UTF-8 BOM + CRLF
- [ ] 游戏内验证：延迟生效、无旧姿势闪烁、预热期正常显示
