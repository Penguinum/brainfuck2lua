local l = require "lpeglabel"
local relabel = require "relabel"

local V, S, P, R, C, Ct, T =
  l.V, l.S, l.P, l.R, l.C, l.Ct, l.T

local operator = function(operator)
  return { type = "operator", data = operator }
end

local loop = function(expressions)
  return { type = "loop", data = expressions }
end

local program = function(expressions)
  return { type = "program", data = expressions }
end

local spaces = S" \t\n\r" ^1
local spaces_maybe = S" \t\n\r" ^0

local brainfuck = P{
  "program",
  program     = Ct(V"expression"^0) * (P(-1) + V"root_errors") / program,
  expression  = V"operator" + V"loop" + spaces,
  loop        = P"[" * Ct(V"expression"^0) * (P"]" + V"loop_errors") / loop,
  operator    = S"<>-+,." / operator,

  loop_errors = spaces_maybe * P(-1) * T"expected_]" + T"bad_symbol",
  root_errors = P"]" * T"unbalanced_]" + T"bad_symbol",
}

local make_concatter = function()
  local data = {}
  return {
    push = function(self, ...)
      for _, str in ipairs({...}) do
        table.insert(data, str)
      end
    end,
    result = function()
      return table.concat(data)
    end,
  }
end

local ast2lua

local translators = {}

local function indent(n)
  return string.rep("  ", n)
end

translators.operator = function(op, info)
  info.concatter:push(
    indent(info.loop_depth) .. ({
      ["."] = "io.write(string.char(data[i]))\n",
      [","] = "data[i] = string.byte(io.read(1))\n",
      ["+"] = "data[i] = data[i] + 1\n",
      ["-"] = "data[i] = data[i] - 1\n",
      [">"] = "i = i + 1\n",
      ["<"] = "i = i - 1\n",
    })[op]
  )
end

translators.loop = function(body, info)
  info.concatter:push(indent(info.loop_depth) .. "while data[i] ~= 0 do\n")
  info.loop_depth = info.loop_depth + 1
  for _, expression in ipairs(body) do
    info.concatter:push(ast2lua(expression, info))
  end
  info.loop_depth = info.loop_depth - 1
  info.concatter:push(indent(info.loop_depth) .. "end\n")
end

translators.program = function(expression_list)
  local code = [[
local data = setmetatable(
  { array = {} },
  {
    __index = function(self, i) return self.array[i] or 0; end,
    __newindex = function(self, i, value) self.array[i] = value % 256; end
  }
)
local i = 0
---------------------------
]]
  local info = {
    loop_depth = 0,
    concatter = make_concatter(),
  }
  info.concatter:push(code)
  for _, expression in ipairs(expression_list) do
    info.concatter:push(ast2lua(expression, info))
  end
  return info.concatter:result()
end

ast2lua = function(ast, info)
  return translators[ast.type](ast.data, info)
end

local function make_error_message(code, label, position)
  local function describe_position(pos)
    local line, col = relabel.calcline(code, pos)
    return ("at line %d (col %d)"):format(line, col)
  end

  if label == "unbalanced_]" then
    position = position - 1
    return ("Unmatched ']' at %s"):format(
      describe_position(position)
    )
  elseif label == "expected_]" then
    return ("Expected ']' but got EOF")
  elseif label == "bad_symbol" then
    return ("Unexpected symbol '%s' at %s"):format(
      code:sub(position, position),
      describe_position(position)
    )
  end
end

local function translate(code)
  local ast, label, position = brainfuck:match(code)
  if not ast then
    return nil, make_error_message(code, label, position)
  end
  return ast2lua(ast)
end

return {
  to_lua = translate,
  to_ast = function(code)
    return brainfuck:match(code)
  end,
}

