-- TopoShader (ModuleScript)
-- Topographic contour line shader.
-- Uses AssetService:CreateEditableImage + Luau buffer.

local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local AssetService     = game:GetService("AssetService")
local GuiService       = game:GetService("GuiService")
local Lighting         = game:GetService("Lighting")

local TopoShader = {}
TopoShader.__index = TopoShader

-- ================================================================
--  DEFAULT CONFIG
-- ================================================================
local DEFAULTS = {
	-- Panel display size
	width  = 460,
	height = 300,

	-- Internal render resolution
	-- Half of panel = 2x faster, bilinear stretch looks fine
	renderWidth  = 230,
	renderHeight = 150,
	upscaleMode = "bilinear", -- bilinear | nearest

	-- ── Contour appearance ───────────────────────────────────
	contourLevels = 12,    -- how many contour bands
	lineWidth     = 0.06,  -- fraction of one band that is "line"
	-- 0.04 = hairline, 0.12 = bold

	-- ── Noise field ──────────────────────────────────────────
	-- baseFrequency controls zoom level.
	-- Tune so (renderWidth * baseFrequency) ≈ 1.5–3.0
	-- For renderWidth=230: 0.008 gives ~1.8 hills across. Good.
	baseFrequency = 0.008,

	octaves     = 4,      -- more = more fine detail ridges
	lacunarity  = 2.10,   -- frequency multiplier per octave
	persistence = 0.52,   -- amplitude multiplier per octave

	-- Domain warp: how much the field folds back on itself
	-- 0 = plain FBM,  1.5 = heavily folded organic shapes
	warpAmount  = 1.0,
	fastMode    = true,   -- use cheaper height sampling path
	ultraFastMode = false, -- minimal noise path for weak CPUs
	checkerboardReconstruction = false, -- cleaner default (no checkerboard stipple)
	interlacedMode = "off", -- off | checkerboard
	temporalBlend = 0.12, -- lower history weight = cleaner/less ghosting

	-- ── Animation ────────────────────────────────────────────
	animSpeed = 0.020,   -- how fast contours drift (noise-space/sec)
	animAngle = 0.45,    -- direction of drift (radians)

	-- ── Mouse interaction ─────────────────────────────────────
	-- Cursor creates a local bump that bends nearby contours
	mouseRadius   = 120,   -- pixels (panel space)
	mouseStrength = 0.35,  -- noise-space push magnitude
	mouseEnabled  = true,
	cursorDitherEnabled = false, -- interactive dither around cursor
	cursorDitherRadius = 120, -- panel pixels
	cursorDitherStrength = 0.35, -- 0..1 line attenuation
	cursorDitherScale = 2, -- dither cell scale
	cursorDitherPattern = "bayer4", -- bayer4 | checker

	-- ── Colors ───────────────────────────────────────────────
	bgColor   = { r=0.016, g=0.016, b=0.022, a=1 },
	lineColor = { r=1,     g=1,     b=1,     a=1 },

	-- Lines tinted by elevation (height in noise field)
	elevationTint = true,
	colorLow  = { r=0.15, g=0.35, b=0.75 },  -- deep / valleys
	colorHigh = { r=0.80, g=0.93, b=1.00 },  -- peaks

	-- 0 = pure white lines, 1 = fully elevation-colored
	tintAmount = 0.50,
	lineSharpness = 1.0, -- >1 thinner/crisper, <1 softer/smoother

	-- ── Glow ─────────────────────────────────────────────────
	glowEnabled  = true,
	glowStrength = 0.20,   -- 0–1
	edgeAAEnabled   = true, -- post AA to smooth jagged contour edges
	edgeAAStrength  = 0.55, -- 0-1 blend amount
	edgeAAThreshold = 16,   -- 0-255 contrast threshold
	edgeAAInterval  = 2,    -- apply AA every Nth frame
	edgeAAQuality   = "hq", -- fast | hq
	lineAAEnabled   = true, -- adaptive contour AA in main pass
	lineAAStrength  = 2.0,  -- extra smoothing from local gradient
	lineAAStep      = 0.55, -- noise-space pixel step factor
	lineAAMode      = "msaa4", -- off | fast | msaa4
	lineAASubpixel  = 0.35, -- subpixel offset scale for msaa sampling
	analyticalAAEnabled = true, -- explicit analytical line AA widening
	analyticalAAStrength = 0.85, -- 0..2 analytical coverage strength
	softEdgesEnabled = true, -- soft analytical edge coverage in contour buffer
	softEdgeWidth = 0.30, -- transition width relative to line half-width
	softEdgeCurve = 1.0, -- >1 crisper, <1 softer
	adaptiveSamplingEnabled = true, -- allocate AA samples based on local edge importance
	aaEdgeThreshold = 0.012, -- gradient threshold before expensive subpixel sampling
	verticalAABoost = 0.75, -- extra subpixel spread on vertical-dominant edges
	generatorScaleEnabled = true, -- edge-aware reconstruction smoothing pass
	generatorScaleStrength = 0.42, -- 0..1 blend amount
	generatorScaleThreshold = 0.08, -- 0..1 edge trigger sensitivity
	generatorScaleAlpha = 0.70, -- alpha blend contribution for edge softening
	generatorScaleInterval = 2, -- run every Nth frame to control budget
	generatorVerticalBias = 1.35, -- spend more reconstruction on vertical edges
	fakeAABlurEnabled = false, -- tiny edge-gated blur as perceptual AA helper
	fakeAABlurStrength = 0.16, -- 0..1 blur blend amount
	fakeAABlurThreshold = 0.06, -- 0..1 edge sensitivity (lower = more blur)
	fakeAABlurInterval = 2, -- run every Nth frame

	-- Runtime quality control
	qualityPreset      = "balanced", -- performance | balanced | quality
	adaptiveQuality    = true,       -- auto-tune under heavy load
	frameBudgetMs      = 12.0,       -- target CPU budget per render
	adaptiveCooldown   = 0.35,       -- seconds between quality adjustments
	debugEnabled       = false,      -- live debug overlay + stats
	debugUpdateRate    = 0.25,       -- seconds between overlay updates
	visualProfile      = "balanced", -- performance | balanced | cinematic
	vignetteEnabled    = true,
	vignetteStrength   = 0.10,       -- subtle edge darkening
	parallelEnabled    = false,      -- requires Actor setup in hierarchy
	parallelWorkers    = 4,          -- desired worker count
	parallelChunkRows  = 32,         -- rows per worker chunk
	parallelTileWidth  = 64,         -- tile width for worker jobs
	parallelTileHeight = 64,         -- tile height for worker jobs
	parallelProgressive = true,      -- update subset of tiles each frame
	parallelTilesPerFrame = 6,       -- tiles to update per frame (progressive mode)

	-- ── Misc ─────────────────────────────────────────────────
	fps          = 60,
	cornerRadius = 16,
	panelTransparency = 0.0, -- 0 = opaque panel, 1 = fully transparent
	imageTransparency = 0.0, -- applies to shader image itself
	outputOpacity = 1.0, -- multiplies per-pixel alpha (0..1)
	localBlurEnabled = true, -- prefers per-panel UIBlurEffect when available
	localBlurSize = 10, -- per-panel blur strength
	backgroundBlurEnabled = false, -- uses Lighting.BlurEffect (global blur)
	backgroundBlurSize = 10, -- 0-56 typical
	fakeLocalBackdropEnabled = false, -- ViewportFrame "cheese" local blur backdrop
	fakeLocalBackdropAlpha = 0.35, -- 0..1 visibility of backdrop layer
	fakeLocalBackdropRefreshHz = 15, -- lower = cheaper
	fakeLocalBackdropQuality = "balanced", -- low | balanced | high
	fakeLocalBackdropMaxParts = 350, -- cap cloned parts for backdrop
	fakeLocalBackdropDistance = 180, -- studs from camera to include
	fakeLocalBackdropRebuildSec = 2.5, -- periodic rescan for moving camera/scenes
	fakeLocalBackdropSimplify = true, -- simplify materials/colors for blur-like look
	fakeLocalBackdropPanelOnly = true, -- include only parts visible behind panel area
	fakeLocalBackdropPanelMargin = 48, -- pixel margin around panel bounds
	fakeLocalBackdropBlurStrength = 0.65, -- 0..1 stronger frosted blur simulation
	topoModeAppliesTheme = true, -- make topo mode switches visibly distinct

	-- ── Pre-Cached Loop Playback ──────────────────────────────────
	-- Bake a finite seamless loop once at startup, then play it back
	-- at zero CPU cost by cycling through pre-rendered buffers.
	cacheEnabled        = false,  -- master toggle; false = classic live render path
	loopDuration        = 4.0,    -- seconds for one complete seamless loop
	loopFPS             = 24,     -- frames baked per second (24 = smooth, 30 = smoother)
	loopAmplitude       = 0.15,   -- noise-space travel magnitude over the loop
	loopZAmplitude      = 0.08,   -- z-slice oscillation magnitude
	bakeOnStart         = true,   -- auto-bake when Start() is called
	bakeUseParallel     = true,   -- use Actor workers during bake if available
	mouseOverlayInCache = true,   -- recompute mouse-warp area live on top of cached frame
	onBakeProgress      = nil,    -- callback(doneFrames, totalFrames) — fired each baked frame
	onBakeComplete      = nil,    -- callback() — fired when bake finishes
}

-- Beginner-safe config schema. Values are clamped/sanitized on write.
local CONFIG_RULES = {
	renderWidth = { t = "number", min = 64, max = 1024 },
	renderHeight = { t = "number", min = 64, max = 1024 },
	baseFrequency = { t = "number", min = 0.001, max = 0.05 },
	contourLevels = { t = "number", min = 2, max = 64, integer = true },
	lineWidth = { t = "number", min = 0.02, max = 0.25 },
	lineSharpness = { t = "number", min = 0.7, max = 1.4 },
	topoMode = { t = "enum", values = { classic = true, godRays = true, precision = true, bold = true, dream = true } },
	octaves = { t = "number", min = 1, max = 8, integer = true },
	lacunarity = { t = "number", min = 1.2, max = 3.5 },
	persistence = { t = "number", min = 0.1, max = 0.95 },
	warpAmount = { t = "number", min = 0, max = 2.5 },
	fastMode = { t = "boolean" },
	ultraFastMode = { t = "boolean" },
	checkerboardReconstruction = { t = "boolean" },
	interlacedMode = { t = "enum", values = { off = true, checkerboard = true } },
	temporalBlend = { t = "number", min = 0, max = 0.5 },
	animSpeed = { t = "number", min = 0, max = 0.2 },
	animAngle = { t = "number", min = -6.3, max = 6.3 },
	mouseRadius = { t = "number", min = 0, max = 600 },
	mouseStrength = { t = "number", min = 0, max = 3.0 },
	mouseEnabled = { t = "boolean" },
	cursorDitherEnabled = { t = "boolean" },
	cursorDitherRadius = { t = "number", min = 0, max = 600 },
	cursorDitherStrength = { t = "number", min = 0, max = 1 },
	cursorDitherScale = { t = "number", min = 1, max = 8, integer = true },
	cursorDitherPattern = { t = "enum", values = { bayer4 = true, checker = true } },
	bgColor = { t = "color4" },
	lineColor = { t = "color4" },
	elevationTint = { t = "boolean" },
	colorLow = { t = "color3" },
	colorHigh = { t = "color3" },
	tintAmount = { t = "number", min = 0, max = 1 },
	glowEnabled = { t = "boolean" },
	glowStrength = { t = "number", min = 0, max = 1 },
	edgeAAEnabled = { t = "boolean" },
	edgeAAStrength = { t = "number", min = 0, max = 1 },
	edgeAAThreshold = { t = "number", min = 1, max = 64, integer = true },
	edgeAAInterval = { t = "number", min = 1, max = 8, integer = true },
	edgeAAQuality = { t = "enum", values = { fast = true, hq = true } },
	lineAAEnabled = { t = "boolean" },
	lineAAStrength = { t = "number", min = 0, max = 4 },
	lineAAStep = { t = "number", min = 0.1, max = 2 },
	lineAAMode = { t = "enum", values = { off = true, fast = true, msaa4 = true } },
	lineAASubpixel = { t = "number", min = 0.1, max = 1.0 },
	analyticalAAEnabled = { t = "boolean" },
	analyticalAAStrength = { t = "number", min = 0, max = 2 },
	softEdgesEnabled = { t = "boolean" },
	softEdgeWidth = { t = "number", min = 0, max = 1.0 },
	softEdgeCurve = { t = "number", min = 0.5, max = 2.5 },
	adaptiveSamplingEnabled = { t = "boolean" },
	aaEdgeThreshold = { t = "number", min = 0, max = 0.1 },
	verticalAABoost = { t = "number", min = 0, max = 2.0 },
	generatorScaleEnabled = { t = "boolean" },
	generatorScaleStrength = { t = "number", min = 0, max = 1 },
	generatorScaleThreshold = { t = "number", min = 0, max = 1 },
	generatorScaleAlpha = { t = "number", min = 0, max = 1 },
	generatorScaleInterval = { t = "number", min = 1, max = 8, integer = true },
	generatorVerticalBias = { t = "number", min = 0.5, max = 2.0 },
	fakeAABlurEnabled = { t = "boolean" },
	fakeAABlurStrength = { t = "number", min = 0, max = 1 },
	fakeAABlurThreshold = { t = "number", min = 0, max = 1 },
	fakeAABlurInterval = { t = "number", min = 1, max = 8, integer = true },
	upscaleMode = { t = "enum", values = { bilinear = true, nearest = true } },
	qualityPreset = { t = "enum", values = { performance = true, balanced = true, quality = true } },
	adaptiveQuality = { t = "boolean" },
	frameBudgetMs = { t = "number", min = 6, max = 40 },
	adaptiveCooldown = { t = "number", min = 0.05, max = 2 },
	debugEnabled = { t = "boolean" },
	debugUpdateRate = { t = "number", min = 0.05, max = 2 },
	visualProfile = { t = "enum", values = { performance = true, balanced = true, cinematic = true } },
	vignetteEnabled = { t = "boolean" },
	vignetteStrength = { t = "number", min = 0, max = 0.5 },
	parallelEnabled = { t = "boolean" },
	parallelWorkers = { t = "number", min = 1, max = 16, integer = true },
	parallelChunkRows = { t = "number", min = 8, max = 128, integer = true },
	parallelTileWidth = { t = "number", min = 16, max = 256, integer = true },
	parallelTileHeight = { t = "number", min = 16, max = 256, integer = true },
	parallelProgressive = { t = "boolean" },
	parallelTilesPerFrame = { t = "number", min = 1, max = 128, integer = true },
	fps = { t = "number", min = 1, max = 240, integer = true },
	cornerRadius = { t = "number", min = 0, max = 80, integer = true },
	theme = { t = "enum", values = { classic = true, ocean = true, neon = true, paper = true } },
	panelTransparency = { t = "number", min = 0, max = 1 },
	imageTransparency = { t = "number", min = 0, max = 1 },
	outputOpacity = { t = "number", min = 0, max = 1 },
	localBlurEnabled = { t = "boolean" },
	localBlurSize = { t = "number", min = 0, max = 56, integer = true },
	backgroundBlurEnabled = { t = "boolean" },
	backgroundBlurSize = { t = "number", min = 0, max = 56, integer = true },
	fakeLocalBackdropEnabled = { t = "boolean" },
	fakeLocalBackdropAlpha = { t = "number", min = 0, max = 1 },
	fakeLocalBackdropRefreshHz = { t = "number", min = 1, max = 60, integer = true },
	fakeLocalBackdropQuality = { t = "enum", values = { low = true, balanced = true, high = true } },
	fakeLocalBackdropMaxParts = { t = "number", min = 50, max = 3000, integer = true },
	fakeLocalBackdropDistance = { t = "number", min = 30, max = 1024 },
	fakeLocalBackdropRebuildSec = { t = "number", min = 0.2, max = 10 },
	fakeLocalBackdropSimplify = { t = "boolean" },
	fakeLocalBackdropPanelOnly = { t = "boolean" },
	fakeLocalBackdropPanelMargin = { t = "number", min = 0, max = 256, integer = true },
	fakeLocalBackdropBlurStrength = { t = "number", min = 0, max = 1 },
	topoModeAppliesTheme = { t = "boolean" },
	-- Pre-cached loop playback
	cacheEnabled        = { t = "boolean" },
	loopDuration        = { t = "number", min = 0.5, max = 60 },
	loopFPS             = { t = "number", min = 1, max = 60, integer = true },
	loopAmplitude       = { t = "number", min = 0, max = 2.0 },
	loopZAmplitude      = { t = "number", min = 0, max = 1.0 },
	bakeOnStart         = { t = "boolean" },
	bakeUseParallel     = { t = "boolean" },
	mouseOverlayInCache = { t = "boolean" },
}

