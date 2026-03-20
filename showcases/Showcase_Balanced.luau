local TopoShader = require(script.Parent.Parent:WaitForChild("TopoShader"))

local shader = TopoShader.new(script.Parent, {
	width = 460,
	height = 300,
	renderWidth = 240,
	renderHeight = 156,
	qualityPreset = "balanced",
	visualProfile = "balanced",
	theme = "classic",
	debugEnabled = true,
})

shader:SetPosition(UDim2.fromScale(0.5, 0.5))
shader:SetAnchor(Vector2.new(0.5, 0.5))
shader:ApplyTheme("classic")
shader:ApplyTopoMode("classic")
shader:Start()
