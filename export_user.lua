-- Collect all top-level posts by a single user in a Slack archive.

-- variables interpolated into generated files
repo = 'https://github.com/akkartik/foc-archive'
upstream_slack = 'futureofcoding'

--

json = require 'json'

if #arg ~= 4 then
  io.stderr:write('Tell me 4 things in the right order on a single line:\n')
  io.stderr:write('  - where the channels.json is\n')
  io.stderr:write('  - where the users.json is\n')
  io.stderr:write('  - a file containing a list of files to scan\n')
  io.stderr:write('  - the name of the user\n')
  io.stderr:write('\nFor example:\n')
  io.stderr:write('  lua export_user.lua input/channels.json input/users.json file_list akkartik\n')
  io.stderr:write('\nfile_list must include a list of relative paths from the current directory.\n')
  io.stderr:write('See README.md for details.\n')
  os.exit(1)
end

function main(channels, users, files, username)
  local user_id = look_up_user(users, username)
  if user_id == nil then
    error('could not look up "' .. username ..'"')
  end

  -- load all channel posts into memory
  -- we'll need them to construct lists
  local posts = {}
  for i, file in ipairs(files) do
    local chan = channel(file)
    if posts[chan] == nil then
      io.stderr:write('reading '..chan..'\n')
      posts[chan] = {}
    end
    read_items(file, posts[chan])
  end

  io.stdout:write('<html>\n')
  io.stdout:write('<head><meta charset="UTF-8"></head>\n')
  local i = 1
  for channel, cposts in pairs(posts) do
    io.stderr:write('writing '..channel..'\n')
    io.stdout:write('<a name="'..i..'"></a><h1>'..channel..'</h1>\n')
    table.sort(cposts, function(a, b) return a.ts < b.ts end)
    for _,post in ipairs(cposts) do
      if post and post.user == user_id then
        io.stdout:write('  <table>\n')
        emit_post_body(io.stdout, post, '../', channel, channels, users)
        io.stdout:write('  </table>\n')
      end
    end
    i=i+1
  end
  io.stdout:write('<hr>\n')
  io.stdout:write('<a href="'..repo..'">download this site</a> (~35MB)\n')
  io.stdout:write('</html>\n')
  io.stdout:close()
end

function look_up_user(users, username)
  for id,user in pairs(users) do
    if user.real_name == username then
      return id
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
      io.stderr:write('ignoring '..filename..'\n')
    elseif not item.thread_ts then
      -- top-level post
      table.insert(out, item)
    elseif item.ts == item.thread_ts then
      table.insert(out, item)
    else
      -- comment on a top-level post
    end
  end
end

function read_json_array_of_items(filename)
  local f = io.open(filename)
  local s = f:read('*a')
  f:close()
  return json.decode(s)
end

function emit_post_body(outfile, post, site_prefix, channel, channels, users)
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

function emit_text(outfile, s, channel, channels, users)
  -- convert links to channels
  s = s:gsub('<(#[^ |>]*)|([^>]*)>', '#%2')  -- no channel pages at the moment
  -- convert external links without anchor text
--?   s = s:gsub('<([^@ |>][^ |>]*)>', '<a href="%1">%1</a>')  -- doesn't truncate
  while true do
--?     print('iter:', s)
    local link = s:match('<([^/@ |>][^ |>]*)>')  -- extra '/' to avoid matching on the </a> we generate
    if link == nil then
      break
    end
    -- get rid of trackers
    if link:match('[?&]utm_.*') then
      local link_without_trackers = link:gsub('[?&]utm_.*', '')
      local escaped_link = link:gsub('[%^%$%(%)%.%[%]%*%+%-%?%%]', '%%%0')  -- https://www.lua.org/manual/5.3/manual.html#6.4.1
      local escaped_link_without_trackers = link_without_trackers:gsub('%%', '%%%%')  -- replacement in gsub doesn't need to escape much
      print('replacing', link, 'with', link_without_trackers)
      s = s:gsub(escaped_link, escaped_link_without_trackers)
--?       print('=>', s)
      link = link_without_trackers
    end
    -- truncate long links on screen
    local link_text = link
    if #link_text > 80 then
      link_text = link_text:sub(1, 60)..'&hellip;'
