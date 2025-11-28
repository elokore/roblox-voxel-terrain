--!strict
-- < Services > --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- < Imports > --
local Renderer = require(ReplicatedStorage.Shared.Renderer)

-- < Types > --
type Renderer = Renderer.Renderer

-- < Variables > --
local LocalPlayer: Player = Players.LocalPlayer
local LOD: number = 10
local renderer: Renderer = Renderer.new(16, LOD, CFrame.new())

local agent: Part = Instance.new("Part")
agent.Name = "Agent"
agent.Size = Vector3.new(2, 2, 2)
agent.BrickColor = BrickColor.Red()
agent.Anchored = true
agent.CanCollide = false
agent.CFrame = CFrame.new(0, 20005, 0)
agent.Parent = workspace

local lastPos: vector = vector.zero
local cf = CFrame.lookAlong(Vector3.zero, -Vector3.yAxis)

local connection
connection = RunService.Heartbeat:Connect(function(dt)
    if not LocalPlayer.Character then return end
    -- cf *= CFrame.Angles(math.rad(5) * dt, 0, 0)
    -- agent.CFrame = cf * CFrame.new(0, 0, 20005)
    --local pos: vector = vector.create(agent.CFrame.X, agent.CFrame.Y, agent.CFrame.Z)

    local playerPos: Vector3 = LocalPlayer.Character:GetPivot().Position
    local camera: Camera = workspace.CurrentCamera
    local pos: vector = vector.create(playerPos.X, playerPos.Y, playerPos.Z)
    local dist: number = vector.magnitude(lastPos - pos)

    if dist >= 1 then
        -- if LocalPlayer.Character then
        --     local playerPos: Vector3 = LocalPlayer.Character:GetPivot().Position
        --     debug.profilebegin("CollisionSurfaces")
        --     renderer:UpdateCollisionSurfaces(vector.create(playerPos.X, playerPos.Y, playerPos.Z))
        --     debug.profileend()
        -- end

        local success: boolean = renderer:RenderAtLocation(pos)
        if success then lastPos = pos end
    end
end)
