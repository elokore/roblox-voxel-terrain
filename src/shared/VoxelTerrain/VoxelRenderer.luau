--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Helper = require(script.Parent.Helper)
local Promise = require(ReplicatedStorage.Packages.Promise)
local TriTables = require(script.Parent.Triangulations)
local Types = require(script.Parent.Types)
local TriangleDrawer = require(script.Parent.TriangleDrawer)

type CellData = TriTables.CellData
type CollisionFace = Types.CollisionFace
type GeometryContainer = Types.GeometryContainer
type Promise<T...> = Promise.TypedPromise<T...>
type TerrainCollider = Types.TerrainCollider
type VoxelRenderer = Types.VoxelRenderer

local CORNER_MASK: { vector } = TriTables.cornerMask
local PLANET_RADIUS: number = 20000
local VOXEL_CLEANUP_PER_FRAME: number = 500
local VOXELS_RENDER_PER_FRAME: number = 500

local VoxelRenderer = {}
VoxelRenderer.__index = VoxelRenderer

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

function VoxelRenderer.new(
    terrainCFrame: CFrame,
    baseVoxelSize: number,
    maxLOD: number,
    container: GeometryContainer,
    meshContainer: Folder
): VoxelRenderer
    local voxelSizes: { number } = {}
    for x: number = 1, maxLOD do
        voxelSizes[x] = baseVoxelSize * (2 ^ (maxLOD - x))
    end

    local self: VoxelRenderer = setmetatable({
        MaxLOD = maxLOD,
        BaseVoxelSize = baseVoxelSize,
        TerrainCFrame = terrainCFrame,
        TerrainPosition = vector.create(terrainCFrame.X, terrainCFrame.Y, terrainCFrame.Z),
        GeoContainer = container,
        IsRendering = false,
        MeshContainer = meshContainer,
        _vertexRecycleBin = {},
        _voxelSizes = voxelSizes,
    }, VoxelRenderer)

    return self
end

function VoxelRenderer:GetVertexId(voxel: vector, lod: number, vertexPos: vector, vertex: number, cornerBuffer: { number }): number
    local direction: vector, reuseIndex: number = getDirectionForVertexOwner(vertex, cornerBuffer)
    local vertexOwnerVoxel: vector = voxel + direction
    local vid: number? = self.GeoContainer:GetVertexId(reuseIndex, vertexOwnerVoxel, lod)

    if vid then
        return vid
    else
        local newVid: number = 0
        local recycleBinSize: number = #self._vertexRecycleBin
        local mesh: EditableMesh = self.GeoContainer.Mesh

        if recycleBinSize > 0 then
            newVid = self._vertexRecycleBin[recycleBinSize]
            table.remove(self._vertexRecycleBin, recycleBinSize)
        else
            newVid = mesh:AddVertex(Vector3.new(vertexPos.x, vertexPos.y, vertexPos.z))
        end

        mesh:SetPosition(newVid, Vector3.new(vertexPos.x, vertexPos.y, vertexPos.z))
        self.GeoContainer:StoreVertexId(newVid, reuseIndex, vertexOwnerVoxel, lod)
        return newVid
    end
end

--[=[
    @param voxel vector -- The location of the voxel grid position within the specified LOD
    @param lod number -- The level of detail of the voxel
]=]
function VoxelRenderer:RenderVoxel(voxel: vector, lod: number, collider: TerrainCollider?): number
    assert(self.GeoContainer._faceStorage[lod][voxel] == nil or collider, `Attempt to render over an existing voxel: {voxel} LOD: {lod}`)

    local mesh: EditableMesh = self.GeoContainer.Mesh
    local voxelSize: number = self._voxelSizes[lod]
    local halfSize: number = voxelSize / 2
    local terrainPos: vector = vector.create(self.TerrainCFrame.Position.X, self.TerrainCFrame.Position.Y, self.TerrainCFrame.Position.Z)
    local voxelPos: vector = Helper.GetVoxelWorldPosition(voxel, voxelSize, terrainPos)
    local cornerBuffer: { number } = Helper.SampleVoxelCorners(voxel, voxelSize, terrainPos, PLANET_RADIUS)
    local caseCode: number = Helper.GetCaseCode(cornerBuffer)
    if caseCode == 0 or caseCode == 255 then return caseCode end

    local cellClass: number = TriTables.regularCellClass[caseCode]
    local cellData: CellData = TriTables.regularCellData[cellClass]
    local vertexData: { number } = TriTables.regularVertexData[caseCode]

    self.GeoContainer._codeStorage[lod][voxel] = caseCode

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
            self.GeoContainer:StoreFaceId(faceId, voxel, lod)
        end
    end

    return caseCode
end