-- Keys that require a full rebake when changed while cacheEnabled = true.
local CACHE_INVALIDATE_KEYS = {
	contourLevels=true, lineWidth=true, lineSharpness=true, baseFrequency=true,
	octaves=true, lacunarity=true, persistence=true, warpAmount=true,
	fastMode=true, ultraFastMode=true,
	elevationTint=true, tintAmount=true,
	softEdgesEnabled=true, softEdgeWidth=true, softEdgeCurve=true,
	loopDuration=true, loopFPS=true, loopAmplitude=true, loopZAmplitude=true,
	animAngle=true,
	lineAAEnabled=true, lineAAMode=true, lineAAStrength=true,
	lineAAStep=true, lineAASubpixel=true,
	analyticalAAEnabled=true, analyticalAAStrength=true,
	edgeAAEnabled=true, edgeAAQuality=true, edgeAAStrength=true, edgeAAThreshold=true,
	generatorScaleEnabled=true, generatorScaleStrength=true,
	glowEnabled=true, glowStrength=true,
	vignetteEnabled=true, vignetteStrength=true,
	bgColor=true, lineColor=true, colorLow=true, colorHigh=true,
}

local THEMES = {
	classic = {
		bgColor = { r=0.016, g=0.016, b=0.022, a=1 },
		lineColor = { r=1, g=1, b=1, a=1 },
		elevationTint = true,
		colorLow = { r=0.12, g=0.28, b=0.68 },
		colorHigh = { r=0.80, g=0.93, b=1.00 },
		tintAmount = 0.45,
		glowEnabled = false,
		glowStrength = 0.18,
	},
	ocean = {
		bgColor = { r=0.008, g=0.020, b=0.045, a=1 },
		lineColor = { r=0.86, g=0.96, b=1.00, a=1 },
		elevationTint = true,
		colorLow = { r=0.08, g=0.38, b=0.82 },
		colorHigh = { r=0.78, g=1.00, b=0.94 },
		tintAmount = 0.62,
		glowEnabled = false,
		glowStrength = 0.16,
	},
	neon = {
		bgColor = { r=0.010, g=0.004, b=0.020, a=1 },
		lineColor = { r=0.97, g=0.95, b=1.00, a=1 },
		elevationTint = true,
		colorLow = { r=0.45, g=0.15, b=1.00 },
		colorHigh = { r=0.00, g=1.00, b=0.95 },
		tintAmount = 0.72,
		glowEnabled = true,
		glowStrength = 0.14,
	},
	paper = {
		bgColor = { r=0.95, g=0.94, b=0.90, a=1 },
		lineColor = { r=0.10, g=0.11, b=0.13, a=1 },
		elevationTint = false,
		colorLow = { r=0.10, g=0.11, b=0.13 },
		colorHigh = { r=0.10, g=0.11, b=0.13 },
		tintAmount = 0.0,
		glowEnabled = false,
		glowStrength = 0.0,
	},
}

local TOPO_MODES = {
	classic = {
		lineWidth = 0.08, lineSharpness = 1.0, contourLevels = 12,
		lineAAMode = "fast", lineAAStrength = 2.0, edgeAAEnabled = false,
		bgColor = { r=0.016, g=0.016, b=0.022, a=1 },
		lineColor = { r=1.00, g=1.00, b=1.00, a=1 },
		elevationTint = true, colorLow = { r=0.12, g=0.28, b=0.68 }, colorHigh = { r=0.80, g=0.93, b=1.00 }, tintAmount = 0.45,
	},
	godRays = {
		lineWidth = 0.10, lineSharpness = 0.92, contourLevels = 10,
		lineAAMode = "msaa4", lineAAStrength = 2.8, edgeAAEnabled = true,
		edgeAAQuality = "hq", edgeAAStrength = 0.58, glowEnabled = true, glowStrength = 0.12,
		bgColor = { r=0.03, g=0.01, b=0.05, a=1 },
		lineColor = { r=1.00, g=0.96, b=0.82, a=1 },
		elevationTint = true, colorLow = { r=0.95, g=0.46, b=0.08 }, colorHigh = { r=1.00, g=0.92, b=0.40 }, tintAmount = 0.62,
	},
	precision = {
		lineWidth = 0.065, lineSharpness = 1.08, contourLevels = 16,
		lineAAMode = "msaa4", lineAAStrength = 2.2, edgeAAEnabled = true,
		edgeAAQuality = "hq", edgeAAStrength = 0.45, glowEnabled = false,
		bgColor = { r=0.01, g=0.02, b=0.03, a=1 },
		lineColor = { r=0.88, g=0.98, b=1.00, a=1 },
		elevationTint = true, colorLow = { r=0.20, g=0.60, b=1.00 }, colorHigh = { r=0.90, g=1.00, b=1.00 }, tintAmount = 0.35,
	},
	bold = {
		lineWidth = 0.12, lineSharpness = 0.88, contourLevels = 9,
		lineAAMode = "fast", lineAAStrength = 1.6, edgeAAEnabled = false,
		glowEnabled = false,
		bgColor = { r=0.00, g=0.00, b=0.00, a=1 },
		lineColor = { r=1.00, g=1.00, b=1.00, a=1 },
		elevationTint = false, tintAmount = 0.0,
	},
	dream = {
		lineWidth = 0.095, lineSharpness = 0.9, contourLevels = 11,
		lineAAMode = "msaa4", lineAAStrength = 2.6, edgeAAEnabled = true,
		edgeAAQuality = "hq", edgeAAStrength = 0.62, glowEnabled = true, glowStrength = 0.10,
		animSpeed = 0.012,
		bgColor = { r=0.02, g=0.01, b=0.05, a=1 },
		lineColor = { r=0.96, g=0.93, b=1.00, a=1 },
		elevationTint = true, colorLow = { r=0.56, g=0.18, b=0.98 }, colorHigh = { r=0.50, g=0.98, b=0.94 }, tintAmount = 0.70,
	},
	wireframe = {
		lineWidth = 0.055, lineSharpness = 1.15, contourLevels = 18,
		lineAAMode = "msaa4", lineAAStrength = 2.0, edgeAAEnabled = true, edgeAAQuality = "hq", edgeAAStrength = 0.40,
		glowEnabled = false, animSpeed = 0.02,
		bgColor = { r=0.010, g=0.012, b=0.016, a=1 },
		lineColor = { r=0.62, g=0.95, b=1.00, a=1 },
		elevationTint = true, colorLow = { r=0.20, g=0.75, b=1.00 }, colorHigh = { r=0.85, g=1.00, b=1.00 }, tintAmount = 0.32,
	},
	molten = {
		lineWidth = 0.11, lineSharpness = 0.9, contourLevels = 10,
		lineAAMode = "fast", lineAAStrength = 2.2, edgeAAEnabled = true, edgeAAQuality = "hq", edgeAAStrength = 0.58,
		glowEnabled = true, glowStrength = 0.16, animSpeed = 0.015,
		bgColor = { r=0.05, g=0.01, b=0.00, a=1 },
		lineColor = { r=1.00, g=0.75, b=0.30, a=1 },
		elevationTint = true, colorLow = { r=0.90, g=0.20, b=0.02 }, colorHigh = { r=1.00, g=0.95, b=0.45 }, tintAmount = 0.78,
	},
	glacier = {
		lineWidth = 0.085, lineSharpness = 0.96, contourLevels = 12,
		lineAAMode = "msaa4", lineAAStrength = 2.4, edgeAAEnabled = true, edgeAAQuality = "hq", edgeAAStrength = 0.50,
		glowEnabled = false, animSpeed = 0.01,
		bgColor = { r=0.00, g=0.03, b=0.06, a=1 },
		lineColor = { r=0.88, g=0.98, b=1.00, a=1 },
		elevationTint = true, colorLow = { r=0.22, g=0.62, b=0.95 }, colorHigh = { r=0.92, g=1.00, b=1.00 }, tintAmount = 0.56,
	},
	radar = {
		lineWidth = 0.09, lineSharpness = 1.0, contourLevels = 14,
		lineAAMode = "fast", lineAAStrength = 1.8, edgeAAEnabled = false,
		glowEnabled = true, glowStrength = 0.10, animSpeed = 0.028,
		bgColor = { r=0.00, g=0.03, b=0.01, a=1 },
		lineColor = { r=0.55, g=1.00, b=0.65, a=1 },
		elevationTint = true, colorLow = { r=0.10, g=0.65, b=0.18 }, colorHigh = { r=0.75, g=1.00, b=0.80 }, tintAmount = 0.48,
	},
	sunset = {
		lineWidth = 0.10, lineSharpness = 0.92, contourLevels = 11,
		lineAAMode = "msaa4", lineAAStrength = 2.5, edgeAAEnabled = true, edgeAAQuality = "hq", edgeAAStrength = 0.56,
		glowEnabled = true, glowStrength = 0.11, animSpeed = 0.014,
		bgColor = { r=0.08, g=0.02, b=0.07, a=1 },
		lineColor = { r=1.00, g=0.86, b=0.70, a=1 },
		elevationTint = true, colorLow = { r=0.94, g=0.32, b=0.45 }, colorHigh = { r=1.00, g=0.85, b=0.50 }, tintAmount = 0.68,
	},
}

local TOPO_MODE_THEME = {
	classic = "classic",
	godRays = "neon",
	precision = "ocean",
	bold = "paper",
	dream = "neon",
	wireframe = "ocean",
	molten = "classic",
	glacier = "ocean",
	radar = "classic",
	sunset = "neon",
}

-- ================================================================
--  MATH
-- ================================================================
local _noise = math.noise
local _floor = math.floor
local _sqrt  = math.sqrt
local _min   = math.min
local _max   = math.max
local _cos   = math.cos
local _sin   = math.sin
local _abs   = math.abs

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function saturate(v)
	return _max(0, _min(1, v))
end

local function cloneTable(t)
	local out = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			local c = {}
			for ck, cv in pairs(v) do c[ck] = cv end
			out[k] = c
		else
			out[k] = v
		end
	end
	return out
end

local function sanitizeValue(key, value)
	local rule = CONFIG_RULES[key]
	if not rule then
		return value
	end
	if rule.t == "boolean" then
		return value and true or false
	end
	if rule.t == "enum" then
		return (rule.values[value] and value) or nil
	end
	if rule.t == "number" then
		local n = tonumber(value)
		if not n then return nil end
		if rule.integer then n = _floor(n + 0.5) end
		if rule.min ~= nil then n = _max(rule.min, n) end
		if rule.max ~= nil then n = _min(rule.max, n) end
		return n
	end
	if rule.t == "color3" then
		if type(value) ~= "table" then return nil end
		local r = tonumber(value.r)
		local g = tonumber(value.g)
		local b = tonumber(value.b)
		if not r or not g or not b then return nil end
		return { r = saturate(r), g = saturate(g), b = saturate(b) }
	end
	if rule.t == "color4" then
		if type(value) ~= "table" then return nil end
		local r = tonumber(value.r)
		local g = tonumber(value.g)
		local b = tonumber(value.b)
		local a = tonumber(value.a)
		if not r or not g or not b then return nil end
		if not a then a = 1 end
		return { r = saturate(r), g = saturate(g), b = saturate(b), a = saturate(a) }
	end
	return value
end

-- Smooth Hermite fade
local function fade(t)
	t = saturate(t)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

-- FBM: layered noise, returns value in [0, 1]
local function fbm(x, y, z, oct, lac, per)
	local sum  = 0
	local amp  = 0.5
	local freq = 1
	local max  = 0

	for _ = 1, oct do
		sum  = sum  + _noise(x * freq, y * freq, z) * amp
		max  = max  + amp
		freq = freq * lac
		amp  = amp  * per
	end

	-- Remap noise range [-max, +max] → [0, 1]
	return (sum / max) * 0.5 + 0.5
end

-- Domain-warped FBM for organic contour shapes
local function heightField(x, y, z, oct, lac, per, warp)
	-- Layer 1 warp
	local w1x = fbm(x + 0.0,  y + 0.0,  z + 0.0,  oct, lac, per) - 0.5
	local w1y = fbm(x + 5.2,  y + 1.3,  z + 0.3,  oct, lac, per) - 0.5

	-- Layer 2 warp (warps the warp — more organic)
	local w2x = fbm(x + w1x * warp + 1.7, y + w1y * warp + 9.2,
		z + 0.15, 3, lac, per) - 0.5
	local w2y = fbm(x + w1x * warp + 8.3, y + w1y * warp + 2.8,
		z - 0.12, 3, lac, per) - 0.5

	return fbm(
		x + w2x * warp * 0.5,
		y + w2y * warp * 0.5,
		z, oct, lac, per
	)
end

-- Cheaper variant for better frame time.
local function heightFieldFast(x, y, z, oct, lac, per, warp)
	local w = fbm(x + 3.1, y + 7.9, z + 0.2, 3, lac, per) - 0.5
	local o = _max(1, oct - 1)
	return fbm(
		x + w * warp * 0.6,
		y - w * warp * 0.6,
		z,
		o, lac, per
	)
end

-- Minimal path: one small warp sample + low octave fbm.
local function heightFieldUltra(x, y, z, lac, per, warp)
	-- Keep this very cheap: 2 noise calls total.
	local w = _noise(x + 1.7, y + 3.9, z + 0.21)
	local sx = (x + w * warp * 0.35) * 1.18
	local sy = (y - w * warp * 0.35) * 1.18
	return _noise(sx, sy, z * 0.9) * 0.5 + 0.5
end

-- Contour line detection.
-- h        = height in [0,1]
-- levels   = number of contour bands
-- halfW    = half-width of line as fraction of one band [0, 0.5]
-- Returns pixel brightness 0-1 (1 = on a line)
local function contour(h, levels, halfW)
	-- Tile h into [levels] repeating bands of width 1/levels
	-- Within each band, position goes 0→1
	local bandPos = (h * levels) % 1.0

	-- Distance to nearest band edge (0 = on the line, 0.5 = centre of gap)
	local d = _min(bandPos, 1 - bandPos)  -- 0 at edges, 0.5 at mid-gap

	-- Normalise so halfW maps to 0
	local t = 1 - saturate(d / halfW)

	-- Smooth the edge
	return fade(t)
end

local function contourValue(h, levels, halfW, softEnabled, softWidth, softCurve)
	local bandPos = (h * levels) % 1.0
	local d = _min(bandPos, 1 - bandPos)
	if not softEnabled then
		return fade(1 - saturate(d / halfW))
	end
	local w = _max(0.0001, halfW)
	local sw = _max(0, _min(1, softWidth or 0)) * w
	local i0 = _max(0, w - sw)
	local i1 = w + sw
	local t = saturate((d - i0) / _max(0.0001, i1 - i0))
	local cov = 1 - fade(t)
	local c = _max(0.5, softCurve or 1)
	if c ~= 1 then
		cov = cov ^ c
	end
	return cov
end

local BAYER4 = {
	{ 0,  8,  2, 10 },
	{ 12, 4, 14,  6 },
	{ 3, 11,  1,  9 },
	{ 15, 7, 13,  5 },
}

