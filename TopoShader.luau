-- TopoShader (ModuleScript)
-- Topographic contour line shader.
-- Uses AssetService:CreateEditableImage + Luau buffer.

local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local AssetService     = game:GetService("AssetService")

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
	temporalBlend = 0.12, -- lower history weight = cleaner/less ghosting

	-- ── Animation ────────────────────────────────────────────
	animSpeed = 0.020,   -- how fast contours drift (noise-space/sec)
	animAngle = 0.45,    -- direction of drift (radians)

	-- ── Mouse interaction ─────────────────────────────────────
	-- Cursor creates a local bump that bends nearby contours
	mouseRadius   = 120,   -- pixels (panel space)
	mouseStrength = 0.35,  -- noise-space push magnitude
	mouseEnabled  = true,

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

	-- ── Misc ─────────────────────────────────────────────────
	fps          = 60,
	cornerRadius = 16,
}

-- Beginner-safe config schema. Values are clamped/sanitized on write.
local CONFIG_RULES = {
	renderWidth = { t = "number", min = 64, max = 1024 },
	renderHeight = { t = "number", min = 64, max = 1024 },
	baseFrequency = { t = "number", min = 0.001, max = 0.05 },
	contourLevels = { t = "number", min = 2, max = 64, integer = true },
	lineWidth = { t = "number", min = 0.02, max = 0.25 },
	lineSharpness = { t = "number", min = 0.7, max = 1.4 },
	octaves = { t = "number", min = 1, max = 8, integer = true },
	lacunarity = { t = "number", min = 1.2, max = 3.5 },
	persistence = { t = "number", min = 0.1, max = 0.95 },
	warpAmount = { t = "number", min = 0, max = 2.5 },
	fastMode = { t = "boolean" },
	ultraFastMode = { t = "boolean" },
	checkerboardReconstruction = { t = "boolean" },
	temporalBlend = { t = "number", min = 0, max = 0.5 },
	animSpeed = { t = "number", min = 0, max = 0.2 },
	animAngle = { t = "number", min = -6.3, max = 6.3 },
	mouseRadius = { t = "number", min = 0, max = 600 },
	mouseStrength = { t = "number", min = 0, max = 3.0 },
	mouseEnabled = { t = "boolean" },
	elevationTint = { t = "boolean" },
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
	fps = { t = "number", min = 1, max = 240, integer = true },
	cornerRadius = { t = "number", min = 0, max = 80, integer = true },
	theme = { t = "enum", values = { classic = true, ocean = true, neon = true, paper = true } },
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

local function contourValue(h, levels, halfW)
	local bandPos = (h * levels) % 1.0
	local d = _min(bandPos, 1 - bandPos)
	return fade(1 - saturate(d / halfW))
end

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
	}
	self._parallelReady = false
	self._parallelWorkers = 0

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
	clip.BackgroundTransparency = 0
	clip.BorderSizePixel        = 0
	clip.ClipsDescendants       = true
	clip.ZIndex                 = 1
	clip.Parent                 = root
	self._clip = clip

	do
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0, cfg.cornerRadius)
		uc.Parent = clip
	end

	-- ImageLabel  (will display our EditableImage)
	local img = Instance.new("ImageLabel")
	img.Name                   = "Output"
	img.Size                   = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.BorderSizePixel        = 0
	img.ScaleType              = Enum.ScaleType.Stretch
	img.ZIndex                 = 2
	img.Parent                 = clip
	self._img = img

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

