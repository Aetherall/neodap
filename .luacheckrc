-- Test configuration for luacheck
globals = { "vim" }
std = "luajit"
files["spec/"] = {
  std = "+busted"
}
