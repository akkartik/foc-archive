data = {}

for line in io.lines(arg[1]) do
  local md5sum, filename = line:match('(%S*)%s*(%S*)')
  if data[md5sum] == nil then
    data[md5sum] = filename
  else
    if string.find(filename, data[md5sum], --[[init]] 1, --[[plain]] true) then
      print('rm '..filename)
    else
--?       print(filename, data[md5sum])
    end
  end
end
