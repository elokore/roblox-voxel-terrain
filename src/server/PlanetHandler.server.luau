--!strict
-- < Services > --
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- < Imports > --
local Renderer = require(ReplicatedStorage.Shared.Renderer)

-- < Types > --
type Renderer = Renderer.Renderer

-- < Variables > --
local LOD: number = 5
local CHUNK_SIZE: number = 15
local renderer: Renderer = Renderer.new(5, LOD, CFrame.new())

local agent: Part = Instance.new("Part")
agent.Name = "Agent"
agent.Size = Vector3.new(2, 2, 2)
agent.BrickColor = BrickColor.Red()
agent.Anchored = true
agent.CanCollide = false
agent.CFrame = CFrame.new(-205, 77.5, 0)
agent.Parent = workspace

local lastPos: vector = vector.zero

while true do
    task.wait(1)
    local pos: vector = vector.create(agent.Position.X, agent.Position.Y, agent.Position.Z)
    local dist: number = vector.magnitude(lastPos - pos)

    if dist >= 5 then
        lastPos = pos
        renderer:RenderAtLocation(pos)
    end
end
