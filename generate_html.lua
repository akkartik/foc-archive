-- Generate a static website out of a Slack archive.

-- variables interpolated into generated files
repo = 'https://github.com/akkartik/foc-archive'

--

json = require 'json'

if #arg ~= 3 then
  io.stderr:write('Tell me 3 things in the right order on a single line:\n')
  io.stderr:write('  - where the users.json is\n')
  io.stderr:write('  - a file containing a list of files to scan\n')
  io.stderr:write('  - the name of a directory to generate html files into\n')
  io.stderr:write('\nFor example:\n')
  io.stderr:write('  lua generate_html.lua input/users.json file_list output\n')
  io.stderr:write('\nfile_list must include a list of relative paths from the current directory.\n')
  io.stderr:write('See README.md for details.\n')
  os.exit(1)
end

function main(users, files, output)
  -- Assumes:
  --   each channel gets its own top-level directory
  --   files for a channel are contiguously arranged in the file list
  --   files within a channel are in chronological order

  os.execute('mkdir -p '..output)
  copy_file('index.html', output)

  -- load all channels entirely into memory
  -- we'll need them to construct lists
  local posts = {}
  for i, file in ipairs(files) do
    local chan = channel(file)
    if posts[chan] == nil then
      posts[chan] = {}
    end
    read_items(file, posts[chan])
  end

  for channel, cposts in pairs(posts) do
    emit_files(cposts, channel, output, users)
  end

  emit_lists(posts, output, users)
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
  local f = io.open(filename)
  local s = f:read('*a')
  f:close()
  return json.decode(s)
end

function emit_files(posts, channel, output, users)
  if channel == nil then return end
  io.stderr:write('emitting #'..channel..'\n')
  os.execute('mkdir -p '..output..'/'..channel)
  emit_posts(posts, channel, output, users)
end

function emit_posts(posts, channel, output, users)
  for ts, post in pairs(posts) do
    local outfilename = output..'/'..channel..'/'..post.ts..'.html'
    local outfile = io.open(outfilename, 'w')
    if outfile == nil then
      error('could not open '..outfilename)
    end
    emit_post(outfile, post, '../', channel, users)
    outfile:close()
  end
end

function emit_post(outfile, post, site_prefix, channel, users)
  if post and post.subtype == 'bot_message' then return end
  if post and post.subtype == 'file_comment' then return end  -- todo
  outfile:write('<html>\n')
  outfile:write('<head><meta charset="UTF-8"></head>')
  outfile:write('<h2><a href="..">Archives</a>, <a href="https://futureofcoding.org/community">Future of Coding Community</a>, #'..channel..'</h2>\n')
  outfile:write('  <table>\n')
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
  emit_text(outfile, post.text, users)
  outfile:write('    </td>\n')
  outfile:write('  </tr>\n')
  if post.comments then
    for _, comment in ipairs(post.comments) do
      outfile:write('  <tr>\n')
      emit_comment(outfile, comment, site_prefix, channel, post.ts, users)
      outfile:write('  </tr>\n')
    end
  end
  outfile:write('  </table>\n')
  outfile:write('<hr>\n')
  outfile:write('<a href="'..repo..'">download this site</a> (~200MB)\n')
  outfile:write('</html>\n')
end

function emit_text(outfile, s, users)
  s = s:gsub('<(#[^ |>]*)|([^>]*)>', '#%2')  -- no channel pages at the moment
  s = s:gsub('<([^@ |>][^ |>]*)>', '<a href="%1">%1</a>')
  s = s:gsub('<([^@ |>][^ |>]*)|([^>]*)>', '<a href="%1">%2</a>')
  -- create a list of user ids to substitute
  tagged_user_ids = {}
  for user_tag in string.gmatch(s, '<@U[^ <>]*>') do
    table.insert(tagged_user_ids, user_tag:sub(3, -2))
  end
  -- substitute the users
  for _, tagged_user_id in ipairs(tagged_user_ids) do
    s = s:gsub('<@'..tagged_user_id..'>', '<span style="background-color:#ccf">@'..name(users[tagged_user_id])..'</span>')
  end
  s = s:gsub('\n', '<br/>')  -- must come after the <...> links syntax
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

function emit_comment(outfile, comment, site_prefix, channel, post_ts, users)
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
  emit_text(outfile, comment.text, users)
  outfile:write('    </td>\n')
end

function emit_lists(posts, output, users)
  emit_list('akkartik', output..'/akkartik.html', 'Kartik&apos;s favorites', posts, users)
end

function emit_list(infilename, outfilename, title, posts, users)
  local infile = io.open(infilename)
  local outfile = io.open(outfilename, 'w')
  outfile:write('<html>\n')
  outfile:write('<head>\n')
  outfile:write('  <meta charset="UTF-8">\n')
  outfile:write('  <title>'..title..'</title>\n')
  outfile:write('</head>\n')
  outfile:write('<h2><a href="..">Archives</a>, <a href="https://futureofcoding.org/community">Future of Coding Community</a>, '..title..'</h2>\n')
  outfile:write('  <table>\n')
  for line in infile:lines() do
    emit_post_or_comment(outfile, line, posts, users)
  end
  outfile:write('  </table>\n')
  outfile:write('<hr>\n')
  outfile:write('<a href="'..repo..'">download this site</a> (~200MB)\n')
  outfile:write('</html>\n')
  infile:close()
  outfile:close()
end

function emit_post_or_comment(outfile, id, posts, users)
  outfile:write('  <tr>\n')
  if not string.match(id, '#') then
    -- post
    local channel, post_ts = string.match(id, '(.*)/(.*)%.html')
    local post = posts[channel][post_ts]
    outfile:write('    <td style="vertical-align:top; padding-bottom:1em">\n')
    if post.user_profile and post.user_profile.image_72 then
      outfile:write('      <img src="'..post.user_profile.image_72..'" style="float:left"/>')
    end
    outfile:write('      <a href="'..channel..'/'..post.ts..'.html" style="color:#aaa">#</a>\n')
    outfile:write('    </td>\n')
    outfile:write('    <td style="vertical-align:top; padding-bottom:1em; padding-left:1em">\n')
    if post.user_profile == nil and post.user == nil and post.username == nil then
      io.stderr:write('no author for '..json.encode(post)..'\n')
    else
      emit_name(outfile, post.user_profile, post.user or post.username, users)
    end
    emit_time(outfile, post.ts)
    outfile:write('<br/>\n')
    emit_text(outfile, post.text, users)
    outfile:write('    </td>\n')
  else
    -- comment
    local channel, post_ts, comment_ts = string.match(id, '(.*)/(.*)%.html#(.*)')
    local comment = find(posts[channel][post_ts].comments, function(c) return c.ts == comment_ts end)
    emit_comment(outfile, comment, '', channel, post_ts, users)
  end
  outfile:write('  </tr>\n')
end

function find(arr, pred)
  for _, x in ipairs(arr) do
    if pred(x) then
      return x
    end
  end
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

function dirname(path)
  return string.gsub(path, "(.*)/.*", "%1")
end

function basename(path)
  return string.gsub(path, ".*/(.*)", "%1")
end

function copy_file(src_filename, dest_dir)
  local infile = io.open(src_filename)
  local outfile = io.open(dest_dir..'/'..src_filename, 'w')
  outfile:write(infile:read('*a'))
  infile:close()
  outfile:close()
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

users = read_json_array(arg[1])
files = read_file_list(arg[2])
output = arg[3]

main(users, files, output)
