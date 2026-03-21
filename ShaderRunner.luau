local TopoShader = require(script:WaitForChild("TopoShader"))

-- Beginner-friendly setup:
-- 1) Start from shader:GetConfigTemplate()
-- 2) Override only what you want
-- 3) All runtime SetConfig/Configure writes are clamped by schema
local shader = TopoShader.new(script.Parent, {
	-- Panel
	width        = 460,
	height       = 300,

	-- Ultra-low runtime baseline (stabilize frame time first)
	renderWidth  = 148,
	renderHeight = 96,
	upscaleMode  = "bilinear",

	-- ── The critical number: LOW frequency = smooth hills ──────
	-- (renderWidth × baseFrequency) should be ~1.5 to 3.0
	-- 230 × 0.008 = 1.84  ← a couple of hills across the panel ✓
	baseFrequency = 0.008,

	-- Contours
	contourLevels = 8,
	lineWidth     = 0.13,

	-- Noise character
	octaves     = 4,
	lacunarity  = 2.10,
	persistence = 0.52,
	warpAmount  = 1.0,
	fastMode    = true,
	ultraFastMode = true,
	checkerboardReconstruction = true,
	interlacedMode = "checkerboard",
	temporalBlend = 0.18,
	edgeAAEnabled   = false,
	edgeAAStrength  = 0.40,
	edgeAAThreshold = 16,
	edgeAAInterval  = 3,
	edgeAAQuality   = "hq",
	lineAAEnabled   = false,
	lineAAStrength  = 1.7,
	lineAAStep      = 0.55,
	lineAAMode      = "off",
	lineAASubpixel  = 0.32,
	analyticalAAEnabled = false,
	analyticalAAStrength = 0.80,
	adaptiveSamplingEnabled = false,
	aaEdgeThreshold = 0.014,
	verticalAABoost = 0.85,
	generatorScaleEnabled = false,
	generatorScaleStrength = 0.24,
	generatorScaleThreshold = 0.07,
	generatorScaleAlpha = 0.68,
	generatorScaleInterval = 4,
	generatorVerticalBias = 1.40,
	fakeAABlurEnabled = false,
	fakeAABlurStrength = 0.06,
	fakeAABlurThreshold = 0.09,
	fakeAABlurInterval = 2,
	qualityPreset   = "balanced",
	adaptiveQuality = true,
	frameBudgetMs   = 16.6,
	debugEnabled    = true,
	debugUpdateRate = 0.25,
	visualProfile   = "performance",
	vignetteEnabled = true,
	vignetteStrength = 0.10,
	lineSharpness   = 0.88,
	parallelEnabled = false,
	parallelWorkers = 4,
	parallelTileWidth = 64,
	parallelTileHeight = 64,
	parallelProgressive = true,
	parallelTilesPerFrame = 6,
	theme = "classic",
	topoMode = "classic",

	-- Slow drift
	animSpeed = 0.018,
	animAngle = 0.50,

	-- Mouse bends contours
	mouseRadius   = 120,
	mouseStrength = 0.35,
	mouseEnabled  = false,
	cursorDitherEnabled = false,
	cursorDitherRadius = 120,
	cursorDitherStrength = 0.35,
	cursorDitherScale = 2,
	cursorDitherPattern = "bayer4",

	-- Dark navy bg, white lines, blue-to-white elevation tint
	bgColor   = { r=0.016, g=0.016, b=0.022, a=1 },
	lineColor = { r=1,     g=1,     b=1,     a=1 },

	elevationTint = true,
	colorLow      = { r=0.12, g=0.28, b=0.68 },
	colorHigh     = { r=0.80, g=0.93, b=1.00 },
	tintAmount    = 0.45,

	glowEnabled  = false,
	glowStrength = 0.08,

	fps          = 60,
	cornerRadius = 16,
	panelTransparency = 1.0,
	imageTransparency = 0.18,
	outputOpacity = 0.82,
	localBlurEnabled = true,
	localBlurSize = 24,
	backgroundBlurEnabled = false,
	backgroundBlurSize = 10,
	fakeLocalBackdropEnabled = false,
	fakeLocalBackdropAlpha = 0.28,
	fakeLocalBackdropRefreshHz = 12,
	fakeLocalBackdropQuality = "balanced",
	fakeLocalBackdropMaxParts = 350,
	fakeLocalBackdropDistance = 180,
	fakeLocalBackdropRebuildSec = 2.5,
	fakeLocalBackdropSimplify = true,
	fakeLocalBackdropPanelOnly = true,
	fakeLocalBackdropPanelMargin = 48,
	fakeLocalBackdropBlurStrength = 0.72,
	topoModeAppliesTheme = true,
})

