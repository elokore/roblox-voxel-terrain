--!strict
-- < Services > --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local closestVoxel: vector = renderer:GetNearestVoxel(vector.create(agent.Position.X, agent.Position.Y, agent.Position.Z), LOD)