-- ================================================================
--  CONSTRUCTOR
-- ================================================================
function TopoShader.new(parentGui, userConfig)
	assert(parentGui, "parentGui required")

	local self = setmetatable({}, TopoShader)

	-- Merge config
	local cfg = {}
	for k, v in pairs(DEFAULTS) do
		cfg[k] = (type(v) == "table")
			and (function()
				local copy = {}
				for ck, cv in pairs(v) do copy[ck] = cv end
				return copy
			end)()
			or v
	end
	if userConfig then
		for k, v in pairs(userConfig) do cfg[k] = v end
	end
	self.cfg = cfg
	self:SetQualityPreset(cfg.qualityPreset or "balanced")
	self:ApplyFakeBackdropQuality(cfg.fakeLocalBackdropQuality or "balanced")
	self._states = {}

	-- Internal state
	self._running   = false
	self._conn      = nil
	self._inputConn = nil
	self._clock     = 0
	self._accumTime = 0
	self._mouseX    = cfg.width  * 0.5
	self._mouseY    = cfg.height * 0.5

	local rW = cfg.renderWidth
	local rH = cfg.renderHeight
	self._rW = rW
	self._rH = rH

	local pixCount  = rW * rH
	self._pixCount  = pixCount
	self._buf       = buffer.create(pixCount * 4)
	self._history   = buffer.create(pixCount * 4)
	self._aaBuf     = buffer.create(pixCount * 4)
	self._checkerPhase = 0
	self._frameId = 0
	self._adaptiveTimer = 0
	self._debugClock = 0
	self._debugReport = {
		frames = 0,
		overBudgetFrames = 0,
		renderMsAvg = 0,
		renderMsMax = 0,
		lastRenderMs = 0,
		fps = 0,
		lastIssues = "",
		parallelReady = false,
		parallelWorkers = 0,
		localBlurReady = false,
		fakeBackdropReady = false,
		-- cache fields
		cacheReady = false,
		bakeProgress = 0,
		bakeTotalFrames = 0,
	}
	self._parallelReady = false
	self._parallelWorkers = 0
	self._localBlurReady = false
	self._parallelActors = {}
	self._parallelConns = {}
	self._parallelJobId = 0
	self._parallelInFlight = false
	self._parallelPending = 0
	self._parallelFrameReady = false
	self._parallelFrameTime = 0
	self._parallelTiles = {}
	self._parallelTileCursor = 1
	self._autoTune = nil

	-- Pre-cached loop playback state
	self._bakeOverride        = nil   -- {driftX,driftY,zSlice} — set during _bakeFrameSerial
	self._cache               = {}    -- array[i] = full RGBA buffer for baked frame i
	self._cacheIdx            = 1     -- current playback frame index
	self._cacheReady          = false
	self._bakeActive          = false
	self._bakeFI              = 0     -- next frame index to bake (0-based)
	self._bakeTotalFrames     = 0
	self._bakeParallelWaiting = false
	self._playBuf             = nil   -- writable scratch copy: cached frame + overlay
	self._cacheAccum          = 0     -- time accumulator for cache frame rate

	-- Pre-bake noise-space XY per pixel
	-- This is the critical fix: frequency must be low
	local freq = cfg.baseFrequency
	local cX   = table.create(pixCount)
	local cY   = table.create(pixCount)
	local pX   = table.create(pixCount)
	local pY   = table.create(pixCount)
	local parity = table.create(pixCount)
	local vig = table.create(pixCount)

	for row = 0, rH - 1 do
		local base = row * rW
		local ny   = row * freq
		for col = 0, rW - 1 do
			local i  = base + col + 1
			cX[i] = col * freq
			cY[i] = ny
			pX[i] = col * (cfg.width / rW)
			pY[i] = row * (cfg.height / rH)
			parity[i] = (row + col) % 2
			do
				local nxn = (col / _max(1, rW - 1)) * 2 - 1
				local nyn = (row / _max(1, rH - 1)) * 2 - 1
				local vv = 1 - (nxn * nxn + nyn * nyn) * 0.22
				vig[i] = saturate(vv)
			end

			local idx = (i - 1) * 4
			local br = _floor(cfg.bgColor.r * 255 + 0.5)
			local bg = _floor(cfg.bgColor.g * 255 + 0.5)
			local bb = _floor(cfg.bgColor.b * 255 + 0.5)
			local ba = _floor(cfg.bgColor.a * 255 + 0.5)
			buffer.writeu8(self._buf, idx, br)
			buffer.writeu8(self._buf, idx + 1, bg)
			buffer.writeu8(self._buf, idx + 2, bb)
			buffer.writeu8(self._buf, idx + 3, ba)
			buffer.writeu8(self._history, idx, br)
			buffer.writeu8(self._history, idx + 1, bg)
			buffer.writeu8(self._history, idx + 2, bb)
			buffer.writeu8(self._history, idx + 3, ba)
		end
	end

	self._cX = cX
	self._cY = cY
	self._pX = pX
	self._pY = pY
	self._parity = parity
	self._vig = vig

	-- Scale factors: render pixel → panel pixel (for mouse warp)
	self._scaleX = cfg.width  / rW
	self._scaleY = cfg.height / rH

	-- ── GUI ────────────────────────────────────────────────────
	local root = Instance.new("Frame")
	root.Name                   = "TopoPanel"
	root.AnchorPoint            = Vector2.new(0.5, 0.5)
	root.Size                   = UDim2.fromOffset(cfg.width, cfg.height)
	root.Position               = UDim2.fromScale(0.5, 0.5)
	root.BackgroundTransparency = 1
	root.BorderSizePixel        = 0
	root.ZIndex                 = 1
	root.Parent                 = parentGui
	self._root = root

	-- Clip frame (rounds corners, hides image overflow)
	local clip = Instance.new("Frame")
	clip.Name                   = "Clip"
	clip.AnchorPoint            = Vector2.new(0.5, 0.5)
	clip.Size                   = UDim2.fromOffset(cfg.width, cfg.height)
	clip.Position               = UDim2.fromScale(0.5, 0.5)
	clip.BackgroundColor3       = Color3.new(0, 0, 0)
	clip.BackgroundTransparency = cfg.panelTransparency or 0
	clip.BorderSizePixel        = 0
	clip.ClipsDescendants       = true
	clip.ZIndex                 = 1
	clip.Parent                 = root
	self._clip = clip
	self._blur = nil
	self._uiBlur = nil
	self:_syncBackgroundBlur()

	do
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0, cfg.cornerRadius)
		uc.Parent = clip
		self._clipCorner = uc
	end

	-- ImageLabel  (will display our EditableImage)
	local img = Instance.new("ImageLabel")
	img.Name                   = "Output"
	img.Size                   = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.BorderSizePixel        = 0
	img.ScaleType              = Enum.ScaleType.Stretch
	img.ResampleMode           = (cfg.upscaleMode == "nearest") and Enum.ResamplerMode.Pixelated or Enum.ResamplerMode.Default
	img.ImageTransparency      = cfg.imageTransparency or 0
	img.ZIndex                 = 2
	img.Parent                 = clip
	self._img = img
	do
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0, cfg.cornerRadius)
		uc.Parent = img
		self._imgCorner = uc
	end

	-- Optional localized backdrop "cheese blur" layer (ViewportFrame)
	local vpf = Instance.new("ViewportFrame")
	vpf.Name = "LocalBackdrop"
	vpf.Size = UDim2.fromScale(1, 1)
	vpf.BackgroundTransparency = 1
	vpf.BorderSizePixel = 0
	vpf.ImageTransparency = 1 - (cfg.fakeLocalBackdropAlpha or 0.35)
	vpf.ZIndex = 1
	vpf.Visible = cfg.fakeLocalBackdropEnabled and true or false
	vpf.ClipsDescendants = true
	vpf.Parent = clip
	self._vpf = vpf
	do
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0, cfg.cornerRadius)
		uc.Parent = vpf
		self._vpfCorner = uc
	end

	local wm = Instance.new("WorldModel")
	wm.Name = "BackdropWorld"
	wm.Parent = vpf
	self._vpfWorld = wm

	local vcam = Instance.new("Camera")
	vcam.Name = "BackdropCamera"
	vcam.Parent = vpf
	vpf.CurrentCamera = vcam
	self._vpfCamera = vcam
	self._vpfMap = {}
	self._vpfAccum = 0
	self._vpfRebuildAccum = 0
	self._vpfReady = false

	-- EditableImage via AssetService
	local ok, ei = pcall(function()
		return AssetService:CreateEditableImage({
			Size = Vector2.new(rW, rH),
		})
	end)
	assert(ok, "[TopoShader] CreateEditableImage failed: " .. tostring(ei))
	self._ei = ei
	img.ImageContent = Content.fromObject(ei)

	-- Rim border
	local rimFrame = Instance.new("Frame")
	rimFrame.Size                   = UDim2.fromScale(1, 1)
	rimFrame.BackgroundTransparency = 1
	rimFrame.BorderSizePixel        = 0
	rimFrame.ZIndex                 = 10
	rimFrame.Parent                 = clip

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness       = 1.2
	stroke.Transparency    = 0.35
	stroke.Color           = Color3.fromRGB(255, 255, 255)
	stroke.Parent          = rimFrame

	-- Top gloss
	local gloss = Instance.new("Frame")
	gloss.Size               = UDim2.new(1, -24, 0, 1)
	gloss.Position           = UDim2.fromOffset(12, 2)
	gloss.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
	gloss.BackgroundTransparency = 0.55
	gloss.BorderSizePixel    = 0
	gloss.ZIndex             = 11
	gloss.Parent             = clip

	do
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0, 1)
		uc.Parent = gloss
	end

	-- Debug overlay (toggled by config/API)
	local debugLabel = Instance.new("TextLabel")
	debugLabel.Name = "DebugOverlay"
	debugLabel.AnchorPoint = Vector2.new(0, 0)
	debugLabel.Position = UDim2.fromOffset(8, 8)
	debugLabel.Size = UDim2.new(1, -16, 0, 64)
	debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	debugLabel.BackgroundTransparency = 0.35
	debugLabel.BorderSizePixel = 0
	debugLabel.TextColor3 = Color3.fromRGB(220, 245, 255)
	debugLabel.TextStrokeTransparency = 0.5
	debugLabel.TextSize = 14
	debugLabel.TextXAlignment = Enum.TextXAlignment.Left
	debugLabel.TextYAlignment = Enum.TextYAlignment.Top
	debugLabel.Font = Enum.Font.Code
	debugLabel.RichText = false
	debugLabel.Visible = cfg.debugEnabled
	debugLabel.ZIndex = 30
	debugLabel.Text = "TopoShader debug"
	debugLabel.Parent = clip
	self._debugLabel = debugLabel

	return self
end

-- Reconstruct checkerboard-missing pixels from spatial neighbors.
function TopoShader:_reconstructCheckerboard(phase)
	local buf = self._buf
	local hist = self._history
	local parity = self._parity
	local rW = self._rW
	local rH = self._rH
	local pixCount = self._pixCount

	for pi = 1, pixCount do
		if parity[pi] ~= phase then
			local col = (pi - 1) % rW
			local row = _floor((pi - 1) / rW)
			local idx = (pi - 1) * 4

			for ch = 0, 3 do
				local sum = 0
				local n = 0

				-- Left
				if col > 0 then
					local lp = pi - 1
					if parity[lp] == phase then
						sum += buffer.readu8(buf, idx - 4 + ch)
						n += 1
					end
				end
				-- Right
				if col < rW - 1 then
					local rp = pi + 1
					if parity[rp] == phase then
						sum += buffer.readu8(buf, idx + 4 + ch)
						n += 1
					end
				end
				-- Up
				if row > 0 then
					local up = pi - rW
					if parity[up] == phase then
						sum += buffer.readu8(buf, idx - rW * 4 + ch)
						n += 1
					end
				end
				-- Down
				if row < rH - 1 then
					local dp = pi + rW
					if parity[dp] == phase then
						sum += buffer.readu8(buf, idx + rW * 4 + ch)
						n += 1
					end
				end

				local out
				if n > 0 then
					local spatial = _floor(sum / n + 0.5)
					-- Blend a little history for stability.
					local h = buffer.readu8(hist, idx + ch)
					out = _floor(spatial * 0.82 + h * 0.18 + 0.5)
				else
					out = buffer.readu8(hist, idx + ch)
				end

				buffer.writeu8(buf, idx + ch, out)
				buffer.writeu8(hist, idx + ch, out)
			end
		end
	end
end

-- Edge-aware AA: smooth only high-contrast transitions (mostly line edges).
function TopoShader:_applyEdgeAA()
	local src = self._buf
	local dst = self._aaBuf
	local rW = self._rW
	local rH = self._rH
	local cfg = self.cfg
	local thr = cfg.edgeAAThreshold or 16
	local str = saturate(cfg.edgeAAStrength or 0.55)
	local highQuality = (cfg.edgeAAQuality == "hq")

	-- Copy borders unchanged.
	for col = 0, rW - 1 do
		local top = col * 4
		local bot = ((rH - 1) * rW + col) * 4
		for ch = 0, 3 do
			buffer.writeu8(dst, top + ch, buffer.readu8(src, top + ch))
			buffer.writeu8(dst, bot + ch, buffer.readu8(src, bot + ch))
		end
	end
	for row = 1, rH - 2 do
		local left = (row * rW) * 4
		local right = (row * rW + (rW - 1)) * 4
		for ch = 0, 3 do
			buffer.writeu8(dst, left + ch, buffer.readu8(src, left + ch))
			buffer.writeu8(dst, right + ch, buffer.readu8(src, right + ch))
		end
	end

	for row = 1, rH - 2 do
		for col = 1, rW - 2 do
			local c = (row * rW + col) * 4
			local l = c - 4
			local r = c + 4
			local u = c - rW * 4
			local d = c + rW * 4

			local cr = buffer.readu8(src, c)
			local cg = buffer.readu8(src, c + 1)
			local cb = buffer.readu8(src, c + 2)
			local ca = buffer.readu8(src, c + 3)

			local lumC = cr * 0.299 + cg * 0.587 + cb * 0.114
			local lumL = buffer.readu8(src, l) * 0.299 + buffer.readu8(src, l + 1) * 0.587 + buffer.readu8(src, l + 2) * 0.114
			local lumR = buffer.readu8(src, r) * 0.299 + buffer.readu8(src, r + 1) * 0.587 + buffer.readu8(src, r + 2) * 0.114
			local lumU = buffer.readu8(src, u) * 0.299 + buffer.readu8(src, u + 1) * 0.587 + buffer.readu8(src, u + 2) * 0.114
			local lumD = buffer.readu8(src, d) * 0.299 + buffer.readu8(src, d + 1) * 0.587 + buffer.readu8(src, d + 2) * 0.114

			local grad = _max(_max(_max(_max(_max(lumC, lumL), lumR), lumU), lumD) - _min(_min(_min(_min(_min(lumC, lumL), lumR), lumU), lumD), 255), 0)
			if grad > thr then
				local avgR, avgG, avgB
				if highQuality then
					local ul = u - 4
					local ur = u + 4
					local dl = d - 4
					local dr = d + 4
					avgR = (
						buffer.readu8(src, l) + buffer.readu8(src, r) +
							buffer.readu8(src, u) + buffer.readu8(src, d) +
							buffer.readu8(src, ul) + buffer.readu8(src, ur) +
							buffer.readu8(src, dl) + buffer.readu8(src, dr)
					) * 0.125
					avgG = (
						buffer.readu8(src, l + 1) + buffer.readu8(src, r + 1) +
							buffer.readu8(src, u + 1) + buffer.readu8(src, d + 1) +
							buffer.readu8(src, ul + 1) + buffer.readu8(src, ur + 1) +
							buffer.readu8(src, dl + 1) + buffer.readu8(src, dr + 1)
					) * 0.125
					avgB = (
						buffer.readu8(src, l + 2) + buffer.readu8(src, r + 2) +
							buffer.readu8(src, u + 2) + buffer.readu8(src, d + 2) +
							buffer.readu8(src, ul + 2) + buffer.readu8(src, ur + 2) +
							buffer.readu8(src, dl + 2) + buffer.readu8(src, dr + 2)
					) * 0.125
				else
					avgR = (buffer.readu8(src, l) + buffer.readu8(src, r) + buffer.readu8(src, u) + buffer.readu8(src, d)) * 0.25
					avgG = (buffer.readu8(src, l + 1) + buffer.readu8(src, r + 1) + buffer.readu8(src, u + 1) + buffer.readu8(src, d + 1)) * 0.25
					avgB = (buffer.readu8(src, l + 2) + buffer.readu8(src, r + 2) + buffer.readu8(src, u + 2) + buffer.readu8(src, d + 2)) * 0.25
				end
				buffer.writeu8(dst, c, _floor(cr * (1 - str) + avgR * str + 0.5))
				buffer.writeu8(dst, c + 1, _floor(cg * (1 - str) + avgG * str + 0.5))
				buffer.writeu8(dst, c + 2, _floor(cb * (1 - str) + avgB * str + 0.5))
				buffer.writeu8(dst, c + 3, ca)
			else
				buffer.writeu8(dst, c, cr)
				buffer.writeu8(dst, c + 1, cg)
				buffer.writeu8(dst, c + 2, cb)
				buffer.writeu8(dst, c + 3, ca)
			end
		end
	end

	-- Copy AA buffer back.
	for i = 0, self._pixCount * 4 - 1 do
		buffer.writeu8(src, i, buffer.readu8(dst, i))
	end
