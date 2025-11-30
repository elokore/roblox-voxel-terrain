--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GeometryContainer = require(ReplicatedStorage.Shared.GeometryContainer)
local Helper = require(script.Parent.Helper)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Types = require(ReplicatedStorage.Shared.Renderer.Types)

-- < Types > --
type Promise<T...> = Promise.TypedPromise<T...>
type VoxelProcessor = Types.VoxelProcessor

local PLANET_RADIUS: number = 20000
local RENDER_RADIUS: number = 700
local SUBDIVIDE_VOXEL_DIST: number = 8
local VOXELS_PROCESS_PER_FRAME: number = 5000
local VoxelProcessor = {}
VoxelProcessor.__index = VoxelProcessor

function VoxelProcessor.new(terrainCFrame: CFrame, baseVoxelSize: number, maxLod: number): VoxelProcessor
    local voxelSizes: { number } = {}
    local renderList: { [number]: { vector } } = {}
    local cleaningList: { [number]: { vector } } = {}

    for x: number = 1, maxLod do
        voxelSizes[x] = baseVoxelSize * (2 ^ (maxLod - x))
        renderList[x] = {}
        cleaningList[x] = {}
    end

    local self: VoxelProcessor = setmetatable({
        BaseVoxelSize = baseVoxelSize,
        TerrainCFrame = terrainCFrame,
        TerrainPosition = vector.create(terrainCFrame.X, terrainCFrame.Y, terrainCFrame.Z),
        MaxLOD = maxLod,
        IsProcessing = false,
        GeoContainer = GeometryContainer.new(maxLod),
        _voxelSizes = voxelSizes,
        _renderList = renderList,
        _cleaningList = cleaningList,
    }, VoxelProcessor)

    return self
end

--[[
    Checks if the voxel should be subdivided. Normally when a voxel is subdivided, that voxel cannot be
    rendered. However, for patching holes between LOD changes, along the border of an LOD change we allow
    a voxel to be both be subdivided AND rendered so that the two LODs overlap.

    This function returns two bools that indicate if the voxel can be subdivided and if it can be rendered respectively.
]]
function VoxelProcessor:CanSubdivide(voxel: vector, lod: number, viewerPosition: vector): (boolean, boolean)
    if lod >= self.MaxLOD then return false, false end
    local voxelSize: number = self._voxelSizes[lod]
    local globalVoxelPos: vector = Helper.GetVoxelWorldPosition(voxel, voxelSize, self.TerrainPosition)
    local distanceStuds: vector = vector.abs(globalVoxelPos - viewerPosition)
    local distanceVoxels: vector = distanceStuds / voxelSize
    local difference: vector = vector.create(SUBDIVIDE_VOXEL_DIST, SUBDIVIDE_VOXEL_DIST, SUBDIVIDE_VOXEL_DIST) - distanceVoxels
    local canDivide: boolean = difference.x >= 0 and difference.y >= 0 and difference.z >= 0
    local canDivideAndRender: boolean = difference.x >= -2 and difference.y >= -2 and difference.z >= -2 and not canDivide

    return canDivide, canDivideAndRender
end

function VoxelProcessor:ShouldCleanupVoxel(voxel: vector, lod: number, viewerPosition: vector): boolean
    local voxelSize: number = self._voxelSizes[lod]
    local voxelWorldPos: vector = Helper.GetVoxelWorldPosition(voxel, voxelSize, self.TerrainPosition)
    local dist: number = vector.magnitude(voxelWorldPos - viewerPosition)
    local inBounds: boolean = dist <= RENDER_RADIUS

    local parentVoxel: vector = self.GeoContainer:GetAncestorVoxel(voxel, 1)
    local canParentSubdivide: boolean, canParentRenderAndDivide: boolean = self:CanSubdivide(parentVoxel, lod - 1, viewerPosition)
    local canBeSubdivided: boolean = self:CanSubdivide(voxel, lod, viewerPosition)
    local shouldCleanup: boolean = not inBounds or canBeSubdivided or (not canParentSubdivide and not canParentRenderAndDivide)
    return shouldCleanup
end