shader:SetPosition(UDim2.fromScale(0.5, 0.5))
shader:SetAnchor(Vector2.new(0.5, 0.5))
shader:ApplyTheme("classic")
shader:SetQualityPreset("performance")
shader:SetVisualProfile("performance")
shader:ApplyTopoMode("classic")
shader:Configure({
	adaptiveQuality = true,
	lineAAMode = "off",
	lineAAEnabled = false,
	analyticalAAEnabled = false,
	edgeAAEnabled = false,
	edgeAAQuality = "hq",
	softEdgesEnabled = true,
	softEdgeWidth = 0.28,
	generatorScaleEnabled = false,
	fakeAABlurEnabled = false,
	checkerboardReconstruction = true,
	interlacedMode = "checkerboard",
	temporalBlend = 0.18,
	mouseEnabled = false,
	fakeLocalBackdropEnabled = false,
	backgroundBlurEnabled = false,
	localBlurEnabled = false,
})
shader:Start()

-- Hotkeys
local UIS = game:GetService("UserInputService")
local themes = shader:GetThemeNames()
local topoModes = shader:GetTopoModes()
local backdropQualities = { "low", "balanced", "high" }
local themeIdx = 1
local topoIdx = 1
local backdropIdx = 2
local morphA = "classic"
local morphB = "precision"
local morphT = 0.0
local morphEnabled = false
for i, m in ipairs(topoModes) do
	if m == shader.cfg.topoMode then
		topoIdx = i
		break
	end
end

local function keyName(inp)
	return inp.KeyCode and inp.KeyCode.Name or ""