-- ================================================================
--  RENDER FRAME
-- ================================================================
function TopoShader:_render(t)
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
	local vignetteEnabled = cfg.vignetteEnabled
	local vignetteStrength = cfg.vignetteStrength or 0
	local lineAAEnabled = cfg.lineAAEnabled
	local lineAAStrength = cfg.lineAAStrength or 2.0
	local aaStep = (cfg.baseFrequency or 0.008) * (cfg.lineAAStep or 0.55)
	local lineAAMode = cfg.lineAAMode or "fast"
	local subpixel = cfg.lineAASubpixel or 0.35

	-- Animate: drift the whole noise field slowly
	local driftX = _cos(cfg.animAngle) * cfg.animSpeed * t
	local driftY = _sin(cfg.animAngle) * cfg.animSpeed * t

	-- Slow morph (z-axis of noise)
	local zSlice = t * 0.12

	-- Mouse warp
	local mX       = self._mouseX
	local mY       = self._mouseY
	local mRad     = cfg.mouseRadius
	local mRadSq   = mRad * mRad
	-- Convert mouse strength from panel-pixels to noise-space units
	local mStr     = cfg.mouseStrength * cfg.baseFrequency * 10
	local mouseWarpEnabled = cfg.mouseEnabled and mStr > 0 and mRad > 0

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

		-- Contour detection  →  0 = gap,  1 = line centre
		local bandPos = (h * levels) % 1.0
		local d = _min(bandPos, 1 - bandPos)
		local aaHalfW = halfW
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
			local gradH = _abs(hx - h) + _abs(hy - h)
			aaHalfW = halfW + gradH * lineAAStrength
		end
		local tEdge = 1 - saturate(d / aaHalfW)
		local lineV = fade(tEdge)
		if lineAAEnabled and lineAAMode == "msaa4" then
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
			local h1 = sampleH(nx - so, ny - so)
			local h2 = sampleH(nx + so, ny - so)
			local h3 = sampleH(nx - so, ny + so)
			local h4 = sampleH(nx + so, ny + so)
			local m1 = contourValue(h1, levels, aaHalfW)
			local m2 = contourValue(h2, levels, aaHalfW)
			local m3 = contourValue(h3, levels, aaHalfW)
			local m4 = contourValue(h4, levels, aaHalfW)
			lineV = (lineV + m1 + m2 + m3 + m4) * 0.2
		end
		if lineSharpness ~= 1 then
			lineV = lineV ^ lineSharpness
		end

		-- Compute final color
		local r, g, b, a

		if lineV < 0.004 then
			-- Background pixel — skip lerp
			r, g, b, a = bgR, bgG, bgB, bgA
		else
			-- Line pixel: start with white
			r, g, b = lnR, lnG, lnB

			-- Optionally tint by elevation
			if doTint then
				local tr = loR + (hiR - loR) * h
				local tg = loG + (hiG - loG) * h
				local tb = loB + (hiB - loB) * h
				r = r * invTint + tr * tintAmt
				g = g * invTint + tg * tintAmt
				b = b * invTint + tb * tintAmt
			end

			-- Anti-alias: blend line over background using lineV
			r = lerp(bgR, r, lineV)
			g = lerp(bgG, g, lineV)
			b = lerp(bgB, b, lineV)
			a = lerp(bgA, lnA, lineV)
		end

		-- Write to Luau buffer (RGBA u8)
		local ur = _floor(saturate(r) * 255 + 0.5)
		local ug = _floor(saturate(g) * 255 + 0.5)
		local ub = _floor(saturate(b) * 255 + 0.5)
		local ua = _floor(saturate(a) * 255 + 0.5)
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

	-- Single GPU upload — the entire buffer in one call
	self._ei:WritePixelsBuffer(Vector2.zero, Vector2.new(rW, rH), buf)
	self._checkerPhase = 1 - phase
	self._frameId += 1

	local renderMs = (os.clock() - renderStart) * 1000
	if cfg.adaptiveQuality then
		self:_updateAdaptiveQuality(renderMs)
	end
	self:_updateDebug(renderMs)
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

	-- Track mouse position in panel-local space
	self._inputConn = UserInputService.InputChanged:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseMovement then
			local mp  = UserInputService:GetMouseLocation()
			local abs = self._clip.AbsolutePosition
			self._mouseX = mp.X - abs.X
			self._mouseY = mp.Y - abs.Y
		end
	end)

	local inv = 1 / self.cfg.fps
	self._conn = RunService.RenderStepped:Connect(function(dt)
		self._debugClock += dt
		if dt > 0 then
			self._debugReport.fps = 1 / dt
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
	if key == "qualityPreset" then
		self:SetQualityPreset(self.cfg.qualityPreset)
	end
	if key == "visualProfile" then
		self:SetVisualProfile(self.cfg.visualProfile)
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
		self.cfg.lineSharpness = 1.05
		self.cfg.vignetteEnabled = false
		self.cfg.vignetteStrength = 0.0
	elseif profile == "cinematic" then
		self.cfg.edgeAAEnabled = true
		self.cfg.edgeAAQuality = "hq"
		self.cfg.lineAAEnabled = true
		self.cfg.lineAAStrength = 2.6
		self.cfg.lineAAMode = "msaa4"
		self.cfg.edgeAAInterval = 2
		self.cfg.lineSharpness = 0.92
		self.cfg.vignetteEnabled = true
		self.cfg.vignetteStrength = 0.14
	else -- balanced
		self.cfg.lineSharpness = 1.0
		self.cfg.lineAAEnabled = true
		self.cfg.lineAAStrength = 2.0
		self.cfg.lineAAMode = "fast"
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

function TopoShader:_refreshParallelState()
	self._parallelReady = false
	self._parallelWorkers = 0

	if not self.cfg.parallelEnabled then
		self._debugReport.parallelReady = false
		self._debugReport.parallelWorkers = 0
		return
	end

	local pool = script:FindFirstChild("TopoActors")
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
			end
		end
	end

	self._parallelWorkers = workers
	self._parallelReady = protocolReady and workers >= _max(1, self.cfg.parallelWorkers or 1)
	self._debugReport.parallelReady = self._parallelReady
	self._debugReport.parallelWorkers = workers
end

function TopoShader:SetParallelEnabled(enabled)
	self.cfg.parallelEnabled = enabled and true or false
	self:_refreshParallelState()
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
		lastIssues = d.lastIssues,
	}
end

function TopoShader:FormatDebugReport()
	local d = self:GetDebugReport()
	return string.format(
		"[TopoShader] fps=%.1f render(ms)=%.2f avg=%.2f max=%.2f frames=%d overBudget=%d preset=%s adaptive=%s checker=%s edgeAA=%s issues=%s",
		d.fps, d.lastRenderMs, d.renderMsAvg, d.renderMsMax, d.frames, d.overBudgetFrames,
		tostring(d.qualityPreset), tostring(d.adaptiveQuality), tostring(d.checkerboard),
		tostring(d.edgeAAEnabled), tostring(d.lastIssues)
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
	d.lastIssues = (#issues > 0) and table.concat(issues, ",") or "ok"

	if self.cfg.debugEnabled and self._debugLabel and self._debugClock >= (self.cfg.debugUpdateRate or 0.25) then
		self._debugClock = 0
		self._debugLabel.Text = string.format(
			"FPS: %.1f | Render: %.2fms (avg %.2f / max %.2f)\nPreset: %s | Adaptive: %s | Over budget: %d\nIssues: %s",
			d.fps, d.lastRenderMs, d.renderMsAvg, d.renderMsMax,
			tostring(self.cfg.qualityPreset), tostring(self.cfg.adaptiveQuality),
			d.overBudgetFrames, d.lastIssues
		)
	end
end

function TopoShader:Destroy()
	self:Stop()
	self._root:Destroy()
end

return TopoShader