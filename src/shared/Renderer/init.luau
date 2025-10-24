--!strict
-- < Services > --
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- < Imports > --
local TriTables = require(script.Triangulations)
local GeometryContainer = require(ReplicatedStorage.Shared.GeometryContainer)

-- < Types > --
type CellData = TriTables.CellData
type GeometryContainer = GeometryContainer.GeometryContainer

type RendererMeta = {
    __index: RendererMeta,
    RenderVoxel: (self: Renderer, voxel: vector, lod: number, cornerBuffer: { number }) -> (),
    GetVertexId: (self: Renderer, voxel: vector, lod: number, vertexPos: vector, vertex: number, cornerBuffer: { number }) -> number,
    GetNearestVoxel: (self: Renderer, globalPosition: vector, lod: number) -> vector,
}

export type Renderer = typeof(setmetatable(
    {} :: {
        VoxelSize: number,
        RenderAreaCFrame: CFrame,
        GeometryContainer: GeometryContainer,
        _mesh: EditableMesh,
        _meshPart: MeshPart?,
        _voxelSizes: { number },
    },
    {} :: RendererMeta
))

-- < Variables > --
local CORNER_MASK: { vector } = TriTables.cornerMask
local Renderer = {}
local RendererInstance = {}
RendererInstance.__index = RendererInstance

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

--[[
	Calculates a smoothed vertex position.
	The position is normalized and relative to the voxel
]]
local function getVertexPositionSmooth(v: number, cornerBuffer: { number }): vector
    local lowEndpoint: number = bit32.rshift(bit32.band(v, 0xF0), 4)
    local highEndpoint: number = bit32.band(v, 0x0F)

    -- Follows calculation in Figure (3.4) of Transvoxel algorithm paper
    local d0: number = cornerBuffer[lowEndpoint]
    local d1: number = cornerBuffer[highEndpoint]
    local t: number = d1 / (d1 - d0)

    local p0: vector = CORNER_MASK[lowEndpoint]
    local p1: vector = CORNER_MASK[highEndpoint]
    local vPos: vector = t * p0 + (1 - t) * p1

    return vPos
end

function Renderer.new(voxelSize: number, highestLOD: number, renderAreaCFrame: CFrame): Renderer
    local voxelSizes: { number } = {}
    for x = 1, highestLOD do
        voxelSizes[x] = voxelSize * (2 ^ (highestLOD - x))
    end

    local self: Renderer = setmetatable({
        VoxelSize = voxelSize,
        RenderAreaCFrame = renderAreaCFrame,
        GeometryContainer = GeometryContainer.new(5),
        _mesh = AssetService:CreateEditableMesh(),
        _voxelSizes = voxelSizes,
        _meshPart = nil,
    }, RendererInstance)

    return self
end

local vCount: number = 0
local tCount: number = 0

function RendererInstance:GetNearestVoxel(globalPosition: vector, lod: number): vector
    local rp: Vector3 = self.RenderAreaCFrame:PointToObjectSpace(Vector3.new(globalPosition.x, globalPosition.y, globalPosition.z))
    local relativePos: vector = vector.create(rp.X, rp.Y, rp.Z)
    local voxelSize: number = self._voxelSizes[lod]

    local voxel: vector = vector.floor((relativePos / voxelSize))
    local min: vector, max: vector = self.GeometryContainer:GetCoordinateRange(lod)
    voxel = vector.clamp(voxel, min, max)

    return voxel
end

function RendererInstance:GetVertexId(voxel: vector, lod: number, vertexPos: vector, vertex: number, cornerBuffer: { number }): number
    local lowEndpointCornerIndex: number = bit32.rshift(bit32.band(vertex, 0xF0), 4)
    local highEndpointCornerIndex: number = bit32.band(vertex, 0x0F)
    local reuseData: number = bit32.rshift(vertex, 8)
    local reuseIndex: number = bit32.band(reuseData, 0x0F)
    local directionCode: number = bit32.rshift(reuseData, 4)
    local zeroCornerIndex: number = -1

    if cornerBuffer[lowEndpointCornerIndex] == 0 then
        zeroCornerIndex = lowEndpointCornerIndex
    elseif cornerBuffer[highEndpointCornerIndex] == 0 then
        zeroCornerIndex = highEndpointCornerIndex
    end

    -- If the vertex lies exactly at a corner instead of along an edge
    -- And it lies on a corner other than corner 7, then invert the direction code
    -- to find the voxel that owns the vertex
    if zeroCornerIndex >= 0 and zeroCornerIndex ~= 7 then
        directionCode = bit32.bxor(directionCode)
        reuseIndex = 0
    end

    local direction: vector = vector.create(
        -bit32.band(directionCode, 1),
        -bit32.band(bit32.rshift(directionCode, 2), 1),
        bit32.band(bit32.rshift(directionCode, 1), 1)
    )

    local vertexOwnerVoxel: vector = voxel + direction
    local vid: number? = self.GeometryContainer:GetVertexId(reuseIndex, vertexOwnerVoxel, lod)

    if vid then
        return vid
    else
        local newVid: number = self._mesh:AddVertex(Vector3.new(vertexPos.x, vertexPos.y, vertexPos.z))
        self.GeometryContainer:StoreVertexId(newVid, reuseIndex, voxel, lod)
        vCount += 1
        return newVid
    end
end

--[=[
    @param voxel vector -- The location of the voxel grid position within the specified LOD
    @param lod number -- 
]=]
function RendererInstance:RenderVoxel(voxel: vector, lod: number, cornerBuffer: { number })
    local mesh: EditableMesh = self._mesh
    local voxelPos: vector = voxel * self.VoxelSize
    local halfSize: number = self.VoxelSize / 2
    local renderAreaPos: vector =
        vector.create(self.RenderAreaCFrame.Position.X, self.RenderAreaCFrame.Position.Y, self.RenderAreaCFrame.Position.Z)

    for i: number = 0, 7 do
        local mask: vector = CORNER_MASK[i]
        local cornerPos: vector = voxelPos + mask * self.VoxelSize / 2

        cornerPos += renderAreaPos
        cornerBuffer[i] = 200 - vector.magnitude(cornerPos)
    end

    local caseCode: number = getCaseCode(cornerBuffer)
    local cellClass: number = TriTables.regularCellClass[caseCode]
    local cellData: CellData = TriTables.regularCellData[cellClass]
    local vertexData: { number } = TriTables.regularVertexData[caseCode]

    for x: number = 1, #cellData.vertexIndex, 3 do
        local v1: number = vertexData[cellData.vertexIndex[x]]
        local v2: number = vertexData[cellData.vertexIndex[x + 1]]
        local v3: number = vertexData[cellData.vertexIndex[x + 2]]

        local v1Pos: vector = voxelPos + getVertexPositionSmooth(v1, cornerBuffer) * halfSize
        local v2Pos: vector = voxelPos + getVertexPositionSmooth(v2, cornerBuffer) * halfSize
        local v3Pos: vector = voxelPos + getVertexPositionSmooth(v3, cornerBuffer) * halfSize

        local vid1: number = self:GetVertexId(voxel, lod, v1Pos, v1, cornerBuffer)
        local vid2: number = self:GetVertexId(voxel, lod, v2Pos, v2, cornerBuffer)
        local vid3: number = self:GetVertexId(voxel, lod, v3Pos, v3, cornerBuffer)

        mesh:AddTriangle(vid3, vid2, vid1)
        tCount += 1
    end
end

return Renderer
