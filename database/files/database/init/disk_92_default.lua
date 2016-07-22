#!/usr/bin/lua

package.path = "../?.lua;" .. package.path

local lfs = require("lfs")
local dc = require("dbcommon")
local common = require("common")
local js = require("cjson.safe")
local config = require("config")

local read = common.read
local shpath = "../db.sh"

local function fatal(fmt, ...)
	io.stderr:write(string.format(fmt, ...), "\n")
	os.exit(1)
end

local function backup_disk(cfg)
	local cmd = string.format("%s backup %s %s", shpath, cfg:disk_dir(), cfg:work_dir())
	local ret, err = os.execute(cmd)
	local _ = (ret == true or ret == 0) or fatal("backup_disk fail %s %s", cmd, err)
end

local cmd_map = {}

function cmd_map.kv(conn)
	local sql = string.format("select * from kv")
	local rs, e = conn:select(sql)
	local exist_map = {}
	for _, r in ipairs(rs) do
		exist_map[r.k] = r
	end

	local new_map = {
		{k = "offline_time", v = "1800"},
		{k = "redirect_ip", v = "1.0.0.8"},
		{k = "no_flow_timeout", v = "1800"},
	}

	local miss, find = {}, false
	for _, r in ipairs(new_map) do 
		if not exist_map[r.k] then 
			miss[r.k], find = r, true
		end 
	end

	if not find then 
		return false 
	end

	local arr = {}
	for k, r in pairs(miss) do
		table.insert(arr, string.format("('%s','%s')", k, r.v))
	end

	local sql = string.format("insert into kv (k, v) values %s", table.concat(arr, ","))
	local r, e = conn:execute(sql) 
	local _ = r or fatal("%s %s", sql , e)
	return true
end

function cmd_map.iface(conn)
	local s = read("uci show network | grep device", io.popen)
	local map = {}
	for idx, ifname in s:gmatch("device%[(%d+)%]%.ifname='(.-)'") do 
		map[idx] = {ifname = ifname}
	end
	for idx, mac in s:gmatch("device%[(%d+)%]%.macaddr='(.-)'") do 
		map[idx].mac = mac
	end

	local sql = string.format("select * from iface")
	local rs, e = conn:select(sql)
	local exist_map, maxid = {}, 0
	for _, r in ipairs(rs) do 
		exist_map[r.name] = r
		local fid = tonumber(r.fid)
		if fid > maxid then 
			maxid = fid 
		end
	end

	local miss, find = {}, false
	for idx, iface in pairs(map) do
		local name = iface.ifname
		if not exist_map[name] then 
			miss[name], find = iface, true
		end
	end

	if not find then 
		return false 
	end

	local arr = {}
	for name, iface in pairs(miss) do 
		maxid = maxid + 1
		table.insert(arr, string.format("(%s,'%s','ether',1500,'%s')", maxid, name, iface.mac))
	end

	local sql = string.format("insert into iface (fid,name,ethertype,mtu,mac) values %s", table.concat(arr, ","))
	local r, e = conn:execute(sql)
	local _ = r or fatal("%s %s", sql , e)
	return true
end

local function main()
	local cfg, e = config.ins() 		assert(cfg, e)
	local conn = dc.new(cfg:get_workdb()) 

	local change = false
	for _, f in pairs(cmd_map) do 
		local r, e = f(conn)
		change = change and change or r
	end

	if change then 
		backup_disk(cfg)
	end

	-- conn:close()
end

main()