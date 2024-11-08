# `strontium`

A dead-simple BNF parsing framework for Lua. Supports Lua 5.*, including LuaJIT. Write your rules in Lua!

Comprehensive documentation can be found in [`doc/index.md`](doc/index.md).

This library is licensed under the MIT license to baltdev. Said license can be found in [`LICENSE`](LICENSE).

```lua
local strontium = require "strontium"

-- Prefix shorthands, reminiscent of f-strings in Python
local l = strontium.Literal
local p = strontium.Pattern

-- Forward declaration
local sum = strontium.Forward.new()

-- This returns nothing, as the pattern doesn't capture anything
local ws = p'[\t\r\n ]*'
-- A quick :map using tonumber takes care of converting to a number
local number = (l'0' / p'([123456789]%d*)')
    :map(function(num)
        return tonumber(num) or error("could not convert to a number", 2)
    end)

-- Due to the use of + and -, this only returns either number or sum
local atom = number / (l'(' + ws + sum - ws - l')')
-- :optional() returns Spacer on no match, 
-- but we don't care about that, so we can ignore it
local unary = ((p'([+-])':optional() - ws) .. atom)
   :map(function(opr, atom)
        if opr == "-" then atom = -atom end
        return atom
    end)

-- Technically this could be done with something like pratt parsing
-- to reduce the code duplication between this and sum,
-- and add capability for things like right-associativity,
-- but that would complicate the example.
local prod = (unary .. ((ws + p'([%*/%%])' - ws) .. unary):group():many())
    :map(function(init, operations)
        -- Iteratively match against the binary operators and apply each one
        for _, pair in ipairs(operations) do
            local opr, val = table.unpack(pair)
            if opr == "*" then
                init = init * val
            elseif opr == "/" then
                init = init / val
            elseif opr == "%" then
                init = init % val
            end
        end
        return init
    end)

-- Complete forward declaration
sum.definition = (prod .. ((ws + p'([+-])' - ws) .. prod):group():many())
    :map(function(init, operations)
        for _, pair in ipairs(operations) do
            local opr, val = table.unpack(pair)
            if opr == "+" then
                init = init + val
            elseif opr == "-" then
                init = init - val
            end
        end
        return init
    end)

-- Full file
local expr = sum .. p"$":err("expected EOF")
```
