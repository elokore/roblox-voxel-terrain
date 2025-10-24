--!strict
-- < Services > --
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
agent.CFrame = CFrame.new(-205, 205, 0)
agent.Parent = workspace

local pos: vector = vector.create(agent.Position.X, agent.Position.Y, agent.Position.Z)
local projectedPos: vector = (pos / vector.magnitude(pos)) * 200

local closestVoxel: vector = renderer:GetNearestVoxel(projectedPos, 2)
print(closestVoxel)

local cornerBuffer: { number } = {}
for y = -CHUNK_SIZE, CHUNK_SIZE do
    for z = CHUNK_SIZE, -CHUNK_SIZE, -1 do
        for x = -CHUNK_SIZE, CHUNK_SIZE do
            local v: vector = closestVoxel + vector.create(x, y, z)
            renderer:RenderVoxel(v, 2, cornerBuffer)
        end
    end
end

local part = AssetService:CreateMeshPartAsync(Content.fromObject(renderer._mesh))
part.Anchored = true
part.Parent = workspace
renderer._meshPart = part

print("Vertices:", #renderer._mesh:GetVertices())
print("Triangles:", #renderer._mesh:GetFaces())
