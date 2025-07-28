--!strict
-- < Services > --
local AssetService = game:GetService("AssetService")

-- < Imports > --
local TriTables = require(script.Triangulations)

-- < Types > --
type CellData = TriTables.CellData

type RendererMeta = {
    __index: RendererMeta,
	Render: (self: Renderer) -> (),
	_RenderVoxel: (self: Renderer, voxel: Vector3, cornerBuffer: { number }) -> (),
	_GetVertexId: (self: Renderer, voxel: Vector3, vertexPos: Vector3, vertex: number, cornerBuffer: { number }) -> number,
}

export type Renderer = typeof(setmetatable({} :: {
	VoxelSize: number,
	RenderAreaDimensions: Vector3,
	RenderAreaCFrame: CFrame,
	_mesh: EditableMesh,
	_meshPart: MeshPart?,
	_vertexMap: { [Vector3]: { number } },
}, {} :: RendererMeta))

-- < Variables > --
local CORNER_MASK: { Vector3 } = TriTables.cornerMask
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
local function getVertexPositionSmooth(v: number, cornerBuffer: { number }): Vector3
	local lowEndpoint: number = bit32.rshift(bit32.band(v, 0xF0), 4)
	local highEndpoint: number = bit32.band(v, 0x0F)

	-- Follows calculation in Figure (3.4) of Transvoxel algorithm paper
	local d0: number = cornerBuffer[lowEndpoint]
	local d1: number = cornerBuffer[highEndpoint]
	local t: number = d1 / (d1 - d0)

	local p0: Vector3 = CORNER_MASK[lowEndpoint]
	local p1: Vector3 = CORNER_MASK[highEndpoint]
	local vPos: Vector3 = t * p0 + (1 - t) * p1 

	return vPos
end

local function getVertexPosition(v: number): Vector3
	local lowEndpoint: number = bit32.rshift(bit32.band(v, 0xF0), 4)
	local highEndpoint: number = bit32.band(v, 0x0F)

	local p0: Vector3 = CORNER_MASK[lowEndpoint]
	local p1: Vector3 = CORNER_MASK[highEndpoint]
	return (p0 + p1) / 2
end

function Renderer.new(voxelSize: number, renderAreaCFrame: CFrame, renderAreaDimensions: Vector3): Renderer
	local self: Renderer = setmetatable({
		VoxelSize = voxelSize,
		RenderAreaDimensions = renderAreaDimensions,
		RenderAreaCFrame = renderAreaCFrame,
		_mesh = AssetService:CreateEditableMesh(),
		_meshPart = nil,
		_vertexMap = {},
	}, RendererInstance)

	return self
end

local vCount: number = 0
local tCount: number = 0

function RendererInstance:Render()
	local cornerBuffer: { number } = {}

	for x = 1, self.RenderAreaDimensions.X do
		for y = 1, self.RenderAreaDimensions.Y do
			for z = 1, self.RenderAreaDimensions.Z do
				local voxel: Vector3 = Vector3.new(x, y, z)
				self:_RenderVoxel(voxel, cornerBuffer)
			end
		end
	end

	print("Vertex Count:", vCount)
	print("Triangle Count:", tCount)

	if not self._meshPart then
		local part: MeshPart = AssetService:CreateMeshPartAsync(Content.fromObject(self._mesh))
		part.Anchored = true
		part.Color = Color3.fromRGB(39, 128, 27)
		part.CFrame = self.RenderAreaCFrame
		part.Name = "TerrainRender"
		part.Parent = workspace
	else
		self._meshPart.CFrame = self.RenderAreaCFrame
	end
end

function RendererInstance:_GetVertexId(voxel: Vector3, vertexPos: Vector3, vertex: number, cornerBuffer: { number }): number
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

	local direction: Vector3 = Vector3.new(
		-bit32.band(directionCode, 1),
		-bit32.band(bit32.rshift(directionCode, 2), 1),
		bit32.band(bit32.rshift(directionCode, 1), 1)
	)

	local vertexOwnerVoxel: Vector3 = voxel + direction
	if not self._vertexMap[vertexOwnerVoxel] then self._vertexMap[vertexOwnerVoxel] = {} end
	local vid: number? = self._vertexMap[vertexOwnerVoxel][reuseIndex]

	if vid then
		return vid
	else
		local newVid: number = self._mesh:AddVertex(vertexPos)
		vCount += 1
		self._vertexMap[vertexOwnerVoxel][reuseIndex] = newVid
		return newVid
	end
end

function RendererInstance:_RenderVoxel(voxel: Vector3, cornerBuffer: { number })
	local mesh: EditableMesh = self._mesh
	local voxelPos: Vector3 = voxel * self.VoxelSize
	local halfSize: number = self.VoxelSize / 2

	for i: number = 0, 7 do
		local mask: Vector3 = CORNER_MASK[i]
		local cornerPos: Vector3 = voxelPos + mask * self.VoxelSize / 2
		cornerPos += self.RenderAreaCFrame.Position
		local scaled: Vector3 = cornerPos  * 1/200
		cornerBuffer[i] = math.noise(scaled.X, scaled.Y, scaled.Z)
	end

	local caseCode: number = getCaseCode(cornerBuffer)
	local cellClass: number = TriTables.regularCellClass[caseCode]
	local cellData: CellData = TriTables.regularCellData[cellClass]
	local vertexData: { number } = TriTables.regularVertexData[caseCode]

	for x: number = 1, #cellData.vertexIndex, 3 do
		local v1: number = vertexData[cellData.vertexIndex[x]]
		local v2: number = vertexData[cellData.vertexIndex[x + 1]]
		local v3: number = vertexData[cellData.vertexIndex[x + 2]]
		
		local v1Pos: Vector3 = voxelPos + getVertexPositionSmooth(v1, cornerBuffer) * halfSize
		local v2Pos: Vector3 = voxelPos + getVertexPositionSmooth(v2, cornerBuffer) * halfSize
		local v3Pos: Vector3 = voxelPos + getVertexPositionSmooth(v3, cornerBuffer) * halfSize

		local vid1: number = self:_GetVertexId(voxel, v1Pos, v1, cornerBuffer)
		local vid2: number = self:_GetVertexId(voxel, v2Pos, v2, cornerBuffer)
		local vid3: number = self:_GetVertexId(voxel, v3Pos, v3, cornerBuffer)

		mesh:AddTriangle(vid1, vid2, vid3)
		tCount += 1
	end
end

return Renderer