--?       print('replacing', link, 'with', link_text)
--?     else
--?       print('no change to', link)
    end
    local escaped_link_text = link_text:gsub('%%', '%%%%')
    s = s:gsub('<([^@ |>/][^ |>]*)>', '<a href="%1">'..escaped_link_text..'</a>', 1)
  end
  -- convert external links with anchor text
--?   s = s:gsub('<([^@ |>][^ |>]*)|([^>]*)>', '<a href="%1">%2</a>')  -- doesn't truncate
  while true do
--?     print('iter:', s)
    local link, link_text = s:match('<([^/@ |>][^ |>]*)|([^>]*)>')  -- extra '/' to avoid matching on the </a> we generate
    if link == nil then
      break
    end
    -- get rid of trackers from link
    if link:match('[?&]utm_.*') then
      local link_without_trackers = link:gsub('[?&]utm_.*', '')
      local escaped_link = link:gsub('[%^%$%(%)%.%[%]%*%+%-%?%%]', '%%%0')  -- https://www.lua.org/manual/5.3/manual.html#6.4.1
      local escaped_link_without_trackers = link_without_trackers:gsub('%%', '%%%%')  -- replacement in gsub doesn't need to escape much
      print('replacing', link, 'with', link_without_trackers)
      s = s:gsub(escaped_link, escaped_link_without_trackers)
--?       print('=>', s)
      link = link_without_trackers
    end
    -- get rid of trackers from link_text
    if link_text:match('[?&]utm_.*') then
      local link_text_without_trackers = link_text:gsub('[?&]utm_.*', '')
      local escaped_link_text = link_text:gsub('[%^%$%(%)%.%[%]%*%+%-%?%%]', '%%%0')  -- https://www.lua.org/manual/5.3/manual.html#6.4.1
      local escaped_link_text_without_trackers = link_text_without_trackers:gsub('%%', '%%%%')  -- replacement in gsub doesn't need to escape much
      print('replacing link text', link_text, 'with', link_text_without_trackers)
      s = s:gsub(escaped_link_text, escaped_link_text_without_trackers)
--?       print('=>', s)
      link_text = link_text_without_trackers
    end
    -- truncate long links on screen
    if #link_text > 80 then
      link_text = link_text:sub(1, 60)..'&hellip;'
