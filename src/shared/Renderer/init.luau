--!strict
-- < Services > --
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- < Imports > --
local TerrainCollider = require(script.TerrainCollider)
local TriangleDrawer = require(script.TriangleDrawer)
local TriTables = require(script.Triangulations)
local GeometryContainer = require(ReplicatedStorage.Shared.GeometryContainer)
local Types = require(script.Types)

-- < Types > --
type CollisionFace = Types.CollisionFace
type CellData = TriTables.CellData
type GeometryContainer = GeometryContainer.GeometryContainer
export type Renderer = Types.Renderer
type RenderState = Types.RenderState
type Collider = Types.TerrainCollider

-- < Variables > --
local PLANET_RADIUS: number = 20000
local RENDER_RADIUS: number = 750
local VOXEL_CLEANUP_PER_FRAME: number = 500
local VOXELS_RENDER_PER_FRAME: number = 500
local VOXELS_PROCESS_PER_FRAME: number = 5000
local SUBDIVIDE_VOXEL_DIST: number = 10
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

local function getNonParallelVector(v: vector): vector
    if math.abs(v.x) > math.abs(v.z) then
        return vector.create(-v.y, v.x, 0)
    else
        return vector.create(0, -v.z, v.y)
    end
end

local function getVoxelWorldPosition(voxel: vector, voxelSize: number, renderAreaPos: vector): vector
    local halfSize: number = voxelSize / 2
    return renderAreaPos + vector.create(halfSize, halfSize, halfSize) + voxel * vector.create(voxelSize, voxelSize, voxelSize)
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
        bit32.band(bit32.rshift(directionCode, 1), 1) -- Z isnt negated because in roblox -Z is the forward direction
    )

    return direction, reuseIndex
end

local sampleCornerBuffer: { number } = {}

local function sampleVoxelCorners(voxel: vector, voxelSize: number, renderAreaPos: vector): { number }
    local voxelPos: vector = getVoxelWorldPosition(voxel, voxelSize, renderAreaPos)
    local halfSize: number = voxelSize / 2

    for i: number = 0, 7 do
        local mask: vector = CORNER_MASK[i]
        local cornerPos: vector = voxelPos + mask * halfSize
        local scaledPos: vector = cornerPos * 1 / 200

        sampleCornerBuffer[i] = PLANET_RADIUS - vector.magnitude(cornerPos) + math.noise(scaledPos.x, scaledPos.y, scaledPos.z) * 50
    end

    return sampleCornerBuffer
end

local function cleanupVoxel(
    voxel: vector,
    lod: number,
    voxelSize: number,
    renderAreaPos: vector,
    geo: GeometryContainer,
    mesh: EditableMesh,
    recycleVerts: { number }
)
    local faceList: { number }? = geo._faceStorage[lod][voxel]
    if not faceList then return end

    local caseCode: number = geo._codeStorage[lod][voxel]
    local cellClass: number = TriTables.regularCellClass[caseCode]
    local cellData: CellData = TriTables.regularCellData[cellClass]
    local vertexData: { number } = TriTables.regularVertexData[caseCode]
    local cornerSamples: { number } = sampleVoxelCorners(voxel, voxelSize, renderAreaPos)

    for i: number, faceId: number in faceList do
        mesh:RemoveFace(faceId)

        local tIndex: number = 1 + (i - 1) * 3
        local v1: number = vertexData[cellData.vertexIndex[tIndex]]
        local v2: number = vertexData[cellData.vertexIndex[tIndex + 1]]
        local v3: number = vertexData[cellData.vertexIndex[tIndex + 2]]

        local v1Dir: vector, v1Index: number = getDirectionForVertexOwner(v1, cornerSamples)
        local v2Dir: vector, v2Index: number = getDirectionForVertexOwner(v2, cornerSamples)
        local v3Dir: vector, v3Index: number = getDirectionForVertexOwner(v3, cornerSamples)

        local v1Voxel: vector = voxel + v1Dir
        local v2Voxel: vector = voxel + v2Dir
        local v3Voxel: vector = voxel + v3Dir

        local v1ID: number? = if geo._vertexStorage[lod][v1Voxel] then geo._vertexStorage[lod][v1Voxel][v1Index] else nil
        local v2ID: number? = if geo._vertexStorage[lod][v2Voxel] then geo._vertexStorage[lod][v2Voxel][v2Index] else nil
        local v3ID: number? = if geo._vertexStorage[lod][v3Voxel] then geo._vertexStorage[lod][v3Voxel][v3Index] else nil

        assert(v1ID)
        assert(v2ID)
        assert(v3ID)

        if v1ID and #mesh:GetVertexFaces(v1ID) == 0 then
            geo:RemoveVertexId(v1Index, v1Voxel, lod)
            table.insert(recycleVerts, v1ID)
        end

        if v2ID and #mesh:GetVertexFaces(v2ID) == 0 then
            geo:RemoveVertexId(v2Index, v2Voxel, lod)
            table.insert(recycleVerts, v2ID)
        end

        if v3ID and #mesh:GetVertexFaces(v3ID) == 0 then
            geo:RemoveVertexId(v3Index, v3Voxel, lod)
            table.insert(recycleVerts, v3ID)
        end
    end

    geo._codeStorage[lod][voxel] = nil
    geo:RemoveFaces(voxel, lod)
