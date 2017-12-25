--
-- Helper functions
--

local function is_water(pos)
	local nn = minetest.get_node(pos).name
	return minetest.get_item_group(nn, "water") ~= 0
end


local function get_sign(i)
	if i == 0 then
		return 0
	else
		return i / math.abs(i)
	end
end


local function get_velocity(v, yaw, y)
	local x = -math.sin(yaw) * v
	local z =  math.cos(yaw) * v
	return {x = x, y = y, z = z}
end


local function get_v(v)
	return math.sqrt(v.x ^ 2 + v.z ^ 2)
end

--
-- Boat entity
--

local boat = {
	physical = true,
	-- Warning: Do not change the position of the collisionbox top surface,
	-- lowering it causes the boat to fall through the world if underwater
	collisionbox = {-0.5, -0.35, -0.5, 0.5, 0.3, 0.5},
	visual = "mesh",
	mesh = "boats_boat.obj",
	textures = {"default_wood.png"},

	driver = nil,
	v = 0,
	last_v = 0,
	removed = false
}


function boat.on_rightclick(self, clicker)
	if not clicker or not clicker:is_player() then
		return
	end
	local name = clicker:get_player_name()
	if self.driver and clicker == self.driver then
		self.driver = nil
		clicker:set_detach()
		default.player_attached[name] = false
		default.player_set_animation(clicker, "stand" , 30)
		local pos = clicker:getpos()
		pos = {x = pos.x, y = pos.y + 0.2, z = pos.z}
		minetest.after(0.1, function()
			clicker:setpos(pos)
		end)
	elseif not self.driver then
		local attach = clicker:get_attach()
		if attach and attach:get_luaentity() then
			local luaentity = attach:get_luaentity()
			if luaentity.driver then
				luaentity.driver = nil
			end
			clicker:set_detach()
		end
		if not self.selfdriving then
		   minetest.chat_send_player(name,"Press E to save path and enter automatic mode")
		end
		self.driver = clicker
		clicker:set_attach(self.object, "",
			{x = 0, y = 11, z = -3}, {x = 0, y = 0, z = 0})
		default.player_attached[name] = true
		minetest.after(0.2, function()
			default.player_set_animation(clicker, "sit" , 30)
		end)
		clicker:set_look_horizontal(self.object:getyaw())
	end
end


function boat.on_activate(self, staticdata, dtime_s)
   self.object:set_armor_groups({immortal = 1})
   local data = {}
   if staticdata then
      data = minetest.deserialize(staticdata)
      if not data then
	 return
      end
      
      self.v = data.v
      self.instructions = data.instr
      self.selfdriving = data.sdr
      self.dnext = data.dn
      self.current = data.cur
   end
   self.last_v = self.v
end


function boat.get_staticdata(self)
   data = {v = self.v, instr = self.instructions, cur = self.current, sdr = self.selfdriving, dn = self.dnext}
   return minetest.serialize(data)
end


function boat.on_punch(self, puncher)
	if not puncher or not puncher:is_player() or self.removed then
		return
	end
	if self.driver and puncher == self.driver then
		self.driver = nil
		puncher:set_detach()
		default.player_attached[puncher:get_player_name()] = false
	end
	if not self.driver then
		self.removed = true
		local inv = puncher:get_inventory()
		if not (creative and creative.is_enabled_for
				and creative.is_enabled_for(puncher:get_player_name()))
				or not inv:contains_item("main", "advboats:boat") then
			local leftover = inv:add_item("main", "advboats:boat")
			-- if no room in inventory add a replacement boat to the world
			if not leftover:is_empty() then
				minetest.add_item(self.object:getpos(), leftover)
			end
		end
		-- delay remove to ensure player is detached
		minetest.after(0.1, function()
			self.object:remove()
		end)
	end
end
minetest.register_entity("advboats:mark", {
	initial_properties = {
		visual = "cube",
		visual_size = {x=1.1, y=1.1},
		textures = {"areas_pos1.png", "areas_pos1.png",
		            "areas_pos1.png", "areas_pos1.png",
		            "areas_pos1.png", "areas_pos1.png"},
		collisionbox = {-0.55, -0.55, -0.55, 0.55, 0.55, 0.55},
	},
	on_punch = function(self, hitter)
		self.object:remove()
	end,
})



