-- TopoActorWorker
-- Real worker implementation for Actor chunk rendering protocol.
--
-- Setup in Studio:
-- 1) Under your TopoShader ModuleScript, create Folder "TopoActors"
-- 2) Add N Actor instances in that folder (2-8 recommended)
-- 3) In each Actor, add:
--    - BindableEvent named "RenderRequest"
--    - BindableEvent named "RenderDone"
--    - Script with this source
--
-- Protocol:
-- - RenderRequest:Fire(payloadTable)
-- - RenderDone:Fire(resultTable)
-- Payload (required fields):
--   jobId, rowStart, rowEnd, rW, rH, time,
--   baseFrequency, contourLevels, lineWidth,
--   bgColor, lineColor, elevationTint, colorLow, colorHigh, tintAmount,
--   animSpeed, animAngle,
--   lacunarity, persistence, warpAmount,
--   fastMode, ultraFastMode, octaves
--
-- Result:
--   { jobId = number, rowStart = number, rowEnd = number, data = buffer }

local actor = script:GetActor()
if not actor then return end

local request = actor:FindFirstChild("RenderRequest")
local done = actor:FindFirstChild("RenderDone")
if not request or not request:IsA("BindableEvent") then return end
if not done or not done:IsA("BindableEvent") then return end

local _noise = math.noise
local _floor = math.floor
local _min = math.min
local _max = math.max
local _cos = math.cos
local _sin = math.sin

local function saturate(v)
	return _max(0, _min(1, v))
end

local function fade(t)
	t = saturate(t)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function fbm(x, y, z, oct, lac, per)
	local sum = 0
	local amp = 0.5
	local freq = 1
	local maxAmp = 0
	for _ = 1, oct do
		sum += _noise(x * freq, y * freq, z) * amp
		maxAmp += amp
		freq *= lac
		amp *= per
	end
	return (sum / maxAmp) * 0.5 + 0.5
end

local function heightField(x, y, z, oct, lac, per, warp)
	local w1x = fbm(x + 0.0, y + 0.0, z + 0.0, oct, lac, per) - 0.5
	local w1y = fbm(x + 5.2, y + 1.3, z + 0.3, oct, lac, per) - 0.5
	local w2x = fbm(x + w1x * warp + 1.7, y + w1y * warp + 9.2, z + 0.15, 3, lac, per) - 0.5
	local w2y = fbm(x + w1x * warp + 8.3, y + w1y * warp + 2.8, z - 0.12, 3, lac, per) - 0.5
	return fbm(x + w2x * warp * 0.5, y + w2y * warp * 0.5, z, oct, lac, per)
end

local function heightFieldFast(x, y, z, oct, lac, per, warp)
	local w = fbm(x + 3.1, y + 7.9, z + 0.2, 3, lac, per) - 0.5
	local o = _max(1, oct - 1)
	return fbm(x + w * warp * 0.6, y - w * warp * 0.6, z, o, lac, per)
end

local function heightFieldUltra(x, y, z, lac, per, warp)
	local w = _noise(x + 1.7, y + 3.9, z + 0.21)
	local sx = (x + w * warp * 0.35) * 1.18
	local sy = (y - w * warp * 0.35) * 1.18
	return _noise(sx, sy, z * 0.9) * 0.5 + 0.5
end

request.Event:Connect(function(p)
	if type(p) ~= "table" then return end

	local rowStart = p.rowStart or 0
	local rowEnd = p.rowEnd or -1
	local rW = p.rW or 0
	local rH = p.rH or 0
	if rW <= 0 or rH <= 0 or rowEnd < rowStart then return end

	local rows = rowEnd - rowStart + 1
	local out = buffer.create(rows * rW * 4)

	local bg = p.bgColor or { r = 0, g = 0, b = 0, a = 1 }
	local ln = p.lineColor or { r = 1, g = 1, b = 1, a = 1 }
	local lo = p.colorLow or { r = 0.2, g = 0.2, b = 0.2 }
	local hi = p.colorHigh or { r = 1, g = 1, b = 1 }

	local levels = p.contourLevels or 12
	local halfW = (p.lineWidth or 0.06) * 0.5
	local doTint = p.elevationTint and true or false
	local tintAmount = p.tintAmount or 0
	local invTint = 1 - tintAmount

	local lac = p.lacunarity or 2.1
	local per = p.persistence or 0.52
	local warp = p.warpAmount or 1.0
	local oct = p.octaves or 4
	local baseFreq = p.baseFrequency or 0.008
	local t = p.time or 0
	local fastMode = p.fastMode and true or false
	local ultraFastMode = p.ultraFastMode and true or false

	local driftX = _cos(p.animAngle or 0.45) * (p.animSpeed or 0.02) * t
	local driftY = _sin(p.animAngle or 0.45) * (p.animSpeed or 0.02) * t
	local zSlice = t * 0.12

	local outPi = 0
	for row = rowStart, rowEnd do
		local ny = row * baseFreq + driftY
		for col = 0, rW - 1 do
			local nx = col * baseFreq + driftX
			local h
			if ultraFastMode then
				h = heightFieldUltra(nx, ny, zSlice, lac, per, warp)
			elseif fastMode then
				h = heightFieldFast(nx, ny, zSlice, oct, lac, per, warp)
			else
				h = heightField(nx, ny, zSlice, oct, lac, per, warp)
			end

			local bandPos = (h * levels) % 1.0
			local d = _min(bandPos, 1 - bandPos)
			local lineV = fade(1 - saturate(d / halfW))

			local r, g, b, a
			if lineV < 0.004 then
				r, g, b, a = bg.r, bg.g, bg.b, bg.a
			else
				r, g, b = ln.r, ln.g, ln.b
				if doTint then
					local tr = lo.r + (hi.r - lo.r) * h
					local tg = lo.g + (hi.g - lo.g) * h
					local tb = lo.b + (hi.b - lo.b) * h
					r = r * invTint + tr * tintAmount
					g = g * invTint + tg * tintAmount
					b = b * invTint + tb * tintAmount
				end
				r = bg.r + (r - bg.r) * lineV
				g = bg.g + (g - bg.g) * lineV
				b = bg.b + (b - bg.b) * lineV
				a = bg.a + (ln.a - bg.a) * lineV
			end

			local i = outPi * 4
			buffer.writeu8(out, i, _floor(saturate(r) * 255 + 0.5))
			buffer.writeu8(out, i + 1, _floor(saturate(g) * 255 + 0.5))
			buffer.writeu8(out, i + 2, _floor(saturate(b) * 255 + 0.5))
			buffer.writeu8(out, i + 3, _floor(saturate(a) * 255 + 0.5))
			outPi += 1
		end
	end

	done:Fire({
		jobId = p.jobId,
		rowStart = rowStart,
		rowEnd = rowEnd,
		data = out,
	})
end)