end

-- Generator scaling: edge-aware reconstruction filter.
-- Smooths jagged transitions while preserving flat regions/details better than simple blur.
function TopoShader:_applyGeneratorScale()
	local src = self._buf
	local dst = self._aaBuf
	local rW = self._rW
	local rH = self._rH
	local str = saturate(self.cfg.generatorScaleStrength or 0.42)
	local thr = saturate(self.cfg.generatorScaleThreshold or 0.08)
	local aStr = saturate(self.cfg.generatorScaleAlpha or 0.70)
	local vBias = _max(0.5, self.cfg.generatorVerticalBias or 1.35)
	if str <= 0 then
		return
	end

	-- Copy borders unchanged.
	for col = 0, rW - 1 do
		local top = col * 4
		local bot = ((rH - 1) * rW + col) * 4
		for ch = 0, 3 do
			buffer.writeu8(dst, top + ch, buffer.readu8(src, top + ch))
			buffer.writeu8(dst, bot + ch, buffer.readu8(src, bot + ch))
		end
	end
	for row = 1, rH - 2 do
		local left = (row * rW) * 4
		local right = (row * rW + (rW - 1)) * 4
		for ch = 0, 3 do
			buffer.writeu8(dst, left + ch, buffer.readu8(src, left + ch))
			buffer.writeu8(dst, right + ch, buffer.readu8(src, right + ch))
		end
	end

	for row = 1, rH - 2 do
		for col = 1, rW - 2 do
			local c = (row * rW + col) * 4
			local l = c - 4
			local r = c + 4
			local u = c - rW * 4
			local d = c + rW * 4

			local cr = buffer.readu8(src, c)
			local cg = buffer.readu8(src, c + 1)
			local cb = buffer.readu8(src, c + 2)
			local ca = buffer.readu8(src, c + 3)
			local lumC = cr * 0.299 + cg * 0.587 + cb * 0.114
			local lumL = buffer.readu8(src, l) * 0.299 + buffer.readu8(src, l + 1) * 0.587 + buffer.readu8(src, l + 2) * 0.114
			local lumR = buffer.readu8(src, r) * 0.299 + buffer.readu8(src, r + 1) * 0.587 + buffer.readu8(src, r + 2) * 0.114
			local lumU = buffer.readu8(src, u) * 0.299 + buffer.readu8(src, u + 1) * 0.587 + buffer.readu8(src, u + 2) * 0.114
			local lumD = buffer.readu8(src, d) * 0.299 + buffer.readu8(src, d + 1) * 0.587 + buffer.readu8(src, d + 2) * 0.114

			local accR, accG, accB, accA = 0, 0, 0, 0
			local wSum = 0
			local maxEdge = 0

			local function sampleNeighbor(n)
				local nr = buffer.readu8(src, n)
				local ng = buffer.readu8(src, n + 1)
				local nb = buffer.readu8(src, n + 2)
				local na = buffer.readu8(src, n + 3)
				local lumN = nr * 0.299 + ng * 0.587 + nb * 0.114
				local contrast = _abs(lumN - lumC) / 255
				local edgeW = saturate((contrast - thr) / _max(0.0001, 1 - thr))
				local rangeW = 1 - contrast * 0.85
				local alphaW = 1 - (_abs(na - ca) / 255) * 0.65
				local w = edgeW * rangeW * alphaW
				if w > 0 then
					accR += nr * w
					accG += ng * w
					accB += nb * w
					accA += na * w
					wSum += w
					if edgeW > maxEdge then
						maxEdge = edgeW
					end
				end
			end

			sampleNeighbor(l)
			sampleNeighbor(r)
			sampleNeighbor(u)
			sampleNeighbor(d)
			sampleNeighbor(u - 4)
			sampleNeighbor(u + 4)
			sampleNeighbor(d - 4)
			sampleNeighbor(d + 4)

			if wSum > 0 then
				local avgR = accR / wSum
				local avgG = accG / wSum
				local avgB = accB / wSum
				local avgA = accA / wSum
				local gx = _abs(lumR - lumL)
				local gy = _abs(lumD - lumU)
				local verticalDom = saturate((gx - gy) / _max(1, gx + gy))
				local dirBoost = 1 + (vBias - 1) * verticalDom
				local k = saturate(str * maxEdge * dirBoost)
				buffer.writeu8(dst, c, _floor(cr * (1 - k) + avgR * k + 0.5))
				buffer.writeu8(dst, c + 1, _floor(cg * (1 - k) + avgG * k + 0.5))
				buffer.writeu8(dst, c + 2, _floor(cb * (1 - k) + avgB * k + 0.5))
				buffer.writeu8(dst, c + 3, _floor(ca * (1 - aStr * k) + avgA * (aStr * k) + 0.5))
			else
				buffer.writeu8(dst, c, cr)
				buffer.writeu8(dst, c + 1, cg)
				buffer.writeu8(dst, c + 2, cb)
				buffer.writeu8(dst, c + 3, ca)
			end
		end
	end

	for i = 0, self._pixCount * 4 - 1 do
		buffer.writeu8(src, i, buffer.readu8(dst, i))
	end
end

-- Tiny edge-gated blur pass (fake AA helper).
-- Applies only where local contrast crosses threshold to avoid global softness.
function TopoShader:_applyFakeAABlur()
	local src = self._buf
	local dst = self._aaBuf
	local rW = self._rW
	local rH = self._rH
	local str = saturate(self.cfg.fakeAABlurStrength or 0.16)
	local thr = saturate(self.cfg.fakeAABlurThreshold or 0.06)
	if str <= 0 then
		return
	end

	for col = 0, rW - 1 do
		local top = col * 4
		local bot = ((rH - 1) * rW + col) * 4
		for ch = 0, 3 do
			buffer.writeu8(dst, top + ch, buffer.readu8(src, top + ch))
			buffer.writeu8(dst, bot + ch, buffer.readu8(src, bot + ch))
		end
	end
	for row = 1, rH - 2 do
		local left = (row * rW) * 4
		local right = (row * rW + (rW - 1)) * 4
		for ch = 0, 3 do
			buffer.writeu8(dst, left + ch, buffer.readu8(src, left + ch))
			buffer.writeu8(dst, right + ch, buffer.readu8(src, right + ch))
		end
	end

	for row = 1, rH - 2 do
		for col = 1, rW - 2 do
			local c = (row * rW + col) * 4
			local l = c - 4
			local r = c + 4
			local u = c - rW * 4
			local d = c + rW * 4

			local cr = buffer.readu8(src, c)
			local cg = buffer.readu8(src, c + 1)
			local cb = buffer.readu8(src, c + 2)
			local ca = buffer.readu8(src, c + 3)

			local lumC = cr * 0.299 + cg * 0.587 + cb * 0.114
			local lumL = buffer.readu8(src, l) * 0.299 + buffer.readu8(src, l + 1) * 0.587 + buffer.readu8(src, l + 2) * 0.114
			local lumR = buffer.readu8(src, r) * 0.299 + buffer.readu8(src, r + 1) * 0.587 + buffer.readu8(src, r + 2) * 0.114
			local lumU = buffer.readu8(src, u) * 0.299 + buffer.readu8(src, u + 1) * 0.587 + buffer.readu8(src, u + 2) * 0.114
			local lumD = buffer.readu8(src, d) * 0.299 + buffer.readu8(src, d + 1) * 0.587 + buffer.readu8(src, d + 2) * 0.114
			local contrast = _max(_max(_abs(lumC - lumL), _abs(lumC - lumR)), _max(_abs(lumC - lumU), _abs(lumC - lumD))) / 255
			local edgeK = saturate((contrast - thr) / _max(0.0001, 1 - thr))
			local k = str * edgeK

			if k > 0 then
				local avgR = (buffer.readu8(src, l) + buffer.readu8(src, r) + buffer.readu8(src, u) + buffer.readu8(src, d) + cr * 2) / 6
				local avgG = (buffer.readu8(src, l + 1) + buffer.readu8(src, r + 1) + buffer.readu8(src, u + 1) + buffer.readu8(src, d + 1) + cg * 2) / 6
				local avgB = (buffer.readu8(src, l + 2) + buffer.readu8(src, r + 2) + buffer.readu8(src, u + 2) + buffer.readu8(src, d + 2) + cb * 2) / 6
				local avgA = (buffer.readu8(src, l + 3) + buffer.readu8(src, r + 3) + buffer.readu8(src, u + 3) + buffer.readu8(src, d + 3) + ca * 2) / 6
				buffer.writeu8(dst, c, _floor(cr * (1 - k) + avgR * k + 0.5))
				buffer.writeu8(dst, c + 1, _floor(cg * (1 - k) + avgG * k + 0.5))
				buffer.writeu8(dst, c + 2, _floor(cb * (1 - k) + avgB * k + 0.5))
				buffer.writeu8(dst, c + 3, _floor(ca * (1 - k) + avgA * k + 0.5))
			else
				buffer.writeu8(dst, c, cr)
				buffer.writeu8(dst, c + 1, cg)
				buffer.writeu8(dst, c + 2, cb)
				buffer.writeu8(dst, c + 3, ca)
			end
		end
	end

	for i = 0, self._pixCount * 4 - 1 do
		buffer.writeu8(src, i, buffer.readu8(dst, i))
	end
end

-- ================================================================
--  PRE-CACHED LOOP PLAYBACK
-- ================================================================

-- Begin a fresh bake. Allocates state; actual rendering happens via _stepBakeTick().
function TopoShader:_startBake()
	local cfg = self.cfg
	local totalFrames = _max(1, _floor((cfg.loopFPS or 24) * (cfg.loopDuration or 4.0) + 0.5))
	self._cache               = {}
	self._cacheIdx            = 1
	self._cacheReady          = false
	self._bakeActive          = true
	self._bakeFI              = 0
	self._bakeTotalFrames     = totalFrames
	self._bakeParallelWaiting = false
	self._cacheAccum          = 0
	self._playBuf             = buffer.create(self._pixCount * 4)
	self._debugReport.cacheReady    = false
	self._debugReport.bakeProgress  = 0
	self._debugReport.bakeTotalFrames = totalFrames
end

-- Copy the current _buf into a fresh buffer and store it as the next cached frame.
function TopoShader:_storeBakeFrame()
	local n   = self._pixCount * 4
	local src = self._buf
	local frame = buffer.create(n)
	for i = 0, n - 1 do
		buffer.writeu8(frame, i, buffer.readu8(src, i))
	end
	self._cache[self._bakeFI + 1] = frame
end

-- Render one bake frame using provided drift values (serial path only).
-- Result lands in _buf; EditableImage upload is intentionally skipped.
function TopoShader:_bakeFrameSerial(driftX, driftY, zSlice)
	self._bakeOverride = { driftX = driftX, driftY = driftY, zSlice = zSlice }
	-- Force serial path and clean settings for a full-quality, non-interlaced frame.
	local savedParallel  = self.cfg.parallelEnabled
	local savedChecker   = self.cfg.checkerboardReconstruction
	local savedTemporal  = self.cfg.temporalBlend
	self.cfg.parallelEnabled            = false
	self.cfg.checkerboardReconstruction = false
	self.cfg.temporalBlend              = 0
	self:_render(0)
	self.cfg.parallelEnabled            = savedParallel
	self.cfg.checkerboardReconstruction = savedChecker
	self.cfg.temporalBlend              = savedTemporal
	self._bakeOverride = nil
end

-- Called once per RenderStepped tick while a bake is active.
-- Renders one frame (serial or parallel) and stores it when complete.
function TopoShader:_stepBakeTick()
	local cfg   = self.cfg
	local fi    = self._bakeFI
	local total = self._bakeTotalFrames

	-- Bake complete?
	if fi >= total then
		self._bakeActive = false
		self._cacheReady = true
		self._debugReport.cacheReady   = true
		self._debugReport.bakeProgress = 1
		if type(cfg.onBakeComplete) == "function" then
			pcall(cfg.onBakeComplete)
		end
		return
	end

	-- Waiting for async parallel workers to finish the current frame.
	if self._bakeParallelWaiting then
		if self._parallelFrameReady then
			-- Apply the same post-processing passes as the parallel live path.
			if cfg.glowEnabled then self:_applyGlow() end
			if cfg.edgeAAEnabled then self:_applyEdgeAA() end
			if cfg.generatorScaleEnabled then self:_applyGeneratorScale() end
			if cfg.fakeAABlurEnabled then self:_applyFakeAABlur() end
			self:_storeBakeFrame()
			self._parallelFrameReady   = false
			self._parallelInFlight     = false
			self._bakeParallelWaiting  = false
			self._bakeFI              += 1
			self._debugReport.bakeProgress = self._bakeFI / total
			if type(cfg.onBakeProgress) == "function" then
				pcall(cfg.onBakeProgress, self._bakeFI, total)
			end
		end
		-- Don't dispatch another frame until this one is collected.
		return
	end

	-- Compute sinusoidal loop phase for this frame.
	-- phase sweeps 0 → 2π over the full loop, guaranteeing frame[0] == frame[N].
	local phase   = (fi / total) * 2 * math.pi
	local loopAmp = cfg.loopAmplitude  or 0.15
	local loopZ   = cfg.loopZAmplitude or 0.08
	local driftX  = _cos(cfg.animAngle or 0.45) * loopAmp *  _sin(phase)
	local driftY  = _sin(cfg.animAngle or 0.45) * loopAmp * (-_cos(phase))
	local zSlice  = loopZ * _sin(phase + math.pi * 0.5)

	-- Try parallel bake first.
	if self._parallelReady and cfg.bakeUseParallel and cfg.parallelEnabled then
		local ok = self:_dispatchParallelFrame(
			0, { driftX = driftX, driftY = driftY, zSlice = zSlice }
		)
		if ok then
			self._bakeParallelWaiting = true
			return
		end
	end

	-- Serial fallback: render directly on the main thread.
	self:_bakeFrameSerial(driftX, driftY, zSlice)
	self:_storeBakeFrame()
	self._bakeFI += 1
	self._debugReport.bakeProgress = self._bakeFI / total
	if type(cfg.onBakeProgress) == "function" then
		pcall(cfg.onBakeProgress, self._bakeFI, total)
	end
end

-- Zero-cost playback: advance cache frame index at loopFPS rate, write to EditableImage.
function TopoShader:_playbackTick(dt)
	if not self._cacheReady then return end
	local total = self._bakeTotalFrames
	if total <= 0 then return end

	-- Advance at loopFPS rate independent of cfg.fps.
	self._cacheAccum += (dt or (1 / _max(1, self.cfg.fps or 60)))
	local cacheInv = 1 / _max(1, self.cfg.loopFPS or 24)
	while self._cacheAccum >= cacheInv do
		self._cacheAccum -= cacheInv
		self._cacheIdx = (self._cacheIdx % total) + 1
	end

	local frame = self._cache[self._cacheIdx]
	if not frame then return end

	-- Copy cached frame into the writable play buffer.
	local playBuf = self._playBuf
	local n = self._pixCount * 4
	for i = 0, n - 1 do
		buffer.writeu8(playBuf, i, buffer.readu8(frame, i))
	end

	-- Optional live mouse overlay (only pixels inside mouse radius are recomputed).
	if self.cfg.mouseOverlayInCache and self.cfg.mouseEnabled
			and (self.cfg.mouseStrength or 0) > 0
			and (self.cfg.mouseRadius  or 0) > 0 then
		self:_applyMouseOverlayPatch(playBuf)
	end

	self._ei:WritePixelsBuffer(Vector2.zero, Vector2.new(self._rW, self._rH), playBuf)
