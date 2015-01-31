--[[
LuCI - Lua Configuration Interface - rTorrent client

Copyright 2014-2015 Sandor Balazsi <sandor.balazsi@gmail.com>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id$
]]--

local rtorrent = require "rtorrent"
local own = require "own"
local nixio = require "nixio"
local common = require "luci.model.cbi.rtorrent.common"

local hash = luci.dispatcher.context.requestpath[4]
local details = rtorrent.batchcall(hash, "d.", {"name", "base_path", "done_percent"})
local files = rtorrent.multicall("f.", hash, 0, "path", "path_depth", "path_components", "size_bytes",
	"chunks_percent", "priority", "frozen_path")

local format = {}

function format.dir(r, v)
	return "<img style=\"vertical-align: text-top;\" src=\"/luci-static/resources/icons/filetypes/dir.png\" /> " .. v
end

function format.icon(r, v)
	local icon_path = "/luci-static/resources/icons/filetypes"
	local ext = v:match("%.([^%.]+)$")
	if ext and nixio.fs.stat("/www/%s/%s.png" % {icon_path, ext:lower()}, "type") then
		return "%s/%s.png" % {icon_path, ext:lower()}
	end
	return "%s/%s.png" % {icon_path, "file"}
end

function format.file(r, v)
	local url = luci.dispatcher.build_url("admin/rtorrent/download/") .. nixio.bin.b64encode(r["frozen_path"])
	local link = r["chunks_percent"] == 100 and "<a href=\"" .. url .. "\" style=\"color: #404040;\">" .. v .. "</a>" or v
	return "<img style=\"vertical-align: middle;\" src=\"" .. format["icon"](r, v) .. "\" /> " .. link
end

function format.size_bytes(r, v)
	return own.html(own.human_size(v), "nowrap", "center")
end

function format.chunks_percent(r, v)
	return own.html(string.format("%.1f%%", v), "center", "vcenter", v < 100 and "red")
end

function format.priority(r, v)
	return tostring(v)
end

function add_id(files)
	for i, r in ipairs(files) do
		r["id"] = i
	end
end

function path_compare(a, b)
	if a["path_depth"] ~= b["path_depth"] and (a["path_depth"] == 1 or b["path_depth"] == 1) then
		return a["path_depth"] > b["path_depth"]
	end
	return a["path"] < b["path"]
end

local list, last_path = {}, {}
add_id(files)
table.sort(files, path_compare)
for _, r in ipairs(files) do
	for i, p in ipairs(r["path_components"]) do
		if last_path[i] ~= p then
			local t = i == #r["path_components"] and "file" or "dir"
			local n = {}
			if t == "file" then
				for m, v in pairs(r) do
					n[m] = format[m] and format[m](r, v) or v
				end
			else
				n["priority"] = "hidden"
			end
			n["name"] = string.rep("&emsp;", i - 1) .. format[t](r, p)
			table.insert(list, n)
		end
		last_path[i] = p
	end
end

f = SimpleForm("rtorrent", details["name"])
f.redirect = luci.dispatcher.build_url("admin/rtorrent/main")
if nixio.fs.stat(details["base_path"], "type") == "dir" and table.getn(list) > 1 then
	f.cancel = "Download all"
else
	f.cancel = false
end

t = f:section(Table, list)
t.template = "rtorrent/list"
t.pages = common.get_pages(hash)
t.page = "file list"
t:option(DummyValue, "name", "Name").rawhtml = true
t:option(DummyValue, "size_bytes", own.html("Size", "center")).rawhtml = true
t:option(DummyValue, "chunks_percent", own.html("Done", "center", "title: Download done percent")).rawhtml = true

local rotate_prio_js = [[
	var inputs = document.getElementsByClassName("cbi-input-select");
	for (var i = 0; i < inputs.length; i++) {
		if (inputs[i].selectedIndex < inputs[i].length - 1) {
			inputs[i].selectedIndex++;
		} else {
			inputs[i].selectedIndex = 0;
		}
	}
]]
prio = t:option(ListValue, "priority", own.html("Priority", "center", "onclick: " .. rotate_prio_js, "title: Rotate priority"))
prio.style = "margin: 0px auto; display: block;"
prio:value("0", "off")
prio:value("1", "normal")
prio:value("2", "high")

function prio.write(self, section, value)
	rtorrent.call("f.set_priority", hash, list[tonumber(section)].id - 1, tonumber(value))
	luci.http.redirect(luci.dispatcher.build_url("admin/rtorrent/files/%s" % hash))
end

function f:on_cancel()
	luci.http.redirect(luci.dispatcher.build_url("admin/rtorrent/downloadall/")
		.. nixio.bin.b64encode(details["base_path"]))
end

return f