end

-- Samples the 8 corners of the voxel and calculates the casecode
local function sampleCaseCode(voxel: vector, voxelSize: number, renderAreaPos: vector): number
    return getCaseCode(sampleVoxelCorners(voxel, voxelSize, renderAreaPos))
end

local function canSubdivide(
    voxel: vector,
    voxelSize: number,
    renderAreaPos: vector,
    lod: number,
    highestLOD: number,
    globalViewerPosition: vector
): boolean
    if lod >= highestLOD then return false end
    local globalVoxelPos: vector = getVoxelWorldPosition(voxel, voxelSize, renderAreaPos)
    local distanceStuds: vector = vector.abs(globalVoxelPos - globalViewerPosition)
    local distanceVoxels: vector = distanceStuds / voxelSize

    return distanceVoxels.x <= SUBDIVIDE_VOXEL_DIST and distanceVoxels.y <= SUBDIVIDE_VOXEL_DIST and distanceVoxels.z <= SUBDIVIDE_VOXEL_DIST
    --return vector.magnitude(distanceVoxels) <= SUBDIVIDE_VOXEL_DIST
end

local function subdivideAndAddToProcessQueue(self: Renderer, voxel: vector, lod: number)
    local childLod: number = lod + 1
    local child0: vector = self.GeometryContainer:GetHighLodVoxelPos(voxel, 1)
    local child0ID: number = getVoxelID(child0, childLod)
    local child1ID: number = getVoxelID(child0 + vector.create(1, 0, 0), childLod)
    local child2ID: number = getVoxelID(child0 + vector.create(0, 0, -1), childLod)
    local child3ID: number = getVoxelID(child0 + vector.create(1, 0, -1), childLod)
    local child4ID: number = getVoxelID(child0 + vector.create(0, 1, 0), childLod)
    local child5ID: number = getVoxelID(child0 + vector.create(1, 1, 0), childLod)
    local child6ID: number = getVoxelID(child0 + vector.create(0, 1, -1), childLod)
    local child7ID: number = getVoxelID(child0 + vector.create(1, 1, -1), childLod)

    local backIndex: number = self._processBackIndex
    self._voxelsToProcess[backIndex + 1] = child0ID
    self._voxelsToProcess[backIndex + 2] = child1ID
    self._voxelsToProcess[backIndex + 3] = child2ID
    self._voxelsToProcess[backIndex + 4] = child3ID
    self._voxelsToProcess[backIndex + 5] = child4ID
    self._voxelsToProcess[backIndex + 6] = child5ID
    self._voxelsToProcess[backIndex + 7] = child6ID
    self._voxelsToProcess[backIndex + 8] = child7ID

    self._processBackIndex += 8
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
        TargetLod = 0,
        ViewerPosition = vector.zero,
        _renderArea = { Min = vector.zero, Max = vector.zero },
        _collisionParts = {},
        _collisionPartsRecycleBin = {},
        _processFrontIndex = 0,
        _processBackIndex = 0,
        _renderListFront = 0,
        _renderListBack = 0,
        _renderListLod = 1,
        _voxelsToProcess = {},
        _voxelsToCleanup = voxelsToCleanup,
        _voxelsToRender = voxelsToRender,
        _recycleVertices = {},
        _recycleFaces = {},
        _mesh = AssetService:CreateEditableMesh(),
        _voxelSizes = voxelSizes,
        _meshPart = nil,
        _renderStep = renderStep,
        _processX = 0,
        _processY = 0,
        _processZ = 0,
    }, RendererInstance)

    renderStep = RunService.Heartbeat:Connect(function()
        local count: number = 0
        local renderAreaPos: vector = vector.create(self.RenderAreaCFrame.X, self.RenderAreaCFrame.Y, self.RenderAreaCFrame.Z)

        if self.State == "Processing" then
            debug.profilebegin("Processing")
            local processCount: number = 0
            local resumeX: number = self._processX
            local resumeY: number = self._processY
            local resumeZ: number = self._processZ
            local isResuming: boolean = true

            for y = resumeY, self._renderArea.Max.y do
                self._processY = y
                local zStart: number = if isResuming then resumeZ else self._renderArea.Max.z

                for z = zStart, self._renderArea.Min.z, -1 do
                    self._processZ = z
                    local xStart: number = if isResuming then resumeX else self._renderArea.Min.x
                    isResuming = false

                    for x = xStart, self._renderArea.Max.x do
                        self._processX = x
                        local v: vector = vector.create(x, y, z)

                        if self._processFrontIndex == 0 and self._processBackIndex == 0 then
                            table.insert(self._voxelsToProcess, getVoxelID(v, self.TargetLod))
                            self._processFrontIndex = 1
                            self._processBackIndex = 1
                        end

                        local maxIterations: number = VOXELS_PROCESS_PER_FRAME - processCount
                        for _ = 1, maxIterations do
                            local voxelID: number = self._voxelsToProcess[self._processFrontIndex]
                            local voxel: vector, lod: number = getVoxelFromID(voxelID)
                            local thisVoxelSize: number = self._voxelSizes[lod]
                            local voxelWorldPos: vector = getVoxelWorldPosition(voxel, thisVoxelSize, renderAreaPos)
                            local dist: number = vector.magnitude(voxelWorldPos - self.ViewerPosition)

                            if canSubdivide(voxel, thisVoxelSize, renderAreaPos, lod, 10, self.ViewerPosition) then
                                subdivideAndAddToProcessQueue(self, voxel, lod)
                            elseif not self.GeometryContainer._faceStorage[lod][voxel] then
                                local caseCode: number = sampleCaseCode(voxel, thisVoxelSize, renderAreaPos)
                                if dist <= RENDER_RADIUS and caseCode ~= 0 and caseCode ~= 255 then
                                    table.insert(self._voxelsToRender[lod], voxel)
                                end
                            end

                            self._voxelsToProcess[self._processFrontIndex] = nil
                            self._processFrontIndex += 1
                            processCount += 1

                            local isFinishedSubdividing: boolean = self._processFrontIndex > self._processBackIndex
                            if isFinishedSubdividing then
                                self._processFrontIndex = 0
                                self._processBackIndex = 0
                                self._processX += 1 --Ensure we dont reprocess this voxel
                            end

                            if processCount >= VOXELS_PROCESS_PER_FRAME then
                                debug.profileend()
                                return
                            elseif isFinishedSubdividing then
                                break
                            end
                        end
                    end
                end
            end

            debug.profileend()

            self.State = "Rendering"
            self._renderListLod = self.TargetLod
            return
        end

        -- Render new voxels
        if self.State == "Rendering" then
            debug.profilebegin("Voxel Rendering")
            local lod: number = self._renderListLod
            local lodIsEmpty: boolean = true
            count = 0

            local voxelList: { vector } = self._voxelsToRender[math.min(lod, 10)]
            for i: number = #voxelList, 1, -1 do
                lodIsEmpty = false
                local voxel: vector = voxelList[i]

                self:RenderVoxel(voxel, lod)
                table.remove(voxelList, i)
                count += 1

                if count >= VOXELS_RENDER_PER_FRAME then break end
            end

            local finishedRendering: boolean = lodIsEmpty and lod > 11
            if lodIsEmpty then
                self.State = "Recycling"
                self._renderListLod += 1
            end

            if finishedRendering then
                self.State = "Idle"
                self._mesh:RemoveUnused()
                table.clear(self._recycleVertices)

                if not self._meshPart and self.GeometryContainer.FaceCount > 0 then
                    task.defer(function()
                        local part: MeshPart = AssetService:CreateMeshPartAsync(Content.fromObject(self._mesh))
                        part.Material = Enum.Material.Grass
                        part.BrickColor = BrickColor.new("Parsley green")
                        part.Anchored = true
                        part.CanCollide = false
                        part.Parent = workspace
                        self._meshPart = part
                        print("Created mesh part")
                    end)
                end
            end
            debug.profileend()
        end

        -- Voxel cleanup
        if self.State == "Recycling" then
            debug.profilebegin("Recycling")
            local isEmpty: boolean = true
            local lod: number = self._renderListLod - 2

            local voxelSize: number = self._voxelSizes[lod]
            local voxelList: { vector } = self._voxelsToCleanup[lod] or {}

            for i: number = #voxelList, 1, -1 do
                isEmpty = false
                local voxel: vector = voxelList[i]
                cleanupVoxel(voxel, lod, voxelSize, renderAreaPos, self.GeometryContainer, self._mesh, self._recycleVertices)
                table.remove(voxelList, i)
                count += 1

                if count >= VOXEL_CLEANUP_PER_FRAME then
                    debug.profileend()
                    return
                end
            end

            if count >= VOXEL_CLEANUP_PER_FRAME then
                debug.profileend()
                return
            end

            if isEmpty then self.State = "Rendering" end
            debug.profileend()
        end
    end)

    return self