local function subdivideAndAddToQueue(self: VoxelProcessor, voxel: vector, lod: number, childrenToProcess: { number }, backIndex: number): number
    local childLod: number = lod + 1
    local child0: vector = self.GeoContainer:GetDescendantVoxel(voxel)
    local child0ID: number = Helper.GetVoxelID(child0, childLod)
    local child1ID: number = Helper.GetVoxelID(child0 + vector.create(1, 0, 0), childLod)
    local child2ID: number = Helper.GetVoxelID(child0 + vector.create(0, 0, -1), childLod)
    local child3ID: number = Helper.GetVoxelID(child0 + vector.create(1, 0, -1), childLod)
    local child4ID: number = Helper.GetVoxelID(child0 + vector.create(0, 1, 0), childLod)
    local child5ID: number = Helper.GetVoxelID(child0 + vector.create(1, 1, 0), childLod)
    local child6ID: number = Helper.GetVoxelID(child0 + vector.create(0, 1, -1), childLod)
    local child7ID: number = Helper.GetVoxelID(child0 + vector.create(1, 1, -1), childLod)

    childrenToProcess[backIndex + 1] = child0ID
    childrenToProcess[backIndex + 2] = child1ID
    childrenToProcess[backIndex + 3] = child2ID
    childrenToProcess[backIndex + 4] = child3ID
    childrenToProcess[backIndex + 5] = child4ID
    childrenToProcess[backIndex + 6] = child5ID
    childrenToProcess[backIndex + 7] = child6ID
    childrenToProcess[backIndex + 8] = child7ID
    return backIndex + 8
end

local function processVoxel(
    self: VoxelProcessor,
    voxel: vector,
    lod: number,
    viewerPosition: vector,
    childrenToProcess: { number },
    backIndex: number
): number
    local voxelSize: number = self._voxelSizes[lod]
    local voxelWorldPos: vector = Helper.GetVoxelWorldPosition(voxel, voxelSize, self.TerrainPosition)
    local dist: number = vector.magnitude(voxelWorldPos - viewerPosition)
    local canDivide: boolean, canDivideAndRender: boolean = self:CanSubdivide(voxel, lod, viewerPosition)
    local isAlreadyRendered: boolean = self.GeoContainer._faceStorage[lod][voxel] ~= nil
    local newBackIndex: number = backIndex
    local canRender: boolean = not canDivide or canDivideAndRender

    if canDivide or canDivideAndRender then newBackIndex = subdivideAndAddToQueue(self, voxel, lod, childrenToProcess, backIndex) end

    if canRender and not isAlreadyRendered and dist <= RENDER_RADIUS then
        local caseCode: number = Helper.GetCaseCode(Helper.SampleVoxelCorners(voxel, voxelSize, self.TerrainPosition, PLANET_RADIUS))
        local isEmpty: boolean = caseCode == 0 or caseCode == 255
        if not isEmpty then table.insert(self._renderList[lod], voxel) end
    end

    return newBackIndex
end

function VoxelProcessor:ProcessChunk(chunkMin: vector, chunkMax: vector, startLOD: number, viewerPosition: vector): Promise<>
    if self.IsProcessing then return Promise.reject() end
    self.IsProcessing = true

    return Promise.new(function(resolve)
        -- Check for voxels to clean
        for lod: number = startLOD, self.MaxLOD do
            for voxel: vector, faces: { number } in self.GeoContainer._faceStorage[lod] do
                if self:ShouldCleanupVoxel(voxel, lod, viewerPosition) then table.insert(self._cleaningList[lod], voxel) end
            end
        end

        local step: RBXScriptConnection
        local chunkSize: vector = chunkMax - chunkMin + vector.one
        local totalVoxelsToProcess: number = chunkSize.x * chunkSize.y * chunkSize.z
        local progress: number = 1

        local childrenToProcess: { number } = {}
        local frontIndex: number = 0
        local backIndex: number = 0

        step = RunService.Heartbeat:Connect(function()
            local processCount: number = 0

            -- Iterate over the render area.
            for i: number = progress, totalVoxelsToProcess do
                progress = i
                local mainVoxel: vector = vector.create(
                    chunkMin.x + (i % chunkSize.x),
                    chunkMin.y + math.floor(i / (chunkSize.x * chunkSize.z)),
                    chunkMax.z - (math.floor(i / chunkSize.x) % chunkSize.z)
                )

                if frontIndex == 0 and backIndex == 0 then
                    childrenToProcess[1] = Helper.GetVoxelID(mainVoxel, startLOD)
                    frontIndex = 1
                    backIndex = 1
                end

                local maxIterations: number = VOXELS_PROCESS_PER_FRAME - processCount
                for _ = 1, maxIterations do
                    local voxelID: number = childrenToProcess[frontIndex]
                    local voxel: vector, lod: number = Helper.GetVoxel(voxelID)
                    backIndex = processVoxel(self, voxel, lod, viewerPosition, childrenToProcess, backIndex)
                    childrenToProcess[frontIndex] = nil
                    frontIndex += 1
                    processCount += 1

                    local allChildrenProcessed: boolean = frontIndex > backIndex
                    if allChildrenProcessed then
                        frontIndex = 0
                        backIndex = 0
                        progress += 1
                    end

                    if processCount >= VOXELS_PROCESS_PER_FRAME then
                        return
                    elseif allChildrenProcessed then
                        break
                    end
                end
            end

            step:Disconnect()
            self.IsProcessing = false
            resolve()
        end)
    end)
end

return VoxelProcessor
