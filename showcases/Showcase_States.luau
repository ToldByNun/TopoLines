local TopoShader = require(script.Parent.Parent:WaitForChild("TopoShader"))
local UIS = game:GetService("UserInputService")

local shader = TopoShader.new(script.Parent, {
	width = 460,
	height = 300,
	renderWidth = 230,
	renderHeight = 150,
	debugEnabled = true,
})

shader:SetPosition(UDim2.fromScale(0.5, 0.5))
shader:SetAnchor(Vector2.new(0.5, 0.5))
shader:ApplyTheme("ocean")
shader:ApplyTopoMode("precision")

shader:SetStates({
	idle = {
		lineWidth = 0.08,
		outputOpacity = 0.80,
	},
	hover = {
		lineWidth = 0.10,
		outputOpacity = 0.92,
		glowEnabled = true,
		glowStrength = 0.10,
	},
	pressed = {
		lineWidth = 0.12,
		outputOpacity = 1.0,
		contourLevels = 9,
	},
})

shader:SetState("idle")
shader:Start()

UIS.InputBegan:Connect(function(inp, gp)
	if gp then return end
	if inp.KeyCode == Enum.KeyCode.One then shader:SetState("idle") end
	if inp.KeyCode == Enum.KeyCode.Two then shader:SetState("hover") end
	if inp.KeyCode == Enum.KeyCode.Three then shader:SetState("pressed") end
end)