function VoxelRenderer:CleanupVoxel(voxel: vector, lod: number)
    local container: GeometryContainer = self.GeoContainer
    local faceList: { number }? = container._faceStorage[lod][voxel]
    if not faceList then return end

    local mesh: EditableMesh = container.Mesh
    local voxelSize: number = self._voxelSizes[lod]
    local caseCode: number = container._codeStorage[lod][voxel]
    local cellClass: number = TriTables.regularCellClass[caseCode]
    local cellData: CellData = TriTables.regularCellData[cellClass]
    local vertexData: { number } = TriTables.regularVertexData[caseCode]
    local cornerSamples: { number } = Helper.SampleVoxelCorners(voxel, voxelSize, self.TerrainPosition, PLANET_RADIUS)

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

        local v1ID: number? = if container._vertexStorage[lod][v1Voxel] then container._vertexStorage[lod][v1Voxel][v1Index] else nil
        local v2ID: number? = if container._vertexStorage[lod][v2Voxel] then container._vertexStorage[lod][v2Voxel][v2Index] else nil
        local v3ID: number? = if container._vertexStorage[lod][v3Voxel] then container._vertexStorage[lod][v3Voxel][v3Index] else nil

        assert(v1ID)
        assert(v2ID)
        assert(v3ID)

        if v1ID and #mesh:GetVertexFaces(v1ID) == 0 then
            container:RemoveVertexId(v1Index, v1Voxel, lod)
            table.insert(self._vertexRecycleBin, v1ID)
        end

        if v2ID and #mesh:GetVertexFaces(v2ID) == 0 then
            container:RemoveVertexId(v2Index, v2Voxel, lod)
            table.insert(self._vertexRecycleBin, v2ID)
        end

        if v3ID and #mesh:GetVertexFaces(v3ID) == 0 then
            container:RemoveVertexId(v3Index, v3Voxel, lod)
            table.insert(self._vertexRecycleBin, v3ID)
        end
    end

    container._codeStorage[lod][voxel] = nil
    container:RemoveFaces(voxel, lod)
end

function VoxelRenderer:Render(
    renderList: { [number]: { vector } },
    cleaningList: { [number]: { vector } },
    renderFirst: { [number]: { vector } },
    startLOD: number
): Promise<>
    if self.IsRendering then return Promise.reject("Render is already in progress") end
    self.IsRendering = true

    return Promise.new(function(resolve, reject)
        local step: RBXScriptConnection
        local currentRenderLOD: number = startLOD
        local currentCleanupLOD: number = startLOD
        local currentFirstRenderLOD: number = startLOD
        local mode: "RenderFirst" | "Render" | "Cleanup" = "RenderFirst"
        local isRenderListEmpty: boolean = false
        local isCleaningListEmpty: boolean = false

        step = RunService.Heartbeat:Connect(function()
            local processCount: number = 0

            -- Render these voxels first to cover any holes that cleaning old voxels may create
            if mode == "RenderFirst" then
                debug.profilebegin("RenderFirst")
                for lod: number = currentFirstRenderLOD, self.MaxLOD do
                    currentFirstRenderLOD = lod

                    for i: number = #renderFirst[lod], 1, -1 do
                        local voxel: vector = renderFirst[lod][i]
                        self:RenderVoxel(voxel, lod, nil)

                        table.remove(renderFirst[lod], i)
                        processCount += 1

                        if processCount >= VOXELS_RENDER_PER_FRAME then
                            debug.profileend()
                            return
                        end
                    end
                end

                debug.profileend()
                mode = "Cleanup"
            end

            if mode == "Cleanup" then
                debug.profilebegin("CleanupVoxels")
                for lod: number = currentCleanupLOD, self.MaxLOD do
                    currentCleanupLOD = lod

                    for i: number = #cleaningList[lod], 1, -1 do
                        local voxel: vector = cleaningList[lod][i]
                        self:CleanupVoxel(voxel, lod)
                        table.remove(cleaningList[lod], i)
                        processCount += 1

                        if processCount >= VOXEL_CLEANUP_PER_FRAME then
                            debug.profileend()
                            return
                        end
                    end
                end

                debug.profileend()
                isCleaningListEmpty = true
                mode = "Render"
                return
            elseif mode == "Render" then
                debug.profilebegin("RenderMain")
                for lod: number = currentRenderLOD, self.MaxLOD do
                    currentRenderLOD = lod

                    for i: number = #renderList[lod], 1, -1 do
                        local voxel: vector = renderList[lod][i]
                        self:RenderVoxel(voxel, lod, nil)

                        table.remove(renderList[lod], i)
                        processCount += 1

                        if processCount >= VOXELS_RENDER_PER_FRAME then
                            debug.profileend()
                            return
                        end
                    end
                end

                debug.profileend()
                isRenderListEmpty = true
            end

            if isRenderListEmpty and isCleaningListEmpty then
                step:Disconnect()
                self.IsRendering = false
                if not self.GeoContainer.MeshPart and self.GeoContainer.FaceCount > 0 then
                    self.GeoContainer:CreateMeshPart(self.MeshContainer)
                end

                resolve()
            end
        end)
    end)
end

return VoxelRenderer
