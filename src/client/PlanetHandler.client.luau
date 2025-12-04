--!strict
-- < Services > --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- < Imports > --
local VoxelTerrain = require(ReplicatedStorage.Shared.VoxelTerrain)
local Types = require(ReplicatedStorage.Shared.VoxelTerrain.Types)

-- < Types > --
type VoxelTerrain = Types.VoxelTerrain

-- < Variables > --
local LocalPlayer: Player = Players.LocalPlayer
local LOD: number = 10
local terrain: VoxelTerrain = VoxelTerrain.new(16, LOD, CFrame.new())

local agent: Part = Instance.new("Part")
agent.Name = "Agent"
agent.Size = Vector3.new(2, 2, 2)
agent.BrickColor = BrickColor.Red()
agent.Anchored = true
agent.CanCollide = false
agent.CFrame = CFrame.new(0, 20005, 0)
agent.Parent = workspace

local lastPos: vector = vector.zero
local colliderLastPos: vector = vector.zero
local cf = CFrame.lookAlong(Vector3.zero, -Vector3.yAxis)

local connection
local disable: boolean = false
connection = RunService.Heartbeat:Connect(function(dt)
    if not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then return end
    -- cf *= CFrame.Angles(math.rad(5) * dt, 0, 0)
    -- agent.CFrame = cf * CFrame.new(0, 0, 20005)
    --local pos: vector = vector.create(agent.CFrame.X, agent.CFrame.Y, agent.CFrame.Z)

    local playerPos: Vector3 = LocalPlayer.Character:GetPivot().Position
    local camera: Camera = workspace.CurrentCamera
    local pos: vector = vector.create(playerPos.X, playerPos.Y, playerPos.Z)
    local dist: number = vector.magnitude(lastPos - pos)

    if dist >= 1 and not disable then
        local success: boolean = terrain:RenderAtLocation(pos)
        if success then lastPos = pos end
    end
end)
