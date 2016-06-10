---- -*- Mode: Lua; -*- 
----
---- syntax.lua   syntactic transformations (AST -> AST)
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"			    -- AST functions
require "list"

syntax = {}

local boundary_ast = common.create_match("ref", 0, common.boundary_identifier)
--local looking_at_boundary_ast = common.create_match("lookat", 0, "@/generated/", boundary_ast)
local looking_at_boundary_ast = common.create_match("predicate",
						    0,
						    "*generated*",
						    common.create_match("lookat", 0, "@"),
						    boundary_ast)



local function err(name, msg)
   error('invalid ast ' .. name .. ': ' .. msg)
end

function syntax.validate(ast)
   if ast==nil then return nil; end
   if type(ast)~="table" then
      error("argument to validate is not an ast: " .. tostring(ast))
   end
   local name, body = next(ast)
   if type(name)~="string" then
      err(tostring(name), "is a non-string name");
   elseif next(ast, name) then
      err(name, "multiple names");
   elseif type(body)~="table" then
      err(name, "has a non-table body");
   else
      for k,v in pairs(body) do
	 if type(k)~="string" then err(name, "non-string key in body");
	 elseif (k=="text") then
	    if (type(v)~="string") then err(name, "text value not a string"); end
	 elseif (k=="pos") then
	    if (type(v)~="number") then err(name, "pos value not a number"); end
	 elseif (k=="subs") then
	    for i,s in pairs(v) do
	       if type(i)~="number" then
		  err(name, "subs list has a non-numeric key")
	       end
	       local ok, msg = syntax.validate(s)
	       if not ok then
		  err(name, "in sub " .. tostring(i) .. ": " .. msg);
	       end
	    end -- loop through subs
	 elseif ((k=="assignment") and (name=="binding")) then
	    if (type(v)~="boolean") then err(name, "value of the assignment flag not a boolean"); end
	 else -- unrecognized key
	    err(name, "unexpected key in ast body: " .. tostring(k));
	 end -- switch on k
      end -- loop through body
   end -- all tests have passed
   return ast;
end

function syntax.generate(node_name, ...)
   -- ... are the subs
   return common.create_match(node_name, 0, "*generated*", ...)
end

function syntax.make_transformer(fcn, target_name, recursive)
   local function target_match(name)
         -- Either match every node
      if (target_name==nil) then return true;
	 -- Or a single node type
      elseif (type(target_name)=="string") then return (name==target_name);
	 -- Or a member of a list
      elseif (type(target_name)=="table") then return member(name, target_name)
      else error("illegal target type: " .. name .. "is not a string or list")
      end
   end -- function target_match
      
   local function transform (ast, ...)
      local name, body = next(ast)
      local rest = {...}
      local mapped_transform = function(ast) return transform(ast, table.unpack(rest)); end
      local new = common.create_match(name,
				      body.pos,
				      body.text,
				      table.unpack((recursive and map(mapped_transform, body.subs))
						or body.subs))
      if target_match(name) then
	 return syntax.validate(fcn(new, ...))
      else
	 return syntax.validate(new)
      end
   end -- function transform
   return transform
end

