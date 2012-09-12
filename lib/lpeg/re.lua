-- $Id: re.lua,v 1.39 2010/11/04 19:44:18 roberto Exp $

-- imported functions and modules
local tonumber, type, print, error = tonumber, type, print, error
local setmetatable = setmetatable
local m = require"lpeg"

-- 'm' will be used to parse expressions, and 'mm' will be used to
-- create expressions; that is, 're' runs on 'm', creating patterns
-- on 'mm'
local mm = m

-- pattern's metatable 
local mt = getmetatable(mm.P(0))



-- No more global accesses after this point
local version = _VERSION
if version == "Lua 5.2" then _ENV = nil end


local any = m.P(1)


-- Pre-defined names
local Predef = { nl = m.P"\n" }


local mem
local fmem
local gmem


local function updatelocale ()
  mm.locale(Predef)
  Predef.a = Predef.alpha
  Predef.c = Predef.cntrl
  Predef.d = Predef.digit
  Predef.g = Predef.graph
  Predef.l = Predef.lower
  Predef.p = Predef.punct
  Predef.s = Predef.space
  Predef.u = Predef.upper
  Predef.w = Predef.alnum
  Predef.x = Predef.xdigit
  Predef.A = any - Predef.a
  Predef.C = any - Predef.c
  Predef.D = any - Predef.d
  Predef.G = any - Predef.g
  Predef.L = any - Predef.l
  Predef.P = any - Predef.p
  Predef.S = any - Predef.s
  Predef.U = any - Predef.u
  Predef.W = any - Predef.w
  Predef.X = any - Predef.x
  mem = {}    -- restart memoization
  fmem = {}
  gmem = {}
  local mt = {__mode = "v"}
  setmetatable(mem, mt)
  setmetatable(fmem, mt)
  setmetatable(gmem, mt)
end


updatelocale()



local I = m.P(function (s,i) print(i, s:sub(1, i-1)); return i end)


local function getdef (id, Defs)
  local c = Defs and Defs[id]
  if not c then error("undefined name: " .. id) end
  return c
end


local function patt_error (s, i)
  local msg = (#s < i + 20) and s:sub(i)
                             or s:sub(i,i+20) .. "..."
  msg = ("pattern error near '%s'"):format(msg)
  error(msg, 2)
end

local function mult (p, n)
  local np = mm.P(true)
  while n >= 1 do
    if n%2 >= 1 then np = np * p end
    p = p * p
    n = n/2
  end
  return np
end

local function equalcap (s, i, c)
  if type(c) ~= "string" then return nil end
  local e = #c + i
  if s:sub(i, e - 1) == c then return e else return nil end
end


local S = (m.S(" \f\n\r\t\v") + "--" * (any - Predef.nl)^0)^0

local name = m.R("AZ", "az") * m.R("AZ", "az", "__", "09")^0

local arrow = S * "<-"

local exp_follow = m.P"/" + ")" + "}" + ":}" + "~}" + (name * arrow) + -1

name = m.C(name)


-- identifiers only have meaning in a given environment
local Identifier = name * m.Carg(1)

local num = m.C(m.R"09"^1) * S / tonumber

local String = "'" * m.C((any - "'")^0) * "'" +
               '"' * m.C((any - '"')^0) * '"'


local defined = "%" * Identifier / function (c,Defs)
  local cat =  Defs and Defs[c] or Predef[c]
  if not cat then error ("name '" .. c .. "' undefined") end
  return cat
end

local Range = m.Cs(any * (m.P"-"/"") * (any - "]")) / mm.R

local item = defined + Range + m.C(any)

local Class =
    "["
  * (m.C(m.P"^"^-1))    -- optional complement symbol
  * m.Cf(item * (item - "]")^0, mt.__add) /
                          function (c, p) return c == "^" and any - p or p end
  * "]"

local function adddef (t, k, Defs, exp)
  if t[k] then
    error("'"..k.."' already defined as a rule")
  else
    t[k] = exp
  end
  return t
end

local function firstdef (n, Defs, r) return adddef({n}, n, Defs, r) end



local exp = m.P{ "Exp",
  Exp = S * ( m.V"Grammar"
            + m.Cf(m.V"Seq" * ("/" * S * m.V"Seq")^0, mt.__add) );
  Seq = m.Cf(m.Cc(m.P"") * m.V"Prefix"^0 , mt.__mul)
        * (#exp_follow + patt_error);
  Prefix = "&" * S * m.V"Prefix" / mt.__len
         + "!" * S * m.V"Prefix" / mt.__unm
         + m.V"Suffix";
  Suffix = m.Cf(m.V"Primary" * S *
          ( ( m.P"+" * m.Cc(1, mt.__pow)
            + m.P"*" * m.Cc(0, mt.__pow)
            + m.P"?" * m.Cc(-1, mt.__pow)
            + "^" * ( m.Cg(num * m.Cc(mult))
                    + m.Cg(m.C(m.S"+-" * m.R"09"^1) * m.Cc(mt.__pow))
                    )
            + "->" * S * ( m.Cg(String * m.Cc(mt.__div))
                         + m.P"{}" * m.Cc(nil, m.Ct)
                         + m.Cg(Identifier / getdef * m.Cc(mt.__div))
                         )
            + "=>" * S * m.Cg(Identifier / getdef * m.Cc(m.Cmt))
            ) * S
          )^0, function (a,b,f) return f(a,b) end );
  Primary = "(" * m.V"Exp" * ")"
            + String / mm.P
            + Class
            + defined
            + "{:" * (name * ":" + m.Cc(nil)) * m.V"Exp" * ":}" /
                     function (n, p) return mm.Cg(p, n) end
            + "=" * name / function (n) return mm.Cmt(mm.Cb(n), equalcap) end
            + m.P"{}" / mm.Cp
            + "{~" * m.V"Exp" * "~}" / mm.Cs
            + "{" * m.V"Exp" * "}" / mm.C
            + m.P"." * m.Cc(any)
            + name * -arrow / mm.V
            + "<" * name * ">" / mm.V;
  Definition = Identifier * arrow * m.V"Exp";
  Grammar = m.Cf(m.V"Definition" / firstdef * m.Cg(m.V"Definition")^0, adddef) /
                mm.P
}

local pattern = S * exp / mm.P * (-any + patt_error)


local function compile (p, defs)
  if mm.type(p) == "pattern" then return p end   -- already compiled
  local cp = pattern:match(p, 1, defs)
  if not cp then error("incorrect pattern", 3) end
  return cp
end

local function match (s, p, i)
  local cp = mem[p]
  if not cp then
    cp = compile(p)
    mem[p] = cp
  end
  return cp:match(s, i or 1)
end

local function find (s, p, i)
  local cp = fmem[p]
  if not cp then
    cp = compile(p)
    cp = mm.P{ mm.Cp() * cp + 1 * mm.V(1) }
    fmem[p] = cp
  end
  return cp:match(s, i or 1)
end

local function gsub (s, p, rep)
  local g = gmem[p] or {}   -- ensure gmem[p] is not collected while here
  gmem[p] = g
  local cp = g[rep]
  if not cp then
    cp = compile(p)
    cp = mm.Cs((cp / rep + 1)^0)
    g[rep] = cp
  end
  return cp:match(s)
end


-- exported names
local re = {
  compile = compile,
  match = match,
  find = find,
  gsub = gsub,
  updatelocale = updatelocale,
}

if version == "Lua 5.1" then _G.re = re end

return re
