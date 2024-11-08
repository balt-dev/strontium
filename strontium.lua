--[[

Version 1.0-1

Dead simple, one file parsing library for Lua.
Made by @baltdev. Copyright 2024.
Licensed under the MIT license.
See https://github.com/balt-dev/strontium.

See the documentation here:
https://github.com/balt-dev/strontium/tree/v1.0.0/doc/index.md

Feel free to copy this file around as much as you want,
as long as this comment at the top stays untouched.

]]

-- shim
---@diagnostic disable: deprecated
local unpack = table.unpack or unpack
--pcall = function(f, ...) return true, f(...) end

--- @class (exact) strontium
--- @field Rule Rule
--- @field Spacer Rule
--- @field Error Error
--- @field Literal fun(lit: string): Rule
--- @field Pattern fun(pat: string): Rule
local T = {}

--- A spacer value, for use when using `nil` would be a logic error.
--- @diagnostic disable-next-line: missing-fields
T.Spacer = {}
setmetatable(T.Spacer, {
    __metatable = false,
    __newindex = function() error("cannot set fields on Spacer", 2) end,
    __tostring = function () return "{strontium.Spacer}" end
})

--- @class Error
--- @field index number
--- @field err any
--- @field private __metatable false
T.Error = { __metatable = false }

function T.Error:__tostring()
    return "parsing error at index " .. self.index .. ": " .. self.err
end

--- @param index number The error index
--- @param err any The error message
--- @return Error
--- @nodiscard
--- Creates a new parsing error.
T.Error.new = function(index, err)
    local o = { index = index, err = err }
    setmetatable(o, T.Error)
    return o
end

T.Error.__index = T.Error

setmetatable(T.Error, {
    __metatable = false,
    __newindex = function() error("cannot create fields on type Error") end
})

--- @class Rule
--- @field package def fun(source: string, index: number): number, ... The function to call when the rule is parsed.
--- @operator add(Rule): Rule
--- @operator sub(Rule): Rule
--- @operator mul(Rule): Rule
--- @operator div(Rule): Rule
--- @operator concat(Rule): Rule
--- @operator unm: Rule
--- @field private __metatable false
--- Definitive Rule class. Look at the Reference for more details.
T.Rule = { __metatable = false }

--- @param other Rule
--- @return Rule
--- @nodiscard
--- Parses the left and right rule, only returning the result of the right rule.
function T.Rule:__add(other)
    return T.Rule.new(function(source, index)
        local i = self.def(source, index)
        return other.def(source, i)
    end)
end

--- @param other Rule
--- @return Rule
--- @nodiscard
--- Parses the left and right rule, only returning the result of the left rule.
function T.Rule:__sub(other)
    return T.Rule.new(function(source, index)
        local ret = { self.def(source, index) }
        local i = other.def(source, ret[1])

        return i, unpack(ret, 2)
    end)
end

--- @param other Rule
--- @return Rule
--- @nodiscard
--- Parses the left rule, discards it, then parses the right rule in the same place.
--- This is equivalent to a positive lookahead.
function T.Rule:__mul(other)
    return T.Rule.new(function(source, index)
        self.def(source, index)
        return other.def(source, index)
    end)
end

--- @param other Rule
--- @return Rule
--- @nodiscard
--- Parses and returns the result of the left rule, or if that fails, the right rule.
function T.Rule:__div(other)
    return T.Rule.new(function(source, index)
        local succ, i, ret = pcall(function()
            local t = { self.def(source, index) }
            return t[1], { unpack(t, 2) }
        end)
        if succ then return i, unpack(ret) end

        return other.def(source, index)
    end)
end

--- @return Rule
--- @nodiscard
--- 
function T.Rule:__unm()
    return T.Rule.new(function(source, index)
        local succ = pcall(self.def, source, index)
        if succ then error(T.Error.new(index, "unexpectedly matched rule"), 2) end
        return index
    end)
end

--- @param other Rule
--- @return Rule
--- @nodiscard
--- Parses the left and right rule, returning the results of both.
function T.Rule:__concat(other)
    return T.Rule.new(function(source, index)
        -- Unpacking two tables right next to each other
        -- leaves a nil at index 1 if the first one is empty.
        -- Thanks, spaghetti monster.
        local ret = {}
        local ret_a = { self.def(source, index) }
        local ret_b = { other.def(source, ret_a[1]) }
        for i = 2, #ret_a do ret[#ret + 1] = ret_a[i] end
        for i = 2, #ret_b do ret[#ret + 1] = ret_b[i] end
        return ret_b[1], unpack(ret)
    end)
end

--- @param fun fun(...): ...
--- @return Rule
--- @nodiscard
--- Maps the output of a rule over a function call.
function T.Rule:map(fun)
    return T.Rule.new(function(source, index)
        local ret = { self.def(source, index) }
        local succ, val = pcall(function(...) return { fun(...) } end, unpack(ret, 2))
        if not succ then error(T.Error.new(ret[1], val), 2) end
        return ret[1], unpack(val)
    end)
end

--- @return Rule
--- @nodiscard
--- Collects the output of a rule into an array.
function T.Rule:group()
    return T.Rule.new(function(source, index)
        local ret = { self.def(source, index) }
        return ret[1], { unpack(ret, 2) }
    end)
end

--- @return Rule
--- @nodiscard
--- Discards the output of a rule.
---
--- Use of this function is generally discouraged, in favor of `+` and `-`, for performance and brevity.
---
--- Only use this if you're writing a rule where the only pattern is ignored.
function T.Rule:discard()
    return T.Rule.new(function(source, index)
        local i = self.def(source, index)
        return i
    end)
end