function syntax.compose(f1, ...)
   -- return f1 o f2 o ... fn
   local fcns = {f1, ...}
   local composition = fcns[#fcns]
   for i = (#fcns - 1), 1, -1 do
      local previous = composition
      composition = function(...)
		       return fcns[i](previous(...))
		    end
   end
   return composition
end

----------------------------------------------------------------------------------------

-- return a list of choices
function syntax.flatten_choice(ast)
   local name, body = next(ast)
   if name=="choice" then
      return apply(append, map(syntax.flatten_choice, body.subs))
   else
      return {ast}
   end
end

-- take a list of choices and build a binary choice ast
function syntax.rebuild_choice(choices)
   if #choices==2 then
      return syntax.generate("choice", choices[1], choices[2])
   else
      return syntax.generate("choice", choices[1], syntax.rebuild_choice(cdr(choices)))
   end
end
		    
syntax.capture =
   syntax.make_transformer(function(ast, id)
			      local name, body = next(ast)
			      return syntax.generate("capture",
						     common.create_match("ref", 0, id),
						     ast)
			   end,
			   nil,
			   false)

syntax.append_looking_at_boundary =
   syntax.make_transformer(function(ast)
			      return syntax.generate("sequence", ast, looking_at_boundary_ast)
			   end,
			   nil,
			   false)

syntax.append_boundary =
   syntax.make_transformer(function(ast)
			      return syntax.generate("sequence", ast, boundary_ast)
			   end,
			   nil,
			   false)

syntax.append_boundary_to_rhs =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local b = syntax.generate("binding", lhs, syntax.append_boundary(rhs))
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			   "binding",
			   false)

function transform_quantified_exp(ast)
   local new_exp = syntax.id_to_ref(ast.quantified_exp.subs[1])
   local name, body = next(new_exp)
   local original_body = body
   if name=="raw" 
      or name=="charset" 
      or name=="named_charset"
      or name=="literal" 
      or name=="ref"
   then
      new_exp = syntax.generate("raw_exp", syntax.raw(new_exp))
   else
      while (name=="cooked") do			    -- in case of nested cooked groups
	 new_exp = body.subs[1]			    -- strip off "cooked"
	 name, body = next(new_exp)
      end
      new_exp = syntax.cook(new_exp)		    -- treat it as raw, because we deal with cooked later
   end
   local new = syntax.generate("new_quantified_exp", new_exp, ast.quantified_exp.subs[2])
   new.new_quantified_exp.text = original_body.text
   new.new_quantified_exp.pos = original_body.pos
   return new
end

syntax.id_to_ref =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      return common.create_match("ref", body.pos, body.text)
			   end,
			   "identifier",
			   true)		    -- RECURSIVE

syntax.raw =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      --print("entering syntax.raw", name)
			      if name=="cooked" then
				 return syntax.cook(body.subs[1])
			      elseif name=="raw" then
				 return syntax.raw(body.subs[1]) -- strip off the "raw" group
			      elseif name=="identifier" then
				 return syntax.id_to_ref(ast)
			      elseif name=="quantified_exp" then
				 return transform_quantified_exp(ast)
			      else
				 local new = syntax.generate(name, table.unpack(map(syntax.raw, body.subs)))
				 new[name].text = body.text
				 new[name].pos = body.pos
				 return new
			      end
			   end,
			   nil,			    -- match all nodes
			   false)		    -- NOT recursive

syntax.cook =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      --print("entering syntax.cook", name)
			      if name=="raw" then
				 local raw_exp = syntax.raw(body.subs[1])
				 --local kind = next(raw_exp)
				 --raw_exp[kind].text = body.text
				 --raw_exp[kind].pos = body.pos
				 return raw_exp
			      elseif name=="cooked" then
				 return syntax.cook(body.subs[1]) -- strip off "cooked" node
			      elseif name=="identifier" then
				 return syntax.id_to_ref(ast)
			      elseif name=="sequence" then
				 local first = body.subs[1]
				 local second = body.subs[2]
				 -- If the first sequent is a predicate, then no boundary is added
				 if next(first)=="predicate" then
				    return syntax.generate("sequence", syntax.cook(body.subs[1]), syntax.cook(body.subs[2]))
				 end
				 local s1 = syntax.generate("sequence", syntax.cook(first), boundary_ast)
				 local s2 = syntax.generate("sequence", s1, syntax.cook(second))
				 return s2
			      elseif name=="choice" then
				 local first = body.subs[1]
				 local second = body.subs[2]
				 local c1 = syntax.generate("sequence", syntax.cook(first), looking_at_boundary_ast)
				 local c2 = syntax.generate("sequence", syntax.cook(second), looking_at_boundary_ast)
				 local new_choice = syntax.generate("choice", c1, c2)
				 return new_choice
			      elseif name=="quantified_exp" then
				 -- do some involved stuff here
				 -- which we will skip for now
				 return transform_quantified_exp(ast)
			       else
				  local new = syntax.generate(name, table.unpack(map(syntax.cook, body.subs)))
				  new[name].text = body.text
				  new[name].pos = body.pos
				  return new
			       end
			    end,
			   nil,			    -- match all nodes
			   false)		    -- NOT recursive

