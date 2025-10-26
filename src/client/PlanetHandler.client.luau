--!strict
-- < Services > --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- < Imports > --
local Renderer = require(ReplicatedStorage.Shared.Renderer)

-- < Types > --
type Renderer = Renderer.Renderer

-- < Variables > --
local LOD: number = 5
local renderer: Renderer = Renderer.new(5, LOD, CFrame.new())

local agent: Part = Instance.new("Part")
agent.Name = "Agent"
agent.Size = Vector3.new(2, 2, 2)
agent.BrickColor = BrickColor.Red()
agent.Anchored = true
agent.CanCollide = false
agent.CFrame = CFrame.new(0, 205, 0)
agent.Parent = workspace

local lastPos: vector = vector.zero

RunService.Heartbeat:Connect(function()
    local camera: Camera = workspace.CurrentCamera
    local pos: vector = vector.create(camera.CFrame.X, camera.CFrame.Y, camera.CFrame.Z)
    local dist: number = vector.magnitude(lastPos - pos)

    if dist >= 1 then
        local success: boolean = renderer:RenderAtLocation(pos)
        if success then lastPos = pos end
    end
end)
