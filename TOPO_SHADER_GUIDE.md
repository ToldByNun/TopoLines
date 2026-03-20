# TopoShader Guide

This guide explains how to configure `TopoShader` in depth, including what each option does, valid modes, and how to tune for either quality or performance.

## Quick Start

```lua
local TopoShader = require(script:WaitForChild("TopoShader"))

local shader = TopoShader.new(script.Parent, {
    width = 460,
    height = 300,
    qualityPreset = "balanced",
    visualProfile = "balanced",
    theme = "classic",
})

shader:SetPosition(UDim2.fromScale(0.5, 0.5))
shader:SetAnchor(Vector2.new(0.5, 0.5))
shader:ApplyTheme("classic")
shader:Start()
```

## Safe Configuration Workflow

`TopoShader` validates and clamps config values internally, so beginners can tweak safely.

- Use `shader:SetConfig(key, value)` for one setting.
- Use `shader:Configure({...})` for multiple settings.
- Use `shader:GetConfigTemplate()` for the full default config.
- Use `shader:GetConfigSchema()` to inspect valid ranges/types.

```lua
shader:Configure({
    contourLevels = 14,
    lineWidth = 0.09,
    lineAAMode = "msaa4",
    frameBudgetMs = 16,
})
```

## Main APIs

- `Start()` / `Stop()` / `Destroy()`
- `SetPosition(udim2)` / `SetAnchor(vec2)`
- `SetConfig(key, value)`
- `Configure(optionsTable)`
- `SetQualityPreset("performance" | "balanced" | "quality")`
- `SetVisualProfile("performance" | "balanced" | "cinematic")`
- `SetPerformanceOptions({ frameBudgetMs, fps, adaptiveQuality, edgeAAInterval })`
- `SetMouseEnabled(boolean)`
- `SetMouseInteraction(radius, strength, enabledOptional)`
- `ApplyTheme(name)`
- `GetThemeNames()`
- `SetDebugEnabled(boolean)`
- `GetDebugReport()`
- `FormatDebugReport()`
- `SetParallelEnabled(boolean)`

## Presets vs Profiles

- **`qualityPreset`**: performance behavior and render workload.
  - `performance`: fastest, least expensive AA path.
  - `balanced`: good quality/perf middle ground.
  - `quality`: best visual quality, heaviest.
- **`visualProfile`**: look style tuning.
  - `performance`: crisper/thinner, lighter.
  - `balanced`: neutral.
  - `cinematic`: smoother/softer with richer polish.

Use both together: for example `qualityPreset="balanced"` + `visualProfile="cinematic"`.

## Full Config Reference

### Panel / Resolution

- `width`, `height`
  - **What**: UI panel size on screen.
  - **Higher**: bigger panel (does not directly change internal pixel cost).
- `renderWidth`, `renderHeight`
  - **What**: internal shader resolution.
  - **Higher**: much cleaner lines, significantly more CPU work.
  - **Lower**: faster, more pixelation.
  - **Tip**: this is your #1 quality/perf lever.
- `cornerRadius`
  - **What**: rounded panel corners.
  - **Visual only**.

### Contours

- `contourLevels`
  - **What**: number of topo bands.
  - **Higher**: denser line field.
- `lineWidth`
  - **What**: line thickness in band fraction.
  - **Higher**: fewer dotted artifacts, stronger lines.
  - **Lower**: more delicate lines, easier to alias.
- `lineSharpness`
  - **What**: post shaping on line mask.
  - `>1`: crisper/thinner look.
  - `<1`: softer/thicker edges.

### Noise / Motion

- `baseFrequency`
  - **What**: macro scale of terrain.
  - **Higher**: tighter/smaller features.
- `octaves`
  - **What**: fine detail layers.
  - **Higher**: richer detail, heavier cost.
- `lacunarity`
  - **What**: frequency multiplier between octaves.
  - **Higher**: more high-frequency detail.
- `persistence`
  - **What**: amplitude falloff between octaves.
  - **Higher**: keeps fine detail stronger.
- `warpAmount`
  - **What**: domain distortion strength.
  - **Higher**: more organic/folded shapes, heavier.
- `animSpeed`, `animAngle`
  - **What**: contour drift speed and direction.
- `fastMode`, `ultraFastMode`
  - **What**: cheaper field evaluators.
  - **Use**: for low-end performance.

### Anti-Aliasing (Most Important for Pixelation)

- `lineAAEnabled`
  - **What**: adaptive in-main-pass contour AA.
- `lineAAMode`
  - `off`: no line AA
  - `fast`: gradient-assisted smoothing
  - `msaa4`: multi-sample (best for tiny lines)
- `lineAAStrength`
  - **What**: how much adaptive widening is applied near edges.
  - **Higher**: smoother but can soften too much.
- `lineAAStep`
  - **What**: sampling distance used for local gradient.
- `lineAASubpixel`
  - **What**: subpixel offset size for `msaa4`.
  - **Higher**: stronger anti-aliasing, a bit softer.

- `edgeAAEnabled`
  - **What**: post-process edge filter.
- `edgeAAQuality`
  - `fast`: 4-neighbor blend
  - `hq`: 8-neighbor blend (cleaner)
- `edgeAAStrength`
  - **What**: blend amount toward neighbor average.
  - **Higher**: smoother edges, more blur risk.
