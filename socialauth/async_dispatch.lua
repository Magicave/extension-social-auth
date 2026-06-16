local M = {}

local queue = {}

function M.enqueue(callback, ...)
    if type(callback) ~= "function" then
        return false
    end
    queue[#queue + 1] = {
        callback = callback,
        args = { ... }
    }
    return true
end

function M.has_pending()
    return #queue > 0
end

function M.drain()
    if #queue <= 0 then
        return 0
    end
    local pending = queue
    queue = {}
    for i = 1, #pending do
        local entry = pending[i]
        if entry ~= nil and type(entry.callback) == "function" then
            entry.callback(unpack(entry.args or {}))
        end
    end
    return #pending
end

return M
