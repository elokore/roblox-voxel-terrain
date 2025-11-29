--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GeometryContainer = require(ReplicatedStorage.Shared.GeometryContainer)
local TriTables = require(ReplicatedStorage.Shared.Renderer.Triangulations)

-- < Types > --
type GeometryContainer = GeometryContainer.GeometryContainer
type Meta = {
    __index: Meta,
    ProcessChunk: (self: VoxelProcessor, chunkMin: vector, chunkMax: vector, lod: number, viewerPosition: vector) -> (),
    CanSubdivide: (self: VoxelProcessor, voxel: vector, lod: number, viewerPosition: vector) -> (boolean, boolean),
    ShouldCleanupVoxel: (self: VoxelProcessor, voxel: vector, lod: number, viewerPosition: vector) -> boolean,
}

export type VoxelProcessor = typeof(setmetatable(
    {} :: {
        BaseVoxelSize: number,
        TerrainCFrame: CFrame,
        TerrainPosition: vector,
        MaxLOD: number,
        IsProcessing: boolean,
        GeoContainer: GeometryContainer,
        _voxelSizes: { number },
        _renderList: { [number]: { vector } },
        _cleaningList: { [number]: { vector } },
    },
    {} :: Meta
))

local PLANET_RADIUS: number = 20000
local RENDER_RADIUS: number = 700
local SUBDIVIDE_VOXEL_DIST: number = 10
local VOXELS_PROCESS_PER_FRAME: number = 5000
local CORNER_MASK: { vector } = TriTables.cornerMask
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

local function getVoxelWorldPosition(voxel: vector, voxelSize: number, terrainPos: vector): vector
    local halfSize: number = voxelSize / 2
    return terrainPos + vector.create(halfSize, halfSize, halfSize) + voxel * vector.create(voxelSize, voxelSize, voxelSize)
end

local function getVoxelID(voxel: vector, lod: number): number
    local sizeRangeXYZ: number = 20001
    local sizeRangeLOD: number = 10

    local x: number = voxel.x + 10000
    local y: number = voxel.y + 10000
    local z: number = voxel.z + 10000
    lod -= 1

    return (((x * sizeRangeXYZ + y) * sizeRangeXYZ + z) * sizeRangeLOD + lod)
end

local function getVoxelFromID(id: number): (vector, number)
    local sizeRangeXYZ: number = 20001
    local sizeRangeLOD: number = 10

    local lod: number = id % sizeRangeLOD
    lod += 1
    id //= sizeRangeLOD

    local z: number = id % sizeRangeXYZ
    z -= 10000
    id //= sizeRangeXYZ

    local y: number = id % sizeRangeXYZ
    y -= 10000
    id //= sizeRangeXYZ

    local x: number = id
    x -= 10000

    return vector.create(x, y, z), lod
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
    local globalVoxelPos: vector = getVoxelWorldPosition(voxel, voxelSize, self.TerrainPosition)
    local distanceStuds: vector = vector.abs(globalVoxelPos - viewerPosition)
    local distanceVoxels: vector = distanceStuds / voxelSize
    local difference: vector = vector.create(SUBDIVIDE_VOXEL_DIST, SUBDIVIDE_VOXEL_DIST, SUBDIVIDE_VOXEL_DIST) - distanceVoxels
    local canDivide: boolean = difference.x >= 0 and difference.y >= 0 and difference.z >= 0
    local isOverlappingBounds: boolean = difference.x >= -2 and difference.y >= -2 and difference.z >= -2 and not canDivide

    if isOverlappingBounds then
        return true, true
    else
        return canDivide, not canDivide
    end
end

function VoxelProcessor:ShouldCleanupVoxel(voxel: vector, lod: number, viewerPosition: vector): boolean
    local voxelSize: number = self._voxelSizes[lod]
    local voxelWorldPos: vector = getVoxelWorldPosition(voxel, voxelSize, self.TerrainPosition)
    local dist: number = vector.magnitude(voxelWorldPos - viewerPosition)
    local inBounds: boolean = dist <= RENDER_RADIUS

    local parentVoxel: vector = self.GeoContainer:GetAncestorVoxel(voxel, 1)
    local canParentSubdivide: boolean, canParentRender: boolean = self:CanSubdivide(parentVoxel, lod - 1, viewerPosition)
    local canBeSubdivided: boolean = self:CanSubdivide(voxel, lod, viewerPosition)
    local shouldCleanup: boolean = not inBounds or canBeSubdivided or (not canParentSubdivide and not canParentRender)
    return shouldCleanup
end

local function subdivideAndAddToQueue(self: VoxelProcessor, voxel: vector, lod: number, childrenToProcess: { number }, backIndex: number): number
    local childLod: number = lod + 1
    local child0: vector = self.GeoContainer:GetDescendantVoxel(voxel)
    local child0ID: number = getVoxelID(child0, childLod)
    local child1ID: number = getVoxelID(child0 + vector.create(1, 0, 0), childLod)
    local child2ID: number = getVoxelID(child0 + vector.create(0, 0, -1), childLod)
    local child3ID: number = getVoxelID(child0 + vector.create(1, 0, -1), childLod)
    local child4ID: number = getVoxelID(child0 + vector.create(0, 1, 0), childLod)
    local child5ID: number = getVoxelID(child0 + vector.create(1, 1, 0), childLod)
    local child6ID: number = getVoxelID(child0 + vector.create(0, 1, -1), childLod)
    local child7ID: number = getVoxelID(child0 + vector.create(1, 1, -1), childLod)

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