end
UIS.InputBegan:Connect(function(inp, gp)
	if gp then return end
	local k = keyName(inp)
	-- P  = pause / resume
	if k == "P" then
		if shader._running then shader:Stop() else shader:Start() end
	end
	-- ] = more contour lines
	if k == "RightBracket" then
		shader:SetConfig("contourLevels", shader.cfg.contourLevels + 1)
	end
	-- [ = fewer contour lines
	if k == "LeftBracket" then
		shader:SetConfig("contourLevels", math.max(3, shader.cfg.contourLevels - 1))
	end
	-- 1/2/3 = quality presets (perf/balanced/quality)
	if k == "One" then
		shader:SetQualityPreset("performance")
		shader:Configure({ adaptiveQuality = false })
		print("[TopoShader] preset=performance (adaptive off)")
	end
	-- 4/5 = topo mode morph t down/up
	if k == "Four" then
		if not morphEnabled then
			morphEnabled = true
			shader:ApplyTopoModeMorph(morphA, morphB, morphT, { strengthA = 1.0, strengthB = 1.0, applyTheme = true })
		end
		morphT = math.max(0, morphT - 0.05)
		shader:SetTopoModeMorph(morphT)
		print(string.format("[TopoShader] morph %s -> %s | t=%.2f", morphA, morphB, morphT))
	end
	if k == "Five" then
		if not morphEnabled then
			morphEnabled = true
			shader:ApplyTopoModeMorph(morphA, morphB, morphT, { strengthA = 1.0, strengthB = 1.0, applyTheme = true })
		end
		morphT = math.min(1, morphT + 0.05)
		shader:SetTopoModeMorph(morphT)
		print(string.format("[TopoShader] morph %s -> %s | t=%.2f", morphA, morphB, morphT))
	end
	-- 6 = cycle morph target mode B
	if k == "Six" then
		local bi = 1
		for i, m in ipairs(topoModes) do
			if m == morphB then bi = i break end
		end
		bi += 1
		if bi > #topoModes then bi = 1 end
		morphB = topoModes[bi]
		morphEnabled = true
		shader:ApplyTopoModeMorph(morphA, morphB, morphT, { strengthA = 1.0, strengthB = 1.0, applyTheme = true })
		print(string.format("[TopoShader] morph target B=%s (A=%s, t=%.2f)", morphB, morphA, morphT))
	end
	if k == "Two" then
		shader:SetQualityPreset("balanced")
		shader:Configure({ adaptiveQuality = false })
		print("[TopoShader] preset=balanced (adaptive off)")
	end
	if k == "Three" then
		shader:SetQualityPreset("quality")
		shader:Configure({ adaptiveQuality = false })
		print("[TopoShader] preset=quality (adaptive off)")
	end
	-- 7/8/9 = visual profiles (perf/balanced/cinematic)
	if k == "Seven" then
		shader:SetVisualProfile("performance")
	end
	if k == "Eight" then
		shader:SetVisualProfile("balanced")
	end
	if k == "Nine" then
		shader:SetVisualProfile("cinematic")
	end
	-- K = toggle adaptive quality
	if k == "K" then
		shader:Configure({ adaptiveQuality = not shader.cfg.adaptiveQuality })
		print("[TopoShader] adaptiveQuality =", shader.cfg.adaptiveQuality)
	end
	-- 0 = force adaptive quality on
	if k == "Zero" then
		shader:Configure({ adaptiveQuality = true })
		print("[TopoShader] adaptiveQuality = true")
	end
	-- F8 = toggle debug overlay
	if k == "F8" then
		shader:SetDebugEnabled(not shader.cfg.debugEnabled)
	end
	-- F9 = print debug report to output
	if k == "F9" then
		print(shader:FormatDebugReport())
	end
	-- F10 = toggle actor-parallel mode (requires TopoActors setup)
	if k == "F10" then
		shader:SetParallelEnabled(not shader.cfg.parallelEnabled)
		print("[TopoShader] parallelEnabled =", shader.cfg.parallelEnabled)
	end
	-- I / O = progressive tiles per frame down / up
	if k == "I" then
		shader:Configure({ parallelTilesPerFrame = math.max(1, (shader.cfg.parallelTilesPerFrame or 6) - 1) })
		print("[TopoShader] parallelTilesPerFrame =", shader.cfg.parallelTilesPerFrame)
	end
	if k == "O" then
		shader:Configure({ parallelTilesPerFrame = math.min(128, (shader.cfg.parallelTilesPerFrame or 6) + 1) })
		print("[TopoShader] parallelTilesPerFrame =", shader.cfg.parallelTilesPerFrame)
	end
	-- F6 = auto tune best settings for hardware
	if k == "F6" then
		shader:BeginAutoTune()
		print("[TopoShader] auto-tune started (about 120 frames)")
	end
	-- M = toggle mouse interaction
	if k == "M" then
		shader:SetMouseEnabled(not shader.cfg.mouseEnabled)
	end
	-- X = toggle cursor dither interaction
	if k == "X" then
		shader:Configure({ cursorDitherEnabled = not shader.cfg.cursorDitherEnabled })
		print("[TopoShader] cursorDitherEnabled =", shader.cfg.cursorDitherEnabled)
	end
	-- C = cycle cursor dither pattern
	if k == "C" then
		local p = (shader.cfg.cursorDitherPattern == "bayer4") and "checker" or "bayer4"
		shader:Configure({ cursorDitherPattern = p, cursorDitherEnabled = true })
		print("[TopoShader] cursorDitherPattern =", p)
	end
	-- ; / ' = mouse strength down / up (layout-safe aliases)
	if k == "Semicolon" or k == "Minus" then
		shader:SetMouseInteraction(nil, math.max(0, shader.cfg.mouseStrength - 0.05), nil)
	end
	if k == "Quote" or k == "Equals" then
		shader:SetMouseInteraction(nil, math.min(2, shader.cfg.mouseStrength + 0.05), nil)
	end
	-- , / . = mouse radius down / up
	if k == "Comma" then
		shader:SetMouseInteraction(math.max(20, shader.cfg.mouseRadius - 10), nil, nil)
	end
	if k == "Period" then
		shader:SetMouseInteraction(math.min(400, shader.cfg.mouseRadius + 10), nil, nil)
	end
	-- V = toggle vignette
	if k == "V" then
		shader:Configure({ vignetteEnabled = not shader.cfg.vignetteEnabled })
	end
	-- B = toggle adaptive line AA
	if k == "B" then
		shader:Configure({ lineAAEnabled = not shader.cfg.lineAAEnabled })
	end
	-- U = cycle line AA mode (off/fast/msaa4)
	if k == "U" then
		local mode = shader.cfg.lineAAMode
		if mode == "off" then mode = "fast"
		elseif mode == "fast" then mode = "msaa4"
		else mode = "off" end
		shader:Configure({ lineAAMode = mode, lineAAEnabled = (mode ~= "off") })
		print("[TopoShader] lineAAMode =", mode)
	end
	-- L = toggle analytical AA
	if k == "L" then
		shader:Configure({ analyticalAAEnabled = not shader.cfg.analyticalAAEnabled })
		print("[TopoShader] analyticalAAEnabled =", shader.cfg.analyticalAAEnabled)
	end
	-- P = cycle interlaced mode (off/checkerboard)
	if k == "BackSlash" then
		local im = (shader.cfg.interlacedMode == "checkerboard") and "off" or "checkerboard"
		shader:Configure({ interlacedMode = im })
		print("[TopoShader] interlacedMode =", im)
	end
	-- Q = toggle upscale mode (bilinear/nearest)
	if k == "Q" then
		local um = (shader.cfg.upscaleMode == "nearest") and "bilinear" or "nearest"
		shader:Configure({ upscaleMode = um })
		print("[TopoShader] upscaleMode =", um)
	end
	-- N = cycle edge AA quality (fast/hq)
	if k == "N" then
		local q = (shader.cfg.edgeAAQuality == "hq") and "fast" or "hq"
		shader:Configure({ edgeAAQuality = q, edgeAAEnabled = true })
		print("[TopoShader] edgeAAQuality =", q)
	end
	-- Z = toggle generator scaling filter
	if k == "Z" then
		shader:Configure({ generatorScaleEnabled = not shader.cfg.generatorScaleEnabled })
		print("[TopoShader] generatorScaleEnabled =", shader.cfg.generatorScaleEnabled)
	end
	-- T = cycle theme packs
	if k == "T" then
		themeIdx += 1
		if themeIdx > #themes then themeIdx = 1 end
		local themeName = themes[themeIdx]
		shader:ApplyTheme(themeName)
		print("[TopoShader] theme =", themeName)
	end
	-- Y = cycle fake local backdrop quality
	if k == "Y" then
		backdropIdx += 1
		if backdropIdx > #backdropQualities then backdropIdx = 1 end
		local q = backdropQualities[backdropIdx]
		shader:ApplyFakeBackdropQuality(q)
		print("[TopoShader] fakeBackdropQuality =", q)
	end
	-- G = cycle topo modes
	if k == "G" then
		topoIdx += 1
		if topoIdx > #topoModes then topoIdx = 1 end
		local m = topoModes[topoIdx]
		shader:ApplyTopoMode(m)
		morphEnabled = false
		morphA = m
		print("[TopoShader] topoMode =", m, "theme =", shader.cfg.theme)
	end
	-- H = print keybind help
	if k == "H" then
		print("[TopoShader keys] P pause | [ ] contours | 1/2/3 quality (locks adaptive off) | 4/5 morph t | 6 morph target B | 7/8/9 visuals | T theme | G topo mode(A) | Y fake backdrop quality | M mouse | X cursor dither | C dither pattern | ;/' mouse strength | ,/. mouse radius | V vignette | B lineAA toggle | U lineAA mode | L analyticalAA | Q upscale mode | \\ interlaced mode | N edgeAA quality | Z generator scaling | K adaptive toggle | 0 adaptive on | F6 auto-tune | F8 overlay | F9 report | F10 parallel | I/O tiles/frame")
	end
	-- J = print schema/template helpers for customization
	if k == "J" then
		print("[TopoShader] Guide: TOPO_SHADER_GUIDE.md | use shader:GetConfigTemplate() and shader:GetConfigSchema()")
	end
end)