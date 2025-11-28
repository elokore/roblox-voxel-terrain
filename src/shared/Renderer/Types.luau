--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GeometryContainer = require(ReplicatedStorage.Shared.GeometryContainer)

export type GeometryContainer = GeometryContainer.GeometryContainer
export type CollisionFace = Model & {
    Wedge1: WedgePart,
    Wedge2: WedgePart,
}

type ColliderMeta = {
    __index: ColliderMeta,
    SetColliderSize: (self: TerrainCollider, sizeInVoxels: number, lod: number) -> (),
    GetCollisionFaceId: (self: TerrainCollider, voxel: vector, triangleNumber: number) -> number,
    GetCollisionFaceFromID: (self: TerrainCollider, id: number) -> (vector, number),
    UpdateCollider: (self: TerrainCollider, at: vector) -> (),
    RecycleFace: (self: TerrainCollider) -> CollisionFace?,
}

export type TerrainCollider = typeof(setmetatable(
    {} :: {
        Container: Folder,
        Renderer: Renderer,
        Size: number,
        LOD: number,
        RecycleBin: { CollisionFace },
        RenderedFaces: { [number]: CollisionFace },
        IsUpdating: boolean,
        _storage: Folder,
    },
    {} :: ColliderMeta
))

type RendererMeta = {
    __index: RendererMeta,
    RenderVoxel: (self: Renderer, voxel: vector, lod: number, collider: TerrainCollider?) -> number,
    GetVertexId: (self: Renderer, voxel: vector, lod: number, vertexPos: vector, vertex: number, cornerBuffer: { number }) -> number,
    GetNearestVoxel: (self: Renderer, globalPosition: vector, lod: number) -> vector,
    GetRenderAreaBoundingBox: (self: Renderer, areaCenter: vector, lod: number) -> (vector, vector),
    RenderAtLocation: (self: Renderer, position: vector) -> boolean,
}

export type RenderState = "Idle" | "Recycling" | "Rendering" | "Processing"
export type Renderer = typeof(setmetatable(
    {} :: {
        VoxelSize: number,
        RenderAreaCFrame: CFrame,
        GeometryContainer: GeometryContainer,
        State: RenderState,
        TargetLod: number,
        ViewerPosition: vector,
        _renderArea: { Min: vector, Max: vector },
        _processFrontIndex: number,
        _processBackIndex: number,
        _voxelsToProcess: { number },
        _voxelsToCleanup: { [number]: { vector } },
        _renderListLod: number,
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

local module = {}
return module
