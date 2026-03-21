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
    analyticalAAEnabled = true,
    interlacedMode = "off",
    upscaleMode = "bilinear",
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
- `ApplyTopoModeMorph(modeA, modeB, t, { strengthA?, strengthB?, applyTheme? })`
- `SetTopoModeMorph(t, { strengthA?, strengthB?, applyTheme? })`
- `ApplyFakeBackdropQuality("low" | "balanced" | "high")`
- `ExportCurrentConfig()` (returns cloned current config table)
- `ApplyConfigPreset(presetTable)` (safe bulk apply)
- `SetStates(statesTable)` / `RegisterState(name, cfg)` / `SetState(name)`
- `ApplyDesignTokens(tokensTable)` (designer-friendly token mapping)
- `SetDebugEnabled(boolean)`
- `GetDebugReport()`
- `FormatDebugReport()`
- `SetParallelEnabled(boolean)`
- `BeginAutoTune()` (tests candidates and applies best profile for your hardware)

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

## Topo Mode Morphing

You can morph between two topo modes with independent strengths, similar to layered shader blending.

```lua
shader:ApplyTopoModeMorph("classic", "precision", 0.35, {
    strengthA = 1.0,
    strengthB = 1.25,
    applyTheme = true,
})

-- animate later:
shader:SetTopoModeMorph(0.60)
```

- `t = 0` means fully mode A, `t = 1` means fully mode B.
- `strengthA/strengthB` bias influence while morphing.
- Numeric and color fields are interpolated; discrete mode flags pick the dominant side.

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
- `analyticalAAEnabled`
  - **What**: explicit analytical contour widening based on local slope.
  - **Use**: improves small-line stability without forcing full post-AA.
- `analyticalAAStrength`
  - **What**: amount of analytical widening.
  - **Higher**: cleaner thin lines, but can look softer.
- `softEdgesEnabled`
  - **What**: writes smooth contour coverage into the buffer instead of hard edge transitions.
- `softEdgeWidth`
  - **What**: soft transition width relative to contour half-width.
  - **Higher**: softer edge rolloff.
- `softEdgeCurve`
  - **What**: shaping curve for soft-edge falloff.
  - **Higher**: crisper edge, lower: smoother edge.
- `adaptiveSamplingEnabled`
  - **What**: dynamic AA sampling budget per pixel.
  - **Use**: reduces cost on simple/straight areas, keeps quality on important edges.
- `aaEdgeThreshold`
  - **What**: minimum local gradient before extra subpixel sampling runs.
  - **Higher**: faster, less micro-detail AA.
- `verticalAABoost`
  - **What**: increases AA sampling spread on vertical-dominant edges.
  - **Use**: cleaner verticals with less overall budget increase.
- `generatorScaleEnabled`
  - **What**: enables edge-aware reconstruction smoothing pass after main shading.
  - **Why**: smoother upscale/jagged transitions without full blur look.
- `generatorScaleStrength`
  - **What**: blend amount of reconstructed neighbors.
  - **Higher**: stronger smoothing.
- `generatorScaleThreshold`
  - **What**: edge sensitivity threshold for reconstruction.
  - **Lower**: triggers on more edges/details.
- `generatorScaleAlpha`
  - **What**: alpha blending amount during generator scaling.
  - **Higher**: softer transparency around line edges.
- `generatorScaleInterval`
  - **What**: run generator scaling every Nth frame.
  - **Higher**: cheaper, slightly less consistent smoothing.
- `generatorVerticalBias`
  - **What**: prioritizes reconstruction strength for vertical-dominant edges.
  - **Use**: keeps verticals cleaner while saving budget elsewhere.
- `fakeAABlurEnabled`
  - **What**: tiny edge-gated blur pass for perceptual anti-aliasing.
  - **Use**: smooths residual shimmer/jaggies without full-scene blur.
- `fakeAABlurStrength`
  - **What**: blend amount of fake blur.
  - **Higher**: smoother but can get soft quickly.
- `fakeAABlurThreshold`
  - **What**: edge sensitivity threshold for fake blur.
  - **Lower**: affects more pixels.
- `fakeAABlurInterval`
  - **What**: run fake blur every Nth frame.
  - **Higher**: lower cost.

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
- `interlacedMode`
  - `off`: render full frame normally.
  - `checkerboard`: interlaced checkerboard path (performance mode).
- `temporalBlend`
  - **What**: blend with previous frame.
  - **Higher**: smoother shimmer, more ghosting risk.

### Upscaling

- `upscaleMode`
  - `bilinear`: smoother upscale (recommended default).
  - `nearest`: pixelated upscale for retro/debug look.

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
- `topoModeAppliesTheme`
  - **What**: when true, `ApplyTopoMode` also maps to a matching theme for strong visual shifts.

### Topographic Modes

Built-in topo modes now include:

- `classic`
- `godRays`
- `precision`
- `bold`
- `dream`
- `wireframe`
- `molten`
- `glacier`
- `radar`
- `sunset`

### Interaction

- `mouseEnabled`
- `mouseRadius`
- `mouseStrength`
  - **Higher strength/radius** can add work and visual warping.
- `cursorDitherEnabled`
  - **What**: enables cursor-driven dithering on contour lines.
- `cursorDitherRadius`
  - **What**: radius around cursor where dithering applies.
- `cursorDitherStrength`
  - **What**: intensity of dither line attenuation.
- `cursorDitherScale`
  - **What**: dither cell size.
