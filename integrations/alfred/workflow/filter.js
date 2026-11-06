#!/usr/bin/osascript -l JavaScript
// Stage One for Alfred (SO-092): the `st` Script Filter. Asks the `stage` CLI for scenes,
// groups and layouts (`stage list --json`) and turns the query into Alfred items.
//   st <scene>        restore a scene        ⌘↩ save the desk as <query>   ⌥↩ rewind 15 minutes
//   st save <name>    save the desk
//   st layout <kind>  arrange the stage
//   st rewind         go back 15 minutes, 1 hour or 3 hours
//   st g <group>      put a group on stage
ObjC.import('Foundation');
const app = Application.currentApplication();
app.includeStandardAdditions = true;

function stagePath() {
  const fm = $.NSFileManager.defaultManager;
  for (const p of ['/usr/local/bin/stage', '/opt/homebrew/bin/stage', '/Applications/Stage One.app/Contents/Helpers/stage']) {
    if (fm.isExecutableFileAtPath(p)) return p;
  }
  return null;
}

// Subsequence match with a bonus for word starts, like the app's own fuzzy search.
function score(q, text) {
  q = q.toLowerCase(); const t = text.toLowerCase();
  if (!q) return 0;
  let s = 0, ti = 0;
  for (const c of q) {
    const i = t.indexOf(c, ti);
    if (i < 0) return null;
    s += 1 + (i === 0 || t[i - 1] === ' ' ? 2 : 0) + (i === ti ? 0.5 : 0);
    ti = i + 1;
  }
  return s - t.length * 0.01;
}
function rank(items, q, key) {
  if (!q) return items;
  return items.map(i => [i, score(q, key(i))]).filter(x => x[1] !== null).sort((a, b) => b[1] - a[1]).map(x => x[0]);
}

const rewindMod = { arg: 'rewind\t15m', subtitle: 'Rewind the desk 15 minutes' };
function saveMod(name) {
  return name ? { arg: 'save\t' + name, subtitle: 'Save the desk as “' + name + '”' }
              : { valid: false, subtitle: 'Type a name, then ⌘↩ to save the desk as a scene' };
}

function run(argv) {
  const query = (argv[0] || '').trim();
  const stage = stagePath();
  if (!stage) {
    return JSON.stringify({ items: [{ title: 'Stage One’s command-line tool isn’t installed',
      subtitle: 'Open Stage One › Settings › General › Install the stage command', valid: false }] });
  }
  let data = { scenes: [], groups: [], layouts: ['free', 'halves', 'focus', 'thirds', 'grid'] };
  try {
    const out = app.doShellScript('"' + stage + '" list --json');
    const reply = JSON.parse(out);
    data.scenes = reply.scenes || [];
    data.groups = reply.groups || [];
    if (reply.layouts && reply.layouts.length) data.layouts = reply.layouts;
  } catch (e) {
    return JSON.stringify({ items: [{ title: 'Stage One isn’t running', subtitle: 'Open Stage One, then try again', valid: false }] });
  }

  const [verb, ...rest] = query.split(/\s+/);
  const tail = rest.join(' ');
  let items = [];

  if (verb === 'save') {
    items.push(tail
      ? { title: 'Save the desk as “' + tail + '”', subtitle: 'Every group and window, as a scene', arg: 'save\t' + tail }
      : { title: 'Save the desk as…', subtitle: 'Type a name', valid: false });
  } else if (verb === 'layout') {
    items = rank(data.layouts, tail, l => l).map(l => ({
      title: 'Arrange: ' + l[0].toUpperCase() + l.slice(1), subtitle: 'Arrange the windows on stage', arg: 'layout\t' + l,
      autocomplete: 'layout ' + l }));
  } else if (verb === 'rewind') {
    items = [['15m', '15 minutes'], ['60m', '1 hour'], ['180m', '3 hours']].map(([t, label]) => ({
      title: 'Rewind ' + label, subtitle: 'Put the desk back the way it was ' + label + ' ago', arg: 'rewind\t' + t }));
  } else if (verb === 'g') {
    items = rank(data.groups, tail, g => g.name).map(g => ({
      title: g.name, subtitle: 'Group ' + g.index + ' · ' + g.windows + ' window' + (g.windows === 1 ? '' : 's') + (g.active ? ' · on stage' : ''),
      arg: 'group\t' + g.name, autocomplete: 'g ' + g.name }));
  } else {
    items = rank(data.scenes, query, s => s.name).map(s => ({
      uid: 'scene:' + s.name,
      title: 'Restore ' + s.name,
      subtitle: s.windows + ' window' + (s.windows === 1 ? '' : 's') + ' in ' + s.groups + ' group' + (s.groups === 1 ? '' : 's') + (s.current ? ' · current' : ''),
      arg: 'restore\t' + s.name,
      autocomplete: s.name,
      mods: { cmd: saveMod(query), alt: rewindMod } }));
    if (!query) {
      items.push({ title: 'Save the desk as…', subtitle: 'st save <name>', autocomplete: 'save ', valid: false });
      items.push({ title: 'Arrange the stage', subtitle: 'st layout <kind>', autocomplete: 'layout ', valid: false });
      items.push({ title: 'Rewind the desk', subtitle: 'st rewind', autocomplete: 'rewind', valid: false });
      items.push({ title: 'Show a group', subtitle: 'st g <group>', autocomplete: 'g ', valid: false });
    } else if (!items.length) {
      items.push({ title: 'No scene matches “' + query + '”', subtitle: '⌘↩ saves the desk under that name',
        valid: false, mods: { cmd: saveMod(query), alt: rewindMod } });
    }
  }
  return JSON.stringify({ items });
}
