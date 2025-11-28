--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TriangleDrawer = require(script.Parent.TriangleDrawer)
local Types = require(script.Parent.Types)

type CollisionFace = Types.CollisionFace
type Renderer = Types.Renderer
export type TerrainCollider = Types.TerrainCollider
type TriangleModel = TriangleDrawer.TriangleModel

local VOXELS_PER_FRAME: number = 1

local TerrainCollider = {}
TerrainCollider.__index = TerrainCollider
local colliderID: number = 0

function TerrainCollider.new(renderer: Renderer): TerrainCollider
    local folder: Folder = Instance.new("Folder")
    folder.Name = `Collider{colliderID}`
    folder.Parent = workspace

    local storageFolder: Folder = Instance.new("Folder")
    storageFolder.Name = `Collider{colliderID}Storage`
    storageFolder.Parent = ReplicatedStorage

    colliderID += 1

    local self: TerrainCollider = setmetatable({
        Renderer = renderer,
        Container = folder,
        Size = 0,
        LOD = 0,
        RecycleBin = {},
        RenderedFaces = {},
        IsUpdating = false,
        _storage = storageFolder,
    }, TerrainCollider)

    return self
end

function TerrainCollider:SetColliderSize(sizeInVoxels: number, lod: number)
    assert(sizeInVoxels % 2 == 0, "Collider size must be an EVEN number")
    self.Size = sizeInVoxels
    self.LOD = lod
end

function TerrainCollider:RecycleFace(): CollisionFace?
    local binSize: number = #self.RecycleBin
    if binSize == 0 then return end

    local face: CollisionFace = self.RecycleBin[binSize]
    table.remove(self.RecycleBin, binSize)
    return face
end

function TerrainCollider:GetCollisionFaceId(voxel: vector, triangleNumber: number): number
    local sizeRangeXYZ: number = 20001
    local triRange: number = 5

    local x: number = voxel.x + 10000
    local y: number = voxel.y + 10000
    local z: number = voxel.z + 10000
    triangleNumber -= 1

    return (((x * sizeRangeXYZ + y) * sizeRangeXYZ + z) * triRange + triangleNumber)
end

function TerrainCollider:GetCollisionFaceFromID(id: number): (vector, number)
    local sizeRangeXYZ: number = 20001
    local triRange: number = 5

    local triangleIndex: number = id % triRange
    triangleIndex += 1
    id //= triRange

    local z: number = id % sizeRangeXYZ
    z -= 10000
    id //= sizeRangeXYZ

    local y: number = id % sizeRangeXYZ
    y -= 10000
    id //= sizeRangeXYZ

    local x: number = id
    x -= 10000

    return vector.create(x, y, z), triangleIndex
end

function TerrainCollider:UpdateCollider(at: vector)
    assert(self.Size ~= 0 and self.LOD ~= 0, "Collider must have a set size")
    if self.IsUpdating then return end

    debug.profilebegin("InitColliderUpdate")
    self.IsUpdating = true
    local lod: number = self.LOD
    local atVoxel: vector = self.Renderer:GetNearestVoxel(at, lod)
    local range: number = self.Size / 2

    local areaMin: vector = atVoxel - vector.create(range, range, range)
    local areaMax: vector = atVoxel + vector.create(range, range, range)

    -- Update recycle bin
    debug.profilebegin("UpdateRecycleBin")
    for faceID: number, face: CollisionFace in self.RenderedFaces do
        local voxel: vector = self:GetCollisionFaceFromID(faceID)

        local inBounds: boolean = voxel.x >= areaMin.x
            and voxel.x <= areaMax.x
            and voxel.y >= areaMin.y
            and voxel.y <= areaMax.y
            and voxel.z >= areaMin.z
            and voxel.z <= areaMax.z

        if not inBounds then
            table.insert(self.RecycleBin, face)
            self.RenderedFaces[faceID] = nil
        end
    end
    debug.profileend()

    local step: RBXScriptConnection
    local startY: number = -range
    local startZ: number = -range
    local startX: number = -range

    step = RunService.Heartbeat:Connect(function()
        debug.profilebegin("ColliderRender")
        local isResuming: boolean = true
        local voxelsRendered: number = 0

        for y = startY, range do
            startY = y
            local resumeZ: number = if isResuming then startZ else -range

            for z = resumeZ, range do
                startZ = z
                local resumeX: number = if isResuming then startX else -range
                isResuming = false

                for x = resumeX, range do
                    startX = x + 1
                    local voxel: vector = atVoxel + vector.create(x, y, z)
                    local firstFaceID: number = self:GetCollisionFaceId(voxel, 1)
                    if self.RenderedFaces[firstFaceID] then continue end

                    local case: number = self.Renderer:RenderVoxel(voxel, lod, self)
                    if case ~= 0 and case ~= 255 then
                        voxelsRendered += 1
                    end
                    if voxelsRendered >= VOXELS_PER_FRAME then
                        debug.profileend()
                        return
                    end
                end
            end
        end

        -- Remove any remaining in the bin
        debug.profilebegin("EmptyBin")
        for x = #self.RecycleBin, 1, -1 do
            local face: CollisionFace = self.RecycleBin[x]
            face.Parent = self._storage
            --table.remove(self.RecycleBin, x)
        end
        debug.profileend()

        self.IsUpdating = false
        step:Disconnect()
        debug.profileend()
    end)

    debug.profileend()
end

return TerrainCollider
