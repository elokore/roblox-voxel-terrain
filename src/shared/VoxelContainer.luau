--!strict
-- < Types > --
type VoxelContainerMeta = {
    __index: VoxelContainerMeta,
    GetLowLodVoxelPos: (self: VoxelContainer, pos: Vector3, levelsLower: number?) -> Vector3,
    GetHighLodVoxelPos: (self: VoxelContainer, pos: Vector3, levelsHigher: number?) -> Vector3,
    StoreVertexId: (self: VoxelContainer, vertexId: number, vertexLocation: number, voxelPos: Vector3, lod: number) -> (),
    RemoveVertexId: (self: VoxelContainer, vertexLocation: number, voxelPos: Vector3, lod: number) -> (),
}

export type VoxelContainer = typeof(setmetatable(
    {} :: {
        LevelsOfDetail: number,
        _vertexStorage: { [number]: { [Vector3]: { number } } },
    },
    {} :: VoxelContainerMeta
))

-- < Variables > --
local VoxelContainer = {}
local VoxelContainerInstance = {}
VoxelContainerInstance.__index = VoxelContainerInstance

function VoxelContainer.new(levelsOfDetail: number): VoxelContainer
    local self: VoxelContainer = setmetatable({
        LevelsOfDetail = levelsOfDetail,
        _vertexStorage = {},
    }, VoxelContainerInstance)

    for x = 1, levelsOfDetail do
        self._vertexStorage[x] = {}
    end

    return self
end

--[=[
    Converts the voxel position to the position of the equivalent voxel in a lower level of detail
    @param pos Vector3 Voxel position to convert
    @param levelsLower number? How many levels of detail lower to convert (Defaults to 1)
    @return The position of the voxel in a lower level of detail
]=]
function VoxelContainerInstance:GetLowLodVoxelPos(pos: Vector3, levelsLower: number?): Vector3
    return pos / (2 ^ (levelsLower or 1))
end

--[=[
    Converts the voxel position to the position of one of its child voxels at a higher level of detail.
    One voxel can fit 8 smaller voxels of one resolution higher inside of itself. The position returned it the position of
    the voxel that fits in corner 0 of the voxel

    @param pos Vector3 Voxel position to convert
    @param levelsHigher number? How many levels of detail higher to convert (Defaults to 1)
    @return The position of the child voxel that fits in corner 0 of the parent
]=]
function VoxelContainerInstance:GetHighLodVoxelPos(pos: Vector3, levelsHigher: number?): Vector3
    return pos * (2 ^ (levelsHigher or 1))
end

--[=[
    Stores the ID of a vertex from an EditableMesh at the vertex location of a voxel. Vertex IDs are stored
    this way so we know which vertices to reuse during triangulation

    @param vertexId number An ID of a vertex from an EditableMesh
    @param vertexLocation number Between 0 and 3. Indexes an edge on a voxel where new vertices can be created and reused
    @param voxelPos Vector3 Postion of the voxel
    @param lod number The level of detail of the voxel
]=]
function VoxelContainerInstance:StoreVertexId(vertexId: number, vertexLocation: number, voxelPos: Vector3, lod: number)
    assert(lod >= 1 and lod <= self.LevelsOfDetail, `'lod' must be between 1 and {self.LevelsOfDetail}`)
    assert(vertexLocation >= 0 and vertexLocation <= 3, "'vertexLocation' must be between 0 and 3")
    if not self._vertexStorage[lod][voxelPos] then self._vertexStorage[lod][voxelPos] = {} end

    self._vertexStorage[lod][voxelPos][vertexLocation] = vertexId
end

--[=[
    Removes a vertex ID from storage at the vertex location of the voxel

    @param vertexLocation number Between 0 and 3. If -1 is provided, all vertices stored for this voxel will be removed
    @param voxelPos Vector3 Position of the voxel
    @param lod number The level of detail of the voxel
]=]
function VoxelContainerInstance:RemoveVertexId(vertexLocation: number, voxelPos: Vector3, lod: number)
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
end

return VoxelContainer
