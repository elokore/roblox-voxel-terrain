--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VoxelProcessor = require(ReplicatedStorage.Shared.VoxelTerrain.VoxelProcessor)
local VoxelRenderer = require(ReplicatedStorage.Shared.VoxelTerrain.VoxelRenderer)
local TerrainCollider = require(ReplicatedStorage.Shared.VoxelTerrain.TerrainCollider)
local Types = require(ReplicatedStorage.Shared.VoxelTerrain.Types)

type VoxelProcessor = Types.VoxelProcessor
type VoxelRenderer = Types.VoxelRenderer
type TerrainCollider = Types.TerrainCollider

local LocalPlayer: Player = Players.LocalPlayer
local actor: Actor = script:GetActor()
local VoxelBaseSize: number = actor:GetAttribute("VoxelBaseSize") :: number
local MaxLOD: number = actor:GetAttribute("MaxLOD") :: number
local TerrainCFrame: CFrame = actor:GetAttribute("TerrainCFrame") :: CFrame
local isCollisionHandler: boolean = (actor:GetAttribute("CollisionHandler") :: boolean) or false
local MeshContainerRef: ObjectValue = actor:FindFirstChild("MeshContainerReference") :: ObjectValue
local MeshContainer: Folder = MeshContainerRef.Value :: Folder

local processor: VoxelProcessor = VoxelProcessor.new(TerrainCFrame, VoxelBaseSize, MaxLOD)
local renderer: VoxelRenderer = VoxelRenderer.new(TerrainCFrame, VoxelBaseSize, MaxLOD, processor.GeoContainer, MeshContainer)

local isBusy: boolean = false

actor:BindToMessage("RenderChunk", function(viewerPosition: vector, startLOD: number, chunkMin: vector, chunkMax: vector)
    if isBusy then return end
    isBusy = true
    actor:SetAttribute("IsBusy", true)

    processor:ProcessChunk(chunkMin, chunkMax, startLOD, viewerPosition):await()
    renderer:Render(processor._renderList, processor._cleaningList, processor._renderFirstList, startLOD):await()
    print(actor.Name, "Triangles:", processor.GeoContainer.FaceCount)

    actor:SetAttribute("IsBusy", false)
    isBusy = false
end)

print("Init", actor.Name)

if isCollisionHandler then
    local collider: TerrainCollider = TerrainCollider.new(renderer)
    collider:SetColliderSize(2, MaxLOD, VoxelBaseSize)
    local lastPos: vector = vector.zero

    RunService.Heartbeat:Connect(function()
        if not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then return end
        local cf: CFrame = LocalPlayer.Character:GetPivot()
        local pos: vector = vector.create(cf.X, cf.Y, cf.Z)
        local dist: number = vector.magnitude(pos - lastPos)

        if dist >= 1 then
            collider:UpdateCollider(pos)
            lastPos = pos
        end
    end)
end
