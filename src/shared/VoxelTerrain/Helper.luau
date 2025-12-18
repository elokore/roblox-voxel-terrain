--!strict
local TriTables = require(script.Parent.Triangulations)
local module = {}

local CORNER_MASK: { vector } = TriTables.cornerMask

function module.GetVoxelWorldPosition(voxel: vector, voxelSize: number, terrainPos: vector): vector
    local halfSize: number = voxelSize / 2
    return terrainPos + vector.create(halfSize, halfSize, halfSize) + voxel * vector.create(voxelSize, voxelSize, voxelSize)
end

function module.GetVoxelID(voxel: vector, lod: number): number
    local sizeRangeXYZ: number = 20001
    local sizeRangeLOD: number = 10

    local x: number = voxel.x + 10000
    local y: number = voxel.y + 10000
    local z: number = voxel.z + 10000
    lod -= 1

    return (((x * sizeRangeXYZ + y) * sizeRangeXYZ + z) * sizeRangeLOD + lod)
end

function module.GetVoxel(id: number): (vector, number)
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

function module.GetCaseCode(corners: { number }): number
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

local sampleCornerBuffer: { number } = {}
function module.SampleVoxelCorners(voxel: vector, voxelSize: number, terrainPos: vector, planetRadius: number): { number }
    local voxelPos: vector = module.GetVoxelWorldPosition(voxel, voxelSize, terrainPos)
    local halfSize: number = voxelSize / 2

    for i: number = 0, 7 do
        local mask: vector = CORNER_MASK[i]
        local cornerPos: vector = voxelPos + mask * halfSize
        local scaledPos: vector = cornerPos * 1 / 400

        sampleCornerBuffer[i] = planetRadius - vector.magnitude(cornerPos) + math.noise(scaledPos.x, scaledPos.y, scaledPos.z) * 200
    end

    return sampleCornerBuffer
end

function module.GetNearestVoxel(terrainCF: CFrame, worldPos: vector, voxelSize: number): vector
    local halfSize: number = voxelSize / 2
    terrainCF *= CFrame.new(halfSize, halfSize, halfSize)
    local rp: Vector3 = terrainCF:PointToObjectSpace(Vector3.new(worldPos.x, worldPos.y, worldPos.z))
    local relativePos: vector = vector.create(rp.X, rp.Y, rp.Z)
    local voxel: vector = vector.floor((relativePos / voxelSize) + vector.create(0.5, 0.5, 0.5))
    return voxel
end

return module