--- @return Rule
--- @nodiscard
--- Attempts to match a rule, or if it doesn't match, returns a [`Spacer`](lua://strontium.Spacer).
function T.Rule:optional()
    return T.Rule.new(function(source, index)
        local succ, i, ret = pcall(function()
            local t = { self.def(source, index) }
            return t[1], { unpack(t, 2) }
        end)

        if not succ then return index, T.Spacer end
        return i, unpack(ret)
    end)
end

--- @return Rule
--- @nodiscard
--- Prepends the matched string and its start and end indices to the rule's return values.
function T.Rule:spanned()
    return T.Rule.new(function(source, index)
        local ret = { self.def(source, index) }
        return ret[1], index, ret[1] - 1, source:sub(index, ret[1] - 1), unpack(ret, 2)
    end)
end

--- @return Rule
--- @param rule Rule
--- @nodiscard
--- Applies the given rule to the first result of the rule's return values,
--- while assuming the first input is a string.
--- Returns any other results verbatim.
---
--- Note that the span returned by [`Rule:spanned()`](lua://Rule.spanned)
--- will be _relative to the returned string_ from the point of view of the called rule.
function T.Rule:apply(rule)
    return T.Rule.new(function(source, index)
        local ret = { self.def(source, index) }
        if type(ret[2]) ~= "string" then
            error(T.Error.new(index, "Rule:apply expected a string, got " .. type(ret[2])), 2)
        end
        local applied = { rule.def(ret[2], 1) }
        local res = {}
        for i, val in ipairs({unpack(applied, 2)}) do res[#res+1] = val end
        for i, val in ipairs({unpack(ret, 3)}) do res[#res+1] = val end
        return ret[1], unpack(res)
    end)
end

--- @return Rule
--- @param max number? A maximum amount of matches.
--- @nodiscard
--- Attempts to match a rule as many times as possible, returning the returned values.
--- If at any point the rule does not advance in the string (i.e. matching the empty string),
--- and there is no maximum match amount set,
--- an error is immediately thrown to prevent an infinite loop.
function T.Rule:many(max)
    return T.Rule.new(function(source, index)
        local vals = {}
        local reps = 0
        repeat
            local succ, ret, i
            reps = reps + 1
            succ, i, ret = pcall(function()
                local t = { self.def(source, index) }
                return t[1], { unpack(t, 2) }
            end)
            if index == i and not max then
                error(T.Error.new(index, "infinite loop detected"), 2)
            end
            if succ then
                index = i
                for idx = 1, #ret do
                    vals[#vals + 1] = ret[idx]
                end
            end
        until not succ or (max and reps > max)
        return index, vals
    end)
end

--- @return Rule
--- @param message string
--- @nodiscard
--- Replaces the error message from this rule failing.
function T.Rule:err(message)
    return T.Rule.new(function(source, index)
        local succ, i, ret = pcall(function()
            local t = { self.def(source, index) }
            return t[1], { unpack(t, 2) }
        end)

        if not succ then error(T.Error.new(index, message), 2) end
        return i, unpack(ret)
    end)
end

--- @return number, ... The index that parsing stopped at, then any returned values from the rule
--- @param source string The string to parse
--- @param index number? The index to start parsing at, defaulting to 0
--- Parses a string into a tree based on the definition of this rule.
function T.Rule:parse(source, index)
    return self.def(source, index or 1)
end

--- Defines a new rule based on a function definition.
---
--- The function is expected to take two arguments:
--- - `source`: The entire source string, and
--- - `index`: An index into the string dictating where the parsing head is.
---
--- It's expected to return an index _offset_ from the index you're given
--- based on what was parsed.
--- For example, in this situation:
--- ```
--- hgfedcba
--- ```
--- with an index of `6`, if you're matching the string `cba`, you would return `9`.
---
--- Additionally, you can return any other values from the function -
--- these will be added to the return values of the rule.
---
--- Due to the semantics of `unpack`, it is _required_ that
--- you do not return `nil` from the function unless
--- you aren't returning anything!
---
--- For example, this:
--- ```lua
--- return index, nil, 3
--- ```
--- is a logic error, and will cause unexpected behavior.
---
--- If you need behavior like this, look at [`strontium.Spacer`](lua://strontium.Spacer).
--- @return Rule
--- @param def fun(source: string, index: number): number, ...
T.Rule.new = function(def)
    local o = { def = def }
    setmetatable(o, T.Rule)
    return o
end

T.Rule.__index = T.Rule

-- Prevent infinite recursion by not taking the shortcut of __index: table
setmetatable(T.Rule, {
    __metatable = false,
    __newindex = function() error("cannot create fields on type Rule") end
})

--- @return Rule A rule that matches the literal string
--- @param literal string The string to match
--- Matches a literal string.
function T.Literal(literal)
    return T.Rule.new(function(source, index)
        if #literal == 0 then return index, "" end
        if source:sub(index, index + #literal - 1) == literal then
            return index + #literal, literal
        end
        error(T.Error.new(index, "did not match literal: " .. literal), 2)
    end)
end

--- @return Rule A rule that matches the pattern
--- @param pattern string The pattern to match
--- Matches a string pattern, returning any captures within the pattern.
function T.Pattern(pattern)
    return T.Rule.new(function(source, index)
        local ret = { source:sub(index):find("^" .. pattern) }
        if not ret[1] then
            error(T.Error.new(index, "did not match pattern: " .. pattern), 2)
        end
        return index + ret[2], unpack(ret, 3)
    end)
end

--- @type strontium
--- @diagnostic disable-next-line: missing-fields
local prox = {}
setmetatable(prox, {
    __metatable = false,
    __index = T,
    __newindex = function() error("cannot set field on module", 2) end
})

return prox