local sampleCornerBuffer: { number } = {}
local function sampleVoxelCorners(voxel: vector, voxelSize: number, terrainPos: vector): { number }
    local voxelPos: vector = getVoxelWorldPosition(voxel, voxelSize, terrainPos)
    local halfSize: number = voxelSize / 2

    for i: number = 0, 7 do
        local mask: vector = CORNER_MASK[i]
        local cornerPos: vector = voxelPos + mask * halfSize
        local scaledPos: vector = cornerPos * 1 / 100

        sampleCornerBuffer[i] = PLANET_RADIUS - vector.magnitude(cornerPos) + math.noise(scaledPos.x, scaledPos.y, scaledPos.z) * 150
    end

    return sampleCornerBuffer
end

local function getCaseCode(corners: { number }): number
    return bit32.bor(
        bit32.band(bit32.rshift(math.floor(corners[0]), 31), 0x01),
        bit32.band(bit32.rshift(math.floor(corners[1]), 30), 0x02),
        bit32.band(bit32.rshift(math.floor(corners[2]), 29), 0x04),
        bit32.band(bit32.rshift(math.floor(corners[3]), 28), 0x08),
        bit32.band(bit32.rshift(math.floor(corners[4]), 27), 0x10),
        bit32.band(bit32.rshift(math.floor(corners[5]), 26), 0x20),
        bit32.band(bit32.rshift(math.floor(corners[6]), 25), 0x40),
        bit32.band(bit32.rshift(math.floor(corners[7]), 24), 0x80)
    )
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
    local voxelWorldPos: vector = getVoxelWorldPosition(voxel, voxelSize, self.TerrainPosition)
    local dist: number = vector.magnitude(voxelWorldPos - viewerPosition)
    local canDivide: boolean, canRender: boolean = self:CanSubdivide(voxel, lod, viewerPosition)
    local isAlreadyRendered: boolean = self.GeoContainer._faceStorage[lod][voxel] ~= nil
    local newBackIndex: number = backIndex

    if canDivide then newBackIndex = subdivideAndAddToQueue(self, voxel, lod, childrenToProcess, backIndex) end

    if canRender and not isAlreadyRendered and dist <= RENDER_RADIUS then
        local caseCode: number = getCaseCode(sampleVoxelCorners(voxel, voxelSize, self.TerrainPosition))
        local isEmpty: boolean = caseCode == 0 or caseCode == 255
        if not isEmpty then table.insert(self._renderList[lod], voxel) end
    end

    return newBackIndex
end

function VoxelProcessor:ProcessChunk(chunkMin: vector, chunkMax: vector, startLOD: number, viewerPosition: vector)
    if self.IsProcessing then return end
    self.IsProcessing = true

    -- Check for voxels to clean
    for lod: number = startLOD, self.MaxLOD do
        for voxel: vector, faces: { number } in self.GeoContainer._faceStorage[lod] do
            if self:ShouldCleanupVoxel(voxel, lod, viewerPosition) then table.insert(self._cleaningList[lod], voxel) end
        end
    end

    local step: RBXScriptConnection
    local progressX: number = chunkMin.x
    local progressY: number = chunkMin.y
    local progressZ: number = chunkMax.z -- Set to max Z because -Z is forward in roblox

    local childrenToProcess: { number } = {}
    local frontIndex: number = 0
    local backIndex: number = 0

    step = RunService.Heartbeat:Connect(function()
        local resumeX: number = progressX
        local resumeY: number = progressY
        local resumeZ: number = progressZ
        local isResuming: boolean = true
        local processCount: number = 0

        -- Iterate over the render area.
        -- There's a limit on iterations per frame. Track progress so we can resume loops next frame
        for y = resumeY, chunkMax.y do
            progressY = y
            local startZ: number = if isResuming then resumeZ else chunkMax.z
            for z = startZ, chunkMin.z, -1 do
                progressZ = z
                local startX: number = if isResuming then resumeX else chunkMin.x
                for x = startX, chunkMax.x do
                    progressX = x
                    isResuming = false

                    local mainVoxel: vector = vector.create(x, y, z)
                    if frontIndex == 0 and backIndex == 0 then
                        childrenToProcess[1] = getVoxelID(mainVoxel, startLOD)
                        frontIndex = 1
                        backIndex = 1
                    end

                    local maxIterations: number = VOXELS_PROCESS_PER_FRAME - processCount
                    for i = 1, maxIterations do
                        local voxelID: number = childrenToProcess[frontIndex]
                        local voxel: vector, lod: number = getVoxelFromID(voxelID)
                        backIndex = processVoxel(self, voxel, lod, viewerPosition, childrenToProcess, backIndex)
                        childrenToProcess[frontIndex] = nil
                        frontIndex += 1
                        processCount += 1

                        local allChildrenProcessed: boolean = frontIndex > backIndex
                        if allChildrenProcessed then
                            frontIndex = 0
                            backIndex = 0
                            progressX += 1
                        end

                        if processCount >= VOXELS_PROCESS_PER_FRAME then
                            return
                        elseif allChildrenProcessed then
                            break
                        end
                    end
                end
            end
        end

        step:Disconnect()
        self.IsProcessing = false
    end)
end

return VoxelProcessor