- `cursorDitherPattern`
  - `bayer4` or `checker`.

### Designer State / Token Features

- `SetStates({...})`
  - Register multiple UI states in one call.
- `SetState("idle" | "hover" | "pressed" | ...)`
  - Instantly apply a named visual state.
- `ApplyDesignTokens({...})`
  - Designer-centric mapping layer:
    - `surfaceColor` -> `bgColor`
    - `foregroundColor` -> `lineColor`
    - `accentLow`/`accentHigh` -> tint gradient
    - `motion` -> `animSpeed` scale
    - `roundness` -> `cornerRadius`
    - `blur` -> local backdrop blur strength
    - `opacity` -> `outputOpacity`

## Showcase Runners

The `showcases/` folder includes ready examples:

- `Showcase_Balanced.luau` (baseline production setup)
- `Showcase_States.luau` (idle/hover/pressed state switching)
- `Showcase_Tokens.luau` (design token workflows for UI designers)
- `Showcase_AutoTune_Parallel.luau` (parallel + auto-tune hardware benchmark)

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
- `parallelTileWidth`, `parallelTileHeight`
  - **What**: worker tile size for tile-based rendering jobs.
- `parallelProgressive`
  - **What**: updates subset of tiles per frame for higher FPS.
- `parallelTilesPerFrame`
  - **What**: number of tiles dispatched each frame (progressive mode).
- `fakeLocalBackdropEnabled`
  - **What**: enables ViewportFrame-based local backdrop blur workaround (panel-only).
- `fakeLocalBackdropQuality`
  - `low`: fastest, fewer parts, softer/less accurate.
  - `balanced`: recommended default.
  - `high`: best local backdrop quality, highest cost.
- `fakeLocalBackdropAlpha`
  - **What**: visibility of the local backdrop layer.
- `fakeLocalBackdropRefreshHz`
  - **What**: backdrop sync refresh rate. Lower = cheaper.
- `fakeLocalBackdropMaxParts`
  - **What**: cap on cloned parts for local backdrop.
- `fakeLocalBackdropDistance`
  - **What**: only parts near camera are cloned/synced.
- `fakeLocalBackdropRebuildSec`
  - **What**: how often the part set is rescanned.
- `fakeLocalBackdropSimplify`
  - **What**: simplifies materials/colors for blur-like appearance and lower cost.
- `fakeLocalBackdropBlurStrength`
  - **What**: strength of the frosted blur simulation (desaturation + transparency + edge bleed).

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

### Local Backdrop Blur (UI-only workaround)

```lua
shader:Configure({
    fakeLocalBackdropEnabled = true,
    fakeLocalBackdropQuality = "balanced",
    fakeLocalBackdropAlpha = 0.30,
})
```

For weaker devices:

```lua
shader:ApplyFakeBackdropQuality("low")
```

For showcase captures:

```lua
shader:ApplyFakeBackdropQuality("high")
```

## Keybinds in `ShaderRunner.luau`

- `P`: pause/resume
- `[ / ]`: contour levels down/up
- `1 / 2 / 3`: quality preset (locks adaptive off)
- `4 / 5`: topo mode morph `t` down/up
- `6`: cycle morph target mode B
- `7 / 8 / 9`: visual profile
- `T`: cycle theme
- `Y`: cycle fake local backdrop quality (`low/balanced/high`)
- `M`: mouse on/off
- `X`: cursor dither on/off
- `C`: cursor dither pattern cycle (`bayer4/checker`)
- `; / '`: mouse strength down/up (`- / =` aliases included)
- `, / .`: mouse radius down/up
- `V`: vignette on/off
- `B`: line AA toggle
- `U`: line AA mode cycle (`off/fast/msaa4`)
- `L`: analytical AA toggle
- `Q`: upscale mode cycle (`bilinear/nearest`)
- `\`: interlaced mode cycle (`off/checkerboard`)
- `N`: edge AA quality cycle (`fast/hq`)
- `Z`: generator scaling toggle
- `K`: adaptive quality toggle
- `0`: force adaptive quality on
- `F8`: debug overlay
- `F9`: print debug report
- `F10`: parallel mode toggle
- `F6`: auto-tune best settings
- `I / O`: tiles-per-frame down/up (parallel progressive tuning)
- `H`: key help
- `J`: config schema/template help

## Actor Worker Setup (Parallel Luau)

Current shader uses safe fallback if actor pool is missing or incomplete.

**Where to put `TopoActors` (important):**

The module looks for a folder named `TopoActors` in this order:

1. Under the **`TopoShader` ModuleScript** (original layout), or  
2. Under the **parent** of `TopoShader` (typical: your runner script contains both `TopoShader` and `TopoActors`), or  
3. Under that parent’s parent (e.g. `ScreenGui`).

So this **does** work: `ScreenGui` → `ShaderRunner` → `TopoActors` + `TopoShader` as siblings.

`Actor` is a normal `Instance` and can be parented under UI hierarchies; parallel workers still run as long as the worker script is inside an `Actor` with the bindables above.

**Inside `TopoActors`:**

1. Add one or more `Actor` children (one is enough; extra actors are used in round-robin).
2. Inside each `Actor`, add:
   - `BindableEvent` named `RenderRequest`
   - `BindableEvent` named `RenderDone`
   - Script with source from `TopoActorWorker.luau`

Then:

```lua
shader:Configure({
    parallelEnabled = true,
    parallelWorkers = 4, -- desired; fewer physical Actors still work
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

