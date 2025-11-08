--!strict
-- < Services > --
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- < Imports > --
local TriTables = require(script.Triangulations)
local GeometryContainer = require(ReplicatedStorage.Shared.GeometryContainer)

-- < Types > --
type CellData = TriTables.CellData
type GeometryContainer = GeometryContainer.GeometryContainer

type RendererMeta = {
    __index: RendererMeta,
    RenderVoxel: (self: Renderer, voxel: vector, lod: number, cornerBuffer: { number }) -> number,
    GetVertexId: (self: Renderer, voxel: vector, lod: number, vertexPos: vector, vertex: number, cornerBuffer: { number }) -> number,
    GetNearestVoxel: (self: Renderer, globalPosition: vector, lod: number) -> vector,
    RenderAtLocation: (self: Renderer, position: vector) -> boolean,
}

export type RenderState = "Idle" | "Recycling" | "Rendering" | "Processing"
export type Renderer = typeof(setmetatable(
    {} :: {
        VoxelSize: number,
        RenderAreaCFrame: CFrame,
        GeometryContainer: GeometryContainer,
        State: RenderState,
        TargetVoxel: vector,
        TargetLod: number,
        _voxelsToCleanup: { [number]: { vector } },
        _voxelsToRender: { [number]: { vector } },
        _recycleVertices: { number },
        _mesh: EditableMesh,
        _meshPart: MeshPart?,
        _voxelSizes: { number },
        _renderStep: RBXScriptConnection,
        _processX: number,
        _processY: number,
        _processZ: number,
    },
    {} :: RendererMeta
))

-- < Variables > --
local PLANET_RADIUS: number = 20000
local CHUNK_SIZE: number = 20
local VOXEL_CLEANUP_PER_FRAME: number = 500
local VOXELS_RENDER_PER_FRAME: number = 500
local VOXELS_PROCESS_PER_FRAME: number = 10000
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

--[[
    Gets the direction to move in to find the voxel that owns this vertex.
    @return (vector, number) -- The direction as a vector and the index in the voxel where the vertex is stored
]]
local function getDirectionForVertexOwner(vertex: number, cornerBuffer: { number }?): (vector, number)
    local reuseData: number = bit32.rshift(vertex, 8)
    local reuseIndex: number = bit32.band(reuseData, 0x0F)
    local directionCode: number = bit32.rshift(reuseData, 4)
    local zeroCornerIndex: number = -1

    if cornerBuffer then
        local lowEndpointCornerIndex: number = bit32.rshift(bit32.band(vertex, 0xF0), 4)
        local highEndpointCornerIndex: number = bit32.band(vertex, 0x0F)
        if cornerBuffer[lowEndpointCornerIndex] == 0 then
            zeroCornerIndex = lowEndpointCornerIndex
        elseif cornerBuffer[highEndpointCornerIndex] == 0 then
            zeroCornerIndex = highEndpointCornerIndex
        end
    end

    -- If the vertex lies exactly at a corner instead of along an edge
    -- And it lies on a corner other than corner 7, then invert the direction code
    -- to find the voxel that owns the vertex
    if zeroCornerIndex >= 0 and zeroCornerIndex ~= 7 then
        directionCode = bit32.bxor(directionCode, 7)
        reuseIndex = 0
    end

    local direction: vector = vector.create(
        -bit32.band(directionCode, 1),
        -bit32.band(bit32.rshift(directionCode, 2), 1),
        bit32.band(bit32.rshift(directionCode, 1), 1)
    )

    return direction, reuseIndex
end