- `edgeAAThreshold`
  - **What**: contrast threshold to trigger AA.
  - **Lower**: AA triggers more often.
- `edgeAAInterval`
  - **What**: run edge AA every Nth frame.
  - **Higher**: faster, less consistent smoothing.

- `checkerboardReconstruction`
  - **What**: half-pixel rendering with reconstruction.
  - **Use carefully**: faster but can cause stipple on thin lines.
- `temporalBlend`
  - **What**: blend with previous frame.
  - **Higher**: smoother shimmer, more ghosting risk.

### Color / Styling

- `bgColor`, `lineColor`
  - **What**: base colors.
- `elevationTint`
  - **What**: tint lines by height.
- `colorLow`, `colorHigh`
  - **What**: tint gradient endpoints.
- `tintAmount`
  - **What**: tint intensity.
- `glowEnabled`, `glowStrength`
  - **What**: glow/bleed around bright lines.
  - **Cost**: can be expensive.
- `vignetteEnabled`, `vignetteStrength`
  - **What**: edge darkening for depth.
- `theme`
  - **Enum**: `classic`, `ocean`, `neon`, `paper`

### Interaction

- `mouseEnabled`
- `mouseRadius`
- `mouseStrength`
  - **Higher strength/radius** can add work and visual warping.

### Performance / Runtime

- `qualityPreset`
  - `performance` / `balanced` / `quality`
- `visualProfile`
  - `performance` / `balanced` / `cinematic`
- `adaptiveQuality`
  - **What**: auto-switches quality preset based on frame budget.
- `frameBudgetMs`
  - **What**: target per-render cost.
  - Lower = stricter (more likely to downshift quality).
- `adaptiveCooldown`
  - **What**: delay between adaptive adjustments.
- `fps`
  - **What**: target shader update rate (not engine FPS).
- `parallelEnabled`, `parallelWorkers`
  - **What**: Actor mode controls.

### Debug

- `debugEnabled`
- `debugUpdateRate`

## Built-In Themes

- `classic`
- `ocean`
- `neon`
- `paper`

```lua
shader:ApplyTheme("ocean")
```

## Tuning Recipes

### Push Quality

```lua
shader:Configure({
    qualityPreset = "quality",
    visualProfile = "cinematic",
    renderWidth = 260,
    renderHeight = 170,
    lineWidth = 0.09,
    lineAAMode = "msaa4",
    lineAAStrength = 2.4,
    edgeAAEnabled = true,
    edgeAAQuality = "hq",
    edgeAAStrength = 0.55,
    edgeAAThreshold = 12,
})
```

### Push Performance

```lua
shader:Configure({
    qualityPreset = "performance",
    renderWidth = 200,
    renderHeight = 130,
    lineAAMode = "off",
    edgeAAEnabled = false,
    glowEnabled = false,
    adaptiveQuality = true,
    frameBudgetMs = 18,
})
```

### Balanced Crisp (recommended baseline)

```lua
shader:Configure({
    qualityPreset = "balanced",
    visualProfile = "balanced",
    lineWidth = 0.085,
    lineAAMode = "fast",
    edgeAAEnabled = false,
})
```

## Keybinds in `ShaderRunner.luau`

- `P`: pause/resume
- `[ / ]`: contour levels down/up
- `1 / 2 / 3`: quality preset (locks adaptive off)
- `7 / 8 / 9`: visual profile
- `T`: cycle theme
- `M`: mouse on/off
- `; / '`: mouse strength down/up (`- / =` aliases included)
- `, / .`: mouse radius down/up
- `V`: vignette on/off
- `B`: line AA toggle
- `U`: line AA mode cycle (`off/fast/msaa4`)
- `N`: edge AA quality cycle (`fast/hq`)
- `K`: adaptive quality toggle
- `0`: force adaptive quality on
- `F8`: debug overlay
- `F9`: print debug report
- `F10`: parallel mode toggle
- `H`: key help
- `J`: config schema/template help

## Actor Worker Setup (Parallel Luau)

Current shader uses safe fallback if actor pool is missing or incomplete.

Required hierarchy:

1. Under `TopoShader` ModuleScript, create folder: `TopoActors`
2. Add multiple `Actor` children (2-8 typical)
3. Inside each `Actor`, add:
   - `BindableEvent` named `RenderRequest`
   - `BindableEvent` named `RenderDone`
   - Script with source from `TopoActorWorker.luau`

Then:

```lua
shader:Configure({
    parallelEnabled = true,
    parallelWorkers = 4,
})
```

If setup is incomplete, debug issues will show `parallel_not_ready`.

## Troubleshooting

- **Preset keeps changing**: `adaptiveQuality` is on. Press `K` to toggle off, or use `1/2/3` (auto-locks off).
- **Lines look dotted**: increase `lineWidth` to around `0.09`, keep `lineAAMode = "msaa4"`.
- **Still jagged**: use `edgeAAEnabled = true`, `edgeAAQuality = "hq"`, and lower `lineSharpness`.
- **Too soft/blurred**: lower `edgeAAStrength`, raise `edgeAAThreshold`, reduce `lineAAStrength`.
- **Too slow**: lower `renderWidth`/`renderHeight`, use `performance`, disable edgeAA/glow.
- **Background 15 FPS when tabbed out**: expected Roblox throttling behavior.

