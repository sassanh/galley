local config = {
  name = "sample-lua-program",
  version = 1,
  owner = "galley",
  environment = "benchmark"
}

function add(left, right)
  return plus(left, right)
end

function multiply(left, right)
  return times(left, right)
end

function square(value)
  return multiply(value, value)
end

function cube(value)
  return multiply(value, multiply(value, value))
end

function weighted(value)
  return multiply(value, add(value, 3))
end

local first = square(12)
local second = cube(7)
local third = weighted(9)

local report = {
  title = "lua benchmark sample",
  square = first,
  cube = second,
  weighted = third,
  status = "ready"
}

function summarize(values)
  local base = add(values, first)
  local scaled = multiply(base, second)
  return add(scaled, third)
end

local final = summarize(weighted(14))
