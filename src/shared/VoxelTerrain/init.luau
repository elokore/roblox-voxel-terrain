--!strict
local Players = game:GetService("Players")
local Helper = require(script.Helper)
local Types = require(script.Types)

-- < Types > --
type CollisionFace = Types.CollisionFace
export type VoxelTerrain = Types.VoxelTerrain
type Collider = Types.TerrainCollider
type VoxelProcessor = Types.VoxelProcessor
type VoxelRenderer = Types.VoxelRenderer
type ChunkBounds = { Min: vector, Max: vector }

-- < Variables > --
local WORKER_TOPIC: string = "RenderChunk"
local PLANET_RADIUS: number = 20000
local RENDER_RADIUS: number = 600
local VoxelTerrain = {}
VoxelTerrain.__index = VoxelTerrain

local function getNonParallelVector(v: vector): vector
    if math.abs(v.x) > math.abs(v.z) then
        return vector.create(-v.y, v.x, 0)
    else
        return vector.create(0, -v.z, v.y)
    end
end

local function getChunkBasis(min: vector, max: vector): (vector, vector, vector)
    local size: vector = max - min
    local minAxis: number = math.min(size.x, size.y, size.z)

    -- if minAxis == size.y then
    --     return vector.create(1, 0, 0), vector.create(0, 1, 0), vector.create(0, 0, 1)
    -- elseif minAxis == size.x then
    --     return vector.create(0, 0, 1), vector.create(1, 0, 0), vector.create(0, 1, 0)
    -- else
    --     return vector.create(1, 0, 0), vector.create(0, 0, 1), vector.create(0, 1, 0)
    -- end
    return vector.create(1, 0, 0), vector.create(0, 1, 0), vector.create(0, 0, 1)
end

local function makeDivisible(v: vector, d: number): vector
    return vector.floor(v / d) * d
end

