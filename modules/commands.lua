local discordia = require('discordia')
local fs = require('fs')
local http = require('coro-http')

local random, max = math.random, math.max
local f, upper = string.format, string.upper
local insert, concat, sort = table.insert, table.concat, table.sort

local clamp = math.clamp -- luacheck: ignore
local pack = table.pack -- luacheck: ignore
local loader = loader -- luacheck: ignore

local Date = discordia.Date

local statusEnum = {online = 1, idle = 2, dnd = 3, offline = 4}
local statusText = {'Online', 'Idle', 'Do Not Disturb', 'Offline'}

local DAPI_GUILD = '81384788765712384'
local DISCORDIA_SUBS = '238388552663171072'
local BOOSTER_COLOR = 0xF47FFF
local SPOTIFY_GREEN = 0x1ED760

local helpers = loader.load('_helpers')

local prefix = '~~'
local function parseContent(content)
	if content:find(prefix, 1, true) ~= 1 then return end
	content = content:sub(prefix:len() + 1)
	local cmd, arg = content:match('(%S+)%s+(.*)')
	return cmd or content, arg
end

local cmds = {}
local replies = {}

local function onMessageCreate(msg)

	local cmd, arg = parseContent(msg.content)
	if not cmds[cmd] then return end

	if msg.author ~= msg.client.owner then
		print(msg.author.username, cmd) -- TODO: better command use logging
	end

	local success, content = pcall(cmds[cmd][1], arg, msg)

	local reply, err

	if success then -- command ran successfully

		if type(content) == 'string' then
			if #content > 1900 then
				reply, err = msg:reply {
					content = 'Content is too large. See attached file.',
					file = {os.time() .. '.txt', content},
					code = true,
				}
			elseif #content > 0 then
				reply, err = msg:reply(content)
			end
		elseif type(content) == 'table' then
			if content.content and #content.content > 1900 then
				local file = {os.time() .. '.txt', content.content}
				content.content = 'Content is too large. See attached file.'
				content.code = true
				if content.files then
					insert(content.files, file)
				else
					content.files = {file}
				end
			end
			reply, err = msg:reply(content)
		end

	else -- command produced an error, try to send it as a message

		reply = msg:reply {content = content,	code = 'lua'}

	end

	if reply then
		replies[msg.id] = reply
	elseif err then
		print(err)
	end

end

local function onMessageDelete(msg)
	if helpers.isBotAuthored(msg) then
		for k, reply in pairs(replies) do
			if msg == reply then
				replies[k] = nil
			end
		end
	else
		if replies[msg.id] then
			replies[msg.id]:delete()
			replies[msg.id] = nil
		end
	end
end

cmds['help'] = {function()
	local buf = {}
	for k, v in pairs(cmds) do
		insert(buf, f('%s - %s', k, v[2]))
	end
	sort(buf)
	return concat(buf, '\n')
end, 'This help command.'}

cmds['time'] = {function()
	return {embed = {description = Date():toISO(' ', ' UTC')}}
end, 'Provides the current time in an abbreviated UTC format.'}

cmds['roll'] = {function(arg)
	local n = tonumber(arg) or 6
	return {
		embed = {
			description = f('You roll a math.random(%i). It returns %i.', n, random(n))
		}
	}
end, 'Provides a random number.'}

cmds['flip'] = {function()
	return {
		embed = {
			description = f('You flip a coin. It lands on %s.', random(2) == 1 and 'heads' or 'tails')
		}
	}
end, 'Flips a coin.'}

cmds['whois'] = {function(arg, msg)

	local m, err = helpers.searchMember(msg, arg)
	if not m then
		return err
	end

	local color = m:getColor().value

	return {
		embed = {
			thumbnail = {url = m.avatarURL},
			fields = {
				{name = 'Name', value = m.nickname and f('%s (%s)', m.username, m.nickname) or m.username, inline = true},
				{name = 'Discriminator', value = m.discriminator, inline = true},
				{name = 'ID', value = m.id, inline = true},
				{name = 'Status', value = m.status:gsub('^%l', upper), inline = true},
				{name = 'Joined Server', value = m.joinedAt and m.joinedAt:gsub('%..*', ''):gsub('T', ' ') or '?', inline = true},
				{name = 'Joined Discord', value = Date.fromSnowflake(m.id):toISO(' ', ''), inline = true},
			},
			color = color > 0 and color or nil,
		}
	}

end, 'Provides information about a guild member.'}