end

function RendererInstance:GetRenderAreaBoundingBox(areaCenter: vector, lod: number): (vector, vector)
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

    local minVoxel: vector = self:GetNearestVoxel(boxMin, lod)
    local maxVoxel: vector = self:GetNearestVoxel(boxMax, lod)
    local size: vector = maxVoxel - minVoxel
    local sizeError: vector = vector.max(vector.create(4, 4, 4) - size, vector.zero)

    maxVoxel += sizeError
    minVoxel -= sizeError

    return minVoxel, maxVoxel
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
        return vid, "Stored"
    else
        local newVid: number = 0
        local recycleBinSize: number = #self._recycleVertices
        local from

        if recycleBinSize > 0 then
            newVid = self._recycleVertices[recycleBinSize]
            table.remove(self._recycleVertices, recycleBinSize)
            from = "RecycleBin"
        else
            newVid = self._mesh:AddVertex(Vector3.new(vertexPos.x, vertexPos.y, vertexPos.z))
            from = "NewVertex"
        end

        self._mesh:SetPosition(newVid, Vector3.new(vertexPos.x, vertexPos.y, vertexPos.z))
        self.GeometryContainer:StoreVertexId(newVid, reuseIndex, vertexOwnerVoxel, lod)
        return newVid, from
    end