function boat.round_pos(self)
   -- Round boat's position to the nearest integer location
   local pos = self.object:getpos()
   pos.x = math.floor(pos.x+0.5)
   pos.z = math.floor(pos.z+0.5)
   self.object:setpos(pos)
--   minetest.add_entity(pos, "advboats:mark")
end
boat.get_instr_pos = function (instruction)
   return {x=instruction[1], y=instruction[2], z=instruction[3]}
end

function boat.save_pos(self)
   local pos = self.object:getpos()
   local o = math.floor(self.object:getyaw()*4/math.pi+0.5)%8
   local s = self.v
--   minetest.chat_send_all(pos.x.." "..pos.y.." "..pos.z.." "..o.." "..s)
   if not self.instructions then
      self.instructions = {}
   end
   local last = self.instructions[#self.instructions]
   self.instructions[#self.instructions+1] = {pos.x, pos.y, pos.z, o, s}
   if not last then
      return
   end
   local lastpos = self.get_instr_pos(last)
--   minetest.chat_send_all("Last position:"..lastpos.x..","..lastpos.y..","..lastpos.z..", Distance to last position: "..vector.distance(pos,lastpos))
   
end

-- Instruction format:
-- {x, y, z, o, s}
-- x,y,z : Coords (int)
-- o: orientation in multiples of pi/4 (0 to 7)
-- s: target speed in m/s

function boat.selfdriving_step(self, dtime)
   if not self.instructions or #self.instructions == 1 then
      return
   end
   if not self.current then
      self.current = 1
      local instr = self.instructions[1]
      local curpos = self.get_instr_pos(instr)
      self.object:setpos(curpos)
      local nextpos = self.instructions[self.current+1]
      nextpos = self.get_instr_pos(nextpos)
      self.object:setpos(curpos)
      self.object:setyaw(core.dir_to_yaw(vector.direction(curpos,nextpos)))
      self.v = instr[5]
      self.dnext = vector.distance(curpos,nextpos)
   end
   if self.dnext < 0 then
      self.current = self.current + 1
      if self.current == #self.instructions then
	 local instr = self.instructions[self.current]
	 self.current = 0
	 local nextpos = self.instructions[1]
	 nextpos = self.get_instr_pos(nextpos)
	 local curpos = self.get_instr_pos(instr)
	 self.object:setyaw(core.dir_to_yaw(vector.direction(curpos,nextpos)))
	 self.dnext = vector.distance(curpos,nextpos)
	 return
      end
	    
      local instr = self.instructions[self.current]
      local curpos = self.get_instr_pos(instr)
      local nextpos = self.instructions[self.current+1]
      if not nextpos then
	 nextpos = self.instructions[1]
      end
      nextpos = self.get_instr_pos(nextpos)
      self.object:setpos(curpos)
      self.object:setyaw(math.pi/4*instr[4])
      self.v = instr[5]
      self.dnext = vector.distance(curpos,nextpos)
   end
   self.dnext = self.dnext - math.abs(self.v*dtime)
--   minetest.chat_send_all(self.dnext)
end

function boat.on_step(self, dtime)
	self.v = get_v(self.object:getvelocity()) * get_sign(self.v)
	if self.driver and not self.selfdriving then
		local ctrl = self.driver:get_player_control()
		local yaw = self.object:getyaw()
		if ctrl.aux1 then
		   self.selfdriving = true
--		   minetest.chat_send_all("Boat is now selfdriving")
		end 
		if ctrl.up then
			self.v = self.v + 0.1
		elseif ctrl.down then
			self.v = self.v - 0.1
		end
		if ctrl.left and not self.pressed then
		   self.pressed = true
		   if self.v < 0 then
		      self.object:setyaw(yaw-math.pi/4)
		   else
		      self.object:setyaw(yaw+math.pi/4)
		   end
		   self:round_pos()
		   self:save_pos()
		elseif ctrl.right and not self.pressed then
		   self.pressed = true
		   if self.v < 0 then
		      self.object:setyaw(yaw+math.pi/4)
		   else
		      self.object:setyaw(yaw-math.pi/4)
		   end
		   self:round_pos()
		   self:save_pos()
		elseif not ctrl.right and not ctrl.left then
		   self.pressed = false
		end
	end
	if self.selfdriving then
	   self:selfdriving_step(dtime)
	end
	local velo = self.object:getvelocity()
	if self.v == 0 and velo.x == 0 and velo.y == 0 and velo.z == 0 then
		self.object:setpos(self.object:getpos())
		return
	end
	local s = get_sign(self.v)
--	self.v = self.v - 0.02 * s
	if s ~= get_sign(self.v) then
		self.object:setvelocity({x = 0, y = 0, z = 0})
		self.v = 0
		return
	end
	if math.abs(self.v) > 5 then
		self.v = 5 * get_sign(self.v)
	end

	local p = self.object:getpos()
	p.y = p.y - 0.5
	local new_velo
	local new_acce = {x = 0, y = 0, z = 0}
	if not is_water(p) then
		local nodedef = minetest.registered_nodes[minetest.get_node(p).name]
		if (not nodedef) or nodedef.walkable then
			self.v = 0
			new_acce = {x = 0, y = 1, z = 0}
		else
			new_acce = {x = 0, y = -9.8, z = 0}
		end
		new_velo = get_velocity(self.v, self.object:getyaw(),
			self.object:getvelocity().y)
		self.object:setpos(self.object:getpos())
	else
		p.y = p.y + 1
		if is_water(p) then
			local y = self.object:getvelocity().y
			if y >= 5 then
				y = 5
			elseif y < 0 then
				new_acce = {x = 0, y = 20, z = 0}
			else
				new_acce = {x = 0, y = 5, z = 0}
			end
			new_velo = get_velocity(self.v, self.object:getyaw(), y)
			self.object:setpos(self.object:getpos())
		else
			new_acce = {x = 0, y = 0, z = 0}
			if math.abs(self.object:getvelocity().y) < 1 then
				local pos = self.object:getpos()
				pos.y = math.floor(pos.y) + 0.5
				self.object:setpos(pos)
				new_velo = get_velocity(self.v, self.object:getyaw(), 0)
			else
				new_velo = get_velocity(self.v, self.object:getyaw(),
					self.object:getvelocity().y)
				self.object:setpos(self.object:getpos())
			end
		end
	end
	self.object:setvelocity(new_velo)
	self.object:setacceleration(new_acce)
end


minetest.register_entity("advboats:boat", boat)


minetest.register_craftitem("advboats:boat", {
	description = "Advanced Boat",
	inventory_image = "advboats_inventory.png",
	wield_image = "advboats_wield.png",
	wield_scale = {x = 2, y = 2, z = 1},
	liquids_pointable = true,
	groups = {flammable = 2},

	on_place = function(itemstack, placer, pointed_thing)
		local under = pointed_thing.under
		local node = minetest.get_node(under)
		local udef = minetest.registered_nodes[node.name]
		if udef and udef.on_rightclick and
				not (placer and placer:get_player_control().sneak) then
			return udef.on_rightclick(under, node, placer, itemstack,
				pointed_thing) or itemstack
		end

		if pointed_thing.type ~= "node" then
			return itemstack
		end
		if not is_water(pointed_thing.under) then
			return itemstack
		end
		pointed_thing.under.y = pointed_thing.under.y + 0.5
		boat = minetest.add_entity(pointed_thing.under, "advboats:boat")
		if boat then
--			boat:setyaw(placer:get_look_horizontal())
			if not (creative and creative.is_enabled_for
					and creative.is_enabled_for(placer:get_player_name())) then
				itemstack:take_item()
			end
		end
		return itemstack
	end,
})


minetest.register_craft({
	output = "advboats:boat",
	recipe = {
		{"",           "",           ""          },
		{"group:wood", "",           "group:wood"},
		{"group:wood", "group:wood", "group:wood"},
	},
})

minetest.register_craft({
	type = "fuel",
	recipe = "advboats:boat",
	burntime = 20,
})
