--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GeometryContainer = require(ReplicatedStorage.Shared.GeometryContainer)
local Promise = require(ReplicatedStorage.Packages.Promise)

type Promise<T...> = Promise.TypedPromise<T...>
export type GeometryContainer = GeometryContainer.GeometryContainer
export type CollisionFace = Model & {
    Wedge1: WedgePart,
    Wedge2: WedgePart,
}

type VoxelRendererMeta = {
    __index: VoxelRendererMeta,
    Render: (
        self: VoxelRenderer,
        renderList: { [number]: { vector } },
        cleaningList: { [number]: { vector } },
        renderFirstList: { [number]: { vector } },
        startLOD: number
    ) -> Promise<>,
    RenderVoxel: (self: VoxelRenderer, voxel: vector, lod: number, collider: TerrainCollider?) -> number,
    CleanupVoxel: (self: VoxelRenderer, voxel: vector, lod: number) -> (),
    GetVertexId: (self: VoxelRenderer, voxel: vector, lod: number, vertexPos: vector, vertex: number, cornerBuffer: { number }) -> number,
}

export type VoxelRenderer = typeof(setmetatable(
    {} :: {
        MaxLOD: number,
        BaseVoxelSize: number,
        TerrainCFrame: CFrame,
        TerrainPosition: vector,
        GeoContainer: GeometryContainer,
        IsRendering: boolean,
        MeshContainer: Folder,
        _voxelSizes: { number },
        _vertexRecycleBin: { number },
    },
    {} :: VoxelRendererMeta
))

type VoxelProcessorMeta = {
    __index: VoxelProcessorMeta,
    ProcessChunk: (self: VoxelProcessor, chunkMin: vector, chunkMax: vector, lod: number, viewerPosition: vector) -> Promise<>,
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
        _renderFirstList: { [number]: { vector } },
        _cleaningList: { [number]: { vector } },
    },
    {} :: VoxelProcessorMeta
))

type ColliderMeta = {
    __index: ColliderMeta,
    SetColliderSize: (self: TerrainCollider, sizeInVoxels: number, lod: number, voxelSize: number) -> (),
    GetCollisionFaceId: (self: TerrainCollider, voxel: vector, triangleNumber: number) -> number,
    GetCollisionFaceFromID: (self: TerrainCollider, id: number) -> (vector, number),
    UpdateCollider: (self: TerrainCollider, at: vector) -> (),
    RecycleFace: (self: TerrainCollider) -> CollisionFace?,
}

export type TerrainCollider = typeof(setmetatable(
    {} :: {
        Container: Folder,
        Renderer: VoxelRenderer,
        VoxelSize: number,
        Size: number,
        LOD: number,
        RecycleBin: { CollisionFace },
        RenderedFaces: { [number]: CollisionFace },
        IsUpdating: boolean,
        _storage: Folder,
    },
    {} :: ColliderMeta
))

type VoxelTerrainMeta = {
    __index: VoxelTerrainMeta,
    GetRenderAreaBoundingBox: (self: VoxelTerrain, areaCenter: vector, lod: number) -> (vector, vector),
    RenderAtLocation: (self: VoxelTerrain, position: vector) -> boolean,
}

export type VoxelTerrain = typeof(setmetatable(
    {} :: {
        VoxelSize: number,
        TerrainCFrame: CFrame,
        TerrainPosition: vector,
        IsBusy: boolean,
        MaxLOD: number,
        WorkerCount: number,
        Workers: { Actor },
        MeshContainer: Folder,
        _workerStates: { boolean },
        _voxelSizes: { number },
    },
    {} :: VoxelTerrainMeta
))

local module = {}
return module
