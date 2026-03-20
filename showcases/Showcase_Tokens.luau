local TopoShader = require(script.Parent.Parent:WaitForChild("TopoShader"))
local UIS = game:GetService("UserInputService")

local shader = TopoShader.new(script.Parent, {
	width = 460,
	height = 300,
	renderWidth = 220,
	renderHeight = 140,
	qualityPreset = "performance",
	debugEnabled = true,
})

shader:SetPosition(UDim2.fromScale(0.5, 0.5))
shader:SetAnchor(Vector2.new(0.5, 0.5))
shader:Start()

local tokenSets = {
	{
		surfaceColor = { r = 0.01, g = 0.01, b = 0.02, a = 1 },
		foregroundColor = { r = 1, g = 1, b = 1, a = 1 },
		accentLow = { r = 0.20, g = 0.50, b = 0.95 },
		accentHigh = { r = 0.90, g = 1.00, b = 1.00 },
		tintAmount = 0.45,
		motion = 1.0,
		roundness = 16,
		blur = 0.6,
		opacity = 0.85,
	},
	{
		surfaceColor = { r = 0.95, g = 0.94, b = 0.90, a = 1 },
		foregroundColor = { r = 0.10, g = 0.11, b = 0.13, a = 1 },
		accentLow = { r = 0.15, g = 0.16, b = 0.18 },
		accentHigh = { r = 0.15, g = 0.16, b = 0.18 },
		tintAmount = 0.0,
		motion = 0.35,
		roundness = 24,
		blur = 0.35,
		opacity = 0.95,
	},
}

local i = 1
shader:ApplyDesignTokens(tokenSets[i])

UIS.InputBegan:Connect(function(inp, gp)
	if gp then return end
	if inp.KeyCode == Enum.KeyCode.T then
		i += 1
		if i > #tokenSets then i = 1 end
		shader:ApplyDesignTokens(tokenSets[i])
	end
end)
