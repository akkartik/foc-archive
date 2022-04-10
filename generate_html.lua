-- Generate a static website out of a Slack archive.

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

function channel(filename)
  return basename(dirname(filename))
end

function dirname(path)
  return string.gsub(path, "(.*)/.*", "%1")
end

function basename(path)
  return string.gsub(path, ".*/(.*)", "%1")
end

function read_items(filename, out)
  local items = read_json_array_of_items(filename)
--?   print(filename, #items)
  for _, item in ipairs(items) do
    if not item.thread_ts then
      -- top-level post
--?       print('top '..item.ts)
      out[item.ts] = item
    elseif item.ts == item.thread_ts then
--?       print('top '..item.ts)
      out[item.ts] = item
    else
--?       print('comment '..item.ts..' '..item.thread_ts)
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
  return json.decode(io.open(filename):read('*a'))
end

function emit_files(posts, channel, output, channels, users)
  if channel == nil then return end
  io.stderr:write('emitting #'..channel..'\n')
  os.execute('mkdir -p '..output..'/'..channel)
  for ts, post in pairs(posts) do
    local outfilename = output..'/'..channel..'/'..post.ts..'.html'
    local outfile = io.open(outfilename, 'w')
    if outfile == nil then
      error('could not open '..outfilename)
    end
    emit_post(outfile, post, channel, users)
    outfile:close()
  end
end

function emit_post(outfile, post, channel, users)
  if post and post.subtype == 'bot_message' then return end
  if post and post.subtype == 'file_comment' then return end  -- todo
  outfile:write('<html>\n')
  outfile:write('<h2>#'..channel..'</h2>\n')
  outfile:write('  <table>\n')
  outfile:write('  <tr>\n')
  outfile:write('    <td style="vertical-align:top; padding-bottom:1em">\n')
  if post.user_profile and post.user_profile.image_72 then
    outfile:write('      <img src="'..post.user_profile.image_72..'" style="float:left"/>')
  end
  outfile:write('    </td>\n')
  outfile:write('    <td style="vertical-align:top; padding-bottom:1em; padding-left:1em">\n')
  if post.user_profile == nil and post.user == nil and post.username == nil then
    io.stderr:write('no author for '..json.encode(post)..'\n')
  else
    print_name(outfile, post.user_profile, post.user or post.username, users)
  end
  print_time(outfile, post.ts)
  outfile:write('<br/>')
  print_text(outfile, post.text)
  outfile:write('    </td>\n')
  outfile:write('</tr>')
  if post.comments then
    for _, comment in ipairs(post.comments) do
      emit_comment(outfile, comment, users)
    end
  end
  outfile:write('  </table>\n')
  outfile:write('<hr>\n')
  outfile:write('<a href="https://github.com/akkartik/foc-archive">download this site</a>\n')
  outfile:write('</html>\n')
end

function print_name(outfile, user, user_id, users)
  if user == nil then
    user = users[user_id]
    if user == nil then
      assert(user_id)
      outfile:write('<b>'..user_id..'</b>\n')
      return
    end
  end
  outfile:write('<b>')
  if not is_blank(user.real_name) then
    outfile:write(user.real_name)
  elseif not is_blank(user.display_name) then
    outfile:write(user.display_name)
  elseif not is_blank(user.name) then
    outfile:write(user.name)
  end
  outfile:write('</b>')
end

function print_time(outfile, ts)
  outfile:write('<span style="margin:2em; color:#606060">')
  outfile:write(os.date('%Y-%m-%d %H:%M', math.floor(tonumber(ts))))
  outfile:write('</span>')
end

function is_blank(s)
  return s == nil or s == ''
end

function print_text(outfile, s)
  local s = s:gsub('\n', '<br/>')
  s = s:gsub('(%W)_([^_]*)_(%W)', '%1<em>%2</em>%3')
  s = s:gsub('^_([^_]*)_(%W)', '<em>%1</em>%2')
  s = s:gsub('(%W)_([^_]*)_$', '%1<em>%2</em>')
  s = s:gsub('^_([^_]*)_$', '<em>%1</em>')
  s = s:gsub('(%W)%*([^%*]*)%*(%W)', '%1<b>%2</b>%3')
  s = s:gsub('^%*([^%*]*)%*(%W)', '<b>%1</b>%2')
  s = s:gsub('(%W)%*([^%*]*)%*$', '%1<b>%2</b>')
  s = s:gsub('^%*([^%*]*)%*$', '<b>%1</b>')
  outfile:write(s..'\n')
end

function emit_comment(outfile, comment, users)
  outfile:write('<div class="comment">')
  outfile:write('  <tr>\n')
  outfile:write('    <td style="vertical-align:top; padding-bottom:1em">\n')
  if comment.user_profile and comment.user_profile.image_72 then
    outfile:write('      <img src="'..comment.user_profile.image_72..'" style="float:left"/>')
  end
  outfile:write('    </td>\n')
  outfile:write('    <td style="vertical-align:top; padding-bottom:1em; padding-left:1em">\n')
  if comment.user_profile == nil and comment.user == nil and comment.username == nil then
    io.stderr:write('no author for '..json.encode(comment)..'\n')
  else
    print_name(outfile, comment.user_profile, comment.user or comment.username, users)
  end
  print_time(outfile, comment.ts)
  outfile:write('<br/>')
  print_text(outfile, comment.text)
  outfile:write('    </td>\n')
  outfile:write('</tr>')
  outfile:write('</div>')
end

-- Assumes:
--   each channel gets its own top-level directory
--   files for a channel are contiguously arranged in the file list
--   files within a channel are in chronological order

channels = read_json_array(arg[1])
users = read_json_array(arg[2])
files = read_file_list(arg[3])
output = arg[4]

-- load each channel entirely into memory before writing it out
local posts = {}
local channel_of_previous_file = nil
for i, file in ipairs(files) do
  local curr_channel = channel(file)
  if curr_channel ~= channel_of_previous_file then
    emit_files(posts, channel_of_previous_file, output, channels, users)
    posts = {}
  end
  read_items(file, posts)
  channel_of_previous_file = curr_channel
end
emit_files(posts, channel_of_previous_file, output, channels, users)
