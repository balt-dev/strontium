# `strontium` Documentation

# Table of Contents
- [Overview](#overview)
  - [A quick example](#a-quick-example)
  - [Basic syntax and operators](#basic-syntax-and-operators)
  - [Pattern matching](#pattern-matching)
  - [Implementing Rule yourself](#implementing-rule-yourself)
- [Reference](#reference)
  - [Rule](#rule)
  - [Error](#error)
  - [Spacer](#spacer)
  - [Literal](#literal)
  - [Pattern](#pattern)

# Overview

`strontium` (spelled exactly that way) is a simple parsing library, defined by its PEG-like syntax and the flexibility of implementing rules in pure Lua.

## A quick example
A simple grammar to parse and evaluate a simple mathematical expression can be defined as follows:
```lua
local strontium = require "strontium"

-- Prefix shorthands, reminiscent of f-strings in Python
local l = strontium.Literal
local p = strontium.Pattern

-- Forward declaration
local sum = strontium.Rule.new()

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
sum.def = (prod .. ((ws + p'([+-])' - ws) .. prod):group():many())
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
    end).def

-- Full file
local expr = sum .. p"$":err("expected EOF")

print(expr:parse "1 * 7 + ((((1 + (((3) + 3)) / 3))) / 2) / 4 + 1 * 2 + 3 * 4" )
--> 60      21.375
```
Everything done here is explained below.

## Basic syntax and operators

You can define a rule that matches a literal string by
prefixing it with [`strontium.Literal`](#literal) - or, for brevity, shortening it to something like `l` like above. A literal string rule will return one result, being the string verbatim.

Rules support the following operators:
- [`a + b`](#rule__add): Given two rules, parse the left, then parse the right, and return the right rule's result
- [`a - b`](#rule__sub): Ditto, but return the left rule's result
- [`a * b`](#rule__mul): Parses the left rule, discards its result, then parses the right rule at the same index (equivalent to a positive lookahead)
- [`a / b`](#rule__div): Parses the left rule, or if that fails, the right
- [`a .. b`](#rule__concat): Parses the left rule, then the right, and returns both of their results
- [`-a`](#rule__unm): Succeeds if the rule _doesn't_ parse (equivalent to a negative lookahead)

## Pattern matching

You can define a rule that matches a Lua pattern using
[`strontium.Pattern`](#pattern) - or again, shortening it to `p` in
the above snippet for brevity.

Rules defined in this way will return any _captures_ defined within the pattern -
meaning that a rule with no captures will return nothing!

This is useful in conjunction with things like `%b()`, or even [`Rule:map`](#rule-map).

For example, parsing `6E` with `p'(%d)([ABCDEF])'`
would return `6 E` - that is, two separate values returned in an unpacked "tuple".

## Implementing Rule yourself

In order to have a function that can be used in [`Rule:new`](#rulenew), the function needs to follow a few guidelines:
1. The function must take two parameters:
    - a `string`, which is the entire source input currently being parsed,
    - and a `number`, which is the index into the source input where parsing is currently at.
2. The function must return at least one value, being _a `number` position offset from the given index._

For example, parsing `cba` in `lkjihgfedcba` would take a string of value `"lkjihgfedcba"` and an index of `9`, and would return an index of `12`, along with the string `"cba"`.

Due to the semantics of `table.unpack`, it is _required_ that
you do not return `nil` as the last return value, as it is
indistinguishable from no return value in that spot.

For example, this:
```lua
return index, tonumber(str)
```
is a logic error, as `tonumber` returns `nil` on error, and will cause unexpected behavior.

If you need behavior like this, look at [`Spacer`](#spacer).

Look inside the source of [`strontium.lua`](../strontium.lua) for some good examples.

# Reference

## `Rule`
> A single rule of a grammar.
### Fields
#### `Rule.def`
> `fun(string, number): number`
> 
> The function to call when the rule is parsed.

### Methods

#### `Rule.new`
> `function(def: fun(string, number): number): Rule`
>
> Constructs a new [`Rule`](#rule). See [the overview section](#implementing-rule-yourself) on how to use this correctly.

#### `Rule:apply`
> `function(self: Rule, other: Rule): Rule`
>
> Applies the given rule to the first result of the rule's return values,
> while assuming the first input is a string.
> Returns any other results verbatim.
> 
> Note that the span returned by [`Rule:spanned`](#rulespanned) will be _relative to the returned string_ from the point of view of the called rule.

#### `Rule:discard`
> `function(self: Rule): Rule`
>
> Discards the output of a rule.
>
> Use of this function is generally discouraged, in favor of [`+`](#rule__add) and [`-`](#rule__sub), for performance and brevity.
>
> Only use this if you're writing a rule where the only pattern is ignored.

#### `Rule:err`
> `function(self: Rule, message: string): Rule`
>
> Replaces the error message from this rule failing.

#### `Rule:group`
> `function(self: Rule): Rule`
>
> Collects the output of a rule into an array.

#### `Rule:many`
> `function(self: Rule, max: number?): Rule`
>
> Attempts to match a rule as many times as possible, returning the returned values.
> 
> If at any point the rule does not advance in the string (i.e. matching the empty string),
> and there is no maximum match amount set,
> ** an error is immediately thrown** to prevent an infinite loop.

#### `Rule:map`
> `function(self: Rule, fn: fun(...): ...): Rule`
>
> Maps the output of a rule over a function call.

#### `Rule:optional`
> `function(self: Rule): Rule`
>
> Attempts to match a rule, or if it doesn't match, returns a [`Spacer`](#spacer).

#### `Rule:parse`
> `function(self: Rule, source: string, index: number? = 1): number, ...`
>
> Parses a string into a tree based on the definition of this rule.
>
> Returns the index that parsing stopped at, then any return values from the parsed rule.

#### `Rule:spanned`
> `function(self: Rule): Rule`
>
> Prepends the start and end indices of the matched string, and the matched string itself, to the rule's return values, in that order.

### Metamethods
#### `Rule:__add`
> `function(self: Rule, other: Rule): Rule`
> 
> Parses the left and right rule, only returning the result of the right rule.

#### `Rule:__sub`
> `function(self: Rule, other: Rule): Rule`
> 
> Parses the left and right rule, only returning the result of the left rule.

#### `Rule:__mul`
> `function(self: Rule, other: Rule): Rule`
> 
> Parses the left rule, discards it, then parses the right rule in the same place.
> This is equivalent to a positive lookahead.

#### `Rule:__div`
> `function(self: Rule, other: Rule): Rule`
> 
> Parses and returns the result of the left rule, or if that fails, the right rule.

#### `Rule:__unm`
> `function(self: Rule): Rule`
> 
> Fails parsing if this rule parses.

#### `Rule:__concat`
> `function(self: Rule, other: Rule): Rule`
> 
> Parses the left and right rule, returning the results of both.

## `Error`
> An error that can be raised from parsing.
>
> Note that in Lua 5.1, the error message won't actually display
> without calling `tostring` on the actual error first.
### Fields
#### `Error.index`
> `number`
>
> The index at which the error occurred.
#### `Error.err`
> `any`
>
> The error message that the error displays.
### Methods
#### `Error.new`
> `function(index: number, err: any): Error`
>
> Creates a new parsing error.
### Metamethods
#### `Error:__tostring`
> `function(self: Error): string`

## `Spacer`
> `{}`
> 
> A spacer value, for use when using `nil` would be a logic error.
> Notable for its use in [`Rule:optional`](#ruleoptional).
#### `Spacer:__tostring`
> `function(self: Spacer): string`

## `Literal`
> `function(lit: string): Rule`
> 
> Creates a [`Rule`](#rule) that matches a specific literal string.

## `Pattern`
> `function(pat: string): Rule`
> 
> Creates a [`Rule`](#rule) that matches a specific pattern, returning any captures.

---

_this was all hand-typed because `luals` doesn't output very good documentation._

_might make a pr to make this format automatic (it's just markdown) as it took me over 3 hours to type all this out and keeping track of the same thing in two places really, really sucks_

_copyright @baltdev 2024_
