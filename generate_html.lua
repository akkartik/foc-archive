-- Generate a static website out of a Slack archive.

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
  io.stderr:write('  - the name of a directory to generate html files into\n')
  io.stderr:write('\nFor example:\n')
  io.stderr:write('  lua generate_html.lua input/channels.json input/users.json file_list output\n')
  io.stderr:write('\nfile_list must include a list of relative paths from the current directory.\n')
  io.stderr:write('See README.md for details.\n')
  os.exit(1)
end

function main(channels, users, files, output)
  -- Assumes:
  --   each channel gets its own top-level directory
  --   files for a channel are contiguously arranged in the file list
  --   files within a channel are in chronological order

  os.execute('mkdir -p '..output)

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

  io.stderr:write('threads\n')
  for channel, cposts in pairs(posts) do
    emit_files(cposts, channel, output, channels, users)
  end

  io.stderr:write('intros by people\n')
  -- urls for bookmarklets:
  --  javascript:(function(){ window.open('http://akkartik.name/archives/foc/introduce-yourself/'+((window.getSelection() != '' ? window.getSelection().toString() : prompt('Please enter a name (case sensitive)')).trim().replaceAll(/[^\w_.~-]/g, '-'))+'.html'); })();
  --  javascript:window.open('http://akkartik.name/archives/foc/introduce-yourself/'+((window.getSelection() != '' ? window.getSelection().toString() : prompt('Please enter a name (case sensitive)')).trim().replaceAll(/[^\w_.~-]/g, '-'))+'.html');undefined
  -- manual tests:
  --  selecting text on window
  --  typing in a name
  --  typing in a name with spaces
  --  typing in a name with special characters: ' Santiago Quintana (he/him)  '
  intros = {}  -- user id -> array of posts in #introduce-yourself
  for ts, post in pairs(posts['introduce-yourself']) do
    if post.user_profile then
      local id = post.user or post.username
      if intros[id] == nil then
        intros[id] = {post}
      else
        table.insert(intros[id], post)
      end
    end
  end
  for id, userdata in pairs(users) do
    local name = userdata.real_name or userdata.name
    local filename = output..'/introduce-yourself/'..encode_for_url(name)..'.html'
    if intros[id] then
      table.sort(intros[id], function(a, b) return a.ts < b.ts end)
      emit_intro(filename, name, intros[id], channels, users)
    end
  end
end

function read_items(filename, out)
  local items = read_json_array_of_items(filename)
--?   print(filename, #items)
  for _, item in ipairs(items) do
    if not item.thread_ts then
      -- top-level post
      out[item.ts] = item
    elseif item.ts == item.thread_ts then
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

function emit_files(posts, channel, output, channels, users)
  if channel == nil then return end
--?   io.stderr:write('emitting #'..channel..'\n')
  os.execute('mkdir -p '..output..'/'..channel)
  emit_posts(posts, channel, output, channels, users)
end

function emit_posts(posts, channel, output, channels, users)
  for ts, post in pairs(posts) do
    local outfilename = output..'/'..channel..'/'..post.ts..'.html'
    local outfile = io.open(outfilename, 'w')
    if outfile == nil then
      error('could not open '..outfilename)
    end
    emit_post(outfile, post, '../', channel, channels, users)
    outfile:close()
  end
end

function emit_post(outfile, post, site_prefix, channel, channels, users)
  if post and post.subtype == 'bot_message' then return end
  if post and post.subtype == 'file_comment' then return end  -- todo
  outfile:write('<html>\n')
  outfile:write('<head><meta charset="UTF-8"></head>')
  outfile:write('<h2>Archives, <a href="https://futureofcoding.org/community">Future of Coding Community</a>, #'..channel..'</h2>\n')
  outfile:write('  <table>\n')
  emit_post_body(outfile, post, site_prefix, channel, channels, users)
  if post.comments then
    for _, comment in ipairs(post.comments) do
      outfile:write('  <tr>\n')
      emit_comment(outfile, comment, site_prefix, channel, post.ts, channels, users)
      outfile:write('  </tr>\n')
    end
  end
  outfile:write('  </table>\n')
  outfile:write('<hr>\n')
  outfile:write('<a href="'..repo..'">download this site</a> (~200MB)\n')
  outfile:write('</html>\n')
end

function emit_intro(outfilename, name, posts, channels, users)
--?   print(outfilename)
  local outfile = io.open(outfilename, 'w')
  outfile:write('<html>\n')
  outfile:write('<head><meta charset="UTF-8"></head>')
  outfile:write('<h2>Archives, <a href="https://futureofcoding.org/community">Future of Coding Community</a>, introductions by '..name..'</h2>\n')
  outfile:write('  <table>\n')
  for _, post in ipairs(posts) do
    emit_post_body(outfile, post, '../', 'introduce-yourself', channels, users)
  end
  outfile:write('  </table>\n')
  outfile:write('<hr>\n')
  outfile:write('<a href="'..repo..'">download this site</a> (~200MB)\n')
  outfile:write('</html>\n')
  outfile:close()
end

function emit_post_body(outfile, post, site_prefix, channel, channels, users)
  outfile:write('  <tr>\n')
  outfile:write('    <td style="vertical-align:top; padding-bottom:1em">\n')
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
  s = s:gsub('<([^@ |>][^ |>]*)>', '<a href="%1">%1</a>')
  -- convert external links with anchor text
  s = s:gsub('<([^@ |>][^ |>]*)|([^>]*)>', '<a href="%1">%2</a>')
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
  -- the remaining substitutions create <..> html, so come after link conversion
  -- also do them line by line to disambiguate e.g. emphasis from bullet lists
  local result = ''
  local fence = false  -- block ```
  for sx,newline in string.gmatch(s, '([^\n]*)(\n?)') do
    if sx:find('```') then
      if not fence then
        sx = sx:gsub('```', '<pre>')
      else
        sx = sx:gsub('```', '</pre>')
      end
      fence = not fence
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
local output = arg[4]

main(channels, users, files, output)