cmds['avatar'] = {function(arg, msg)
	if not arg then
		return {embed = {image = {url = msg.author.avatarURL}}}
	else
		local member, err = helpers.searchMember(msg, arg)
		if not member then
			return err
		end
		return {embed = {image = {url = member.avatarURL}, description = member.mentionString}}
	end
end, 'Provides the avatar of a guild member.'}

cmds['icon'] = {function(_, msg)
	return {embed = {image = {url = msg.guild.iconURL}}}
end, 'Provides the guild icon.'}

cmds['serverinfo'] = {function(_, msg)

	local guild = msg.guild
	local owner = guild.owner

	return {
		embed = {
			thumbnail = {url = guild.iconURL},
			fields = {
				{name = 'Name', value = guild.name, inline = true},
				{name = 'ID', value = guild.id, inline = true},
				{name = 'Owner', value = owner.tag, inline = true},
				{name = 'Created', value = Date.fromSnowflake(guild.id):toISO(' ', ''), inline = true},
				{name = 'Members', value = guild.members:count(helpers.isOnline) .. ' / ' .. guild.totalMemberCount, inline = true},
				{name = 'Categories', value = tostring(#guild.categories), inline = true},
				{name = 'Text Channels', value = tostring(#guild.textChannels), inline = true},
				{name = 'Voice Channels', value = tostring(#guild.voiceChannels), inline = true},
				{name = 'Roles', value = tostring(#guild.roles), inline = true},
				{name = 'Emojis', value = tostring(#guild.emojis), inline = true},
			}
		}
	}

end, 'Provides information about the guild.'}

cmds['color'] = {function(arg)
	local c = discordia.Color(tonumber(arg))
	return {
		embed = {
			color = c.value,
			fields = {
				{name = 'Decimal', value = c.value},
				{name = 'Hexadecimal', value = c:toHex()},
				{name = 'RGB', value = f('%i, %i, %i', c:toRGB())},
				{name = 'HSV', value = f('%i, %.2f, %.2f', c:toHSV())},
				{name = 'HSL', value = f('%i, %.2f, %.2f', c:toHSL())},
			}
		}
	}
end, 'Provides some information about a provided color.'}

cmds['colors'] = {function(_, msg)

	local roles = msg.guild.roles:toArray('position', helpers.hasColor)

	local len = 0
	for _, role in ipairs(roles) do
		len = max(len, #role.name)
	end

	local ret = {}
	for i = #roles, 1, -1 do
		local role = roles[i]
		local c = role:getColor()
		local row = f('%s | %s | %s | %s | %s',
			role.name:pad(len, 'right'),
			c:toHex(),
			tostring(c.r):pad(3, 'right'),
			tostring(c.g):pad(3, 'right'),
			tostring(c.b):pad(3, 'right')
		)
		insert(ret, row)
	end

	return {content = concat(ret, '\n'), code = true}

end, 'Shows the colors of all of the colored roles in the guild.'}

cmds['poop'] = {function(arg, msg)

	local guild = msg.guild

	local author = guild:getMember(msg.author)
	if not author then return end

	if not author:hasPermission('manageNicknames') then return end
	if not guild.me:hasPermission('manageNicknames') then return end

	local member = helpers.searchMember(msg, arg)
	if not member then return end

	if author.highestRole.position > member.highestRole.position then
		if member:setNickname('💩') then
			return msg:addReaction('✅')
		end
	end

end, 'Moderator only. Changes a nickname to a poop emoji.'}

local sandbox = setmetatable({
	require = require,
	discordia = discordia,
}, {__index = _G})

cmds['lua'] = {function(arg, msg)

	if not arg then return end

	if msg.author ~= msg.client.owner then return end

	arg = arg:gsub('```lua\n?', ''):gsub('```\n?', '')

	local lines = {}

	sandbox.message = msg
	sandbox.channel = msg.channel
	sandbox.guild = msg.guild
	sandbox.client = msg.client
	sandbox.print = function(...) insert(lines, helpers.printLine(...)) end
	sandbox.p = function(...) insert(lines, helpers.prettyLine(...)) end

	local fn, err = load(arg, 'Luna', 't', sandbox)
	if not fn then return error(err) end

	local res = pack(fn())
	if res.n > 0 then
		for i = 1, res.n do
			res[i] = tostring(res[i])
		end
		insert(lines, concat(res, '\t'))
	end

	if #lines > 0 then
		return {content = concat(lines, '\n'), code = 'lua'}
	end

end, 'Bot owner only. Executes Lua code.'}

cmds['subs'] = {function(_, msg)

	local guild = msg.client:getGuild(DAPI_GUILD)
	if not guild then return end
	local role = guild:getRole(DISCORDIA_SUBS)
	if not role then return end

	local n = 0
	local ret = {{}, {}, {}, {}}
	for member in role.members:iter() do
		insert(ret[statusEnum[member.status]], member.name)
		n = n + 1
	end

	local fields = {}
	for i, v in ipairs(ret) do
		if #v > 0 then
			sort(v)
			insert(fields, {name = statusText[i], value = concat(v, ', ')})
		end
	end

	return {
		embed = {
			title = 'Discordia News Subscribers',
			description = 'Total: ' .. n,
			fields = fields
		}
	}

end, 'Shows all subscribers to the Discordia news role.'}

cmds['boosters'] = {function(_, msg)

	local guild = msg.guild

	local members = {}
	for member in guild.members:findAll(function(m) return m.premiumSince end) do
		insert(members, {member.premiumSince, member.username})
	end
	sort(members, function(a, b) return a[1] < b[1] end)

	local desc = {}
	local now = Date()
	for i, v in ipairs(members) do
		local days = (now - Date.fromISO(v[1]))
		insert(desc, f('%i. %s - %.2f', i, v[2], days:toDays()))
	end

	return {
		embed = {
			title = f('%s Boosters (name - days)', guild.name),
			description = concat(desc, '\n'),
			color = BOOSTER_COLOR,
		}
	}

end, 'Shows all current guild boosters.'}

cmds['lenny'] = {function()
	return '( ͡° ͜ʖ ͡°)'
end, '( ͡° ͜ʖ ͡°)'}

cmds['clean'] = {function(arg, msg)
	if msg.author == msg.client.owner and msg.guild.me:hasPermission(msg.channel, 'manageMessages') then
		if not tonumber(arg) then return end
		local messages = msg.channel:getMessagesAfter(arg, 100)
		if messages then
			return msg.channel:bulkDelete(messages)
		end
	end
end, 'Bot owner only. Cleans chat messages after a specific ID.'}

cmds['joined'] = {function(_, msg)

	local members = {}
	for m in msg.channel:getMessages(100):iter() do
		local member = m.member
		if member and member.joinedAt then
			members[member] = true
		end
	end

	local sorted = {}
	for member in pairs(members) do
		insert(sorted, {member.joinedAt, member.name})
	end
	sort(sorted, function(a, b) return a[1] > b[1] end)

	local fields = {}

	local now = Date()
	for i = 1, math.min(#sorted, 5) do
		local v = sorted[i]
		local seconds = Date.parseISO(v[1])
		local t = now - Date(seconds)
		insert(fields, {name = v[2], value = t:toString() .. ' ago'})
	end

	return {
		embed = {fields = fields}
	}

end, 'Shows recently joined members based on recent message authors.'}

cmds['playing'] = {function(arg, msg)

	local counts = helpers.zeroTable()
	for m in msg.guild.members:iter() do
		local name = not m.bot and m.activity and m.activity.type == 0 and m.activity.name
		if name then
			counts[name] = counts[name] + 1
		end
	end

	local sorted, n = {}, 0
	for name, count in pairs(counts) do
		if count > 1 then
			insert(sorted, {name, count})
			n = n + count
		end
	end
	sort(sorted, function(a, b) return a[2] > b[2] end)

	local tbl = {[0] = {' ', f('Common Applications (%i)', #sorted), f('Count (%i)', n)}}
	for i = 1, tonumber(arg) or 10 do
		local v = sorted[i]
		if v then
			tbl[i] = {tostring(i), sorted[i][1], tostring(sorted[i][2])}
		else
			break
		end
	end

	return helpers.markdown(tbl)

end, 'Shows common games according to playing statuses.'}

cmds['discrims'] = {function(arg, msg)

	local counts = helpers.zeroTable()

	for member in msg.guild.members:iter() do
		local d = tonumber(member.discriminator)
		counts[d] = counts[d] + 1
	end

	local sorted = {}
	for i = 1, 9999 do
		if counts[i] > 0 then
			insert(sorted, {i, counts[i]})
		end
	end

	sort(sorted, function(a, b) return a[2] > b[2] end)

	local content = {}
	local n = tonumber(arg) or 10
	for i = 1, n do
		local d = sorted[i]
		if d then
			local fmt = f('%%%ii | %%04i | %%i', #tostring(n))
			insert(content, f(fmt, i, d[1], d[2]))
		else
			break
		end
	end
	return {content = concat(content, '\n'), code = true}

end, 'Shows the top discriminators in use for the guild.'}

cmds['artists'] = {function(arg, msg)

	local listeners = 0
	local counts = {}

	for member in msg.guild.members:findAll(helpers.spotifyActivity) do
		local artist = member.activity.state
		if artist then
			listeners = listeners + 1
			local hash = artist
			helpers.spotifyIncrement(counts, hash, member)
		end

	end

	return helpers.spotifyEmbed(msg, 'Artists', listeners, counts, arg, SPOTIFY_GREEN)

end, 'Shows common artists according to Spotify statuses.'}

cmds['albums'] = {function(arg, msg)

	local listeners = 0
	local counts = {}

	for member in msg.guild.members:findAll(helpers.spotifyActivity) do
		local artist = member.activity.state
		local album = member.activity.textLarge
		if artist and album then
			listeners = listeners + 1
			local hash = f('%s by %s', album, artist)
			helpers.spotifyIncrement(counts, hash, member)
		end
	end

	return helpers.spotifyEmbed(msg, 'Albums', listeners, counts, arg, SPOTIFY_GREEN)

end, 'Shows common albums according to Spotify statuses.'}

cmds['tracks'] = {function(arg, msg)

	local listeners = 0
	local counts = {}

	for member in msg.guild.members:findAll(helpers.spotifyActivity) do
		local artist = member.activity.state
		local track = member.activity.details
		if artist and track then
			listeners = listeners + 1
			local hash = f('%s by %s', track, artist)
			helpers.spotifyIncrement(counts, hash, member)
		end
	end

	return helpers.spotifyEmbed(msg, 'Tracks', listeners, counts, arg, SPOTIFY_GREEN)

end, 'Shows common tracks according to Spotify statuses.'}

cmds['listening'] = {function(arg, msg)

	local member = arg and helpers.searchMember(msg, arg) or msg.guild:getMember(msg.author)
	if not member then return end

	local artist, album, track, start, stop, image
	if helpers.spotifyActivity(member) then
		artist = member.activity.state
		album = member.activity.textLarge
		track = member.activity.details
		start = member.activity.start
		stop = member.activity.stop
		image = member.activity.imageLarge
	end

	if artist and album and track and start and stop then

		local other = {artists = {}, albums = {}, tracks = {}}

		for m in msg.guild.members:findAll(helpers.spotifyActivity) do
			if m.id ~= member.id then
				local act = m.activity
				if act.state == artist then
					if act.textLarge == album then
						if act.details == track then
							insert(other.tracks, m.tag)
						else
							insert(other.albums, m.tag)
						end
					else
						insert(other.artists, m.tag)
					end
				end
			end
		end

		local fields = {
			{name = track, value = f('by %s on %s', artist, album)},
		}

		if #other.artists > 0 then
			insert(fields, {name = 'Current Artist Listeners', value = concat(other.artists, ', ')})
		end

		if #other.albums > 0 then
			insert(fields, {name = 'Current Album Listeners', value = concat(other.albums, ', ')})
		end

		if #other.tracks > 0 then
			insert(fields, {name = 'Current Track Listeners', value = concat(other.tracks, ', ')})
		end

		local thumbnail = image and helpers.getAlbumCover(image:match('spotify:(.*)'))

		return {
			file = thumbnail and {'image.jpg', thumbnail},
			embed = {
				author = {
					name = member.name,
					icon_url = member.avatarURL,
				},
				description = 'Listening on Spotify',
				fields = fields,
				color = SPOTIFY_GREEN,
				thumbnail = thumbnail and {url = "attachment://image.jpg"},
			}
		}

	end

end, 'Shows what a member is listening too according to a Spotify status.'}

cmds['steal'] = {function(arg, msg)

	if not arg then return end
	if msg.author ~= msg.client.owner then return end
	local messages = msg.channel:getMessages(50)

	arg = arg:lower()

	local subs = {}
	local other = {}

	for message in messages:iter() do
		for animated, name, id in message.content:gmatch('<(a?):([%w_]+):(%d+)>') do
			if name:lower():find(arg) then
				insert(subs, {name, id, animated == 'a'})
			else
				insert(other, {name, id, animated == 'a'})
			end
		end
	end

	local function levensort(a, b)
		return helpers.levenshtein(a[1], arg) < helpers.levenshtein(b[1], arg)
	end

	local emoji
	if subs[1] then
		sort(subs, levensort)
		emoji = subs[1]
	elseif other[1] then
		sort(other, levensort)
		emoji = other[1]
	end

	if emoji then
		local guild = msg.client:getGuild('149206227455311873')
		if guild then
			local ext = emoji[3] and 'gif' or 'png'
			local res, data = http.request('GET', f("https://cdn.discordapp.com/emojis/%s.%s", emoji[2], ext))
			if res.code == 200 then
				local filename = f('temp.%s', ext)
				fs.writeFileSync(filename, data) -- hack for now
				emoji = guild:createEmoji(emoji[1], filename)
				if emoji then
					return f("Emoji %s stolen!", emoji.mentionString)
				end
			end
		end
	end

end, 'Bot owner only. Steals an emoji.'}

cmds['emojify'] = {function(arg, msg)

	if msg.author ~= msg.client.owner then return end

	local member = helpers.searchMember(msg, arg)
	if not member then return end

	if member.avatar then
		local guild = msg.client:getGuild('149206227455311873')
		if guild then
			local ext = member.avatar:find('a_') and 'gif' or 'png'
			local res, data = http.request('GET', member.avatarURL)
			if res.code == 200 then
				local filename = f('temp.%s', ext)
				fs.writeFileSync(filename, data) -- hack for now
				local emoji = assert(guild:createEmoji(member.username, filename))
				return {mention = emoji}
			end
		end
	end

end, 'Bot owner only. Converts a member avatar into an emoji.'}

cmds['rate'] = {function(arg, msg)

	local n = tonumber(arg)
	n = n and clamp(arg, 2, 100) or 100

	local m = msg.channel:getMessages(n):toArray('id')
	n = #m

	local t = Date.fromSnowflake(m[1].id) - Date.fromSnowflake(m[n].id)

	local content = '%s message rate: **%g** per minute, or 1 every **%g** seconds, measured for the previous **%i**'

	return f(content, msg.channel.mentionString, n / t:toMinutes(), t:toSeconds() / n, n)

end, 'Shows the current rate of channel messages.'}

cmds['cleanup'] = {function(_, msg)

	local c = msg.channel
	local member = c.guild:getMember(msg.author)
	if not member then return end
	if not member:hasPermission(c, 'manageMessages') then return end

	if c.guild.me:hasPermission(c, 'manageMessages') then
		local messages = {}
		for message in c:getMessages(100):findAll(helpers.canBulkDelete) do
			local cmd = parseContent(message.content)
			if cmds[cmd] then
				insert(messages, message)
			end
		end
		c:bulkDelete(messages)
	else
		for message in c:getMessages(100):findAll(helpers.isBotAuthored) do
			message:delete()
		end
	end

end, 'Moderator only. Removes recently used commands.'}

local json = require('json')

cmds['msg'] = {function(arg, msg)

	if not tonumber(arg) then return end

	local data = msg.client._api:getChannelMessage(msg.channel.id, arg)

	return {
		content = json.encode(data, {indent = true}),
		code = 'json',
	}

end, 'Provides the raw JSON for a message.'}

cmds['ping'] = {function()
	return 'No.'
end, 'Ping command.'}

cmds['members'] = {function(arg, msg)

	local guild = msg.guild
	local lowered = arg:lower()

	local matches = {
		{title = 'Matched Usernames'},
		{title = 'Similar Usernames'},
		{title = 'Matched Nicknames', nick = true},
		{title = 'Similar Nicknames', nick = true},
	}

	local n = 5

	for member in guild.members:iter() do

		local username = member.username
		local loweredUsername = username:lower()
		if loweredUsername:find(lowered) then
			insert(matches[1], {member, helpers.levenshtein(username, arg)})
		else
			insert(matches[2], {member, helpers.levenshtein(username, arg)})
		end

		local nickname = member.nickname
		if nickname then
			local loweredNickname = nickname:lower()
			if loweredNickname:find(lowered) then
				insert(matches[3], {member, helpers.levenshtein(nickname, arg)})
			else
				insert(matches[4], {member, helpers.levenshtein(nickname, arg)})
			end
		end

	end

	for _, v in ipairs(matches) do
		sort(v, function(a, b) return a[2] < b[2]	end)
	end

	local fields = {}
	for _, v in ipairs(matches) do
		local field = {}
		if v.nick then
			field[0] = {'User', 'Nickname', 'Δ'}
		else
			field[0] = {'User', 'Δ'}
		end
		for j = 1, n do
			local member = v[j] and v[j][1]
			if member then
				if v.nick then
					insert(field, {member.tag, member.nickname, tostring(v[j][2])})
				else
					insert(field, {member.tag, tostring(v[j][2])})
				end
			end
		end
		if #field > 1 then
			insert(fields, {name = f('%s (%i)', v.title, #v), value = helpers.markdown(field)})
		end
	end

	return {
		embed = {
			fields = fields
		}
	}

end, 'Shows members that match a specific query.'}

cmds['quotelink'] = {function(_, msg)

	local messages = msg.channel:getMessages():toArray('id')
	local client = msg.client

	for i = #messages, 1, -1 do

		local m = messages[i]
		local guildId, channelId, messageId = m.content:match('https://.-%.?discordapp.com/channels/(%d+)/(%d+)/(%d+)')

		if guildId and channelId and messageId then

			local guild = assert(client:getGuild(guildId), 'unknown guild')
			local channel = assert(guild:getChannel(channelId), 'unknown channel')
			local bot = assert(guild:getMember(client.user))

			assert(bot:hasPermission(channel, 'readMessages'), 'missing read permission')
			assert(bot:hasPermission(channel, 'readMessageHistory'), 'missing read permission')
			assert(msg.member:hasPermission(channel, 'readMessages'), 'missing read permission')
			assert(msg.member:hasPermission(channel, 'readMessageHistory'), 'missing read permission')

			local message = assert(channel:getMessage(messageId) or channel:getMessagesAfter(messageId, 1):iter()())

			return helpers.makeQuote(message)

		end

	end

end, 'Shows the content of the most recent message link.'}

cmds['quote'] = {function(arg, msg)

	local client = msg.client

	local channelId, messageId = arg:match('(%d+)%D+(%d+)')

	if messageId and channelId then

		local channel = assert(client:getChannel(channelId), 'unknown channel')
		local bot = assert(msg.guild:getMember(client.user))

		assert(bot:hasPermission(channel, 'readMessages'), 'missing read permission')
		assert(bot:hasPermission(channel, 'readMessageHistory'), 'missing read permission')
		assert(msg.member:hasPermission(channel, 'readMessages'), 'missing read permission')
		assert(msg.member:hasPermission(channel, 'readMessageHistory'), 'missing read permission')

		local message = assert(channel:getMessage(messageId))

		return helpers.makeQuote(message)

	else

		messageId = arg:match('%d+')
		if messageId then
			local message = assert(msg.channel:getMessage(messageId))
			return helpers.makeQuote(message)
		end

	end

end, 'Shows a quote based on the provided [message id] or [channel id] [message id]'}

return {
	onMessageCreate = onMessageCreate,
	onMessageDelete = onMessageDelete,
}
