package = "strontium"
version = "1.0.0"
source = {
   url = "git://github.com/balt-dev/strontium",
   tag = "v1.0.0"
}
description = {
   homepage = "https://github.com/balt-dev/strontium",
   issues_url = "https://github.com/balt-dev/strontium/issues",
   license = "MIT",
   maintainer = "baltdev <heptor42+luarocks@gmail.com>",
   labels = { "parsing" },
   summary = "A pure Lua, one file, dead-simple LL(k) parser generator library."
}
dependencies = {
   "lua ~> 5"
}
build = {
   type = "none",
   install = {lua = {
      ["strontium"] = "strontium.lua"
   }},
   copy_directories = { "doc" }
}
