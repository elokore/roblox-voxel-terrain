--!strict
local StarterGui = game:GetService("StarterGui")
local TriTables = require(script.Parent.Triangulations)
local module = {}

local CORNER_MASK: { vector } = TriTables.cornerMask
local continentCurve: Path2D = StarterGui:WaitForChild("Heightmap").MainFrame.Path2D

function sphereToOctahedral(point: vector, planetRadius: number): vector
    -- Normalize to octahedron surface (|x| + |y| + |z| = 1)
    local absSum = math.abs(point.x) + math.abs(point.y) + math.abs(point.z)
    local oct = point / absSum

    local u: number
    local v: number

    if oct.y >= 0 then
        -- Top hemisphere - direct mapping
        u = oct.x
        v = oct.z
    else
        -- Bottom hemisphere - unfold with reflection
        u = (1 - math.abs(oct.z)) * (if oct.x >= 0 then 1 else -1)
        v = (1 - math.abs(oct.x)) * (if oct.z >= 0 then 1 else -1)
    end

    -- Convert from [-1, 1] to [0, 1]
    u = (u + 1) * 0.5
    v = (v + 1) * 0.5

    return vector.create(u, v) * planetRadius
end

local function sampleNoise(point: vector, octaves: number): number
    local noise: number = 0

    for x = 1, octaves do
        local factor: number = (x ^ 2)
        local p: vector = point * factor

        noise += math.noise(p.x, p.y) / factor
    end

    return noise
end

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
        local samplePos: vector = sphereToOctahedral(cornerPos, planetRadius) * 1 / 800 --octrahedralProjection(cornerPos, planetRadius) * 1 / 500
        local continentalness: number = sampleNoise(samplePos, 4)
        local t: number = (continentalness + 1) / 2
        local n: number = 1 - continentCurve:GetPositionOnCurve(t).Y.Scale

        sampleCornerBuffer[i] = planetRadius - vector.magnitude(cornerPos) + n * 500
    end

    return sampleCornerBuffer
end

function module.IsVoxelEmpty(voxel: vector, voxelSize: number, terrainPos: vector, planetRadius: number): boolean
    local corners: { number } = module.SampleVoxelCorners(voxel, voxelSize, terrainPos, planetRadius)
    local sign0: number = math.sign(corners[0])

    for i: number = 1, 7 do
        if sign0 ~= math.sign(corners[i]) then return false end
    end

    return true
end

function module.GetNearestVoxel(terrainCF: CFrame, worldPos: vector, voxelSize: number): vector
    local halfSize: number = voxelSize / 2
    terrainCF *= CFrame.new(halfSize, halfSize, halfSize)
    local rp: Vector3 = terrainCF:PointToObjectSpace(Vector3.new(worldPos.x, worldPos.y, worldPos.z))
    local relativePos: vector = vector.create(rp.x, rp.y, rp.z)
    local voxel: vector = vector.floor((relativePos / voxelSize) + vector.create(0.5, 0.5, 0.5))
    return voxel
end

return module
