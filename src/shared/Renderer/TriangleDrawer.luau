--!strict
--[[
	Given 3 points can render any triangle
	Authored by EgoMoose
	Edited by Elocore
]]

---- < Services > ----
export type TriangleModel = Model & {
    Wedge1: WedgePart,
    Wedge2: WedgePart,
}

---- < Variables > ----
local module = {}
local wedge: BasePart = Instance.new("WedgePart")
wedge.CastShadow = false
wedge.Transparency = 0.5
wedge.Material = Enum.Material.SmoothPlastic
wedge.Anchored = true

--[[
	Draws a triangle with the tree points given.
	Each triangle is made using two right triangle meshes
]]
function module.DrawTriangle(a: vector, b: vector, c: vector, material: Enum.Material, reuse: TriangleModel?): TriangleModel
    local w1: BasePart = if reuse then reuse.Wedge1 else wedge:Clone()
    local w2: BasePart = if reuse then reuse.Wedge2 else wedge:Clone()

    local ab: vector, ac: vector, bc: vector = b - a, c - a, c - b
    local abd: number, acd: number, bcd: number = vector.dot(ab, ab), vector.dot(ac, ac), vector.dot(bc, bc)

    if abd > acd and abd > bcd then
        c, a = a, c
    elseif acd > bcd and acd > abd then
        a, b = b, a
    end

    ab, ac, bc = b - a, c - a, c - b

    local right: vector = vector.normalize(vector.cross(ac, ab))
    local up: vector = vector.normalize(vector.cross(bc, right))
    local back: vector = vector.normalize(bc)
    local height: number = math.abs(vector.dot(ab, up))

    --Define triangle CFrames and sizes
    local w1CFrame: CFrame = CFrame.fromMatrix((a + b) * 0.5, right, up, back)
    local w2CFrame: CFrame = CFrame.fromMatrix((a + c) * 0.5, -right, up, -back)
    local w1Size: vector = vector.create(0, height, math.abs(vector.dot(ab, back)))
    local w2Size: vector = vector.create(0, height, math.abs(vector.dot(ac, back)))
    local model: TriangleModel = if reuse then reuse else Instance.new("Model") :: TriangleModel

    w1.Size = w1Size
    w2.Size = w2Size

    w1.CFrame = w1CFrame
    w2.CFrame = w2CFrame

    w1.Material = material
    w2.Material = material

    if not reuse then
        w1.Color = Color3.new()
        w2.Color = Color3.new()

        w1.Name = "Wedge1"
        w2.Name = "Wedge2"

        model.Name = "Triangle"

        w1.Parent = model
        w2.Parent = model
    end

    return model
end

return module
