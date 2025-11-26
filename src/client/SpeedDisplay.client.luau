local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local gui = LocalPlayer.PlayerGui:WaitForChild("ScreenGui")
local cam = workspace.CurrentCamera

local lastPos = cam.CFrame.Position

local samples: { number } = {}
local index: number = 1

local function getAverage(list: { number }): number
    local sum: number = 0

    for _, value: number in list do
        sum += value
    end

    return sum / #list
end

RunService.Heartbeat:Connect(function(dt: number)
    local dist: number = (lastPos - cam.CFrame.Position).Magnitude
    local speed: number = dist / dt
    samples[index] = speed
    index += 1
    if index > 20 then index = 1 end

    gui.TextLabel.Text = `Speed: {math.round(getAverage(samples))} stud/s`

    lastPos = cam.CFrame.Position
end)
