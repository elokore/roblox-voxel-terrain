--!strict
local AssetService = game:GetService("AssetService")

-- < Types > --
type GeometryContainerMeta = {
    __index: GeometryContainerMeta,
    GetAncestorVoxel: (self: GeometryContainer, pos: vector, levelsLower: number?) -> vector,
    GetDescendantVoxel: (self: GeometryContainer, pos: vector, levelsHigher: number?) -> vector,
    GetVertexId: (self: GeometryContainer, vertexLocation: number, voxelPos: vector, lod: number) -> number?,
    StoreVertexId: (self: GeometryContainer, vertexId: number, vertexLocation: number, voxelPos: vector, lod: number) -> (),
    RemoveVertexId: (self: GeometryContainer, vertexLocation: number, voxelPos: vector, lod: number) -> (),
    StoreFaceId: (self: GeometryContainer, faceId: number, voxel: vector, lod: number) -> (),
    RemoveFaces: (self: GeometryContainer, voxel: vector, lod: number) -> (),
    StoreCaseCode: (self: GeometryContainer, caseCode: number, voxel: vector, lod: number) -> (),
    CreateMeshPart: (self: GeometryContainer) -> MeshPart,
}

export type GeometryContainer = typeof(setmetatable(
    {} :: {
        LevelsOfDetail: number,
        VertexCount: number,
        FaceCount: number,
        Mesh: EditableMesh,
        MeshPart: MeshPart?,
        _vertexStorage: { [number]: { [vector]: { number } } },
        _faceStorage: { [number]: { [vector]: { number } } },
        _codeStorage: { [number]: { [vector]: number } },
    },
    {} :: GeometryContainerMeta
))

-- < Variables > --
local Z_CORRECTION: vector = vector.create(0, 0, 1)

local GeometryContainer = {}
GeometryContainer.__index = GeometryContainer

--[=[
    Contains the voxels at all Levels of detail and helper functions for finding voxel positions
    between different LODs. Also stores vertex IDs for reuse in triangulation
    @class GeometryContainer
]=]
function GeometryContainer.new(levelsOfDetail: number): GeometryContainer
    local self: GeometryContainer = setmetatable({
        LevelsOfDetail = levelsOfDetail,
        VertexCount = 0,
        FaceCount = 0,
        Mesh = AssetService:CreateEditableMesh(),
        MeshPart = nil,
        _vertexStorage = {},
        _faceStorage = {},
        _codeStorage = {},
    }, GeometryContainer)

    for x = 1, levelsOfDetail do
        self._vertexStorage[x] = {}
        self._faceStorage[x] = {}
        self._codeStorage[x] = {}
    end

    return self
end

function GeometryContainer:CreateMeshPart(): MeshPart
    assert(self.VertexCount > 0 and self.FaceCount > 0, "Mesh cannot be empty")
    local part: MeshPart = AssetService:CreateMeshPartAsync(Content.fromObject(self.Mesh))
    part.Material = Enum.Material.Grass
    part.BrickColor = BrickColor.new("Parsley green")
    part.Anchored = true
    part.CanCollide = false
    part.Parent = workspace
    self.MeshPart = part
    return part
end

--[=[
    Converts the voxel position to the position of the equivalent voxel in a lower level of detail
    @param pos vector -- Voxel position to convert
    @param levelsLower -- number? How many levels of detail lower to convert (Defaults to 1)
    @return The position of the voxel in a lower level of detail
    @within GeometryContainer
]=]
function GeometryContainer:GetAncestorVoxel(pos: vector, levelsLower: number?): vector
    return vector.floor(pos / (2 ^ (levelsLower or 1)))
end

--[=[
    Converts the voxel position to the position of one of its child voxels at a higher level of detail.
    One voxel can fit 8 smaller voxels of one resolution higher inside of itself. The position returned it the position of
    the voxel that fits in corner 0 of the voxel

    @param pos vector -- Voxel position to convert
    @param levelsHigher number? -- How many levels of detail higher to convert (Defaults to 1)
    @return The position of the child voxel that fits in corner 0 of the parent
    @within GeometryContainer
]=]
function GeometryContainer:GetDescendantVoxel(pos: vector, levelsHigher: number?): vector
    return pos * (2 ^ (levelsHigher or 1)) + Z_CORRECTION
