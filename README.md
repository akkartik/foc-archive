# Goals

* Self-contained; all you need is some sort of POSIX OS and Lua. No LuaRocks,
  no need to compile additional libraries.

# Steps

* Download and unzip a Slack archive to some directory, say `input/`.

* Generate a list of files inside all channels:
  ```
  ls input/*/*.json > file_list
  ```

* Generate html for `file_list` into directory `input/`:
  ```
  lua generate_html.lua input/channels.json input/users.json file_list output
  ```

  Works with any Lua >= 5.0.

  Does _not_ work with filenames with strange characters like spaces, but
  Slack exports seem well-behaved so far.

  Will not perform any operations outside of file operations, and will not
  perform file operations to anything outside of `file_list` and `output/`.