local function cleanupVoxel(voxel: vector, lod: number, geo: GeometryContainer, mesh: EditableMesh, recycleVerts: { number })
    local faceList: { number }? = geo._faceStorage[lod][voxel]
    if not faceList then return end

    local caseCode: number = geo._codeStorage[lod][voxel]
    local cellClass: number = TriTables.regularCellClass[caseCode]
    local cellData: CellData = TriTables.regularCellData[cellClass]
    local vertexData: { number } = TriTables.regularVertexData[caseCode]

    for i: number, faceId: number in faceList do
        mesh:RemoveFace(faceId)

        local tIndex: number = 1 + (i - 1) * 3
        local v1: number = vertexData[cellData.vertexIndex[tIndex]]
        local v2: number = vertexData[cellData.vertexIndex[tIndex + 1]]
        local v3: number = vertexData[cellData.vertexIndex[tIndex + 2]]

        local v1Dir: vector, v1Index: number = getDirectionForVertexOwner(v1)
        local v2Dir: vector, v2Index: number = getDirectionForVertexOwner(v2)
        local v3Dir: vector, v3Index: number = getDirectionForVertexOwner(v3)

        local v1Voxel: vector = voxel + v1Dir
        local v2Voxel: vector = voxel + v2Dir
        local v3Voxel: vector = voxel + v3Dir

        local v1ID: number = if geo._vertexStorage[lod][v1Voxel] then geo._vertexStorage[lod][v1Voxel][v1Index] else 0
        local v2ID: number = if geo._vertexStorage[lod][v2Voxel] then geo._vertexStorage[lod][v2Voxel][v2Index] else 0
        local v3ID: number = if geo._vertexStorage[lod][v3Voxel] then geo._vertexStorage[lod][v3Voxel][v3Index] else 0

        if v1ID and v1ID ~= 0 and #mesh:GetVertexFaces(v1ID) == 0 then
            geo:RemoveVertexId(v1Index, v1Voxel, lod)
            table.insert(recycleVerts, v1ID)
        end

        if v2ID and v2ID ~= 0 and #mesh:GetVertexFaces(v2ID) == 0 then
            geo:RemoveVertexId(v2Index, v2Voxel, lod)
            table.insert(recycleVerts, v2ID)
        end

        if v3ID and v3ID ~= 0 and #mesh:GetVertexFaces(v3ID) == 0 then
            geo:RemoveVertexId(v3Index, v3Voxel, lod)
            table.insert(recycleVerts, v3ID)
        end
    end

    geo._codeStorage[lod][voxel] = nil
    geo:RemoveFaces(voxel, lod)
end