end

-- Recompute only the pixels within mouseRadius of the cursor and patch playBuf.
-- Cost is O(mouseRadius²) in render-space, not O(rW*rH).
function TopoShader:_applyMouseOverlayPatch(playBuf)
	local cfg     = self.cfg
	local rW      = self._rW
	local rH      = self._rH
	local total   = self._bakeTotalFrames
	local fi      = self._cacheIdx - 1   -- 0-based frame index

	-- Reconstruct the exact drift used for this cached frame.
	local phase   = (fi / _max(1, total)) * 2 * math.pi
	local loopAmp = cfg.loopAmplitude  or 0.15
	local loopZ   = cfg.loopZAmplitude or 0.08
	local driftX  = _cos(cfg.animAngle or 0.45) * loopAmp *  _sin(phase)
	local driftY  = _sin(cfg.animAngle or 0.45) * loopAmp * (-_cos(phase))
	local zSlice  = loopZ * _sin(phase + math.pi * 0.5)

	local mX     = self._mouseX
	local mY     = self._mouseY
	local mRad   = cfg.mouseRadius or 120
	local mRadSq = mRad * mRad
	local mStr   = (cfg.mouseStrength or 0.35) * (cfg.baseFrequency or 0.008) * 10
	local scaleX = self._scaleX
	local scaleY = self._scaleY

	-- Restrict to the bounding box of the mouse circle in render space.
	local mRX   = mX / scaleX
	local mRY   = mY / scaleY
	local mRRad = mRad / _min(scaleX, scaleY)
	local rowMin = _max(0,      _floor(mRY - mRRad))
	local rowMax = _min(rH - 1, _floor(mRY + mRRad))
	local colMin = _max(0,      _floor(mRX - mRRad))
	local colMax = _min(rW - 1, _floor(mRX + mRRad))

	local levels     = cfg.contourLevels
	local halfW      = (cfg.lineWidth or 0.06) * 0.5
	local softEn     = cfg.softEdgesEnabled
	local softWidth  = cfg.softEdgeWidth or 0.30
	local softCurve  = cfg.softEdgeCurve or 1.0
	local bgR = cfg.bgColor.r;   local bgG = cfg.bgColor.g
	local bgB = cfg.bgColor.b;   local bgA = cfg.bgColor.a
	local lnR = cfg.lineColor.r; local lnG = cfg.lineColor.g
	local lnB = cfg.lineColor.b; local lnA = cfg.lineColor.a
	local doTint  = cfg.elevationTint
	local tintAmt = cfg.tintAmount or 0
	local invTint = 1 - tintAmt
	local loR = cfg.colorLow.r;  local loG = cfg.colorLow.g;  local loB = cfg.colorLow.b
	local hiR = cfg.colorHigh.r; local hiG = cfg.colorHigh.g; local hiB = cfg.colorHigh.b
	local oct = cfg.octaves; local lac = cfg.lacunarity
	local per = cfg.persistence; local warp = cfg.warpAmount
	local fastMode  = cfg.fastMode; local ultraFast = cfg.ultraFastMode
	local outputOpacity = cfg.outputOpacity or 1.0
	local vigEn  = cfg.vignetteEnabled
	local vigStr = cfg.vignetteStrength or 0
	local vig    = self._vig
	local cX = self._cX; local cY = self._cY
	local pX = self._pX; local pY = self._pY

	for row = rowMin, rowMax do
		for col = colMin, colMax do
			local pi  = row * rW + col + 1
			local dx  = pX[pi] - mX
			local dy  = pY[pi] - mY
			local dSq = dx * dx + dy * dy
			if dSq < mRadSq then
				local nx   = cX[pi] + driftX
				local ny   = cY[pi] + driftY
				local dist = _sqrt(dSq) + 0.0001
				local fall = 1 - dist / mRad
				fall = fall * fall * (3 - 2 * fall)
				local push = fall * mStr
				nx = nx - (dx / dist) * push
				ny = ny - (dy / dist) * push
				local h
				if ultraFast then
					h = heightFieldUltra(nx, ny, zSlice, lac, per, warp)
				elseif fastMode then
					h = heightFieldFast(nx, ny, zSlice, oct, lac, per, warp)
				else
					h = heightField(nx, ny, zSlice, oct, lac, per, warp)
				end
				local lineV = contourValue(h, levels, halfW, softEn, softWidth, softCurve)
				local r, g, b = lnR, lnG, lnB
				if doTint then
					local tr = loR + (hiR - loR) * h
					local tg = loG + (hiG - loG) * h
					local tb = loB + (hiB - loB) * h
					r = r * invTint + tr * tintAmt
					g = g * invTint + tg * tintAmt
					b = b * invTint + tb * tintAmt
				end
				r = bgR + (r - bgR) * lineV
				g = bgG + (g - bgG) * lineV
				b = bgB + (b - bgB) * lineV
				local a = bgA + (lnA - bgA) * lineV
				local ur = _floor(saturate(r) * 255 + 0.5)
				local ug = _floor(saturate(g) * 255 + 0.5)
				local ub = _floor(saturate(b) * 255 + 0.5)
				local ua = _floor(saturate(a * outputOpacity) * 255 + 0.5)
				if vigEn and vigStr > 0 then
					local vf = 1 - (1 - vig[pi]) * vigStr
					ur = _floor(ur * vf + 0.5)
					ug = _floor(ug * vf + 0.5)
					ub = _floor(ub * vf + 0.5)
				end
				local idx = (pi - 1) * 4
				buffer.writeu8(playBuf, idx,     ur)
				buffer.writeu8(playBuf, idx + 1, ug)
				buffer.writeu8(playBuf, idx + 2, ub)
				buffer.writeu8(playBuf, idx + 3, ua)
			end
		end
	end
end

-- Public API: manually trigger a fresh bake (e.g. after config changes).
-- Start() must have been called first so the RenderStepped loop is running.
function TopoShader:Rebake()
	if not self.cfg.cacheEnabled then
		return false, "cacheEnabled is false — enable it first"
	end
	if self._bakeActive then
		return false, "bake already in progress"
	end
	self:_startBake()
	return true
end

