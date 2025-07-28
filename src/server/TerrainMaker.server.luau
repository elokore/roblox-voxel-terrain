--!strict
-- < Services > --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- < Imports > --
local Renderer = require(ReplicatedStorage.Shared.Renderer)

-- < Types > --
type Renderer = Renderer.Renderer

-- < Variables > --
local VOXEL_SIZE: number = 15

for x = 0, 1 do
    for z = 0, 1 do
        local renderer: Renderer = Renderer.new(VOXEL_SIZE, CFrame.new(VOXEL_SIZE * 30 * x, 20, VOXEL_SIZE * 30 * z), Vector3.new(30, 30, 30))
        renderer:Render()
    end
end