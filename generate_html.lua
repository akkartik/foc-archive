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
    outfile:write(json.encode(post))
    outfile:close()
  end
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
