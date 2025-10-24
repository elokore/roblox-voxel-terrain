--!strict
-- < Services > --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- < Imports > --
local GeometryContainer = require(ReplicatedStorage.Shared.GeometryContainer)
local Renderer = require(ReplicatedStorage.Shared.Renderer)

-- < Types > --
type GeometryContainer = GeometryContainer.GeometryContainer

-- < Variables > --
local CHILDREN_DIR: { vector } = {
    vector.zero,
    vector.create(1, 0, 0),
    vector.create(0, 0, 1),
    vector.create(1, 0, 1),
    vector.create(0, 1, 0),
    vector.create(1, 1, 0),
    vector.create(0, 1, 1),
    vector.create(1, 1, 1),
}
local renderer = Renderer.new(5, 5, CFrame.new())
local container: GeometryContainer = renderer.GeometryContainer

local function showVoxelsInLod(lod: number)
    local lowBound: vector, highBound: vector = container:GetCoordinateRange(lod)
    local voxelSize: number = renderer._voxelSizes[lod]

    for x = lowBound.x, highBound.x do
        for y = lowBound.y, highBound.y do
            for z = lowBound.z, highBound.z do
                local p = Instance.new("Part")
                p.Transparency = 0.5
                p.TopSurface = Enum.SurfaceType.Smooth
                p.BottomSurface = Enum.SurfaceType.Smooth
                p.BrickColor = BrickColor.random()
                p.Size = Vector3.new(voxelSize, voxelSize, voxelSize)
                p.Anchored = true
                p.CanCollide = false
                p.CFrame = CFrame.new(Vector3.new(x, y, z) * voxelSize) * CFrame.new(Vector3.new(voxelSize, voxelSize, voxelSize) / 2)
                p.Name = `LOD {lod} - ({x}, {y}, {z})`
                p.Parent = workspace
            end
            task.wait()
        end
    end
end

local function renderChildren(pos: Vector3, lod: number, maxLod: number)
    local rootChild: vector = container:GetHighLodVoxelPos(vector.create(pos.X, pos.Y, pos.Z))
    local voxelSize: number = renderer._voxelSizes[lod]

    for _, dir: vector in CHILDREN_DIR do
        task.wait()
        local childPosV: vector = rootChild + dir
        local childPos: Vector3 = Vector3.new(childPosV.x, childPosV.y, childPosV.z)

        local p = Instance.new("Part")
        p.Transparency = 0.5
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        p.BrickColor = BrickColor.random()
        p.Size = Vector3.new(voxelSize, voxelSize, voxelSize)
        p.Anchored = true
        p.CanCollide = false
        p.CFrame = CFrame.new(childPos * voxelSize) * CFrame.new(Vector3.new(voxelSize, voxelSize, voxelSize) / 2)
        p.Name = `LOD {lod} - ({childPos.X}, {childPos.Y}, {childPos.Z})`
        p.Parent = workspace

        if lod < maxLod then renderChildren(childPos, lod + 1, maxLod) end
        task.wait()
    end
end

local function renderParents(pos: Vector3, lod: number)
    local parentPosV: vector = container:GetLowLodVoxelPos(vector.create(pos.X, pos.Y, pos.Z), 2)
    local voxelSize: number = renderer._voxelSizes[lod]
    local parentPos: Vector3 = Vector3.new(parentPosV.x, parentPosV.y, parentPosV.z)

    local p = Instance.new("Part")
    p.Transparency = 0.5
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.BrickColor = BrickColor.random()
    p.Size = Vector3.new(voxelSize, voxelSize, voxelSize)
    p.Anchored = true
    p.CanCollide = false
    p.CFrame = CFrame.new(parentPos * voxelSize) * CFrame.new(Vector3.new(voxelSize, voxelSize, voxelSize) / 2)
    p.Name = `LOD {lod} - ({parentPos.X}, {parentPos.Y}, {parentPos.Z})`
    p.Parent = workspace

    if lod > 1 then
        task.wait()
        renderParents(parentPos, lod - 2)
    end
end

showVoxelsInLod(2)

local agent: Part = workspace:WaitForChild("Agent")
RunService.Heartbeat:Connect(function()
    local voxel: vector = renderer:GetNearestVoxel(vector.create(agent.Position.X, agent.Position.Y, agent.Position.Z), 2)
    local name: string = `LOD 2 - ({voxel.x}, {voxel.y}, {voxel.z})`
    local part: Part? = workspace:FindFirstChild(name)

    if part then
        part.BrickColor = BrickColor.Blue()
        part.Transparency = 0
    end
end)