end

-- local lodColors = {}
-- for i = 1, 10 do
--     lodColors[i] = BrickColor.random()
-- end

--[=[
    @param voxel vector -- The location of the voxel grid position within the specified LOD
    @param lod number -- The level of detail of the voxel
]=]
function RendererInstance:RenderVoxel(voxel: vector, lod: number, collider: Collider?): number
    local mesh: EditableMesh = self._mesh
    local voxelSize: number = self._voxelSizes[lod]
    local halfSize: number = voxelSize / 2
    local renderAreaPos: vector =
        vector.create(self.RenderAreaCFrame.Position.X, self.RenderAreaCFrame.Position.Y, self.RenderAreaCFrame.Position.Z)
    local voxelPos: vector = getVoxelWorldPosition(voxel, voxelSize, renderAreaPos)
    local cornerBuffer: { number } = sampleVoxelCorners(voxel, voxelSize, renderAreaPos)
    local caseCode: number = getCaseCode(cornerBuffer)
    if caseCode == 0 or caseCode == 255 then return caseCode end

    local cellClass: number = TriTables.regularCellClass[caseCode]
    local cellData: CellData = TriTables.regularCellData[cellClass]
    local vertexData: { number } = TriTables.regularVertexData[caseCode]

    self.GeometryContainer._codeStorage[lod][voxel] = caseCode
    assert(self.GeometryContainer._faceStorage[lod][voxel] == nil or collider, "Attempt to render over an existing voxel")

    for x: number = 1, #cellData.vertexIndex, 3 do
        local v1: number = vertexData[cellData.vertexIndex[x]]
        local v2: number = vertexData[cellData.vertexIndex[x + 1]]
        local v3: number = vertexData[cellData.vertexIndex[x + 2]]

        local v1Pos: vector = voxelPos + getVertexPositionSmooth(v1, cornerBuffer) * halfSize
        local v2Pos: vector = voxelPos + getVertexPositionSmooth(v2, cornerBuffer) * halfSize
        local v3Pos: vector = voxelPos + getVertexPositionSmooth(v3, cornerBuffer) * halfSize

        if collider then
            local triangleNumber: number = (x // 3) + 1
            local recycledFace: CollisionFace? = collider:RecycleFace()
            local collisionFace: CollisionFace = TriangleDrawer.DrawTriangle(v1Pos, v2Pos, v3Pos, Enum.Material.SmoothPlastic, recycledFace)
            collisionFace.Parent = collider.Container

            local colFaceId: number = collider:GetCollisionFaceId(voxel, triangleNumber)
            collider.RenderedFaces[colFaceId] = collisionFace
        else
            local vid1: number = self:GetVertexId(voxel, lod, v1Pos, v1, cornerBuffer)
            local vid2: number = self:GetVertexId(voxel, lod, v2Pos, v2, cornerBuffer)
            local vid3: number = self:GetVertexId(voxel, lod, v3Pos, v3, cornerBuffer)

            local faceId: number = mesh:AddTriangle(vid3, vid2, vid1)
            self.GeometryContainer:StoreFaceId(faceId, voxel, lod)
        end
    end

    return caseCode
end

function RendererInstance:RenderAtLocation(position: vector): boolean
    if self.State ~= "Idle" then return false end

    local startingLOD: number = 6
    local posOnPlanet: vector = (position / vector.magnitude(position)) * PLANET_RADIUS
    local renderMin: vector, renderMax: vector = self:GetRenderAreaBoundingBox(posOnPlanet, startingLOD)
    self._renderArea.Min = renderMin
    self._renderArea.Max = renderMax
    local renderAreaPos: vector = vector.create(self.RenderAreaCFrame.X, self.RenderAreaCFrame.Y, self.RenderAreaCFrame.Z)

    print("RenderMin:", renderMin, "RenderMax", renderMax)
    local cleanCount: number = 0

    --Find voxels we can cleanup for all relevant LODs
    for lod: number = startingLOD, 10 do
        local voxelSize: number = self._voxelSizes[lod]

        for voxel: vector, faces: { number } in self.GeometryContainer._faceStorage[lod] do
            local voxelWorldPos: vector = getVoxelWorldPosition(voxel, voxelSize, renderAreaPos)
            local dist: number = vector.magnitude(voxelWorldPos - posOnPlanet)
            local inBounds: boolean = dist <= RENDER_RADIUS

            local parentVoxel: vector = self.GeometryContainer:GetLowLodVoxelPos(voxel, 1)
            local parentVoxelSize: number = self._voxelSizes[lod - 1]
            local canParentSubdivide: boolean = canSubdivide(parentVoxel, parentVoxelSize, renderAreaPos, lod - 1, 10, posOnPlanet)
            local canBeSubdivided: boolean = canSubdivide(voxel, voxelSize, renderAreaPos, lod, 10, posOnPlanet)
            local shouldCleanup: boolean = not inBounds or canBeSubdivided or not canParentSubdivide

            if shouldCleanup then
                --BinaryArray.BinaryInsert(self._voxelsToCleanup[lod], voxel, voxelEval)
                cleanCount += 1
                table.insert(self._voxelsToCleanup[lod], voxel)
            end
        end
    end

    print("VoxelsToClean:", cleanCount)

    self._processX = renderMin.x
    self._processY = renderMin.y
    self._processZ = renderMax.z

    self.ViewerPosition = posOnPlanet
    self.TargetLod = startingLOD
    self.State = "Processing"

    return true
end

return Renderer
