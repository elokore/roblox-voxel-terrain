--!strict
local voxelsize: number = 5 * 2 ^ 9
local radius: number = 20000

local startCF: CFrame = CFrame.new(-radius, -radius, -radius)

local count: number = radius / voxelsize
local vcount: number = 0

for x = 1, count * 2 do
    for y = 1, count * 2 do
        for z = 1, count * 2 do
            local voxel: Vector3 = Vector3.new(x, y, z)
            local voxelCF: CFrame = startCF * CFrame.new(voxel * voxelsize)
            if voxelCF.Position.Magnitude > radius then continue end

            local p = Instance.new("Part")
            p.Transparency = 0.75
            p.BrickColor = BrickColor.random()
            p.Anchored = true
            p.Size = Vector3.new(voxelsize, voxelsize, voxelsize)
            p.CFrame = voxelCF
            p.CanCollide = false
            p.Parent = workspace
            vcount += 1
        end
    end
end

print("Count:", vcount)
