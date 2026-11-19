const fs = require('node:fs');
const path = require('node:path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
for (const file of ['Logic.lua', 'UncBars.lua', 'Options.lua']) {
  const source = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
  require('luaparse').parse(source, { luaVersion: '5.1' });
  lua.lua_pushstring(state, to_luastring(source));
  lua.lua_setglobal(state, to_luastring(file === 'Logic.lua' ? 'LOGIC_SOURCE' : file === 'Options.lua' ? 'OPTIONS_SOURCE' : 'ADDON_SOURCE'));
}
const test = fs.readFileSync(path.join(__dirname, 'runtime.lua'), 'utf8');
if (lauxlib.luaL_dostring(state, to_luastring(test)) !== lua.LUA_OK) {
  throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
}
console.log('Lua 5.1 syntax and mocked Forever runtime checks passed.');