function Renderer.new(voxelSize: number, highestLOD: number, renderAreaCFrame: CFrame): Renderer
    local voxelSizes: { number } = {}
    local voxelsToCleanup: { [number]: { vector } } = {}
    local voxelsToRender: { [number]: { vector } } = {}
    for x = 1, highestLOD do
        voxelSizes[x] = voxelSize * (2 ^ (highestLOD - x))
        voxelsToCleanup[x] = {}
        voxelsToRender[x] = {}
    end

    local renderStep: RBXScriptConnection = nil
    local self: Renderer = setmetatable({
        VoxelSize = voxelSize,
        RenderAreaCFrame = renderAreaCFrame,
        GeometryContainer = GeometryContainer.new(highestLOD),
        State = "Idle" :: RenderState,
        TargetVoxel = vector.zero,
        TargetLod = 0,
        _voxelsToCleanup = voxelsToCleanup,
        _voxelsToRender = voxelsToRender,
        _recycleVertices = {},
        _mesh = AssetService:CreateEditableMesh(),
        _voxelSizes = voxelSizes,
        _meshPart = nil,
        _renderStep = renderStep,
        _processX = 0,
        _processY = 0,
        _processZ = 0,
    }, RendererInstance)

    local cornerBuffer: { number } = {}
    renderStep = RunService.Heartbeat:Connect(function(dt: number)
        local count: number = 0

        if self.State == "Processing" then
            debug.profilebegin("Processing")
            local processCount: number = 0
            local resumeX: number = self._processX
            local resumeY: number = self._processY
            local resumeZ: number = self._processZ
            local renderAreaPos: vector = vector.create(self.RenderAreaCFrame.X, self.RenderAreaCFrame.Y, self.RenderAreaCFrame.Z)
            local voxelSize: number = self._voxelSizes[self.TargetLod]
            local halfSize: number = voxelSize / 2
            local isResuming: boolean = true

            for y = resumeY, CHUNK_SIZE do
                self._processY = y
                local zStart: number = if isResuming then resumeZ else CHUNK_SIZE

                for z = zStart, -CHUNK_SIZE, -1 do
                    self._processZ = z
                    local xStart: number = if isResuming then resumeX else -CHUNK_SIZE
                    isResuming = false

                    for x = xStart, CHUNK_SIZE do
                        self._processX = x + 1
                        processCount += 1

                        local v: vector = self.TargetVoxel + vector.create(x, y, z)
                        if self.GeometryContainer._faceStorage[self.TargetLod][v] then
                            if processCount >= VOXELS_PROCESS_PER_FRAME then
                                debug.profileend()
                                return
                            end
                            continue
                        end

                        local voxelPos: vector = v * voxelSize
                        for i: number = 0, 7 do
                            local mask: vector = CORNER_MASK[i]
                            local cornerPos: vector = voxelPos + mask * halfSize

                            cornerPos += renderAreaPos
                            cornerBuffer[i] = PLANET_RADIUS - vector.magnitude(cornerPos)
                        end

                        local caseCode: number = getCaseCode(cornerBuffer)
                        if caseCode ~= 0 and caseCode ~= 255 then table.insert(self._voxelsToRender[self.TargetLod], v) end

                        if processCount >= VOXELS_PROCESS_PER_FRAME then
                            debug.profileend()
                            return
                        end
                    end
                end
            end

            debug.profileend()
            self.State = "Recycling"
        end

        -- Voxel cleanup
        if self.State == "Recycling" then
            debug.profilebegin("Recycling")
            local isEmpty: boolean = true

            for lod: number, voxelList: { vector } in voxelsToCleanup do
                for i: number = #voxelList, 1, -1 do
                    isEmpty = false
                    local voxel: vector = voxelList[i]
                    cleanupVoxel(voxel, lod, self.GeometryContainer, self._mesh, self._recycleVertices)
                    table.remove(voxelList, i)
                    count += 1

                    if count >= VOXEL_CLEANUP_PER_FRAME then break end
                end

                if count >= VOXEL_CLEANUP_PER_FRAME then break end
            end

            if isEmpty then self.State = "Rendering" end
            debug.profileend()
        end

        -- Render new voxels
        if self.State == "Rendering" then
            debug.profilebegin("Voxel Rendering")
            local renderIsEmpty: boolean = true
            count = 0

            for lod: number, voxelList: { vector } in voxelsToRender do
                for i: number = #voxelList, 1, -1 do
                    renderIsEmpty = false
                    local voxel: vector = voxelList[i]
                    self:RenderVoxel(voxel, lod, cornerBuffer)
                    table.remove(voxelList, i)
                    count += 1

                    if count >= VOXELS_RENDER_PER_FRAME then break end
                end

                if count >= VOXELS_RENDER_PER_FRAME then break end
            end

            if renderIsEmpty then
                self.State = "Idle"
                self._mesh:RemoveUnused()
                table.clear(self._recycleVertices)

                if not self._meshPart and self.GeometryContainer.FaceCount > 0 then
                    task.defer(function()
                        local part: MeshPart = AssetService:CreateMeshPartAsync(Content.fromObject(self._mesh))
                        part.Anchored = true
                        part.Parent = workspace
                        self._meshPart = part
                        print("Created mesh part")
                    end)
                end
            end
            debug.profileend()
        end
    end)

    return self
end

function RendererInstance:GetNearestVoxel(globalPosition: vector, lod: number): vector
    local rp: Vector3 = self.RenderAreaCFrame:PointToObjectSpace(Vector3.new(globalPosition.x, globalPosition.y, globalPosition.z))
    local relativePos: vector = vector.create(rp.X, rp.Y, rp.Z)
    local voxelSize: number = self._voxelSizes[lod]

    local voxel: vector = vector.floor((relativePos / voxelSize))

    return voxel
