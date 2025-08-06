--!strict
-- < Services > --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- < Imports > --
local Renderer = require(ReplicatedStorage.Shared.Renderer)

-- < Types > --
type Renderer = Renderer.Renderer

-- < Variables > --
local VOXEL_SIZE: number = 10
local regionSize: Vector3 = Vector3.new(100, 100, 100)
local list = {}

local renderer: Renderer = Renderer.new(VOXEL_SIZE, CFrame.new(-VOXEL_SIZE * regionSize / 2), regionSize)
renderer:Render()