-- ================================================================
--  RENDER FRAME
-- ================================================================
function TopoShader:_render(t)
	-- Pre-cached loop playback: if cache is ready just display the baked frame.
	if self.cfg.cacheEnabled and self._cacheReady and not self._bakeOverride then
		self:_playbackTick(1 / _max(1, self.cfg.fps or 60))
		self:_updateDebug(0.05)
		return
	end

	if self._parallelReady and self.cfg.parallelEnabled then
		local renderStart = os.clock()
		if not self._parallelInFlight then
			self:_dispatchParallelFrame(t)
		end
		if self._parallelFrameReady then
			if self.cfg.edgeAAEnabled and (self._frameId % _max(1, self.cfg.edgeAAInterval or 1) == 0) then
				self:_applyEdgeAA()
			end
			if self.cfg.generatorScaleEnabled and (self._frameId % _max(1, self.cfg.generatorScaleInterval or 1) == 0) then
				self:_applyGeneratorScale()
			end
			if self.cfg.fakeAABlurEnabled and (self._frameId % _max(1, self.cfg.fakeAABlurInterval or 1) == 0) then
				self:_applyFakeAABlur()
			end
			self._ei:WritePixelsBuffer(Vector2.zero, Vector2.new(self._rW, self._rH), self._buf)
			self._parallelFrameReady = false
			self._frameId += 1
		end
		local renderMs = (os.clock() - renderStart) * 1000
		self:_updateDebug(renderMs)
		return
	end

	local renderStart = os.clock()
	local cfg      = self.cfg
	local rW       = self._rW
	local rH       = self._rH
	local buf      = self._buf
	local hist     = self._history
	local cX       = self._cX
	local cY       = self._cY
	local pX       = self._pX
	local pY       = self._pY
	local parity   = self._parity
	local vig      = self._vig

	-- Unpack constants (avoid table indexing in the pixel loop)
	local levels   = cfg.contourLevels
	local halfW    = cfg.lineWidth * 0.5
	local lineSharpness = _max(0.5, cfg.lineSharpness or 1.0)

	local bgR  = cfg.bgColor.r
	local bgG  = cfg.bgColor.g
	local bgB  = cfg.bgColor.b
	local bgA  = cfg.bgColor.a

	local lnR  = cfg.lineColor.r
	local lnG  = cfg.lineColor.g
	local lnB  = cfg.lineColor.b
	local lnA  = cfg.lineColor.a

	local loR  = cfg.colorLow.r
	local loG  = cfg.colorLow.g
	local loB  = cfg.colorLow.b

	local hiR  = cfg.colorHigh.r
	local hiG  = cfg.colorHigh.g
	local hiB  = cfg.colorHigh.b

	local doTint   = cfg.elevationTint
	local tintAmt  = cfg.tintAmount
	local invTint  = 1 - tintAmt
	local oct      = cfg.octaves
	local lac      = cfg.lacunarity
	local per      = cfg.persistence
	local warp     = cfg.warpAmount
	local fastMode = cfg.fastMode
	local ultraFast = cfg.ultraFastMode
	local temporalBlend = saturate(cfg.temporalBlend or 0)
	local temporalKeep  = 1 - temporalBlend
	local checkerboard  = cfg.checkerboardReconstruction
	local phase         = self._checkerPhase
	local outputOpacity = cfg.outputOpacity or 1.0
	local vignetteEnabled = cfg.vignetteEnabled
	local vignetteStrength = cfg.vignetteStrength or 0
	local lineAAEnabled = cfg.lineAAEnabled
	local lineAAStrength = cfg.lineAAStrength or 2.0
	local aaStep = (cfg.baseFrequency or 0.008) * (cfg.lineAAStep or 0.55)
	local lineAAMode = cfg.lineAAMode or "fast"
	local subpixel = cfg.lineAASubpixel or 0.35
	local analyticalAAEnabled = cfg.analyticalAAEnabled
	local analyticalAAStrength = cfg.analyticalAAStrength or 0.85
	local softEdgesEnabled = cfg.softEdgesEnabled
	local softEdgeWidth = cfg.softEdgeWidth or 0.30
	local softEdgeCurve = cfg.softEdgeCurve or 1.0
	local adaptiveSamplingEnabled = cfg.adaptiveSamplingEnabled
	local aaEdgeThreshold = cfg.aaEdgeThreshold or 0.012
	local verticalAABoost = cfg.verticalAABoost or 0.75

	-- Animate: drift the whole noise field slowly.
	-- _bakeOverride replaces these with sinusoidal loop values during baking.
	local _bo    = self._bakeOverride
	local driftX = _bo and _bo.driftX or (_cos(cfg.animAngle) * cfg.animSpeed * t)
	local driftY = _bo and _bo.driftY or (_sin(cfg.animAngle) * cfg.animSpeed * t)

	-- Slow morph (z-axis of noise)
	local zSlice = _bo and _bo.zSlice or (t * 0.12)

	-- Mouse warp
	local mX       = self._mouseX
	local mY       = self._mouseY
	local mRad     = cfg.mouseRadius
	local mRadSq   = mRad * mRad
	-- Convert mouse strength from panel-pixels to noise-space units
	local mStr     = cfg.mouseStrength * cfg.baseFrequency * 10
	local mouseWarpEnabled = cfg.mouseEnabled and mStr > 0 and mRad > 0
	local ditherEnabled = cfg.cursorDitherEnabled
	local ditherRad = cfg.cursorDitherRadius or mRad
	local ditherRadSq = ditherRad * ditherRad
	local ditherStr = cfg.cursorDitherStrength or 0.35
	local ditherScale = _max(1, cfg.cursorDitherScale or 2)
	local ditherPattern = cfg.cursorDitherPattern or "bayer4"

	local pixCount = self._pixCount

	for pi = 1, pixCount do
		local idx = (pi - 1) * 4
		if checkerboard and parity[pi] ~= phase then
			continue
		end

		-- Noise-space position (pre-baked + drift offset)
		local nx = cX[pi] + driftX
		local ny = cY[pi] + driftY

		-- Mouse warp: push noise coords away from cursor
		local dx, dy, dSq = 0, 0, 0
		if mouseWarpEnabled then
			dx  = pX[pi] - mX
			dy  = pY[pi] - mY
			dSq = dx * dx + dy * dy
		end

		if dSq < mRadSq and mouseWarpEnabled then
			local dist = _sqrt(dSq) + 0.0001
			local fall = 1 - dist / mRad
			fall = fall * fall * (3 - 2 * fall)   -- smoothstep
			local push = fall * mStr
			nx = nx - (dx / dist) * push
			ny = ny - (dy / dist) * push
		end

		-- Sample height field
		local h
		if ultraFast then
			h = heightFieldUltra(nx, ny, zSlice, lac, per, warp)
		elseif fastMode then
			h = heightFieldFast(nx, ny, zSlice, oct, lac, per, warp)
		else
			h = heightField(nx, ny, zSlice, oct, lac, per, warp)
		end

		local r, g, b, a
		-- Contour detection  →  0 = gap,  1 = line centre
		local bandPos = (h * levels) % 1.0
		local d = _min(bandPos, 1 - bandPos)
		local aaHalfW = halfW
		local gradX, gradY, gradH = 0, 0, 0
		if lineAAEnabled and lineAAMode ~= "off" then
			local hx, hy
			if ultraFast then
				hx = heightFieldUltra(nx + aaStep, ny, zSlice, lac, per, warp)
				hy = heightFieldUltra(nx, ny + aaStep, zSlice, lac, per, warp)
			elseif fastMode then
				hx = heightFieldFast(nx + aaStep, ny, zSlice, oct, lac, per, warp)
				hy = heightFieldFast(nx, ny + aaStep, zSlice, oct, lac, per, warp)
			else
				hx = heightField(nx + aaStep, ny, zSlice, oct, lac, per, warp)
				hy = heightField(nx, ny + aaStep, zSlice, oct, lac, per, warp)
			end
			gradX = _abs(hx - h)
			gradY = _abs(hy - h)
			gradH = gradX + gradY
			aaHalfW = halfW + gradH * lineAAStrength
			if analyticalAAEnabled then
				-- Analytical widening proportional to local iso-line slope.
				local analyticalW = gradH * levels * 0.08 * analyticalAAStrength
				aaHalfW = aaHalfW + analyticalW
			end
		end
		local lineV = contourValue(h, levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
		if lineAAEnabled and lineAAMode == "msaa4" then
			local edgeImportant = (not adaptiveSamplingEnabled) or (gradH >= aaEdgeThreshold)
			if edgeImportant then
				local so = aaStep * subpixel
				local function sampleH(sx, sy)
					if ultraFast then
						return heightFieldUltra(sx, sy, zSlice, lac, per, warp)
					elseif fastMode then
						return heightFieldFast(sx, sy, zSlice, oct, lac, per, warp)
					else
						return heightField(sx, sy, zSlice, oct, lac, per, warp)
					end
				end
				if not adaptiveSamplingEnabled then
					local h1 = sampleH(nx - so, ny - so)
					local h2 = sampleH(nx + so, ny - so)
					local h3 = sampleH(nx - so, ny + so)
					local h4 = sampleH(nx + so, ny + so)
					local m1 = contourValue(h1, levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
					local m2 = contourValue(h2, levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
					local m3 = contourValue(h3, levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
					local m4 = contourValue(h4, levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
					lineV = (lineV + m1 + m2 + m3 + m4) * 0.2
				else
					local verticalDom = saturate((gradX - gradY) / _max(0.0001, gradH))
					local hSum, n = lineV, 1
					if verticalDom > 0.12 then
						local soV = so * (1 + verticalAABoost * verticalDom)
						hSum += contourValue(sampleH(nx - soV, ny), levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
						hSum += contourValue(sampleH(nx + soV, ny), levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
						hSum += contourValue(sampleH(nx - so, ny - so), levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
						hSum += contourValue(sampleH(nx + so, ny + so), levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
						n = 5
					else
						hSum += contourValue(sampleH(nx, ny - so), levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
						hSum += contourValue(sampleH(nx, ny + so), levels, aaHalfW, softEdgesEnabled, softEdgeWidth, softEdgeCurve)
						n = 3
					end
					lineV = hSum / n
				end
			end
		end
		if lineSharpness ~= 1 then
			lineV = lineV ^ lineSharpness
		end

		-- Cursor-centric dither interaction for lines.
		if ditherEnabled and ditherRad > 0 and dSq < ditherRadSq then
			local dist = _sqrt(dSq) + 0.0001
			local fall = 1 - dist / ditherRad
			fall = fall * fall * (3 - 2 * fall)
			local cellX = _floor(pX[pi] / ditherScale)
			local cellY = _floor(pY[pi] / ditherScale)
			local threshold
			if ditherPattern == "checker" then
				threshold = ((cellX + cellY) % 2 == 0) and 0.25 or 0.75
			else
				local bx = (cellX % 4) + 1
				local by = (cellY % 4) + 1
				threshold = BAYER4[by][bx] / 16
			end
			local mask = (fall * ditherStr > threshold) and 0 or 1
			lineV = lineV * mask
		end

		-- Analytical AA path: always blend continuously (no binary line threshold branch).
		r, g, b = lnR, lnG, lnB
		if doTint then
			local tr = loR + (hiR - loR) * h
			local tg = loG + (hiG - loG) * h
			local tb = loB + (hiB - loB) * h
			r = r * invTint + tr * tintAmt
			g = g * invTint + tg * tintAmt
			b = b * invTint + tb * tintAmt
		end
		r = lerp(bgR, r, lineV)
		g = lerp(bgG, g, lineV)
		b = lerp(bgB, b, lineV)
		a = lerp(bgA, lnA, lineV)

		-- Write to Luau buffer (RGBA u8)
		local ur = _floor(saturate(r) * 255 + 0.5)
		local ug = _floor(saturate(g) * 255 + 0.5)
		local ub = _floor(saturate(b) * 255 + 0.5)
		local ua = _floor(saturate(a * outputOpacity) * 255 + 0.5)
		if temporalBlend > 0 then
			ur = _floor(ur * temporalKeep + buffer.readu8(hist, idx) * temporalBlend + 0.5)
			ug = _floor(ug * temporalKeep + buffer.readu8(hist, idx + 1) * temporalBlend + 0.5)
			ub = _floor(ub * temporalKeep + buffer.readu8(hist, idx + 2) * temporalBlend + 0.5)
			ua = _floor(ua * temporalKeep + buffer.readu8(hist, idx + 3) * temporalBlend + 0.5)
		end
		if vignetteEnabled and vignetteStrength > 0 then
			local vf = 1 - (1 - vig[pi]) * vignetteStrength
			ur = _floor(ur * vf + 0.5)
			ug = _floor(ug * vf + 0.5)
			ub = _floor(ub * vf + 0.5)
		end

		buffer.writeu8(buf, idx, ur)
		buffer.writeu8(buf, idx + 1, ug)
		buffer.writeu8(buf, idx + 2, ub)
		buffer.writeu8(buf, idx + 3, ua)
		buffer.writeu8(hist, idx, ur)
		buffer.writeu8(hist, idx + 1, ug)
		buffer.writeu8(hist, idx + 2, ub)
		buffer.writeu8(hist, idx + 3, ua)
	end

	if checkerboard then
		self:_reconstructCheckerboard(phase)
	end

	-- Optional glow pass (smears bright pixels into neighbors)
	if cfg.glowEnabled then
		self:_applyGlow()
	end
	if cfg.edgeAAEnabled and (self._frameId % _max(1, cfg.edgeAAInterval or 1) == 0) then
		self:_applyEdgeAA()
	end
	if cfg.generatorScaleEnabled and (self._frameId % _max(1, cfg.generatorScaleInterval or 1) == 0) then
		self:_applyGeneratorScale()
	end
	if cfg.fakeAABlurEnabled and (self._frameId % _max(1, cfg.fakeAABlurInterval or 1) == 0) then
		self:_applyFakeAABlur()
	end

	-- Single GPU upload — skip when this call is from _bakeFrameSerial
	-- (caller handles display and buffer storage in that case).
	if not self._bakeOverride then
		self._ei:WritePixelsBuffer(Vector2.zero, Vector2.new(rW, rH), buf)
		self._checkerPhase = 1 - phase
		self._frameId += 1
	end

	local renderMs = (os.clock() - renderStart) * 1000
	if not self._bakeOverride then
		if cfg.adaptiveQuality then
			self:_updateAdaptiveQuality(renderMs)
		end
		self:_updateDebug(renderMs)
	end
end

-- ================================================================
--  GLOW  (horizontal box blur, bright pixels only)
-- ================================================================
function TopoShader:_applyGlow()
	local buf = self._buf
	local rW  = self._rW
	local rH  = self._rH
	local str = self.cfg.glowStrength

	for row = 0, rH - 1 do
		for col = 1, rW - 2 do
			local c  = (row * rW + col)     * 4
			local cL = c - 4
			local cR = c + 4

			-- Only process bright (line) pixels
			local bright = buffer.readu8(buf, c)
			if bright > 60 then
				for ch = 0, 2 do
					local avg = (
						buffer.readu8(buf, cL + ch) +
							buffer.readu8(buf, c  + ch) * 2 +
							buffer.readu8(buf, cR + ch)
					) * 0.25
					buffer.writeu8(buf, c + ch,
						_floor(lerp(buffer.readu8(buf, c + ch), avg, str)))
				end
			end
		end
	end
end

-- ================================================================
--  PUBLIC API
-- ================================================================

function TopoShader:Start()
	if self._running then return end
	self._running = true
	self:_refreshParallelState()

	-- Auto-bake on start if the cache mode is enabled.
	if self.cfg.cacheEnabled and self.cfg.bakeOnStart
			and not self._cacheReady and not self._bakeActive then
		self:_startBake()
	end

	-- Track mouse position in panel-local space (with GUI inset correction)
	self._inputConn = UserInputService.InputChanged:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseMovement then
			local mp = UserInputService:GetMouseLocation()
			local insetTL = GuiService:GetGuiInset()
			local abs = self._clip.AbsolutePosition
			local size = self._clip.AbsoluteSize
			local localX = mp.X - insetTL.X - abs.X
			local localY = mp.Y - insetTL.Y - abs.Y
			self._mouseX = _max(0, _min(size.X, localX))
			self._mouseY = _max(0, _min(size.Y, localY))
		end
	end)

	local inv = 1 / self.cfg.fps
	self._conn = RunService.RenderStepped:Connect(function(dt)
		self:_syncLocalBackdrop(dt)
		self._debugClock += dt
		if dt > 0 then
			self._debugReport.fps = 1 / dt
		end

		-- Bake phase runs every tick (no fps throttle) so it finishes as fast as possible.
		-- The most-recently-baked frame is shown as a live preview while baking.
		if self.cfg.cacheEnabled and self._bakeActive then
			local bakeStart = os.clock()
			self:_stepBakeTick()
			-- Show the current _buf as a preview (updated by serial bake; may lag 1 tick for parallel).
			self._ei:WritePixelsBuffer(Vector2.zero, Vector2.new(self._rW, self._rH), self._buf)
			self:_updateDebug((os.clock() - bakeStart) * 1000)
			return
		end

		self._accumTime += dt
		if self._accumTime < inv then return end
		self._accumTime -= inv
		self:_render(os.clock())
	end)
end

function TopoShader:Stop()
	if not self._running then return end
	self._running = false
	if self._conn      then self._conn:Disconnect()      self._conn      = nil end
	if self._inputConn then self._inputConn:Disconnect() self._inputConn = nil end
end

function TopoShader:SetPosition(udim2) self._root.Position   = udim2 end
function TopoShader:SetAnchor(vec2)    self._root.AnchorPoint = vec2  end

function TopoShader:SetConfig(key, value)
	local sv = sanitizeValue(key, value)
	if sv == nil and CONFIG_RULES[key] then
		return false, "Invalid value for " .. tostring(key)
	end
	self.cfg[key] = (sv ~= nil) and sv or value
	if key == "debugEnabled" and self._debugLabel then
		self._debugLabel.Visible = self.cfg.debugEnabled and true or false
	end
	if key == "panelTransparency" and self._clip then
		self._clip.BackgroundTransparency = self.cfg.panelTransparency or 0
	end
	if key == "imageTransparency" and self._img then
		self._img.ImageTransparency = self.cfg.imageTransparency or 0
	end
	if key == "upscaleMode" and self._img then
		self._img.ResampleMode = (self.cfg.upscaleMode == "nearest") and Enum.ResamplerMode.Pixelated or Enum.ResamplerMode.Default
	end
	if key == "interlacedMode" then
		self.cfg.checkerboardReconstruction = (self.cfg.interlacedMode == "checkerboard")
	end
	if key == "checkerboardReconstruction" then
		self.cfg.interlacedMode = self.cfg.checkerboardReconstruction and "checkerboard" or "off"
	end
	if key == "cornerRadius" then
		local cr = UDim.new(0, self.cfg.cornerRadius or 0)
		if self._clipCorner then self._clipCorner.CornerRadius = cr end
		if self._imgCorner then self._imgCorner.CornerRadius = cr end
		if self._vpfCorner then self._vpfCorner.CornerRadius = cr end
	end

	-- Rebuild coord cache if spatial frequency changed
	if key == "baseFrequency" then
		local freq = self.cfg.baseFrequency
		local rW   = self._rW
		local rH   = self._rH
		local w    = self.cfg.width
		local h    = self.cfg.height
		for row = 0, rH - 1 do
			local base = row * rW
			local ny   = row * freq
			for col = 0, rW - 1 do
				local i = base + col + 1
				self._cX[i] = col * freq
				self._cY[i] = ny
				self._pX[i] = col * (w / rW)
				self._pY[i] = row * (h / rH)
			end
		end
	end
	if key == "parallelEnabled" then
		self:SetParallelEnabled(self.cfg.parallelEnabled)
	end
	if key == "parallelTileWidth" or key == "parallelTileHeight" then
		self:_rebuildParallelTiles()
	end
	if key == "qualityPreset" then
		self:SetQualityPreset(self.cfg.qualityPreset)
	end
	if key == "visualProfile" then
		self:SetVisualProfile(self.cfg.visualProfile)
	end
	if key == "backgroundBlurEnabled" or key == "backgroundBlurSize" then
		self:_syncBackgroundBlur()
	end
	if key == "localBlurEnabled" or key == "localBlurSize" then
		self:_syncBackgroundBlur()
	end
	if key == "fakeLocalBackdropEnabled" or key == "fakeLocalBackdropAlpha" then
		if self._vpf then
			self._vpf.Visible = self.cfg.fakeLocalBackdropEnabled and true or false
			self._vpf.ImageTransparency = 1 - (self.cfg.fakeLocalBackdropAlpha or 0.35)
		end
		if self.cfg.fakeLocalBackdropEnabled and not self._vpfReady then
			self:_rebuildLocalBackdrop()
		end
	end
	if key == "fakeLocalBackdropQuality" then
		self:ApplyFakeBackdropQuality(self.cfg.fakeLocalBackdropQuality)
	end
	if key == "fakeLocalBackdropDistance" or key == "fakeLocalBackdropMaxParts" or key == "fakeLocalBackdropSimplify" then
		if self.cfg.fakeLocalBackdropEnabled then
			self:_rebuildLocalBackdrop()
		end
	end

	-- Cache invalidation: if a rendering-affecting key changed, discard the baked frames
	-- and start a fresh bake (if bakeOnStart is true).
	if self.cfg.cacheEnabled and self._cacheReady and CACHE_INVALIDATE_KEYS[key] then
		self._cacheReady = false
		self._cache      = {}
		if self.cfg.bakeOnStart and self._running then
			self:_startBake()
		end
	end

	return true
end

function TopoShader:Configure(options)
	if not options then return end
	local requestedPreset = options.qualityPreset
	local requestedVisual = options.visualProfile
	for k, v in pairs(options) do
		if k ~= "qualityPreset" and k ~= "visualProfile" then
			self:SetConfig(k, v)
		end
	end
	if requestedPreset then
		self:SetQualityPreset(requestedPreset)
	end
	if requestedVisual then
		self:SetVisualProfile(requestedVisual)
	end
end

function TopoShader:SetQualityPreset(preset)
	if preset == "performance" then
		self.cfg.fastMode = true
		self.cfg.ultraFastMode = true
		self.cfg.checkerboardReconstruction = false
		self.cfg.temporalBlend = 0.0
		self.cfg.edgeAAEnabled = false
		self.cfg.lineAAEnabled = false
		self.cfg.lineAAMode = "off"
		self.cfg.analyticalAAEnabled = false
		self.cfg.adaptiveSamplingEnabled = true
		self.cfg.aaEdgeThreshold = 0.020
		self.cfg.verticalAABoost = 0.45
		self.cfg.generatorScaleEnabled = false
		self.cfg.fakeAABlurEnabled = false
		self.cfg.edgeAAInterval = 3
		self.cfg.glowEnabled = false
		self.cfg.warpAmount = _min(self.cfg.warpAmount, 0.75)
		self.cfg.octaves = 2
		self.cfg.frameBudgetMs = _max(self.cfg.frameBudgetMs or 12.0, 18.0)
	elseif preset == "quality" then
		self.cfg.fastMode = false
		self.cfg.ultraFastMode = false
		self.cfg.checkerboardReconstruction = false
		self.cfg.temporalBlend = 0.06
		self.cfg.edgeAAEnabled = true
		self.cfg.edgeAAQuality = "hq"
		self.cfg.lineAAEnabled = true
		self.cfg.lineAAStrength = 2.4
		self.cfg.lineAAMode = "msaa4"
		self.cfg.analyticalAAEnabled = true
		self.cfg.analyticalAAStrength = 1.0
		self.cfg.adaptiveSamplingEnabled = true
		self.cfg.aaEdgeThreshold = 0.008
		self.cfg.verticalAABoost = 1.05
		self.cfg.generatorScaleEnabled = true
		self.cfg.generatorScaleStrength = 0.56
		self.cfg.generatorScaleThreshold = 0.06
		self.cfg.generatorScaleAlpha = 0.82
		self.cfg.generatorScaleInterval = 1
		self.cfg.generatorVerticalBias = 1.45
		self.cfg.fakeAABlurEnabled = true
		self.cfg.fakeAABlurStrength = 0.14
		self.cfg.fakeAABlurThreshold = 0.05
		self.cfg.fakeAABlurInterval = 1
		self.cfg.edgeAAInterval = 1
		self.cfg.glowEnabled = false
		self.cfg.octaves = _min(6, self.cfg.octaves + 1)
		self.cfg.frameBudgetMs = _min(self.cfg.frameBudgetMs or 12.0, 12.0)
	else -- balanced
		self.cfg.fastMode = true
		self.cfg.ultraFastMode = false
		self.cfg.checkerboardReconstruction = false
		self.cfg.temporalBlend = 0.08
		self.cfg.edgeAAEnabled = false
		self.cfg.lineAAEnabled = true
		self.cfg.lineAAStrength = 2.0
		self.cfg.lineAAMode = "fast"
		self.cfg.analyticalAAEnabled = true
		self.cfg.analyticalAAStrength = 0.85
		self.cfg.adaptiveSamplingEnabled = true
		self.cfg.aaEdgeThreshold = 0.012
		self.cfg.verticalAABoost = 0.75
		self.cfg.generatorScaleEnabled = true
		self.cfg.generatorScaleStrength = 0.42
		self.cfg.generatorScaleThreshold = 0.08
		self.cfg.generatorScaleAlpha = 0.70
		self.cfg.generatorScaleInterval = 2
		self.cfg.generatorVerticalBias = 1.35
		self.cfg.fakeAABlurEnabled = true
		self.cfg.fakeAABlurStrength = 0.10
		self.cfg.fakeAABlurThreshold = 0.07
		self.cfg.fakeAABlurInterval = 2
		self.cfg.edgeAAInterval = 2
		self.cfg.glowEnabled = false
		self.cfg.octaves = _max(3, _min(4, self.cfg.octaves))
		self.cfg.frameBudgetMs = _max(14.0, _min(self.cfg.frameBudgetMs or 14.0, 16.0))
	end
	self.cfg.qualityPreset = preset
end

function TopoShader:SetVisualProfile(profile)
	if profile == "performance" then
		self.cfg.edgeAAEnabled = false
		self.cfg.lineAAEnabled = false
		self.cfg.lineAAMode = "off"
		self.cfg.analyticalAAEnabled = false
		self.cfg.adaptiveSamplingEnabled = true
		self.cfg.aaEdgeThreshold = 0.020
		self.cfg.verticalAABoost = 0.45
		self.cfg.generatorScaleEnabled = false
		self.cfg.fakeAABlurEnabled = false
		self.cfg.lineSharpness = 1.05
		self.cfg.vignetteEnabled = false
		self.cfg.vignetteStrength = 0.0
	elseif profile == "cinematic" then
		self.cfg.edgeAAEnabled = true
		self.cfg.edgeAAQuality = "hq"
		self.cfg.lineAAEnabled = true
		self.cfg.lineAAStrength = 2.6
		self.cfg.lineAAMode = "msaa4"
		self.cfg.analyticalAAEnabled = true
		self.cfg.analyticalAAStrength = 1.1
		self.cfg.adaptiveSamplingEnabled = true
		self.cfg.aaEdgeThreshold = 0.008
		self.cfg.verticalAABoost = 1.10
		self.cfg.generatorScaleEnabled = true
		self.cfg.generatorScaleStrength = 0.58
		self.cfg.generatorScaleThreshold = 0.05
		self.cfg.generatorScaleAlpha = 0.86
		self.cfg.generatorScaleInterval = 1
		self.cfg.generatorVerticalBias = 1.50
		self.cfg.fakeAABlurEnabled = true
		self.cfg.fakeAABlurStrength = 0.16
		self.cfg.fakeAABlurThreshold = 0.05
		self.cfg.fakeAABlurInterval = 1
		self.cfg.edgeAAInterval = 2
		self.cfg.lineSharpness = 0.92
		self.cfg.vignetteEnabled = true
		self.cfg.vignetteStrength = 0.14
	else -- balanced
		self.cfg.lineSharpness = 1.0
		self.cfg.lineAAEnabled = true
		self.cfg.lineAAStrength = 2.0
		self.cfg.lineAAMode = "fast"
		self.cfg.analyticalAAEnabled = true
		self.cfg.analyticalAAStrength = 0.85
		self.cfg.adaptiveSamplingEnabled = true
		self.cfg.aaEdgeThreshold = 0.012
		self.cfg.verticalAABoost = 0.75
		self.cfg.generatorScaleEnabled = true
		self.cfg.generatorScaleStrength = 0.42
		self.cfg.generatorScaleThreshold = 0.08
		self.cfg.generatorScaleAlpha = 0.70
		self.cfg.generatorScaleInterval = 2
		self.cfg.generatorVerticalBias = 1.35
		self.cfg.fakeAABlurEnabled = true
		self.cfg.fakeAABlurStrength = 0.10
		self.cfg.fakeAABlurThreshold = 0.07
		self.cfg.fakeAABlurInterval = 2
		self.cfg.vignetteEnabled = true
		self.cfg.vignetteStrength = 0.10
	end
	self.cfg.visualProfile = profile
end

function TopoShader:SetPerformanceOptions(opts)
	if not opts then return end
	if opts.frameBudgetMs ~= nil then self:SetConfig("frameBudgetMs", opts.frameBudgetMs) end
	if opts.fps ~= nil then self:SetConfig("fps", opts.fps) end
	if opts.adaptiveQuality ~= nil then self:SetConfig("adaptiveQuality", opts.adaptiveQuality) end
	if opts.edgeAAInterval ~= nil then self:SetConfig("edgeAAInterval", opts.edgeAAInterval) end
end

function TopoShader:GetConfigTemplate()
	return cloneTable(DEFAULTS)
end

function TopoShader:GetConfigSchema()
	return cloneTable(CONFIG_RULES)
end

function TopoShader:GetThemeNames()
	return { "classic", "ocean", "neon", "paper" }
end

function TopoShader:ApplyTheme(name)
	local theme = THEMES[name]
	if not theme then
		return false, "Unknown theme: " .. tostring(name)
	end
	for k, v in pairs(theme) do
		if type(v) == "table" then
			self.cfg[k] = cloneTable(v)
		else
			self:SetConfig(k, v)
		end
	end
	self.cfg.theme = name
	return true
end

-- TopoActors folder may live:
-- 1) under the TopoShader ModuleScript (original layout), or
-- 2) next to it under the same parent (e.g. ShaderRunner Script contains both ModuleScript + TopoActors).
local function findTopoActorsPool()
	local pool = script:FindFirstChild("TopoActors")
	if pool then return pool end
	local p = script.Parent
	if p then
		pool = p:FindFirstChild("TopoActors")
		if pool then return pool end
		p = p.Parent
		if p then
			pool = p:FindFirstChild("TopoActors")
			if pool then return pool end
		end
	end
	return nil
end

function TopoShader:_refreshParallelState()
	for _, c in ipairs(self._parallelConns) do
		c:Disconnect()
	end
	self._parallelConns = {}
	self._parallelActors = {}
	self._parallelReady = false
	self._parallelWorkers = 0

	if not self.cfg.parallelEnabled then
		self._debugReport.parallelReady = false
		self._debugReport.parallelWorkers = 0
		return
	end

	local pool = findTopoActorsPool()
	if not pool then
		self._debugReport.parallelReady = false
		self._debugReport.parallelWorkers = 0
		return
	end

	local workers = 0
	local protocolReady = true
	for _, child in ipairs(pool:GetChildren()) do
		if child:IsA("Actor") then
			workers += 1
			local rq = child:FindFirstChild("RenderRequest")
			local dn = child:FindFirstChild("RenderDone")
			if not (rq and rq:IsA("BindableEvent") and dn and dn:IsA("BindableEvent")) then
				protocolReady = false
			else
				table.insert(self._parallelActors, {
					actor = child,
					request = rq,
					done = dn,
				})
			end
		end
	end

	self._parallelWorkers = workers
	-- Any number of valid workers can be used (round-robin); do not require `parallelWorkers` separate Actor instances.
	self._parallelReady = protocolReady and #self._parallelActors >= 1
	if self._parallelReady then
		self:_rebuildParallelTiles()
		for _, w in ipairs(self._parallelActors) do
			local conn = w.done.Event:Connect(function(result)
				self:_onParallelChunkDone(result)
			end)
			table.insert(self._parallelConns, conn)
		end
	end
	self._debugReport.parallelReady = self._parallelReady
	self._debugReport.parallelWorkers = #self._parallelActors
end

function TopoShader:SetParallelEnabled(enabled)
	self.cfg.parallelEnabled = enabled and true or false
	self:_refreshParallelState()
end

function TopoShader:_syncBackgroundBlur()
	-- Try local panel blur first (if class is supported by client/runtime).
	self._localBlurReady = false
	if self.cfg.localBlurEnabled and self._clip then
		if not self._uiBlur then
			local ok, inst = pcall(function()
				return Instance.new("UIBlurEffect")
			end)
			if ok and inst then
				inst.Name = "TopoPanelBlur"
				inst.Size = self.cfg.localBlurSize or 10
				inst.Parent = self._clip
				self._uiBlur = inst
				self._localBlurReady = true
			end
		else
			self._uiBlur.Size = self.cfg.localBlurSize or 10
			if self._uiBlur.Parent ~= self._clip then
				self._uiBlur.Parent = self._clip
			end
			self._localBlurReady = true
		end
	else
		if self._uiBlur then
			self._uiBlur:Destroy()
			self._uiBlur = nil
		end
	end
	self._debugReport.localBlurReady = self._localBlurReady

	-- Optional global blur fallback/stack.
	if self.cfg.backgroundBlurEnabled then
		if not self._blur then
			local blur = Instance.new("BlurEffect")
			blur.Name = "TopoShaderBlur"
			blur.Size = self.cfg.backgroundBlurSize or 10
			blur.Parent = Lighting
			self._blur = blur
		else
			self._blur.Size = self.cfg.backgroundBlurSize or 10
			if not self._blur.Parent then
				self._blur.Parent = Lighting
			end
		end
	else
		if self._blur then
			self._blur:Destroy()
			self._blur = nil
		end
	end
end

function TopoShader:_rebuildLocalBackdrop()
	if not (self._vpf and self._vpfWorld) then return end
	self._vpfMap = {}
	self._vpfWorld:ClearAllChildren()

	local cam = workspace.CurrentCamera
	if not cam then
		self._vpfReady = false
		self._debugReport.fakeBackdropReady = false
		return
	end
	local camPos = cam and cam.CFrame.Position
	local maxDist = self.cfg.fakeLocalBackdropDistance or 180
	local maxDistSq = maxDist * maxDist
	local cap = _max(1, self.cfg.fakeLocalBackdropMaxParts or 350)
	local simplify = self.cfg.fakeLocalBackdropSimplify
	local panelOnly = self.cfg.fakeLocalBackdropPanelOnly
	local panelMargin = self.cfg.fakeLocalBackdropPanelMargin or 48
	local inset = GuiService:GetGuiInset()
	local abs = self._clip and self._clip.AbsolutePosition or Vector2.zero
	local size = self._clip and self._clip.AbsoluteSize or Vector2.zero

	local function inPanelThreshold(worldPos)
		if not panelOnly then return true end
		local vp, onScreen = cam:WorldToViewportPoint(worldPos)
		if not onScreen then return false end
		local sx = vp.X - inset.X
		local sy = vp.Y - inset.Y
		local minX = abs.X - panelMargin
		local minY = abs.Y - panelMargin
		local maxX = abs.X + size.X + panelMargin
		local maxY = abs.Y + size.Y + panelMargin
		return sx >= minX and sx <= maxX and sy >= minY and sy <= maxY
	end

	local count = 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and not inst:IsDescendantOf(self._root) then
			if camPos then
				local dp = inst.Position - camPos
				local dSq = dp.X * dp.X + dp.Y * dp.Y + dp.Z * dp.Z
				if dSq > maxDistSq then
					continue
				end
			end
			if not inPanelThreshold(inst.Position) then
				continue
			end
			local ok, clone = pcall(function()
				return inst:Clone()
			end)
			if ok and clone then
				clone.Anchored = true
				clone.CanCollide = false
				if simplify then
					clone.Material = Enum.Material.SmoothPlastic
					local gray = (clone.Color.R + clone.Color.G + clone.Color.B) / 3
					clone.Color = Color3.new(gray, gray, gray):Lerp(Color3.fromRGB(110, 125, 145), 0.35)
					clone.Reflectance = 0
				end
				clone.Parent = self._vpfWorld
				self._vpfMap[inst] = clone
				count += 1
				if count >= cap then
					break
				end
			end
		end
	end
	self._vpfReady = count > 0
	self._debugReport.fakeBackdropReady = self._vpfReady
end

function TopoShader:_syncLocalBackdrop(dt)
	if not self.cfg.fakeLocalBackdropEnabled then
		if self._vpf then self._vpf.Visible = false end
		self._debugReport.fakeBackdropReady = false
		return
	end
	if not self._vpf or not self._vpfCamera then return end

	self._vpf.Visible = true
	self._vpf.ImageTransparency = 1 - (self.cfg.fakeLocalBackdropAlpha or 0.35)
	local blurS = self.cfg.fakeLocalBackdropBlurStrength or 0.65
	self._vpf.ImageColor3 = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(155, 170, 190), blurS * 0.55)

	self._vpfRebuildAccum += dt
	if self._vpfRebuildAccum >= (self.cfg.fakeLocalBackdropRebuildSec or 2.5) then
		self._vpfRebuildAccum = 0
		self:_rebuildLocalBackdrop()
	end

	if not self._vpfReady then
		self:_rebuildLocalBackdrop()
		if not self._vpfReady then
			self._vpf.Visible = false
			return
		end
	end

	local hz = _max(1, self.cfg.fakeLocalBackdropRefreshHz or 15)
	local interval = 1 / hz
	self._vpfAccum += dt
	if self._vpfAccum < interval then
		return
	end
	self._vpfAccum = 0

	local cam = workspace.CurrentCamera
	if cam then
		self._vpfCamera.CFrame = cam.CFrame
		self._vpfCamera.FieldOfView = cam.FieldOfView
		self._vpf.Visible = true
	end

	for src, dst in pairs(self._vpfMap) do
		if src and src.Parent and dst then
			dst.CFrame = src.CFrame
			local sizeBoost = 1 + blurS * 0.025
			dst.Size = src.Size * sizeBoost
			if self.cfg.fakeLocalBackdropSimplify then
				local gray = (src.Color.R + src.Color.G + src.Color.B) / 3
				dst.Color = Color3.new(gray, gray, gray):Lerp(Color3.fromRGB(115, 130, 150), 0.45 + blurS * 0.2)
				dst.Material = Enum.Material.SmoothPlastic
			else
				dst.Color = src.Color
				dst.Material = src.Material
			end
			dst.Transparency = _min(1, src.Transparency + 0.12 + blurS * 0.45)
			if dst:IsA("MeshPart") and src:IsA("MeshPart") then
				dst.TextureID = src.TextureID
			end
		else
			self._vpfMap[src] = nil
		end
	end
end

function TopoShader:_onParallelChunkDone(result)
	if type(result) ~= "table" then return end
	if result.jobId ~= self._parallelJobId then return end
	local data = result.data
	local rowStart = result.rowStart
	local rowEnd = result.rowEnd
	if not data or rowStart == nil or rowEnd == nil then return end

	local rW = self._rW
	local colStart = result.colStart or 0
	local colEnd = result.colEnd or (rW - 1)
	local rows = rowEnd - rowStart + 1
	local cols = colEnd - colStart + 1
	local src = 0
	for rr = 0, rows - 1 do
		local dstBase = ((rowStart + rr) * rW + colStart) * 4
		local count = cols * 4
		for i = 0, count - 1 do
			buffer.writeu8(self._buf, dstBase + i, buffer.readu8(data, src + i))
		end
		src += count
	end

	self._parallelPending -= 1
	if self._parallelPending <= 0 then
		self._parallelInFlight = false
		self._parallelFrameReady = true
	end
end

function TopoShader:_rebuildParallelTiles()
	self._parallelTiles = {}
	self._parallelTileCursor = 1
	local rW = self._rW
	local rH = self._rH
	local tw = _max(16, self.cfg.parallelTileWidth or 64)
	local th = _max(16, self.cfg.parallelTileHeight or 64)
	for row = 0, rH - 1, th do
		local rowEnd = _min(rH - 1, row + th - 1)
		for col = 0, rW - 1, tw do
			local colEnd = _min(rW - 1, col + tw - 1)
			table.insert(self._parallelTiles, {
				rowStart = row,
				rowEnd = rowEnd,
				colStart = col,
				colEnd = colEnd,
			})
		end
	end
end

-- driftOverride (optional): {driftX, driftY, zSlice} — used during bake to supply
-- sinusoidal loop drift instead of time-based linear drift.
function TopoShader:_dispatchParallelFrame(t, driftOverride)
	if not self._parallelReady then return false end
	if self._parallelInFlight then return false end

	local workers = self._parallelActors
	if #workers == 0 then return false end
	if #self._parallelTiles == 0 then
		self:_rebuildParallelTiles()
	end

	self._parallelJobId += 1
	self._parallelFrameTime = t
	self._parallelPending = 0
	self._parallelInFlight = true

	local tiles = self._parallelTiles
	local total = #tiles
	local progressive = self.cfg.parallelProgressive
	local budget = progressive and _max(1, self.cfg.parallelTilesPerFrame or 6) or total
	local wi = 1
	for _ = 1, budget do
		if total == 0 then break end
		local ti = self._parallelTileCursor
		if ti > total then ti = 1 end
		local tile = tiles[ti]
		self._parallelTileCursor = ti + 1
		if self._parallelTileCursor > total then
			self._parallelTileCursor = 1
		end

		local w = workers[wi]
		self._parallelPending += 1
		w.request:Fire({
			jobId = self._parallelJobId,
			rowStart = tile.rowStart,
			rowEnd = tile.rowEnd,
			colStart = tile.colStart,
			colEnd = tile.colEnd,
			rW = self._rW,
			rH = self._rH,
			time = t,
				-- Bake mode: pass pre-computed sinusoidal drift so workers produce
				-- the correct seamless-loop frame instead of time-based drift.
				bakeDriftX = driftOverride and driftOverride.driftX or nil,
				bakeDriftY = driftOverride and driftOverride.driftY or nil,
				bakeZSlice = driftOverride and driftOverride.zSlice or nil,
				baseFrequency = self.cfg.baseFrequency,
			contourLevels = self.cfg.contourLevels,
			lineWidth = self.cfg.lineWidth,
			softEdgesEnabled = self.cfg.softEdgesEnabled,
			softEdgeWidth = self.cfg.softEdgeWidth,
			softEdgeCurve = self.cfg.softEdgeCurve,
			bgColor = self.cfg.bgColor,
			lineColor = self.cfg.lineColor,
			elevationTint = self.cfg.elevationTint,
			colorLow = self.cfg.colorLow,
			colorHigh = self.cfg.colorHigh,
			tintAmount = self.cfg.tintAmount,
			animSpeed = self.cfg.animSpeed,
			animAngle = self.cfg.animAngle,
			lacunarity = self.cfg.lacunarity,
			persistence = self.cfg.persistence,
			warpAmount = self.cfg.warpAmount,
			fastMode = self.cfg.fastMode,
			ultraFastMode = self.cfg.ultraFastMode,
			octaves = self.cfg.octaves,
		})
		wi += 1
		if wi > #workers then wi = 1 end
	end

	if self._parallelPending == 0 then
		self._parallelInFlight = false
		return false
	end
	return true
end

function TopoShader:GetTopoModes()
	return { "classic", "godRays", "precision", "bold", "dream", "wireframe", "molten", "glacier", "radar", "sunset" }
end

function TopoShader:ApplyFakeBackdropQuality(profile)
	if profile == "low" then
		self:SetConfig("fakeLocalBackdropRefreshHz", 8)
		self:SetConfig("fakeLocalBackdropMaxParts", 180)
		self:SetConfig("fakeLocalBackdropDistance", 120)
		self:SetConfig("fakeLocalBackdropAlpha", 0.22)
		self:SetConfig("fakeLocalBackdropRebuildSec", 3.0)
		self:SetConfig("fakeLocalBackdropSimplify", true)
		self:SetConfig("fakeLocalBackdropPanelMargin", 36)
		self:SetConfig("fakeLocalBackdropBlurStrength", 0.45)
	elseif profile == "high" then
		self:SetConfig("fakeLocalBackdropRefreshHz", 20)
		self:SetConfig("fakeLocalBackdropMaxParts", 700)
		self:SetConfig("fakeLocalBackdropDistance", 260)
		self:SetConfig("fakeLocalBackdropAlpha", 0.38)
		self:SetConfig("fakeLocalBackdropRebuildSec", 1.2)
		self:SetConfig("fakeLocalBackdropSimplify", false)
		self:SetConfig("fakeLocalBackdropPanelMargin", 72)
		self:SetConfig("fakeLocalBackdropBlurStrength", 0.82)
	else -- balanced
		self:SetConfig("fakeLocalBackdropRefreshHz", 12)
		self:SetConfig("fakeLocalBackdropMaxParts", 350)
		self:SetConfig("fakeLocalBackdropDistance", 180)
		self:SetConfig("fakeLocalBackdropAlpha", 0.30)
		self:SetConfig("fakeLocalBackdropRebuildSec", 2.5)
		self:SetConfig("fakeLocalBackdropSimplify", true)
		self:SetConfig("fakeLocalBackdropPanelMargin", 48)
		self:SetConfig("fakeLocalBackdropBlurStrength", 0.65)
	end
	self.cfg.fakeLocalBackdropQuality = profile
	if self.cfg.fakeLocalBackdropEnabled then
		self:_rebuildLocalBackdrop()
	end
end

function TopoShader:BeginAutoTune()
	local candidates = {
		{ name = "ultra_perf", cfg = { renderWidth = 184, renderHeight = 120, qualityPreset = "performance", lineAAMode = "off", edgeAAEnabled = false } },
		{ name = "perf_clean", cfg = { renderWidth = 220, renderHeight = 140, qualityPreset = "performance", lineAAMode = "fast", edgeAAEnabled = false } },
		{ name = "balanced", cfg = { renderWidth = 240, renderHeight = 156, qualityPreset = "balanced", lineAAMode = "fast", edgeAAEnabled = false } },
		{ name = "balanced_plus", cfg = { renderWidth = 260, renderHeight = 170, qualityPreset = "balanced", lineAAMode = "fast", edgeAAEnabled = true, edgeAAInterval = 2 } },
	}
	self._autoTune = {
		candidates = candidates,
		i = 1,
		frameCount = 0,
		accMs = 0,
		best = nil,
		bestScore = -1e9,
		targetMs = 16.6,
		done = false,
	}
	self:Configure(candidates[1].cfg)
	return true
end

function TopoShader:_stepAutoTune(renderMs)
	local a = self._autoTune
	if not a or a.done then return end
	a.frameCount += 1
	a.accMs += renderMs
	if a.frameCount < 30 then
		return
	end

	local avg = a.accMs / a.frameCount
	local c = a.candidates[a.i]
	local qualityBonus = a.i * 1.75
	local score = (avg <= a.targetMs and 1000 or 0) + qualityBonus - avg
	if score > a.bestScore then
		a.bestScore = score
		a.best = c
	end

	a.i += 1
	if a.i > #a.candidates then
		if a.best then
			self:Configure(a.best.cfg)
		end
		a.done = true
		self._autoTune = nil
		return
	end

	a.frameCount = 0
	a.accMs = 0
	self:Configure(a.candidates[a.i].cfg)
end

function TopoShader:ApplyTopoMode(mode)
	local preset = TOPO_MODES[mode]
	if not preset then
		return false, "Unknown topo mode: " .. tostring(mode)
	end
	if self.cfg.topoModeAppliesTheme then
		local themeName = TOPO_MODE_THEME[mode]
		if themeName then
			self:ApplyTheme(themeName)
		end
	end
	for k, v in pairs(preset) do
		self:SetConfig(k, v)
	end
	self.cfg.topoMode = mode
	return true
end

function TopoShader:ExportCurrentConfig()
	return cloneTable(self.cfg)
end

function TopoShader:ApplyConfigPreset(preset)
	if type(preset) ~= "table" then
		return false, "preset must be a table"
	end
	self:Configure(cloneTable(preset))
	return true
end

function TopoShader:SetStates(states)
	if type(states) ~= "table" then
		return false, "states must be a table"
	end
	self._states = {}
	for name, stateCfg in pairs(states) do
		if type(name) == "string" and type(stateCfg) == "table" then
			self._states[name] = cloneTable(stateCfg)
		end
	end
	return true
end

function TopoShader:RegisterState(name, stateCfg)
	if type(name) ~= "string" then
		return false, "state name must be string"
	end
	if type(stateCfg) ~= "table" then
		return false, "state config must be table"
	end
	self._states[name] = cloneTable(stateCfg)
	return true
end

function TopoShader:SetState(name)
	local stateCfg = self._states and self._states[name]
	if not stateCfg then
		return false, "unknown state: " .. tostring(name)
	end
	self:Configure(stateCfg)
	return true
end

function TopoShader:ApplyDesignTokens(tokens)
	if type(tokens) ~= "table" then
		return false, "tokens must be a table"
	end
	local mapped = {}
	if tokens.surfaceColor then mapped.bgColor = tokens.surfaceColor end
	if tokens.foregroundColor then mapped.lineColor = tokens.foregroundColor end
	if tokens.accentLow then mapped.colorLow = tokens.accentLow end
	if tokens.accentHigh then mapped.colorHigh = tokens.accentHigh end
	if tokens.tintAmount ~= nil then mapped.tintAmount = tokens.tintAmount end
	if tokens.motion ~= nil then
		mapped.animSpeed = _max(0, (self.cfg.animSpeed or 0.02) * tokens.motion)
	end
	if tokens.roundness ~= nil then mapped.cornerRadius = tokens.roundness end
	if tokens.blur ~= nil then
		mapped.fakeLocalBackdropBlurStrength = tokens.blur
		mapped.fakeLocalBackdropEnabled = true
	end
	if tokens.opacity ~= nil then
		mapped.outputOpacity = tokens.opacity
	end
	self:Configure(mapped)
	return true
end

function TopoShader:_updateAdaptiveQuality(renderMs)
	local cfg = self.cfg
	local budget = cfg.frameBudgetMs or 12.0
	self._adaptiveTimer += 1 / _max(1, cfg.fps)
	if self._adaptiveTimer < (cfg.adaptiveCooldown or 0.35) then
		return
	end
	self._adaptiveTimer = 0

	if renderMs > budget * 1.15 then
		if cfg.qualityPreset == "quality" then
			self:SetQualityPreset("balanced")
		elseif cfg.qualityPreset == "balanced" then
			self:SetQualityPreset("performance")
		end
	elseif renderMs < budget * 0.70 then
		if cfg.qualityPreset == "performance" then
			self:SetQualityPreset("balanced")
		end
	end
end

function TopoShader:SetMouseEnabled(enabled)
	self.cfg.mouseEnabled = enabled and true or false
end

function TopoShader:SetMouseInteraction(radius, strength, enabled)
	if radius ~= nil then self.cfg.mouseRadius = radius end
	if strength ~= nil then self.cfg.mouseStrength = strength end
	if enabled ~= nil then self.cfg.mouseEnabled = enabled and true or false end
end

function TopoShader:SetDebugEnabled(enabled)
	self.cfg.debugEnabled = enabled and true or false
	if self._debugLabel then
		self._debugLabel.Visible = self.cfg.debugEnabled
	end
end

function TopoShader:GetDebugReport()
	local d = self._debugReport
	return {
		fps = d.fps,
		frames = d.frames,
		lastRenderMs = d.lastRenderMs,
		renderMsAvg = d.renderMsAvg,
		renderMsMax = d.renderMsMax,
		overBudgetFrames = d.overBudgetFrames,
		qualityPreset = self.cfg.qualityPreset,
		adaptiveQuality = self.cfg.adaptiveQuality,
		checkerboard = self.cfg.checkerboardReconstruction,
		ultraFastMode = self.cfg.ultraFastMode,
		edgeAAEnabled = self.cfg.edgeAAEnabled,
		parallelEnabled = self.cfg.parallelEnabled,
		parallelReady = d.parallelReady,
		parallelWorkers = d.parallelWorkers,
		localBlurEnabled = self.cfg.localBlurEnabled,
		localBlurReady = d.localBlurReady,
		backgroundBlurEnabled = self.cfg.backgroundBlurEnabled,
		fakeLocalBackdropEnabled = self.cfg.fakeLocalBackdropEnabled,
		fakeBackdropReady = d.fakeBackdropReady,
		lastIssues = d.lastIssues,
		-- cache
		cacheEnabled    = self.cfg.cacheEnabled,
		cacheReady      = d.cacheReady,
		bakeActive      = self._bakeActive,
		bakeProgress    = d.bakeProgress,
		bakeTotalFrames = d.bakeTotalFrames,
	}
end

function TopoShader:FormatDebugReport()
	local d = self:GetDebugReport()
	local cacheStr
	if d.cacheEnabled then
		if d.cacheReady then
			cacheStr = string.format("cache:ready(%dframes)", d.bakeTotalFrames)
		elseif d.bakeActive then
			cacheStr = string.format("baking:%.0f%%", d.bakeProgress * 100)
		else
			cacheStr = "cache:idle"
		end
	else
		cacheStr = "cache:off"
	end
	return string.format(
		"[TopoShader] fps=%.1f render(ms)=%.2f avg=%.2f max=%.2f frames=%d overBudget=%d preset=%s adaptive=%s checker=%s edgeAA=%s %s issues=%s",
		d.fps, d.lastRenderMs, d.renderMsAvg, d.renderMsMax, d.frames, d.overBudgetFrames,
		tostring(d.qualityPreset), tostring(d.adaptiveQuality), tostring(d.checkerboard),
		tostring(d.edgeAAEnabled), cacheStr, tostring(d.lastIssues)
	)
end

function TopoShader:_updateDebug(renderMs)
	local d = self._debugReport
	d.frames += 1
	d.lastRenderMs = renderMs
	d.renderMsAvg += (renderMs - d.renderMsAvg) / _max(1, d.frames)
	d.renderMsMax = _max(d.renderMsMax, renderMs)
	if renderMs > (self.cfg.frameBudgetMs or 12.0) then
		d.overBudgetFrames += 1
	end

	local issues = {}
	if renderMs > (self.cfg.frameBudgetMs or 12.0) then
		table.insert(issues, "over_budget")
	end
	if self.cfg.checkerboardReconstruction and self.cfg.lineWidth < 0.08 then
		table.insert(issues, "possible_stipple")
	end
	if self.cfg.edgeAAEnabled and (self.cfg.edgeAAInterval or 1) <= 1 then
		table.insert(issues, "heavy_edgeAA")
	end
	if self.cfg.lineAAEnabled and self.cfg.lineAAStrength >= 2.5 then
		table.insert(issues, "heavy_lineAA")
	end
	if self.cfg.parallelEnabled and not self._parallelReady then
		table.insert(issues, "parallel_not_ready")
	end
	if self.cfg.localBlurEnabled and not self._localBlurReady then
		table.insert(issues, "local_blur_unavailable")
	end
	if self.cfg.fakeLocalBackdropEnabled and not self._vpfReady then
		table.insert(issues, "fake_backdrop_unavailable")
	end
	if self.cfg.fakeLocalBackdropEnabled and self._vpfReady and (self.cfg.fakeLocalBackdropMaxParts or 0) <= 120 then
		table.insert(issues, "fake_backdrop_low_detail")
	end
	if self.cfg.cacheEnabled and self._bakeActive then
		table.insert(issues, string.format("baking_%d%%", _floor((d.bakeProgress or 0) * 100)))
	end
	d.lastIssues = (#issues > 0) and table.concat(issues, ",") or "ok"

	if self.cfg.debugEnabled and self._debugLabel and self._debugClock >= (self.cfg.debugUpdateRate or 0.25) then
		self._debugClock = 0
		local cacheStatusStr
		if self.cfg.cacheEnabled then
			if self._cacheReady then
				cacheStatusStr = string.format("Cache: ready (%d fr)", self._bakeTotalFrames)
			elseif self._bakeActive then
				cacheStatusStr = string.format("Baking: %d/%d (%.0f%%)",
					self._bakeFI, self._bakeTotalFrames, d.bakeProgress * 100)
			else
				cacheStatusStr = "Cache: idle"
			end
		else
			cacheStatusStr = "Cache: off"
		end
		self._debugLabel.Text = string.format(
			"FPS: %.1f | Render: %.2fms (avg %.2f / max %.2f)\nPreset: %s | Adaptive: %s | Over budget: %d\n%s | Blur local/global: %s/%s | Issues: %s",
			d.fps, d.lastRenderMs, d.renderMsAvg, d.renderMsMax,
			tostring(self.cfg.qualityPreset), tostring(self.cfg.adaptiveQuality),
			d.overBudgetFrames, cacheStatusStr,
			tostring(self._localBlurReady), tostring(self.cfg.backgroundBlurEnabled), d.lastIssues
		)
	end
	self:_stepAutoTune(renderMs)
end

function TopoShader:Destroy()
	self:Stop()
	if self._uiBlur then
		self._uiBlur:Destroy()
		self._uiBlur = nil
	end
	if self._blur then
		self._blur:Destroy()
		self._blur = nil
	end
	if self._vpf then
		self._vpf:Destroy()
		self._vpf = nil
	end
	self._root:Destroy()
end

return TopoShader