syntax.cook_rhs =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local new_rhs = syntax.cook(rhs)
			      local b = syntax.generate("binding", lhs, new_rhs)
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			   "binding",
			   false)

syntax.cooked_to_raw =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      if name=="raw" then
				 -- re-wrap the top level with "raw_exp" so that we know at top level
				 -- not to append a boundary
				 return syntax.generate("raw_exp", syntax.raw(ast))
			      else
				 return syntax.cook(ast)
			      end
			   end,
			   nil,
			   false)
syntax.to_binding = 
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local original_rhs_name = next(rhs)
			      if (name=="assignment_") then
				 local name, pos, text, subs = common.decode_match(lhs)
				 assert(name=="identifier")
				 rhs = syntax.capture(rhs, text)
			      end
			      local b
			      if original_rhs_name=="raw" then
				 -- wrap with "raw_exp" so that we know at top level not to append a boundary
				 b = syntax.generate("binding",
						     lhs,
						     syntax.generate("raw_exp", syntax.raw(rhs)))
			      else
				 b = syntax.generate("binding", lhs, syntax.cook(rhs))
			      end
			      b.binding.assignment = (name=="assignment_")
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			   {"assignment_", "alias_"},
			   false)

-- At top level:
--   If the exp to match is an identifier, then look it up in the env.
--     If the pattern is marked as "raw" then match its peg.
--     If the pattern is marked as "cooked", then match its peg followed by a boundary.
--   Else we don't have an identifier, so do this:
--     Transform the exp as we would the rhs of an assignment (which includes capturing a value).
--     Compile the exp to a pattern.
--     Proceed as above based on whether the pattern is marked "raw" or not.

-- syntax.top_level_transform =
--    syntax.compose(syntax.cooked_to_raw, syntax.capture)

function syntax.expression_p(ast)
   local name, body = next(ast)
   return ((name=="identifier") or
	   (name=="raw") or
	   (name=="raw_exp") or
	   (name=="cooked") or
	   (name=="literal") or
	   (name=="quantified_exp") or
	   (name=="named_charset") or
	   (name=="charset") or
	   (name=="choice") or
	   (name=="sequence") or
	   (name=="predicate"))
end

function syntax.top_level_transform(ast)
   local name, body = next(ast)
   if name=="identifier" then
      return syntax.id_to_ref(ast)
   elseif syntax.expression_p(ast) then
      local new = ast				    --syntax.capture(ast, "*")?
      if ((name=="raw") or (name=="literal") or (name=="charset") or
          (name=="named_charset") or (name=="predicate")) then
      	 new = syntax.raw(new)
      else
      	 new = syntax.append_looking_at_boundary(syntax.cook(new))
      end
      return syntax.generate("raw_exp", new)
   elseif (name=="assignment_") or (name=="alias_") then
      return syntax.to_binding(ast)
   elseif (name=="grammar_") then
      local new_bindings = map(syntax.to_binding, ast.grammar_.subs)
      local new = syntax.generate("new_grammar", table.unpack(new_bindings))
      new.new_grammar.text = ast.grammar_.text
      new.new_grammar.pos = ast.grammar_.pos
      return new
   elseif (name=="syntax_error") then
      return ast				    -- errors will be culled out later
   else
      error("Error in transform: unrecognized parse result: " .. name)
   end
end

-- function syntax.contains_capture(ast)
--    local name, body = next(ast)
--    if name=="capture" then return true; end
--    return reduce(or_function, false, map(syntax.contains_capture, body.subs))
-- end

---------------------------------------------------------------------------------------------------
-- Testing
---------------------------------------------------------------------------------------------------
-- syntax.assignment_to_alias =
--    syntax.make_transformer(function(ast)
-- 			      local name, body = next(ast)
-- 			      local lhs = body.subs[1]
-- 			      local rhs = body.subs[2]
-- 			      local b = syntax.generate("alias_", lhs, rhs)
-- 			      b.alias_.text = body.text
-- 			      b.alias_.pos = body.pos
-- 			      return b
-- 			   end,
-- 			   "assignment_",
-- 			   false)

return syntax


