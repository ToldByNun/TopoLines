local TopoShader = require(script.Parent.Parent:WaitForChild("TopoShader"))
local UIS = game:GetService("UserInputService")

local shader = TopoShader.new(script.Parent, {
	width = 460,
	height = 300,
	renderWidth = 260,
	renderHeight = 170,
	parallelEnabled = true,
	parallelWorkers = 4,
	parallelChunkRows = 24,
	debugEnabled = true,
})

shader:SetPosition(UDim2.fromScale(0.5, 0.5))
shader:SetAnchor(Vector2.new(0.5, 0.5))
shader:ApplyTheme("classic")
shader:ApplyTopoMode("precision")
shader:Start()

-- Press F6 to auto-tune for this device.
UIS.InputBegan:Connect(function(inp, gp)
	if gp then return end
	if inp.KeyCode == Enum.KeyCode.F6 then
		shader:BeginAutoTune()
	end
end)
