-- Comprehensive Lua syntax sample.
-- This file is designed as parser test data, not as a runtime test suite.

local _VERSION_TAG = "lua-feature-sample"
local nil_value = nil
local truthy, falsy = true, false

-- Numbers: decimal, exponent, hexadecimal integer, hexadecimal float.
local int_value = 42
local negative_value = -17
local float_value = 3.14159
local exponent_value = 6.022e23
local hex_value = 0xff
local hex_float = 0x1.8p+2

-- Strings: short strings, escapes, long strings, and long comments.
local single_quoted = 'single quoted string'
local double_quoted = "double quoted string with \"escapes\" and \\slashes"
local escaped = "tab:\t newline:\n byte:\65 hex:\x41 unicode:\u{41}"
local long_string = [[
line one
line two with "quotes" and 'apostrophes'
]]

--[[
  Long comments may contain punctuation, unbalanced delimiters like ( [ {
  and Lua-looking text such as function fake() return "ignored" end.
]]

-- Tables: array part, hash part, computed keys, trailing separators.
local config = {
  "alpha",
  "beta",
  name = "sample-lua-program",
  version = 2,
  ["feature-name"] = "complete-lua-syntax",
  [1 + 2] = "computed key",
  nested = {
    enabled = true,
    thresholds = { 1, 2, 3, 5, 8, 13 },
  },
}

-- Local functions, varargs, arithmetic, concatenation, length, and returns.
local function join(...)
  local parts = { ... }
  local output = ""

  for index = 1, #parts do
    if index > 1 then
      output = output .. ":"
    end
    output = output .. tostring(parts[index])
  end

  return output, #parts
end

local function factorial(n)
  if n <= 1 then
    return 1
  elseif n == 2 then
    return 2
  else
    return n * factorial(n - 1)
  end
end

local function classify(value)
  if value == nil then
    return "nil"
  elseif type(value) == "number" and value % 2 == 0 then
    return "even-number"
  elseif type(value) == "number" then
    return "odd-number"
  else
    return "other"
  end
end

-- Numeric for, while, repeat-until, break, and goto labels.
local total = 0
for i = 1, 10, 1 do
  total = total + i
end

local countdown = 3
while countdown > 0 do
  countdown = countdown - 1
  if countdown == 1 then
    goto skipped
  end
end

::skipped::

repeat
  total = total - 1
until total < 40

for _, value in ipairs(config.nested.thresholds) do
  if value > 10 then
    break
  end
  total = total + value
end

-- Assignment forms, logical operators, precedence, and table indexing.
local a, b, c = 1, 2, 3
a, b = b, a
config.result = (a + b * c ^ 2) / 3
config["logic"] = (truthy and not falsy) or false
config.nested.thresholds[#config.nested.thresholds + 1] = total

-- Function definitions with dotted and method names.
local accumulator = { value = 0 }

function accumulator.add(self, amount)
  self.value = self.value + amount
  return self.value
end

function accumulator:reset(value)
  self.value = value or 0
  return self
end

accumulator:add(5)
accumulator:reset(10):add(7)

-- Closures and upvalues.
local function make_counter(start)
  local current = start or 0

  return function(step)
    current = current + (step or 1)
    return current
  end
end

local next_id = make_counter(100)
local id_a = next_id()
local id_b = next_id(10)

-- Metatables and metamethod names.
local vector = {}
vector.__index = vector

function vector.new(x, y)
  return setmetatable({ x = x or 0, y = y or 0 }, vector)
end

function vector:__add(other)
  return vector.new(self.x + other.x, self.y + other.y)
end

function vector:__tostring()
  return "(" .. self.x .. ", " .. self.y .. ")"
end

local v1 = vector.new(3, 4)
local v2 = vector.new(5, 6)
local v3 = v1 + v2

-- Coroutines, protected calls, and require-style module access.
local worker = coroutine.create(function(limit)
  for i = 1, limit do
    coroutine.yield(i, i * i)
  end
  return "done"
end)

local ok, first_value, first_square = coroutine.resume(worker, 3)
local protected_ok, protected_value = pcall(function()
  return require("math").max(first_value, first_square)
end)

-- do-end scope, local shadowing, and multiple return values.
do
  local total = "shadowed"
  config.scope_check = total
end

local joined, joined_count = join(_VERSION_TAG, id_a, id_b, tostring(v3))

return {
  config = config,
  numbers = {
    int_value,
    negative_value,
    float_value,
    exponent_value,
    hex_value,
    hex_float,
  },
  strings = {
    single_quoted,
    double_quoted,
    escaped,
    long_string,
  },
  results = {
    total = total,
    factorial = factorial(6),
    class = classify(total),
    coroutine = { ok, first_value, first_square },
    protected = { protected_ok, protected_value },
    joined = joined,
    joined_count = joined_count,
  },
}
