-- Query a Slack archive.
--
-- Load it up using `lua -i`

json = require 'json'

if #arg ~= 3 then
  io.stderr:write('Tell me 3 things in the right order on a single line:\n')
  io.stderr:write('  - where the channels.json is\n')
  io.stderr:write('  - where the users.json is\n')
  io.stderr:write('  - a file containing a list of files to scan\n')
  io.stderr:write('\nFor example:\n')
  io.stderr:write('  lua -i query.lua input/channels.json input/users.json file_list\n')
  io.stderr:write('\nfile_list must include a list of relative paths from the current directory.\n')
  io.stderr:write('See README.md for details.\n')
  os.exit(1)
end

function main(channels, users, files)
  -- load all channels entirely into memory
  -- we'll need them to construct lists
  io.stderr:write('read\n')
  local posts = {}
  for i, file in ipairs(files) do
    local chan = channel(file)
    if posts[chan] == nil then
      posts[chan] = {}
    end
    read_items(file, posts[chan])
  end
  posts_by_comments = {}
  posts_by_commenters = {}
  posts_by_reactions = {}
  for chan,posts in pairs(posts) do
--?     print(chan)
    for ts, post in pairs(posts) do
      post.comments = nil
      post.channel = chan
--?       print(json.encode(post))
      if post.reactions then
        local num_reactions = total_unique_users(post.reactions)
        if posts_by_reactions[num_reactions] == nil then
          posts_by_reactions[num_reactions] = {}
        end
        table.insert(posts_by_reactions[num_reactions], post)
      end
      if post.reply_count then
        local count = tonumber(post.reply_count)
        if posts_by_comments[count] == nil then
          posts_by_comments[count] = {}
        end
        table.insert(posts_by_comments[count], post)
      end
      if post.reply_users_count then
        local count = tonumber(post.reply_users_count)
        if posts_by_commenters[count] == nil then
          posts_by_commenters[count] = {}
        end
        table.insert(posts_by_commenters[count], post)
      end
    end
  end
end

function total_unique_users(reactions)
  local result = 0
  for k, v in pairs(reactions) do
    if v.count then
      result = result + tostring(v.count)
    end
  end
  return result
end

function slug(post)
  return post.channel..'/'..post.ts
end

function url(post)
  return ('https://akkartik.name/archives/foc/%s/%s.html'):format(post.channel, post.ts)
end

function topn(buckets, n)
  keys = {}
  for k,v in pairs(buckets) do
    table.insert(keys, k)
  end
  table.sort(keys, function(a, b) return a > b end)
  local count = 0
  for _, k in ipairs(keys) do
    print('--', k)
    for _,post in ipairs(buckets[k]) do
      print(slug(post))
      count = count+1
    end
    if count > n then
      break
    end
  end
end

array = {}
function array.find(arr, elem)
  for i,x in ipairs(arr) do
    if x == elem then
      return i
    end
  end
  return nil
end

function read_items(filename, out)
  local items = read_json_array_of_items(filename)
--?   print(filename, #items)
  for _, item in ipairs(items) do
    if item.ts == nil then
      print('ignoring', filename)
    elseif not item.thread_ts then
      -- top-level post
      assert(out[item.ts] == nil)
      out[item.ts] = item
    elseif item.ts == item.thread_ts then
      assert(out[item.ts] == nil)
      out[item.ts] = item
    else
      -- comment on a top-level post
      local parent = out[item.thread_ts]
      assert(parent)
      if parent.comments == nil then
        parent.comments = {item}
      else
        table.insert(parent.comments, item)
      end
    end
  end
end

function read_json_array_of_items(filename)
  local f = io.open(filename)
  local s = f:read('*a')
  f:close()
  return json.decode(s)
end

function lookup_channel_id(channels, channel)
  for k,chan in pairs(channels) do
    if chan.name == channel then
      return chan.id
    end
  end
end

function emit_post(outfile, post, site_prefix, channel, channels, users)
  if post and post.subtype == 'bot_message' then return end
  if post and post.subtype == 'file_comment' then return end  -- todo
  outfile:write('  <tr>\n')
  outfile:write('    <td style="width:72px; vertical-align:top; padding-bottom:1em">\n')
  if post.user_profile and post.user_profile.image_72 then
    outfile:write('      <img src="'..post.user_profile.image_72..'" style="float:left"/>\n')
  end
  outfile:write('      <a href="'..site_prefix..channel..'/'..post.ts..'.html" style="color:#aaa">#</a>\n')
  outfile:write('    </td>\n')
  outfile:write('    <td style="vertical-align:top; padding-bottom:1em; padding-left:1em">\n')
  if post.user_profile == nil and post.user == nil and post.username == nil then
    io.stderr:write('no author for '..json.encode(post)..'\n')
  else
    emit_name(outfile, post.user_profile, post.user or post.username, users)
  end
  emit_time(outfile, post.ts)
  outfile:write('<br/>\n')
  emit_text(outfile, post.text, channel, channels, users)
  outfile:write('    </td>\n')
  outfile:write('  </tr>\n')
end

-- bart's comment at https://stackoverflow.com/questions/1426954/split-string-in-lua
function split(inputstr, sep)
  sep=sep or '%s'
  local t={}
  for field,s in string.gmatch(inputstr, "([^"..sep.."]*)("..sep.."?)") do
    table.insert(t,field)
    if s=="" then return t end
  end
end

function emit_comment(outfile, comment, site_prefix, channel, post_ts, channels, users)
  outfile:write('    <td style="vertical-align:top; padding-bottom:1em">\n')
  outfile:write('      <a name="'..comment.ts..'"></a>\n')
  if comment.user_profile and comment.user_profile.image_72 then
    outfile:write('      <img src="'..comment.user_profile.image_72..'" style="float:left"/>\n')
  end
  outfile:write('      <a href="'..site_prefix..channel..'/'..post_ts..'.html#'..comment.ts..'" style="color:#aaa">#</a>\n')
  outfile:write('    </td>\n')
  outfile:write('    <td style="vertical-align:top; padding-bottom:1em; padding-left:1em">\n')
  if comment.user_profile == nil and comment.user == nil and comment.username == nil then
    io.stderr:write('no author for '..json.encode(comment)..'\n')
  else
    emit_name(outfile, comment.user_profile, comment.user or comment.username, users)
  end
  emit_time(outfile, comment.ts)
  outfile:write('<br/>\n')
  emit_text(outfile, comment.text, channel, channels, users)
  outfile:write('    </td>\n')
end

function name(user)
  if not is_blank(user.real_name) then
    return user.real_name
  elseif not is_blank(user.display_name) then
    return user.display_name
  elseif not is_blank(user.name) then
    return user.name
  end
  return ''
end

function channel(filename)
  return basename(dirname(filename))
end

function dirname(path)
  return string.gsub(path, "(.*)/.*", "%1")
end

function basename(path)
  return string.gsub(path, ".*/(.*)", "%1")
end

function is_blank(s)
  return s == nil or s == ''
end

function read_json_array(filename)
  local result = {}
  local item_list = json.decode(io.open(filename):read('*a'))
  for _, x in ipairs(item_list) do
    assert(x.id)
    result[x.id] = x
  end
  return result
end

function read_file_list(filename)
  local result = {}
  for line in io.open(filename):lines() do
    table.insert(result, line)
  end
  return result
end

local channels = read_json_array(arg[1])
local users = read_json_array(arg[2])
local files = read_file_list(arg[3])

main(channels, users, files)