--?       print('replacing', link, 'with', link_text)
--?     else
--?       print('no change to', link)
    end
    local escaped_link_text = link_text:gsub('%%', '%%%%')
    s = s:gsub('<([^/@ |>][^ |>]*)|([^>]*)>', '<a href="%1">'..escaped_link_text..'</a>', 1)
  end
  -- convert links to tagged users
  tagged_user_ids = {}
  for user_tag in string.gmatch(s, '<@U[^ <>]*>') do
    table.insert(tagged_user_ids, user_tag:sub(3, -2))
  end
  for _, tagged_user_id in ipairs(tagged_user_ids) do
    s = s:gsub('<@'..tagged_user_id..'>', '<span style="background-color:#ccf">@'..name(users[tagged_user_id])..'</span>')
  end
  -- convert links to individual items to go to this archive
  slack_urls = {}
  for slack_url in string.gmatch(s, 'https://'..upstream_slack..'.slack.com/archives/[^/ ]*/p[0-9]*%?thread_ts=[0-9]*%.[0-9]*&?[^ \'"|<>]*') do
    -- turn slack_url into a regex
    slack_url = slack_url:gsub('%?', '%%?')
    table.insert(slack_urls, slack_url)
  end
  for _, slack_url in ipairs(slack_urls) do
    local channel_id, comment_ts_int, comment_ts_frac, post_ts = string.match(slack_url, 'https://'..upstream_slack..'.slack.com/archives/([^/ ]*)/p([0-9]*)([0-9][0-9][0-9][0-9][0-9][0-9])%%%?thread_ts=([0-9]*%.[0-9]*)')
    assert(channel_id)
    if channels[channel_id] then
      if channels[channel_id].name == channel then
        s = s:gsub(slack_url, post_ts..'.html#'..comment_ts_int..'.'..comment_ts_frac)
      else
        s = s:gsub(slack_url, '../'..channels[channel_id].name..'/'..post_ts..'.html#'..comment_ts_int..'.'..comment_ts_frac)
      end
    else
      io.stderr:write(channel_id..' not found\n')
    end
  end
  slack_urls = {}
  for slack_url in string.gmatch(s, 'https://'..upstream_slack..'.slack.com/archives/[^/ ]*/p[0-9]*') do
    table.insert(slack_urls, slack_url)
  end
  for _, slack_url in ipairs(slack_urls) do
    local channel_id, ts_int, ts_frac = string.match(slack_url, 'https://'..upstream_slack..'.slack.com/archives/([^/ ]*)/p([0-9]*)([0-9][0-9][0-9][0-9][0-9][0-9])')
    if channel_id then  -- check for truncation above
      if channels[channel_id] then
        if channels[channel_id].name == channel then
          s = s:gsub(slack_url, ts_int..'.'..ts_frac..'.html')
        else
          s = s:gsub(slack_url, '../'..channels[channel_id].name..'/'..ts_int..'.'..ts_frac..'.html')
        end
      else
        io.stderr:write(channel_id..' not found\n')
      end
    end
  end
  -- the remaining substitutions create <..> html, so come after link conversion
  -- also do them line by line to disambiguate e.g. emphasis from bullet lists
  local result = ''
  local fence = false  -- block ```
  for sx,newline in string.gmatch(s, '([^\n]*)(\n?)') do
    if sx:find('```') then
      while true do
        local nsubs
        if not fence then
          -- https://stackoverflow.com/questions/248011/how-do-i-wrap-text-in-a-pre-tag
          sx, nsubs = sx:gsub('```', '<pre style="white-space:pre-wrap">', 1)
        else
          sx, nsubs = sx:gsub('```', '</pre>', 1)
        end
        if nsubs == 0 then
          break
        end
        fence = not fence
      end
    else
      if not fence then
        if not sx:find('`') then
          sx = postprocess(sx)
        else
          local subresult = ''
          local backtick = false  -- inline `...`
          local first = true
          for frag in string.gmatch(sx, '[^`]*') do
            if not backtick then
              frag = postprocess(frag)
            end
            if first then
              subresult = subresult..frag
            else
              if backtick then
                subresult = subresult..'<tt>'..frag
              else
                subresult = subresult..'</tt>'..frag
              end
            end
            first = false
            backtick = not backtick
          end
          sx = subresult
        end
      end
    end
    result = result..sx
    if newline ~= '' then
      result = result..'<br/>'
    end
  end
  outfile:write(result..'\n')
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

function postprocess(s)
  s = s:gsub('(%W)_([^_]*)_(%W)', '%1<em>%2</em>%3')
  s = s:gsub('^_([^_]*)_(%W)', '<em>%1</em>%2')
  s = s:gsub('(%W)_([^_]*)_$', '%1<em>%2</em>')
  s = s:gsub('^_([^_]*)_$', '<em>%1</em>')
  s = s:gsub('(%W)%*([^%*]*)%*(%W)', '%1<b>%2</b>%3')
  s = s:gsub('^%*([^%*]*)%*(%W)', '<b>%1</b>%2')
  s = s:gsub('(%W)%*([^%*]*)%*$', '%1<b>%2</b>')
  s = s:gsub('^%*([^%*]*)%*$', '<b>%1</b>')
  s = s:gsub('^%s*%*', '<li>')
  return s
end

function emit_name(outfile, user, user_id, users)
  if user == nil then
    user = users[user_id]
    if user == nil then
      assert(user_id)
      outfile:write('<b>'..user_id..'</b>\n')
      return
    end
  end
  outfile:write('<b>'..name(user)..'</b>\n')
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

function emit_time(outfile, ts)
  outfile:write('<span style="margin:2em; color:#606060">')
  outfile:write(os.date('%Y-%m-%d %H:%M', math.floor(tonumber(ts))))
  outfile:write('</span>')
end

function channel(filename)
  return basename(dirname(filename))
end

-- https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
function encode_for_url(url)
  url = url:gsub('([^%w _ %- . ~])', '-')
  url = url:gsub(' ', '-')
  return url
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
local username = arg[4]

main(channels, users, files, username)
