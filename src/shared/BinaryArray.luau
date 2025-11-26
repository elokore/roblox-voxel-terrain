--!strict
local module = {}

function module.BinaryInsert<T>(sorted_table: { T }, value: T, evaluator: (T) -> number): number
    local low: number = 1
    local high: number = #sorted_table
    local pos: number = #sorted_table + 1 -- Default to end if larger than all elements
    local sortValue: number = evaluator(value)

    while low <= high do
        local mid = math.floor((low + high) / 2)
        if sorted_table[mid] == value then
            pos = mid
            break -- Found exact match, insert here
        elseif evaluator(sorted_table[mid]) < sortValue then
            low = mid + 1
        else
            pos = mid -- Potential insertion point
            high = mid - 1
        end
    end

    -- Insert the value at the determined position
    table.insert(sorted_table, pos, value)
    return pos
end

return module
