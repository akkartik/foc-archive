-- Generate a static website out of a Slack archive.

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

for i, a in ipairs(arg) do
  print(a)
end
