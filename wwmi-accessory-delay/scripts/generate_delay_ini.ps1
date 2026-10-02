# 生成 WWMI 配件饰品延迟显示 ini（wwmi-accessory-delay skill）
# 用 Pool 按 FRAME_NUMBER 保存 vs-cb3/vs-cb4 骨骼矩阵，N 帧后重画。
# 用法示例：
#   powershell -ExecutionPolicy Bypass -File generate_delay_ini.ps1 -Hash e04b517b -Delay 60 -OutFile "...\WWMI\Mods\AccessoryDelay\AccessoryDelay_e04b517b.ini"
#   仅预览：省略 -OutFile 或加 -Preview；覆盖已存在文件：-Force
param(
    [Parameter(Mandatory = $true)]
    [string]$Hash,
    [int]$Delay = 60,
    [string]$OutFile = "",
    [string]$Namespace = "",
    [switch]$Preview,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ---- 校验 hash（8 位 hex，允许 0x 前缀）----
$h = $Hash.Trim().ToLower()
if ($h.StartsWith('0x')) { $h = $h.Substring(2) }
if ($h -notmatch '^[0-9a-f]{8}$') {
    throw "Hash '$Hash' 不是 8 位十六进制 vb0 hash（示例：e04b517b）"
}

# ---- 校验延迟帧数 ----
if ($Delay -lt 1) { throw "Delay 必须 >= 1（1 = 与人物合并骨骼一帧延迟对齐）" }
if ($Delay -gt 120) {
    Write-Warning "Delay = $Delay 帧 > 120：Pool 占用与延迟幅度都会明显增大，请确认确有需要"
}

# ---- namespace（默认按 hash 隔离，多饰品共存）----
if (-not $Namespace) { $Namespace = "Mods\AccessoryDelay_$h" }

# ---- Pool 参数 ----
# N == 1: pool_size = 2，无过期配置（社区模板约定）
# N  > 1: pool_size = >= 2N 的最小 2 的幂；expiration = 2N；读时刷新
$expiration = $null
if ($Delay -le 1) {
    $poolSize = 2
} else {
    $poolSize = 2
    while ($poolSize -lt (2 * $Delay)) { $poolSize *= 2 }
    $expiration = 2 * $Delay
}

function New-PoolBlock([string]$name, [int]$size, [object]$exp) {
    $lines = @("[$name]", "pool_size = $size", "pool_index_type = fifo")
    if ($null -ne $exp) {
        $lines += "pool_expiration_timeout_frames = $exp"
        $lines += "pool_expiration_refresh_on_read = 1"
    }
    return $lines
}

# ---- 组装 ini 内容（行数组保证 CRLF 输出）----
$nl = "`r`n"
$lines = @(
    '; WWMI 配件饰品延迟显示',
    ('; vb0 hash: {0}    延迟: {1} 帧' -f $h, $Delay),
    '; 由 wwmi-accessory-delay skill 生成',
    '',
    ('namespace = {0}' -f $Namespace),
    '',
    '[Constants]',
    'global $accessory_status = 0',
    ''
) + (New-PoolBlock 'PoolAccessoryVSCB4' $poolSize $expiration) + @('') +
  (New-PoolBlock 'PoolAccessoryVSCB3' $poolSize $expiration) + @(
    '',
    '[Present]',
    '$accessory_status = 0',
    '',
    '[TextureOverride_Accessory]',
    ('hash = {0}' -f $h),
    'if $accessory_status != 2',
    '    if $accessory_status == 0',
    '        if vs-cb4 == 3381.7777',
    '            PoolAccessoryVSCB4[FRAME_NUMBER] = copy vs-cb4',
    '            $accessory_status = 1',
    '        endif',
    '    endif',
    '    if $accessory_status == 1',
    '        if vs-cb4 == 3381.7777 && vs-cb3 == 3381.7777',
    '            PoolAccessoryVSCB3[FRAME_NUMBER] = copy vs-cb3',
    '            $accessory_status = 2',
    '        endif',
    '    endif',
    'endif',
    '',
    ('local $index = FRAME_NUMBER - {0}' -f $Delay),
    '',
    'if #PoolAccessoryVSCB4[$index] != -1',
    '',
    '    handling = skip',
    '',
    '    if vs-cb4 == 3381.7777',
    '        vs-cb4 = ref PoolAccessoryVSCB4[$index]',
    '        if vs-cb3 == 3381.7777',
    '            vs-cb3 = ref PoolAccessoryVSCB3[$index]',
    '        endif',
    '    elif vs-cb3 == 3381.7777',
    '        vs-cb3 = ref PoolAccessoryVSCB4[$index]',
    '    endif',
    '',
    '    drawindexed = auto',
    '',
    'endif',
    ''
)

$content = ($lines -join $nl) + $nl

# ---- 输出 ----
if ($Preview -or -not $OutFile) {
    Write-Host $content
    if (-not $OutFile) {
        Write-Host "[预览模式] 加 -OutFile <路径.ini> 写入文件；-Force 覆盖已存在文件"
    }
    exit 0
}

# 解析为绝对路径（文件可不存在的相对路径也支持）
$outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
$dir = Split-Path -Parent $outPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
if ((Test-Path -LiteralPath $outPath) -and -not $Force) {
    throw "目标文件已存在：$outPath（加 -Force 覆盖）"
}

# UTF-8 BOM + CRLF（WWMI ini 惯例）
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($outPath, $content, $utf8Bom)

Write-Host "已生成：$outPath"
Write-Host "  vb0 hash : $h"
Write-Host "  延迟     : $Delay 帧"
Write-Host "  pool_size: $poolSize" $(if ($null -ne $expiration) { "  过期帧数 : $expiration" })
Write-Host "  namespace: $Namespace"
Write-Host "提示：需已安装带 [TextureOverrideMarkBoneDataCB] filter_index = 3381.7777 标记的 wwmi-tool mod；"
Write-Host "      同一 hash 不能同时存在多个延迟节（如旧 delay.ini），需先移除。"