end

function RendererInstance:GetVertexId(voxel: vector, lod: number, vertexPos: vector, vertex: number, cornerBuffer: { number }): number
    local direction: vector, reuseIndex: number = getDirectionForVertexOwner(vertex, cornerBuffer)
    local vertexOwnerVoxel: vector = voxel + direction
    local vid: number? = self.GeometryContainer:GetVertexId(reuseIndex, vertexOwnerVoxel, lod)

    if vid then
        return vid
    else
        local newVid: number = 0
        local recycleBinSize: number = #self._recycleVertices

        if recycleBinSize > 0 then
            newVid = self._recycleVertices[recycleBinSize]
            self._mesh:SetPosition(newVid, Vector3.new(vertexPos.x, vertexPos.y, vertexPos.z))
            table.remove(self._recycleVertices, recycleBinSize)
        else
            newVid = self._mesh:AddVertex(Vector3.new(vertexPos.x, vertexPos.y, vertexPos.z))
        end

        self.GeometryContainer:StoreVertexId(newVid, reuseIndex, vertexOwnerVoxel, lod)
        return newVid
    end
end

--[=[
    @param voxel vector -- The location of the voxel grid position within the specified LOD
    @param lod number -- The level of detail of the voxel
]=]
function RendererInstance:RenderVoxel(voxel: vector, lod: number, cornerBuffer: { number }): number
    local mesh: EditableMesh = self._mesh
    local voxelSize: number = self._voxelSizes[lod]
    local halfSize: number = voxelSize / 2
    local voxelPos: vector = voxel * voxelSize
    local renderAreaPos: vector =
        vector.create(self.RenderAreaCFrame.Position.X, self.RenderAreaCFrame.Position.Y, self.RenderAreaCFrame.Position.Z)

    for i: number = 0, 7 do
        local mask: vector = CORNER_MASK[i]
        local cornerPos: vector = voxelPos + mask * halfSize

        cornerPos += renderAreaPos
        cornerBuffer[i] = PLANET_RADIUS - vector.magnitude(cornerPos)
    end

    local caseCode: number = getCaseCode(cornerBuffer)
    local cellClass: number = TriTables.regularCellClass[caseCode]
    local cellData: CellData = TriTables.regularCellData[cellClass]
    local vertexData: { number } = TriTables.regularVertexData[caseCode]

    self.GeometryContainer._codeStorage[lod][voxel] = caseCode

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

        local faceId: number = mesh:AddTriangle(vid3, vid2, vid1)
        self.GeometryContainer:StoreFaceId(faceId, voxel, lod)
    end

    return caseCode
end

function RendererInstance:RenderAtLocation(position: vector): boolean
    if self.State ~= "Idle" then return false end

    local lod: number = 5
    local posOnPlanet: vector = (position / vector.magnitude(position)) * PLANET_RADIUS
    local targetVoxel: vector = self:GetNearestVoxel(posOnPlanet, lod)
    print("Target Voxel:", targetVoxel)

    --Find voxels we can cleanup
    for voxel: vector, faces: { number } in self.GeometryContainer._faceStorage[lod] do
        local dist: vector = vector.abs(targetVoxel - voxel)
        local inBounds: boolean = dist.x <= CHUNK_SIZE and dist.y <= CHUNK_SIZE and dist.z <= CHUNK_SIZE
        if inBounds then continue end

        table.insert(self._voxelsToCleanup[lod], voxel)
    end

    self._processX = -CHUNK_SIZE
    self._processY = -CHUNK_SIZE
    self._processZ = CHUNK_SIZE

    self.TargetVoxel = targetVoxel
    self.TargetLod = lod

    self.State = "Processing"
    return true
end

return Renderer
