--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Renderer = require(ReplicatedStorage.Shared.Renderer)

type Renderer = Renderer.Renderer

local actor: Actor = script:GetActor()
local VoxelBaseSize: number = actor:GetAttribute("VoxelBaseSize") :: number
local HighestLOD: number = actor:GetAttribute("HighestLOD") :: number
local TerrainCFrame: CFrame = actor:GetAttribute("TerrainCFrame") :: CFrame
local workerRenderer: Renderer = Renderer.new(VoxelBaseSize, HighestLOD, TerrainCFrame)

actor:BindToMessageParallel(
    "RenderTerrain",
    function(viewerPosition: vector, startLOD: number, minBoundVoxel: vector, maxBoundVoxel: vector) end
)
