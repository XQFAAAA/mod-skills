---
name: "wwmi-ui-regex-to-hash"
description: "将 WWMI ShaderRegex 正则（如 HideUI_Regex.ini 的 UI 隐藏正则）在 d3d11_log.txt 中命中的像素着色器 hash 提取去重，并按 ShaderOverride 哈希节模板（allow_duplicate_hash = overrule + run = CommandListUI）写入 HideUI_Hash.ini，把正则隐藏方案转为 hash 精确匹配方案。当用户要求收集正则匹配到的 shader hash、UI 正则转 hash、为正则命中的着色器建 ShaderOverride 时使用。"
---

# WWMI UI 正则转 Hash 指南

把 `[ShaderRegex*]` 正则匹配（每次 shader 加载都要反汇编 + 正则匹配，开销大）固化为 `[ShaderOverride*]` 精确 hash 匹配：从 `d3d11_log.txt` 提取正则命中的所有像素着色器 hash，去重后以统一模板写入 hash ini，复用其中已有的 CommandList 做条件跳过。

## 何时使用

- 用户要求"把 UI 正则转成 hash"、"收集日志中正则匹配到的着色器 hash"
- 用户要求为某个 `HideUI_*_Regex.ini` 生成对应的 `HideUI_*_Hash.ini` ShaderOverride 节
- 正则 ini 更新了 pattern，需要重新收集命中 hash 更新 hash ini

## 输入文件（三个）

| 文件 | 说明 |
|------|------|
| 正则 ini | 如 `Mods/character/others/UI/HideUI_Regex.ini`，含 `[ShaderRegexXxx]` + `[ShaderRegexXxx.Pattern]` |
| `d3d11_log.txt` | WWMI 根目录；必须是在该正则 ini 生效、开启日志且游戏内加载过相关 UI 画面时抓取的 |
| 目标 hash ini | 如 `Mods/character/others/UI/HideUI_Hash.ini`，须已含 `[CommandListUI]`（`if $enable == 1 / handling = skip / endif`）与至少一个 `[ShaderOverride*]` 模板块 |

## 日志行格式（关键）

```
ShaderRegex: ps_5_0 <16位hex hash> matches [ShaderRegex\<Mods下相对路径>\<ini文件名>\<节名>]
```

示例：

```
ShaderRegex: ps_5_0 0f8b8a0411198826 matches [ShaderRegex\Mods\character\others\UI\HideUI_Regex.ini\UI]
```

- 同一 hash 可同时命中多个正则节（如 DynamicUI + UI），去重后每个 hash 只生成一节
- `shader_model = ps_5_0` 只命中像素着色器；日志中的 vs/cs 命中（如 WWMIv1\EnableTextureOverrides）与本项目无关
- 必须按 ini 文件名过滤，避免混入其他 ini 的正则命中
- 若日志格式与上述不符，先 `grep "ShaderRegex"` 确认实际格式再调整脚本中的模式

## 输出节模板（与既有条目保持一致）

```ini
[ShaderOverride_<hash>]
hash = <hash>
allow_duplicate_hash = overrule
run = CommandListUI
```

- `allow_duplicate_hash = overrule`：允许与其他 ShaderOverride 节共用同一 hash
- 插入位置：现有 `[ShaderOverride*]` 块（`run = <CommandList>` 行）之后、其余节（TextureOverride 等）之前
- **保留既有条目**：手动添加过的 hash（如 `9f56b28db5ba5a73`）在日志中未必有正则命中记录，不得删除
- 与目标 ini 中已存在的 hash 去重，重复运行脚本不会产生重复节

## 使用脚本（推荐）

`scripts/extract_regex_hashes.ps1` 封装了收集节名 → 扫描日志 → 去重 → 插入 → 保留编码的完整流程：

```powershell
# 试运行（不写文件，只报告命中的节名/hash 数量与将插入的内容预览）
powershell -ExecutionPolicy Bypass -File f:\AI\mod-skills\wwmi-ui-regex-to-hash\scripts\extract_regex_hashes.ps1 `
  -RegexIni  "f:\Mod\3Dmigoto Game\XXMI-Launcher-Portable-v1.8.7\WWMI\Mods\character\others\UI\HideUI_Regex.ini" `
  -LogPath   "f:\Mod\3Dmigoto Game\XXMI-Launcher-Portable-v1.8.7\WWMI\d3d11_log.txt" `
  -HashIni   "f:\Mod\3Dmigoto Game\XXMI-Launcher-Portable-v1.8.7\WWMI\Mods\character\others\UI\HideUI_Hash.ini" `
  -DryRun

# 确认无误后去掉 -DryRun 正式写入；CommandList 名不同时加 -RunCommand Xxx
```

手动实现时的核心 PowerShell（去重提取部分）：

```powershell
Select-String -Path <日志> -Pattern 'ShaderRegex: ps_5_0 ([0-9a-f]{16}) matches \[ShaderRegex\\.*?\\HideUI_Regex\.ini\\(UI|UI3d|UIDtest|DynamicUI|Map|MapLayer)\]' |
  ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique
```

## 编码与格式（不可破坏）

- 目标 ini 为 UTF-8 带 BOM（EF BB BF）+ CRLF 时，必须原样保留
- 用 `[System.IO.File]::ReadAllText` / `WriteAllText` + `UTF8Encoding($hasBom)` 读写；不要用 `Set-Content -Encoding UTF8`（Windows PowerShell 5.1 会强制加 BOM，且可能改变换行）

## 注意事项

- 日志可达 100MB+，`Select-String` 全文扫描需给足超时（约 3-5 分钟）
- 转 hash 后正则 ini 仍会继续生效（重复 skip 无害）；如需完全切换以省开销，另确认后注释掉正则 ini 的 `[ShaderRegex*]` 节（`.Pattern` 随节一起失效）
- ShaderRegex 只匹配原始字节码；若该 hash 的 shader 已被 ShaderFixes 替换或属于 CustomShader bypass 流程，正则不生效，hash 方案不受此限制
- 游戏版本更新后出现新 UI shader，日志中会出现新 hash，重跑本 skill 即可增量补齐
- 目标 ini 的 CommandList 名不一定叫 `CommandListUI`，以实际文件为准

## 检查清单

- [ ] 正则节名全部收集（排除 `.Pattern` 节）
- [ ] 日志命中按 ini 文件名过滤，未混入其他 ini（如 WWMIv1\EnableTextureOverrides）
- [ ] hash 去重：多节命中只留一个节；与目标 ini 已有 hash 去重
- [ ] 既有条目全部保留，插入格式与现有模板块一致
- [ ] 文件 BOM 与 CRLF 未改变
- [ ] 试运行确认数量后正式写入
- [ ] 游戏内验证：切换隐藏键（如 Alt+X）UI 隐藏效果与正则方案一致