end

--[=[
    Stores the ID of a vertex from an EditableMesh at the vertex location of a voxel. Vertex IDs are stored
    this way so we know which vertices to reuse during triangulation

    @param vertexId number -- An ID of a vertex from an EditableMesh
    @param vertexLocation number -- Between 0 and 3. Indexes an edge on a voxel where new vertices can be created and reused
    @param voxelPos vector -- Postion of the voxel
    @param lod number -- The level of detail of the voxel
    @within GeometryContainer
]=]
function GeometryContainer:StoreVertexId(vertexId: number, vertexLocation: number, voxelPos: vector, lod: number)
    assert(lod >= 1 and lod <= self.LevelsOfDetail, `'lod' must be between 1 and {self.LevelsOfDetail}`)
    assert(vertexLocation >= 0 and vertexLocation <= 3, "'vertexLocation' must be between 0 and 3")
    if not self._vertexStorage[lod][voxelPos] then self._vertexStorage[lod][voxelPos] = {} end

    self.VertexCount += 1
    self._vertexStorage[lod][voxelPos][vertexLocation] = vertexId
end

function GeometryContainer:GetVertexId(vertexLocation: number, voxelPos: vector, lod: number): number?
    assert(lod >= 1 and lod <= self.LevelsOfDetail, `'lod' must be between 1 and {self.LevelsOfDetail}`)
    assert(vertexLocation >= 0 and vertexLocation <= 3, "'vertexLocation' must be between 0 and 3")
    if not self._vertexStorage[lod][voxelPos] then return end

    return self._vertexStorage[lod][voxelPos][vertexLocation]
end

--[=[
    Removes a vertex ID from storage at the vertex location of the voxel

    @param vertexLocation number -- Between 0 and 3. If -1 is provided, all vertices stored for this voxel will be removed
    @param voxelPos vector -- Position of the voxel
    @param lod number -- The level of detail of the voxel
    @within GeometryContainer
]=]
function GeometryContainer:RemoveVertexId(vertexLocation: number, voxelPos: vector, lod: number)
    assert(lod >= 1 and lod <= self.LevelsOfDetail, `'lod' must be between 1 and {self.LevelsOfDetail}`)
    assert(vertexLocation >= -1 and vertexLocation <= 3, "'vertexLocation' must be between -1 and 3")

    local storage: { number }? = self._vertexStorage[lod][voxelPos]
    if not storage then return end

    if vertexLocation == -1 then
        self._vertexStorage[lod][voxelPos] = nil
    else
        storage[vertexLocation] = nil
        local areAllVerticesRemoved: boolean = not storage[0] and not storage[1] and not storage[2] and not storage[3]
        if areAllVerticesRemoved then self._vertexStorage[lod][voxelPos] = nil end
    end

    self.VertexCount -= 1
end

function GeometryContainer:StoreFaceId(faceId: number, voxelPos: vector, lod: number)
    assert(lod >= 1 and lod <= self.LevelsOfDetail, `'lod' must be between 1 and {self.LevelsOfDetail}`)
    if not self._faceStorage[lod][voxelPos] then self._faceStorage[lod][voxelPos] = {} end
    table.insert(self._faceStorage[lod][voxelPos], faceId)
    self.FaceCount += 1
end

function GeometryContainer:RemoveFaces(voxelPos: vector, lod: number)
    assert(lod >= 1 and lod <= self.LevelsOfDetail, `'lod' must be between 1 and {self.LevelsOfDetail}`)
    local faceCountInVoxel: number = #self._faceStorage[lod][voxelPos]
    self.FaceCount -= faceCountInVoxel
    self._faceStorage[lod][voxelPos] = nil
end

function GeometryContainer:StoreCaseCode(caseCode: number, voxel: vector, lod: number)
    assert(lod >= 1 and lod <= self.LevelsOfDetail, `'lod' must be between 1 and {self.LevelsOfDetail}`)
    self._codeStorage[lod][voxel] = caseCode
end

return GeometryContainer