local function getChunkBounds(areaMin: vector, areaMax: vector, dimensionX: number, dimensionY: number): { ChunkBounds }
    local areaSize: vector = areaMax - areaMin
    local rightVector: vector, upVector: vector, lookVector: vector = getChunkBasis(areaMin, areaMax)

    local rightSize: vector = makeDivisible(areaSize * rightVector, dimensionX)
    local upSize: vector = areaSize * upVector
    local lookSize: vector = makeDivisible(areaSize * lookVector, dimensionY)

    local xChunkSize: number = vector.magnitude(rightSize // dimensionX)
    local zChunkSize: number = vector.magnitude(lookSize // dimensionY)

    local boundsContainer: { ChunkBounds } = {}

    for z = 0, dimensionY - 1 do
        for x = 0, dimensionX - 1 do
            local chunkMin: vector = areaMin + rightVector * xChunkSize * x + lookVector * zChunkSize * z
            local chunkMax: vector = chunkMin + rightVector * xChunkSize + lookVector * zChunkSize + upSize

            chunkMax -= (rightVector + lookVector)

            if x == dimensionX - 1 then
                local distFromMaxX: vector = (areaMax * rightVector) - (chunkMax * rightVector)
                chunkMax += distFromMaxX
            end

            if z == dimensionY - 1 then
                local distFromMaxZ: vector = (areaMax * lookVector) - (chunkMax * lookVector)
                chunkMax += distFromMaxZ
            end

            table.insert(boundsContainer, {
                Min = chunkMin,
                Max = chunkMax,
            })
        end
    end

    return boundsContainer
end

local function createWorkers(workerCount: number, terrainCF: CFrame, baseVoxelSize: number, maxLOD: number, meshContainer: Folder): { Actor }
    local container: Folder = Instance.new("Folder")
    container.Name = "TerrainWorkers"

    local workerList: { Actor } = {}

    for i = 1, workerCount do
        local actor: Actor = Instance.new("Actor")
        actor.Name = `TerrainWorker{i}`

        local containerRef: ObjectValue = Instance.new("ObjectValue")
        containerRef.Name = "MeshContainerReference"
        containerRef.Value = meshContainer
        containerRef.Parent = actor

        actor:SetAttribute("TerrainCFrame", terrainCF)
        actor:SetAttribute("MaxLOD", maxLOD)
        actor:SetAttribute("VoxelBaseSize", baseVoxelSize)
        actor:SetAttribute("IsBusy", false)

        if i == 1 then actor:SetAttribute("CollisionHandler", true) end

        for _, object: Instance in script.Worker:GetChildren() do
            object:Clone().Parent = actor
        end

        actor.Parent = container
        table.insert(workerList, actor)
    end

    container.Parent = Players.LocalPlayer.PlayerScripts
    return workerList
end

function VoxelTerrain.new(voxelSize: number, maxLOD: number, TerrainCFrame: CFrame): VoxelTerrain
    local voxelSizes: { number } = {}
    for x = 1, maxLOD do
        voxelSizes[x] = voxelSize * (2 ^ (maxLOD - x))
    end

    local meshContainer: Folder = Instance.new("Folder")
    meshContainer.Name = "TerrainMeshes"
    meshContainer.Parent = workspace

    local workerCount: number = 8
    local workers: { Actor } = createWorkers(workerCount, TerrainCFrame, voxelSize, maxLOD, meshContainer)

    local self: VoxelTerrain = setmetatable({
        VoxelSize = voxelSize,
        TerrainCFrame = TerrainCFrame,
        TerrainPosition = vector.create(TerrainCFrame.X, TerrainCFrame.Y, TerrainCFrame.Z),
        IsBusy = false,
        MaxLOD = maxLOD,
        WorkerCount = workerCount,
        Workers = workers,
        MeshContainer = meshContainer,
        _workerStates = table.create(workerCount, false),
        _voxelSizes = voxelSizes,
    }, VoxelTerrain)

    for i: number, worker: Actor in workers do
        worker:GetAttributeChangedSignal("IsBusy"):Connect(function()
            self._workerStates[i] = worker:GetAttribute("IsBusy") :: boolean

            local isBusy: boolean = false

            for _, isWorkerBusy: boolean in self._workerStates do
                if isWorkerBusy then
                    isBusy = true
                    break
                end
            end

            self.IsBusy = isBusy
        end)
    end

    return self
end

function VoxelTerrain:GetRenderAreaBoundingBox(areaCenter: vector, lod: number): (vector, vector)
    local up: vector = vector.normalize(areaCenter)
    local right: vector = vector.cross(up, getNonParallelVector(up))
    local look: vector = vector.cross(up, right)

    local alpha: number = RENDER_RADIUS / PLANET_RADIUS
    local cosAlpha: number = math.cos(alpha)
    local sinAlpha: number = math.sin(alpha)

    local planetRad: number = PLANET_RADIUS

    local p0: vector = up * planetRad
    local p1: vector = vector.normalize(up * cosAlpha + right * sinAlpha) * planetRad
    local p2: vector = vector.normalize(up * cosAlpha + look * sinAlpha) * planetRad
    local p3: vector = vector.normalize(up * cosAlpha - right * sinAlpha) * planetRad
    local p4: vector = vector.normalize(up * cosAlpha - look * sinAlpha) * planetRad

    local boxMin: vector =
        vector.create(math.min(p0.x, p1.x, p2.x, p3.x, p4.x), math.min(p0.y, p1.y, p2.y, p3.y, p4.y), math.min(p0.z, p1.z, p2.z, p3.z, p4.z))
    local boxMax: vector =
        vector.create(math.max(p0.x, p1.x, p2.x, p3.x, p4.x), math.max(p0.y, p1.y, p2.y, p3.y, p4.y), math.max(p0.z, p1.z, p2.z, p3.z, p4.z))

    local minVoxel: vector = Helper.GetNearestVoxel(self.TerrainCFrame, boxMin, self._voxelSizes[lod])
    local maxVoxel: vector = Helper.GetNearestVoxel(self.TerrainCFrame, boxMax, self._voxelSizes[lod])
    local size: vector = maxVoxel - minVoxel
    local sizeError: vector = vector.max(vector.create(4, 4, 4) - size, vector.zero)

    maxVoxel += sizeError
    minVoxel -= sizeError

    return minVoxel, maxVoxel
end

function VoxelTerrain:RenderAtLocation(position: vector): boolean
    if self.IsBusy then return false end

    self.IsBusy = true
    local startingLOD: number = 6
    local posOnPlanet: vector = (position / vector.magnitude(position)) * PLANET_RADIUS
    local renderMin: vector, renderMax: vector = self:GetRenderAreaBoundingBox(posOnPlanet, startingLOD)
    local chunkBoundsList: { ChunkBounds } = getChunkBounds(renderMin, renderMax, 2, 4)

    for i: number, bounds: ChunkBounds in chunkBoundsList do
        local worker: Actor = self.Workers[i]
        worker:SendMessage(WORKER_TOPIC, posOnPlanet, startingLOD, bounds.Min, bounds.Max)

        -- local minPos: vector = Helper.GetVoxelWorldPosition(bounds.Min, self._voxelSizes[startingLOD], self.TerrainPosition)
        -- local maxPos: vector = Helper.GetVoxelWorldPosition(bounds.Max, self._voxelSizes[startingLOD], self.TerrainPosition)

        -- local size: vector = maxPos - minPos
        -- local pos: vector = (maxPos + minPos) / 2

        -- local p = Instance.new("Part")
        -- p.BrickColor = BrickColor.random()
        -- p.Transparency = 0.5
        -- p.Anchored = true
        -- p.CanCollide = false
        -- p.Size = size
        -- p.Position = pos
        -- p.Name = tostring(i)
        -- p.Parent = workspace
    end

    print("Sent messages")

    return true
end

return VoxelTerrain
