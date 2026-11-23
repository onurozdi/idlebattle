import {
  WORLD, ISLANDS, SITES, FLOOR, METERS, KEY, SHOP, YARD, ICONS, clamp, toward, distance, fresh,
  bagSize, footprint, fits, landing, landAt, depthAt, LEVEL_WIDTH, PINE_ROCK_X, CAVE_LEDGE, CAVE_FLOOR, DECK,
} from './data.js?v=5';
import { createRenderer } from './render.js?v=5';
import { CAST_TIME, LIFT_TIME, RELEASE_TIME, chooseFish, fishItem, fishSpecies, rodCell } from './fish.js?v=5';

const $ = (id) => document.getElementById(id);
const canvas = $('world');
const { draw: render, artIcon, ready: sceneryReady } = createRenderer(canvas);
const W = canvas.width;
const H = canvas.height;
const keys = new Set();
const pressed = new Set();
const keyMap = {
  ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right',
  ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down',
  Space: 'jump', KeyE: 'action', KeyF: 'utility',
};
let gamepadButtons = [];
let stick = { x: 0, y: 0 };
let pad = { x: 0, y: 0 };
let data = fresh();
let dock = -1;
let player = { x: 122, y: 340, vx: 0, vy: 0, face: 1, crouch: false };
let camera = { x: 0, y: 0 };
let time = 0;
let noticeTime = 0;
let anchor = null;
let dive = null;
let fishing = null;
let returnScene = 'land';
let caveDig = 0;
let ui = '';
let pending = null;
let bag = 'backpack';
let bagTarget = null;
let activeActions = [];
let activeKey = '';
let choice = 0;
let choiceGroup = '';
let shots = [];
let animals = [];
let localSound;
let debugStep = 0;
const winchCapacity = [0, 75, 155, 260];
const tubeTime = [0, 46, 79, 122];
const lineCapacity = [0, 65, 82, 100];
const townDoors = [
  [363, 'Restaurant'], [511, 'Hotel'], [736, 'Hunting Shop'], [864, 'Shipyard'], [1089, 'Clothier'],
];

function silenceSound() {
  if (!data.sound) return;
  try {
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (!Audio) return;
    localSound ??= new Audio();
    if (localSound.state !== 'running') void localSound.resume().catch(() => {});
    const oscillator = localSound.createOscillator();
    const gain = localSound.createGain();
    oscillator.frequency.value = 370;
    gain.gain.value = .035;
    gain.gain.exponentialRampToValueAtTime(.001, localSound.currentTime + .09);
    oscillator.connect(gain).connect(localSound.destination);
    oscillator.start();
    oscillator.stop(localSound.currentTime + .1);
  } catch {}
}
function toast(message, seconds = 3) {
  $('notice').textContent = message;
  noticeTime = seconds;
}
function save(quiet = false) {
  try {
    localStorage.setItem(KEY, JSON.stringify({ ...data, scene: 'sea' }));
    if (!quiet) toast('Saved. The voyage resumes at your current map position.');
  } catch {
    if (!quiet) toast('Local storage is unavailable.');
  }
}
function load(quiet = false) {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) {
      if (!quiet) toast('No saved voyage yet.');
      return false;
    }
    const saved = JSON.parse(raw);
    const base = fresh();
    data = { ...base, ...saved, scene: 'sea', gear: { ...base.gear, ...saved.gear }, condition: { ...base.condition, ...saved.condition } };
    for (const drop of data.drops) {
      if (drop.scene === 'land' && drop.island === 0) drop.wx = clamp(drop.wx, 40, LEVEL_WIDTH.pine - 65);
    }
    dock = -1;
    anchor = null;
    dive = null;
    fishing = null;
    pending = null;
    closePanel();
    if (!quiet) toast('Voyage loaded.');
    return true;
  } catch {
    toast('This save could not be opened.');
    return false;
  }
}
function panel(title, content, type = title) {
  ui = type;
  activeKey = '';
  $('context').replaceChildren();
  $('panel-title').textContent = title;
  $('panel-body').replaceChildren(...(Array.isArray(content) ? content : [content]));
  $('overlay').hidden = false;
  $('panel').focus();
}
function closePanel() {
  if (ui === 'bag' && pending) return;
  ui = '';
  $('overlay').hidden = true;
  activeKey = '';
}
function paragraph(text) {
  const p = document.createElement('p');
  p.textContent = text;
  return p;
}
function button(text, fn, className = '', value = '', disabled = false) {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = className;
  b.append(text);
  if (value) {
    const price = document.createElement('strong');
    price.textContent = value;
    b.append(price);
  }
  b.disabled = disabled;
  b.addEventListener('click', () => {
    silenceSound();
    fn();
  });
  return b;
}
function rows(entries) {
  const list = document.createElement('div');
  list.className = 'rows';
  list.append(...entries.map(([text, fn, value, disabled]) => button(text, fn, 'row', value, disabled)));
  return list;
}
function openSettings() {
  panel('Settings', rows([
    ['Save', () => { save(); closePanel(); }], ['Load', () => load()],
    ['Settings', preferences], ['Exit Game', exitGame],
  ]));
}
function preferences() {
  panel('Settings', rows([
    ['Sound', () => { data.sound = !data.sound; preferences(); }, data.sound ? 'On' : 'Off'],
    ['Camera lead', () => { data.shake = !data.shake; preferences(); }, data.shake ? 'On' : 'Off'],
    ['Controls', help], ['Back', openSettings],
  ]));
}
function exitGame() {
  panel('End playtest', rows([
    ['Save and return to title', () => { save(true); title(); }],
    ['Resume', closePanel],
  ]));
}
function help() {
  panel('Controls', [
    paragraph('Move with WASD, the arrow keys or the left stick. Space / A jumps. E / X interacts. R / RB cycles nearby actions. F / B is the secondary action. Open Inventory with I / Y. Use the touch controls or trackpad for menus and bag placement.'),
    paragraph('At the crane, left/right changes reach, up/down changes the boom angle, Jump pays out chain, and Action retrieves it. Lower the boom over the stern before paying out. Hold Down while moving left/right with the chain stowed to trim the boat.'),
    rows([['Back', preferences]]),
  ]);
}
function title() {
  panel('Soundings', [
    paragraph('A maritime salvage playtest. Sail the islands, charter your workboat, and follow the lost survey expedition.'),
    rows([['Continue voyage', () => load() || closePanel()], ['Controls', help]]),
  ]);
}
function stats() {
  const clues = ['Ask the innkeeper about the old survey.', 'Search the cave for the missing survey note.', 'Recover the antique jar near Pine Island and bring it ashore.', 'The lost survey is recorded. Check the deeper buoys for the plane.'];
  panel('Stats', [
    paragraph(`Diving Suit Lv. ${data.gear.suit} · Oxygen Tank Lv. ${data.gear.tank} · Hooker Lv. ${data.gear.hooker}`),
    paragraph(`Winch Lv. ${data.gear.winch} · Shooting Lv. ${1 + Math.floor(data.shooting / 7)} · Salvage recovered ${data.completed.length}`),
    paragraph(`Lost Survey — ${clues[data.mystery]}`),
    paragraph(`On board: ${data.cargo.length ? data.cargo.map((load) => load.name).join(', ') : 'empty'}`),
    rows([['Controls', help]]),
  ]);
}
function spend(amount, fn) {
  if (data.cash < amount) {
    toast('Not enough money.');
    return;
  }
  data.cash -= amount;
  fn();
  save(true);
}
function shop(title, catalog) {
  const catalogRows = rows(catalog.map(([name, key, level, price]) => [
    `${name}${['belt', 'remote', 'repair', 'light'].includes(key) ? '' : ` · Lv. ${level}`}`,
    () => spend(price, () => {
      data.gear[key] = level;
      if (key === 'pistol' || key === 'knife') data.selected = key;
      if (key === 'winch') data.condition.winch = 100;
      toast(`${name} is ready.`);
      shop(title, catalog);
    }),
    (data.gear[key] || 0) >= level ? 'Owned' : `$${price}`,
    (data.gear[key] || 0) >= level,
  ]));
  catalog.forEach(([, key, level], index) => {
    if (key !== 'casting' && key !== 'jigging') return;
    const row = catalogRows.children[index];
    const label = document.createElement('span');
    label.append(artIcon('rods', rodCell(key === 'jigging' ? 'jig' : 'cast', level)), row.firstChild);
    label.className = 'shop-rod';
    row.prepend(label);
  });
  panel(title, catalogRows);
}
function repairs(aboard = false, filters = ['pistol', 'knife', 'rods', 'winch']) {
  panel(aboard ? 'Repair Station' : 'Repair', rows(Object.entries(data.condition).filter(([key]) => filters.includes(key)).map(([key, value]) => {
    const price = Math.ceil((100 - value) / 3);
    return [`${key[0].toUpperCase() + key.slice(1)} · ${Math.round(value)}%`, () => {
      const repair = () => { data.condition[key] = 100; toast('Equipment repaired.'); repairs(aboard, filters); save(true); };
      if (aboard) repair();
      else spend(price, repair);
    }, aboard ? 'Repair' : `$${price}`, value >= 100];
  })));
}
function sellItems(kinds, title) {
  const items = data.inventory.filter((item) => kinds.includes(item.kind));
  panel(title, items.length ? rows(items.map((item) => [item.name, () => {
    data.inventory.splice(data.inventory.indexOf(item), 1);
    data.cash += item.value;
    save(true);
    sellItems(kinds, title);
  }, `+$${item.value}`])) : paragraph('Nothing to sell here yet.'));
}
function sellCargo() {
  panel('Recovered cargo', data.cargo.length ? rows(data.cargo.map((item) => {
    const price = Math.max(1, Math.round(item.value * (1 - item.damage / 100)));
    return [`${item.name} · ${Math.round(item.damage)}% damage`, () => {
      data.cash += price;
      data.cargo.splice(data.cargo.indexOf(item), 1);
      if (item.kind === 'jar' && data.mystery >= 2) data.mystery = 3;
      save(true);
      sellCargo();
      toast(`Sold for $${price}.`);
    }, `+$${price}`];
  })) : paragraph('The deck is empty.'));
}
function rest(hotel) {
  const finish = () => {
    data.fatigue = hotel ? 0 : Math.max(0, data.fatigue - 44);
    closePanel();
    toast(hotel ? 'One hour at the inn. Fully rested.' : 'Four hours on the boat. Fatigue reduced.');
    save(true);
  };
  if (hotel) spend(18, finish);
  else finish();
}
function openStore(name) {
  const stores = {
    Restaurant: [
      ['Eat a meal', () => spend(12, () => { data.hunger = Math.max(0, data.hunger - 65); toast('You feel less hungry.'); }), '$12'],
      ['Sell fish and meat', () => sellItems(['fish', 'meat'], 'Restaurant')],
    ],
    Hotel: [['Rest · 1 hour', () => rest(true), '$18'], ['Talk to the innkeeper', () => {
      data.mystery = Math.max(1, data.mystery);
      panel('Innkeeper', paragraph('The survey crew disappeared after marking the coastal wrecks. Follow the inland path past the lake. A cairn in the cave may hold their field notes.'));
      save(true);
    }]],
    'Hunting Shop': [['Repair', () => repairs(false, ['pistol', 'knife', 'rods'])], ['Buy New Gear', () => shop('Buy New Gear', SHOP)]],
    Shipyard: [['Buy / Upgrade', () => shop('Shipyard', YARD)], ['Sell recovered cargo', sellCargo], ['Repair winch', () => repairs(false, ['winch'])]],
    Clothier: [['Sell hides', () => sellItems(['hide'], 'Clothier')], ['Buy clothing', () => shop('Clothing', SHOP.filter((entry) => entry[1] === 'armor'))]],
  };
  panel(name, rows(stores[name]));
}

function collect(item) {
  pending = { rotation: 0, ...item };
  bagTarget = null;
  openBag();
}

function fishThumbnail(item) {
  const fish = fishSpecies(item);
  return fish ? artIcon(fish.atlas, fish.cell, item.rotation) : null;
}

function openBag() {
  if (bag === 'belt' && !data.gear.belt) bag = 'backpack';
  const [cols, count] = bagSize(data.gear, bag);
  const grid = document.createElement('div');
  grid.className = 'bag-grid';
  grid.style.gridTemplateColumns = `repeat(${cols}, var(--cell))`;
  grid.setAttribute('aria-label', `${bag} slots`);
  const existing = data.inventory.filter((item) => item.bag === bag);
  const preview = pending && bagTarget ? footprint(pending, ...bagTarget) : [];
  const valid = pending && bagTarget && fits(data, pending, bag, ...bagTarget);
  const choose = (x, y, item) => {
    if (!pending && item) {
      panel(item.name, rows([
        ['Move / rotate', () => { data.inventory.splice(data.inventory.indexOf(item), 1); collect(item); }],
        ['Drop', () => { data.inventory.splice(data.inventory.indexOf(item), 1); dropItem(item); openBag(); }],
        ['Back', openBag],
      ]));
      return;
    }
    if (!pending) return;
    if (bagTarget?.[0] === x && bagTarget?.[1] === y && fits(data, pending, bag, x, y)) {
      data.inventory.push({ ...pending, bag, x, y });
      pending = null;
      bagTarget = null;
      save(true);
    } else {
      bagTarget = [x, y];
    }
    openBag();
  };
  for (let y = 0; y < count; y++) {
    for (let x = 0; x < cols; x++) {
      const item = existing.find((candidate) => footprint(candidate).some(([cx, cy]) => x === cx && y === cy));
      const covered = preview.some(([cx, cy]) => x === cx && y === cy);
      const firstCell = item && footprint(item).sort(([ax, ay], [bx, by]) => ay - by || ax - bx)[0];
      const start = firstCell && firstCell[0] === x && firstCell[1] === y;
      const label = item && !fishSpecies(item) ? (start ? ICONS[item.kind] || '◆' : '·') : '';
      const cell = button(label, () => choose(x, y, item), [item ? 'occupied' : '', covered ? (valid ? 'valid' : 'invalid') : ''].join(' '));
      cell.setAttribute('aria-label', `${x + 1}, ${y + 1}${item ? `, ${item.name}` : ''}`);
      grid.append(cell);
    }
  }
  const overlayFish = (item, cells, className) => {
    const icon = fishThumbnail(item);
    if (!icon) return;
    const xs = cells.map(([x]) => x);
    const ys = cells.map(([, y]) => y);
    icon.className = className;
    icon.style.gridColumn = `${Math.min(...xs) + 1} / ${Math.max(...xs) + 2}`;
    icon.style.gridRow = `${Math.min(...ys) + 1} / ${Math.max(...ys) + 2}`;
    grid.append(icon);
  };
  for (const item of existing) overlayFish(item, footprint(item), 'bag-fish');
  if (valid) overlayFish(pending, preview, 'bag-fish ghost');
  const nav = document.createElement('div');
  nav.className = 'bag-bar';
  const switchBag = () => { bag = bag === 'belt' ? 'backpack' : 'belt'; bagTarget = null; openBag(); };
  nav.append(button('◀', switchBag, '', '', !data.gear.belt), paragraph(bag === 'belt' ? 'Belt Pouch' : 'Backpack'), button('▶', switchBag, '', '', !data.gear.belt));
  const children = [];
  if (pending) {
    const icon = fishThumbnail(pending);
    const rotate = button(`${icon ? '' : (ICONS[pending.kind] || '◆') + '  '}${pending.name}  ↻`, () => {
      pending.rotation = ((pending.rotation || 0) + 1) % 4; openBag();
    }, 'pending');
    if (icon) rotate.prepend(icon);
    children.push(rotate);
  }
  children.push(grid, nav);
  if (pending) {
    children.push(rows([
      ['Place', () => choose(...bagTarget, null), '', !valid],
      ['Drop', () => { dropItem(pending); pending = null; bagTarget = null; openBag(); }],
    ]));
  }
  panel(bag === 'belt' ? 'Belt Pouch' : `Backpack · Lv. ${data.gear.bag}`, children, 'bag');
  $('close').disabled = Boolean(pending);
}
function dropItem(item) {
  const scene = data.scene === 'fish' ? returnScene : data.scene;
  const wx = data.scene === 'fish' && scene === 'land' ? lakeX() : player.x;
  data.drops.push({ ...item, scene, island: dock, wx, wy: player.y });
  save(true);
  toast('Left here.');
}
function spawnAnimals() {
  const species = ['Rabbit', 'Deer', 'Boar', 'Snake', 'Bear'];
  const range = landed() ? [1190, 1305, 1530, 1780, 1950] : [465, 655, 810, 1120, 1295];
  animals = species.map((name, index) => {
    const id = `${dock}:${name}`;
    return { id, name, x: range[index], origin: range[index], hp: 1, damage: 0,
      state: data.kills[id] ? 'gone' : 'live', face: -1, spin: 0, vx: 0, flash: 0, marks: [] };
  });
}
function setScene(scene, x = 100) {
  data.scene = scene;
  player = { x, y: 330, vx: 0, vy: 0, face: 1, crouch: false };
  const deckCamera = ['deck', 'moored'].includes(scene) || (scene === 'fish' && returnScene === 'deck');
  camera = { x: deckCamera ? clamp((x - 550) * .19, -43, 43) : Math.max(0, x - W * .34), y: 0 };
  activeKey = '';
  $('context').replaceChildren();
  shots = [];
  if (scene === 'land') spawnAnimals();
}
function startAnchor(site = -1) {
  dock = -1;
  const tier = site < 0 ? depthAt(data.boat.x, data.boat.y) : SITES[site].depth;
  anchor = {
    site, tier, floor: FLOOR[tier], mode: false, boom: 0, angle: 0, chain: 0, trim: 0,
    phase: 'idle', lines: [], rig: false, attached: null, piece: null,
    surveyKey: site < 0 ? `shore:${Math.round(data.boat.x / 180)}:${Math.round(data.boat.y / 180)}` : `salvage:${site}`,
  };
  if (site >= 0 && !data.completed.includes(site)) {
    anchor.piece = { ...SITES[site], x: 430 + SITES[site].offset, y: anchor.floor - 31, angle: 0, damage: 0, sway: 0, vx: 0 };
  }
  setScene('deck', 512);
  toast(site >= 0 ? 'Anchor down. Prepare the crane at mid-deck.' : 'Anchor down.');
}
function startDive() {
  if (data.gear.suit < anchor.tier) {
    toast(`Diving Suit Lv. ${anchor.tier} required for this depth.`);
    return;
  }
  setScene('dive', 385);
  player.y = 48;
  dive = { air: tubeTime[data.gear.tank], held: false, lit: Boolean(data.gear.light) };
  data.explored[anchor.surveyKey] ??= [];
  if (anchor.tier === 3 && !dive.lit) toast('The seabed is dark. An underwater flashlight will help.');
}
function surface() {
  dive = null;
  if (anchor.phase === 'lifting') anchor.mode = false;
  setScene('deck', DECK.walkMin);
}
function hookPosition() {
  const sling = Math.sin(time * 1.6) * Math.min(8, anchor.chain * .012);
  return { x: 430 + anchor.trim + sling, y: anchor.chain };
}
function startLift() {
  if (!anchor.piece || !anchor.lines.length) {
    toast('There is no load attached.');
    return;
  }
  if (anchor.piece.mass > winchCapacity[data.gear.winch] || data.condition.winch < 15) {
    toast('The winch cannot lift this load. Unhook it underwater.');
    return;
  }
  const perRope = anchor.piece.mass / anchor.lines.length;
  anchor.lines = anchor.lines.filter(() => perRope <= lineCapacity[data.gear.hooker]);
  if (!anchor.lines.length) {
    toast('The ropes snapped.');
    anchor.phase = 'idle';
    return;
  }
  anchor.phase = 'lifting';
  anchor.rig = false;
  if (dive) dive.held = false;
}
function finishCargo() {
  const item = anchor.piece;
  if (data.completed.includes(anchor.site)) return;
  data.cargo.push({ kind: item.kind, name: item.name, value: item.value, damage: item.damage });
  data.completed.push(anchor.site);
  anchor.piece = null;
  anchor.lines = [];
  anchor.phase = 'idle';
  anchor.chain = 0;
  anchor.boom = .35;
  save(true);
  toast(`${item.name} secured · ${Math.round(item.damage)}% damage. Sell at the Shipyard.`, 4);
}
function beginFish(from) {
  const key = from === 'deck' ? 'jigging' : 'casting';
  if (!data.gear[key]) {
    toast(`You need a ${from === 'deck' ? 'Jigging' : 'Casting'} Rod.`);
    return;
  }
  if (data.condition.rods <= 0) {
    toast('The rod needs repair.');
    return;
  }
  returnScene = from;
  fishing = { style: from === 'deck' ? 'jig' : 'cast', level: data.gear[key], phase: 'ready', timer: 0, reeling: 0, progress: 0, tension: 12, fish: null };
  player.x = from === 'deck' ? DECK.walkMin : 235;
  setScene('fish', player.x);
}
function nextCast() {
  if (data.condition.rods <= 0) {
    toast('The rod needs repair.');
    return;
  }
  fishing.phase = 'casting';
  fishing.timer = 0;
  fishing.reeling = 0;
  fishing.waitTime = 3 + Math.random() * 2.1;
  fishing.progress = 0;
  fishing.tension = 12;
  fishing.fish = chooseFish(fishing.style, fishing.level);
}
function keepFish() {
  if (fishing?.phase !== 'caught') return;
  const item = fishItem(fishing.fish);
  fishing.phase = 'ready';
  fishing.fish = null;
  bag = 'backpack';
  collect(item);
}
function releaseFish() {
  if (fishing?.phase !== 'caught') return;
  fishing.phase = 'release';
  fishing.timer = 0;
}
function fishAction() {
  if (fishing.phase === 'caught') selectAction()?.[1]();
  else if (fishing.phase === 'ready') nextCast();
  else if (fishing.phase === 'bite') {
    fishing.phase = 'reel';
    fishing.timer = 0;
  } else if (fishing.phase === 'reel' || fishing.phase === 'jigging') {
    fishing.reeling = .19;
  }
}
function breakLine() {
  fishing.phase = 'ready';
  fishing.tension = 0;
  fishing.fish = null;
  data.condition.rods = Math.max(0, data.condition.rods - 5);
  toast('The fish got away. Cast again.');
}
function fishUpdate(dt) {
  const f = fishing;
  if (f.phase === 'casting') {
    f.timer += dt;
    if (f.timer >= CAST_TIME[f.style]) {
      f.phase = f.style === 'jig' ? 'jigging' : 'wait';
      f.timer = f.waitTime;
    }
    return;
  }
  if (f.phase === 'lift' || f.phase === 'release') {
    f.timer += dt;
    if (f.phase === 'lift' && f.timer >= LIFT_TIME) {
      f.phase = 'caught';
      f.timer = 0;
    } else if (f.phase === 'release' && f.timer >= RELEASE_TIME) {
      f.phase = 'ready';
      f.fish = null;
    }
    return;
  }
  if (f.phase === 'wait' || f.phase === 'bite') {
    f.timer -= dt;
    if (f.timer <= 0) {
      if (f.phase === 'wait') {
        f.phase = 'bite';
        f.timer = 1.1;
      } else {
        f.phase = 'ready';
        f.fish = null;
        toast('Missed the bite.');
      }
    }
  }
  if (f.phase !== 'jigging' && f.phase !== 'reel') return;
  const pulling = held('action') || f.reeling > 0;
  f.reeling = Math.max(0, f.reeling - dt);
  if (f.phase === 'jigging') {
    if (pulling) f.timer -= dt * 1.45;
    if (f.timer <= 0) {
      f.phase = 'reel';
      f.timer = 0;
    }
    return;
  }
  f.timer += dt;
  const resistance = Math.max(0, f.fish.fight - (f.level - 1) * .14);
  const surge = Math.max(0, Math.sin(f.timer * 3)) * 13;
  f.tension = clamp(f.tension + dt * (pulling ? 19 + surge + resistance * 25 : -34 + surge * .4), 0, 102);
  if (pulling) f.progress += dt * (.34 - resistance * .15);
  if (f.tension >= 100) breakLine();
  else if (f.progress >= 1) {
    f.phase = 'lift';
    f.timer = 0;
    f.progress = 1;
  }
}

function dockNearest() {
  return ISLANDS.findIndex((island) => distance(landing(island), data.boat) < 78);
}
function siteNearest() {
  return SITES.findIndex((site, index) => !data.completed.includes(index) && distance(site, data.boat) < 79);
}
function stickToDock(index) {
  dock = index;
  data.boat = { ...landing(ISLANDS[index]), angle: data.boat.angle };
  setScene('moored', 100);
  toast(`Moored at ${ISLANDS[index].name}.`);
}
function exitToSea() {
  anchor = null;
  dock = -1;
  setScene('sea');
  save(true);
}
function landed() {
  return dock >= 0 && ISLANDS[dock].town;
}
function lakeX() { return landed() ? 1658 : 940; }
function caveX() { return landed() ? 2088 : 1470; }
function closeTo(x, range = 83) { return Math.abs(player.x - x) < range; }
function caveMound() { return 1030; }
function caveKey() { return `cave:${dock}`; }
function worldDrop() {
  return data.drops.find((item) => item.scene === data.scene && item.island === dock && closeTo(item.wx, 70));
}
function dig() {
  if (!data.gear.shovel) {
    toast('You don’t have a shovel.');
    return;
  }
  caveDig = 3.2 / data.gear.shovel;
}
function claimDig() {
  data.excavated[caveKey()] = 'claimed';
  if (landed() && !data.read.survey) {
    data.read.survey = true;
    const jarAlreadySold = data.completed.includes(0) && !data.cargo.some((item) => item.kind === 'jar');
    data.mystery = Math.max(data.mystery, jarAlreadySold ? 3 : 2);
    toast('The valve is wrapped in the survey crew’s field note.');
  }
  collect({ name: 'Brass Valve', kind: 'valve', value: 70, shape: [[0, 0], [1, 0], [1, 1]] });
}
function harvest(animal, part) {
  data.kills[animal.id] = 'harvested';
  animal.state = 'gone';
  if (part === 'meat') {
    data.drops.push({ scene: 'land', island: dock, wx: animal.x, name: `${animal.name} Hide`, kind: 'hide', value: 34, shape: [[0, 0], [1, 0], [0, 1]] });
    collect({ name: `${animal.name} Meat`, kind: 'meat', value: 28, shape: [[0, 0], [1, 0]] });
  }
}
function nearbyLine() {
  if (!anchor.piece) return -1;
  const h = hookPosition();
  return anchor.lines.findIndex((line) => {
    const x = anchor.piece.x + line * 26;
    const y = anchor.piece.y - 16;
    const run = x - h.x, rise = y - h.y;
    const ratio = clamp(((player.x - h.x) * run + (player.y - h.y) * rise) / (run * run + rise * rise || 1), 0, 1);
    return Math.hypot(player.x - h.x - ratio * run, player.y - h.y - ratio * rise) < 44;
  });
}
function getActions() {
  const scene = data.scene;
  if (scene === 'sea') {
    const island = dockNearest();
    const mark = siteNearest();
    if (island >= 0) return [[`Moor at ${ISLANDS[island].name}`, () => stickToDock(island)], ['Drop Anchor', () => startAnchor()]];
    if (mark >= 0) return [['Start Salvage', () => startAnchor(mark)], ['Drop Anchor', () => startAnchor()]];
    return [['Drop Anchor', () => startAnchor()]];
  }
  if (scene === 'moored') return [['Explore Island', () => setScene('land', 106)], ['Rest', () => rest(false)], ['Cast Off', exitToSea]];
  if (scene === 'fish') return fishing.phase === 'caught' ? [['Keep', keepFish], ['Release', releaseFish]] : [];
  const drop = worldDrop();
  if (drop) return [[`Collect ${drop.name}`, () => { data.drops.splice(data.drops.indexOf(drop), 1); collect(drop); }]];
  if (scene === 'land') {
    if (player.x < 165) return [['Return to Boat', () => setScene('moored')]];
    if (landed()) {
      const door = townDoors.find(([x]) => closeTo(x));
      if (door) return [[door[1], () => openStore(door[1])]];
    }
    if (closeTo(lakeX(), 118)) return [['Fish Here', () => beginFish('land')]];
    if (closeTo(caveX(), 90)) return [['Enter the Cave', () => {
      caveDig = 0;
      setScene('cave', 100);
      if (!data.gear.lantern) toast('No lantern. It is easy to lose your way in here.');
    }]];
    const carcass = animals.find((animal) => animal.state === 'dead' && animal.damage < 2.2 && closeTo(animal.x, 70));
    return carcass ? [[`Skin ${carcass.name}`, () => harvest(carcass, 'meat')]] : [];
  }
  if (scene === 'cave') {
    if (player.x < 150) return [['Leave Cave', () => setScene('land', caveX() - 100)]];
    if (closeTo(caveMound(), 75) && player.y > 300 && caveDig <= 0) {
      const state = data.excavated[caveKey()];
      if (!state) return [['Dig', dig]];
      if (state === 'open') return [['Collect', claimDig]];
    }
    return [];
  }
  if (scene === 'deck') {
    if (anchor.mode) {
      if (anchor.chain <= 0 && anchor.phase === 'idle') {
        return [
          ['Trim Aft', () => trimCrane(-95)],
          ['Trim Forward', () => trimCrane(95)],
        ];
      }
      return [];
    }
    if (player.x < 383) {
      return [['Dive', startDive], ['Fish Here', () => beginFish('deck')]];
    }
    if (player.x < 600) return [['Crane Controls', () => {
      anchor.mode = true;
      toast('←/→ Reach · ↑/↓ Boom · Jump lowers chain · Action raises · Utility exits', 5);
    }]];
    return [
      ['Weigh Anchor', () => {
        if (anchor.lines.length || anchor.phase === 'onDeck' || anchor.phase === 'lifting') toast('Secure or unhook the load first.');
        else exitToSea();
      }],
      ['Rest', () => rest(false)],
      ...(data.gear.repair ? [['Repair Station', () => repairs(true)]] : []),
    ];
  }
  if (scene !== 'dive') return [];
  const actions = [];
  const h = hookPosition();
  const item = anchor.piece;
  const nearHook = distance(player, h) < 66 && anchor.chain > 12;
  const nearItem = item && distance(player, item) < 104 && anchor.phase !== 'lifting';
  const line = nearbyLine();
  if (anchor.attached !== null && nearHook && item) {
    actions.push(['Hook', () => { anchor.lines.push(anchor.attached); anchor.attached = null; dive.held = false; }]);
  } else if (anchor.rig && nearItem && anchor.attached === null && anchor.lines.length < data.gear.hooker) {
    actions.push(['Tie Rope', () => {
      const options = player.x < item.x ? [-1, 0, 1] : [1, 0, -1];
      anchor.attached = options.find((position) => !anchor.lines.includes(position));
      if (anchor.attached === undefined) anchor.attached = null;
      toast('Swim to the crane hook.');
    }]);
  }
  if (anchor.rig && line >= 0 && anchor.phase !== 'lifting') actions.push(['Unhook', () => {
    anchor.lines.splice(line, 1);
    toast('Rope released.');
  }]);
  if (nearHook && anchor.attached === null && anchor.phase !== 'lifting') {
    actions.push([dive.held ? 'Release Hook' : 'Grab Hook', () => { dive.held = !dive.held; }]);
  }
  if (data.gear.remote && anchor.lines.length && anchor.phase === 'idle') actions.push(['Raise Crane', startLift]);
  if (player.y < 43) actions.push(['Climb Aboard', surface]);
  return actions;
}

function held(name) {
  return keys.has(name);
}
function axis(low, high, analog) {
  return clamp((held(high) ? 1 : 0) - (held(low) ? 1 : 0) + analog, -1, 1);
}
function movement() {
  return { x: axis('left', 'right', stick.x + pad.x), y: axis('up', 'down', stick.y + pad.y) };
}
function selectAction(actions = getActions()) {
  return actions[clamp(choice, 0, Math.max(0, actions.length - 1))];
}
function nextAction() {
  const actions = getActions();
  if (actions.length < 2) return;
  choice = (choice + 1) % actions.length;
  activeKey = '';
}
function trimCrane(amount) {
  anchor.trimBase = clamp((anchor.trimBase || 0) + amount, -300, 300);
  anchor.trim = anchor.trimBase;
  toast('Crane alignment adjusted.', 1.2);
}
function trigger(name) {
  if (ui) return;
  if (name === 'action') {
    if (data.scene === 'fish') fishAction();
    else if (anchor?.mode && data.scene === 'deck') {
      if (anchor.phase === 'onDeck') finishCargo();
      else if (anchor.phase === 'idle' && anchor.lines.length) startLift();
    } else selectAction()?.[1]();
  }
  if (name === 'utility') {
    if (data.scene === 'fish') {
      if (fishing.phase === 'reel') breakLine();
      else if (fishing.phase === 'caught') releaseFish();
      else if (fishing.phase === 'lift' || fishing.phase === 'release') return;
      else { setScene(returnScene, returnScene === 'deck' ? 340 : lakeX() - 50); fishing = null; }
    } else if (data.scene === 'dive') {
      anchor.rig = !anchor.rig;
      dive.held = false;
      toast(anchor.rig ? 'Hooker equipped.' : 'Hooker stowed.', 1.4);
    } else if (data.scene === 'deck' && anchor.mode) {
      anchor.mode = false;
    } else if (data.scene === 'sea') {
      startAnchor();
    } else if (data.scene === 'moored') {
      exitToSea();
    }
  }
}
function down(name) {
  if (name && !held(name)) {
    pressed.add(name);
    const target = Array.from(document.querySelectorAll('[data-input]')).find((el) => el.dataset.input === name);
    target?.classList.add('is-held');
    trigger(name);
  }
  keys.add(name);
}
function up(name) {
  keys.delete(name);
  document.querySelectorAll(`[data-input="${name}"]`).forEach((el) => el.classList.remove('is-held'));
}
function menuNav(direction) {
  const list = [...$('panel').querySelectorAll('button:not(:disabled)')];
  const index = list.indexOf(document.activeElement);
  list[clamp(index + direction, 0, list.length - 1)]?.focus();
}
function inputGamepad() {
  const controller = Array.from(navigator.getGamepads?.() || []).find((item) => item?.connected);
  if (!controller) {
    pad = { x: 0, y: 0 };
    for (const name of ['jump', 'utility', 'action', 'up', 'down', 'left', 'right']) if (gamepadButtons.length) up(name);
    gamepadButtons = [];
    return;
  }
  const deadzone = (value) => Math.abs(value) > .22 ? value : 0;
  pad = { x: deadzone(controller.axes[0] || 0), y: deadzone(controller.axes[1] || 0) };
  const mapping = { 0: 'jump', 1: 'utility', 2: 'action', 12: 'up', 13: 'down', 14: 'left', 15: 'right' };
  for (const [index, input] of Object.entries(mapping)) {
    const active = controller.buttons[index]?.pressed;
    if (active === gamepadButtons[index]) continue;
    gamepadButtons[index] = active;
    if (!active) up(input);
    else if (ui) {
      if (input === 'action' || input === 'jump') {
        if ($('panel').contains(document.activeElement) && document.activeElement.tagName === 'BUTTON') document.activeElement.click();
        else menuNav(1);
      } else if (input === 'utility') closePanel();
      else menuNav(input === 'up' || input === 'left' ? -1 : 1);
    } else down(input);
  }
  for (const [index, fn] of [[3, () => ui ? closePanel() : openBag()], [9, () => ui ? closePanel() : openSettings()]]) {
    const current = controller.buttons[index]?.pressed;
    if (current && !gamepadButtons[index]) fn();
    gamepadButtons[index] = current;
  }
  const cycle = controller.buttons[5]?.pressed;
  if (cycle && !gamepadButtons[5] && !ui) nextAction();
  gamepadButtons[5] = cycle;
}
window.addEventListener('keydown', (event) => {
  if (event.repeat) return;
  if (event.code === 'Escape') {
    ui ? closePanel() : openSettings();
    return;
  }
  if (event.code === 'KeyI') {
    ui ? closePanel() : openBag();
    return;
  }
  if (event.code === 'KeyR' && !ui) {
    nextAction();
    return;
  }
  if (event.code === 'KeyQ' && data.scene === 'land' && data.gear.pistol) {
    data.selected = data.selected === 'pistol' ? 'knife' : 'pistol';
    toast(data.selected === 'pistol' ? 'Pistol equipped' : 'Blade equipped', 1.2);
    return;
  }
  if (ui) {
    if (event.code === 'ArrowDown' || event.code === 'ArrowUp') {
      event.preventDefault();
      menuNav(event.code === 'ArrowDown' ? 1 : -1);
    }
    return;
  }
  const name = keyMap[event.code];
  if (name) {
    event.preventDefault();
    down(name);
  }
});
window.addEventListener('keyup', (event) => { if (keyMap[event.code]) up(keyMap[event.code]); });
window.addEventListener('blur', () => { keys.clear(); pressed.clear(); stick = { x: 0, y: 0 }; });
document.querySelectorAll('[data-input]').forEach((element) => {
  element.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    element.setPointerCapture(event.pointerId);
    down(element.dataset.input);
  });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    element.addEventListener(type, () => up(element.dataset.input));
  }
  element.addEventListener('click', (event) => {
    if (event.detail === 0) { down(element.dataset.input); up(element.dataset.input); }
  });
});
function steer(event) {
  const rect = $('stick').getBoundingClientRect();
  const x = (event.clientX - rect.left - rect.width / 2) / (rect.width * .31);
  const y = (event.clientY - rect.top - rect.height / 2) / (rect.height * .31);
  const limit = Math.max(1, Math.hypot(x, y));
  stick = { x: x / limit, y: y / limit };
  $('knob').style.transform = `translate(${stick.x * 64}%, ${stick.y * 64}%)`;
}
$('stick').addEventListener('pointerdown', (event) => { $('stick').setPointerCapture(event.pointerId); steer(event); });
$('stick').addEventListener('pointermove', (event) => { if ($('stick').hasPointerCapture(event.pointerId)) steer(event); });
for (const event of ['pointerup', 'pointercancel', 'lostpointercapture']) {
  $('stick').addEventListener(event, () => { stick = { x: 0, y: 0 }; $('knob').style.transform = ''; });
}
$('stats').addEventListener('click', stats);
$('inventory').addEventListener('click', openBag);
$('menu').addEventListener('click', openSettings);
$('close').addEventListener('click', closePanel);
window.addEventListener('pagehide', () => { if (!pending && data.scene === 'sea') save(true); });

function sideFloor(scene, x, top = false) {
  if (scene === 'deck' || scene === 'moored' || (scene === 'fish' && returnScene === 'deck')) return DECK.floor;
  if (scene === 'fish') return 309;
  if (scene === 'cave') {
    const { left, right, top: height } = CAVE_LEDGE;
    if (top && x >= left && x <= right) return height + Math.sin((x - left) / 192) * 6;
    const end = CAVE_FLOOR.findIndex(([px]) => px >= x);
    if (end <= 0) return end === 0 ? CAVE_FLOOR[0][1] : CAVE_FLOOR.at(-1)[1];
    const [ax, ay] = CAVE_FLOOR[end - 1];
    const [bx, by] = CAVE_FLOOR[end];
    return ay + (by - ay) * (x - ax) / (bx - ax);
  }
  return landed() ? 371 : 329;
}
function aimAt(event) {
  if (ui || data.scene !== 'land') return;
  const bounds = canvas.getBoundingClientRect();
  const x = (event.clientX - bounds.left) / bounds.width * W + camera.x;
  const y = (event.clientY - bounds.top) / bounds.height * H;
  attack(x, y);
}
function attack(x, y) {
  const type = data.selected;
  if (data.condition[type] <= 0) {
    toast('This gear needs repair.');
    return;
  }
  if (player.cooldown > 0) return;
  player.cooldown = type === 'pistol' ? .36 : .42;
  player.face = x < player.x ? -1 : 1;
  player.attack = .18;
  if (type === 'knife') {
    const target = animals.find((animal) => Math.abs(animal.x - player.x) < 75 && Math.sign(animal.x - player.x) === player.face && animal.state !== 'gone');
    if (target) hit(target, data.gear.knife * .48, player.face);
  } else {
    const angle = Math.atan2(y - player.y + 37, x - player.x) + (Math.random() - .5) * (.15 / (1 + data.shooting * .06));
    shots.push({ x: player.x, y: player.y - 37, vx: Math.cos(angle) * 730, vy: Math.sin(angle) * 730, age: 0 });
  }
  data.condition[type] = Math.max(0, data.condition[type] - .8);
}
canvas.addEventListener('pointerdown', (event) => aimAt(event));
function hit(animal, damage, direction) {
  animal.damage += damage;
  animal.vx += direction * 57;
  animal.flash = .2;
  animal.marks.push([direction * (3 + animal.marks.length * 3), -14 + animal.marks.length * 3]);
  if (animal.state === 'live' && animal.damage >= (animal.name === 'Bear' ? 1.8 : 1)) {
    animal.state = 'dead';
    animal.spin = direction * 1.4;
    data.shooting += Number(data.selected === 'pistol');
  }
}
function landUpdate(dt) {
  if (pressed.has('utility')) {
    if (data.gear.pistol && held('down')) {
      data.selected = data.selected === 'pistol' ? 'knife' : 'pistol';
      toast(data.selected === 'pistol' ? 'Pistol equipped' : 'Blade equipped', 1.2);
    } else attack(player.x + player.face * 350, player.y - 30);
  }
  for (const animal of animals) {
    if (animal.state === 'gone') continue;
    animal.flash = Math.max(0, animal.flash - dt);
    animal.vx = toward(animal.vx, 0, dt * 126);
    if (animal.state === 'live') {
      if (animal.name === 'Boar' && animal.damage > 0 || ['Bear', 'Snake'].includes(animal.name)) {
        if (closeTo(animal.x, 192)) {
          animal.face = Math.sign(player.x - animal.x);
          animal.vx += animal.face * 19 * dt;
          if (closeTo(animal.x, 19)) data.fatigue = clamp(data.fatigue + dt * (data.gear.armor ? 2 : 6), 0, 100);
        }
      } else {
        animal.vx += Math.cos(time * .7 + animal.origin) * 7 * dt;
      }
    } else {
      animal.spin = toward(animal.spin, Math.sign(animal.spin) * 1.54, dt * .72);
    }
    animal.x += animal.vx * dt;
  }
  for (const shot of shots) {
    const x = shot.x;
    shot.x += shot.vx * dt;
    shot.y += shot.vy * dt;
    shot.vy += dt * 36;
    shot.age += dt;
    for (const animal of animals) {
      if (animal.state === 'gone' || Math.min(x, shot.x) > animal.x + 16 || Math.max(x, shot.x) < animal.x - 16) continue;
      const bottom = sideFloor('land', animal.x);
      if (shot.y < bottom - (animal.name === 'Rabbit' ? 25 : 50) || shot.y > bottom + 3) continue;
      hit(animal, .8 + data.gear.pistol * .28, Math.sign(shot.vx));
      shot.age = 5;
      break;
    }
    if (shot.y > sideFloor('land', shot.x) || (landed() && Math.abs(shot.x - PINE_ROCK_X) < 23 && shot.y > sideFloor('land', shot.x) - 27)) shot.age = 5;
  }
  shots = shots.filter((shot) => shot.age < 1.8);
}
function sideUpdate(dt) {
  const scene = data.scene;
  const bounds = scene === 'deck' || scene === 'moored' ? [DECK.walkMin, DECK.walkMax] : [40, scene === 'land' ? (landed() ? LEVEL_WIDTH.pine - 65 : 1520) : 1680];
  const m = movement();
  const priorX = player.x;
  const wasGrounded = player.y >= sideFloor(scene, player.x, player.upper) - 2;
  player.crouch = m.y > .3 || (held('utility') && scene === 'cave');
  if (m.x) player.face = Math.sign(m.x);
  const speed = 140 * (player.crouch ? .53 : 1) * (data.fatigue >= 75 ? .8 : 1);
  player.vx = toward(player.vx, m.x * speed, (wasGrounded ? 845 : 415) * dt);
  if (caveDig > 0 && scene === 'cave') {
    caveDig -= dt;
    player.vx = 0;
    if (caveDig <= 0) data.excavated[caveKey()] = 'open';
  }
  if (pressed.has('jump') && wasGrounded) player.vy = -357;
  player.x = clamp(player.x + player.vx * dt, ...bounds);
  const leftRock = PINE_ROCK_X - 23;
  const rightRock = PINE_ROCK_X + 22;
  const crossingRock = (priorX < leftRock && player.x >= leftRock) || (priorX > rightRock && player.x <= rightRock);
  if (scene === 'land' && landed() && crossingRock && player.y > sideFloor(scene, player.x) - 34) player.x = priorX;
  if (scene === 'cave') {
    if (priorX < CAVE_LEDGE.left && player.x >= CAVE_LEDGE.left && player.y < 265 && player.vy < 94) {
      player.upper = true;
      player.y = sideFloor(scene, player.x, true);
      player.vy = 0;
    }
    if (player.upper && (player.x < CAVE_LEDGE.left || player.x > CAVE_LEDGE.right)) player.upper = false;
    const leftEntry = CAVE_LEDGE.left + 24;
    const rightEntry = CAVE_LEDGE.right - 38;
    const enteringLower = (priorX < leftEntry && player.x >= leftEntry) || (priorX > rightEntry && player.x <= rightEntry);
    if (!player.upper && !player.crouch && enteringLower && player.y > 245) player.x = priorX;
  }
  const floor = sideFloor(scene, player.x, player.upper);
  player.vy += dt * 685;
  player.y += player.vy * dt;
  if (player.y >= floor) {
    player.y = floor;
    player.vy = 0;
  }
  player.cooldown = Math.max(0, (player.cooldown || 0) - dt);
  player.attack = Math.max(0, (player.attack || 0) - dt);
  const lead = data.shake ? player.face > 0 ? .33 : .67 : .5;
  if (scene === 'land' || scene === 'cave') {
    const width = scene === 'cave' ? LEVEL_WIDTH.cave : landed() ? LEVEL_WIDTH.pine : LEVEL_WIDTH.wild;
    const finalX = Math.max(0, width - W);
    camera.x = toward(camera.x, clamp(player.x - W * lead, 0, finalX), 320 * dt);
  } else {
    camera.x = toward(camera.x, clamp((player.x - 550) * .19, -43, 43), 145 * dt);
  }
}
function diveUpdate(dt) {
  const m = movement();
  player.vx = toward(player.vx, m.x * 129, dt * 340);
  player.vy = toward(player.vy, m.y * 111, dt * 305);
  player.x = clamp(player.x + player.vx * dt, 34, 1046);
  player.y = clamp(player.y + player.vy * dt, 12, anchor.floor - 34);
  if (m.x) player.face = Math.sign(m.x);
  if (dive.held) {
    anchor.chain = clamp(anchor.chain + Math.max(0, m.y) * dt * 125, 14, anchor.floor - 14);
    anchor.trim = toward(anchor.trim, (player.x - 430) * .72, dt * 100);
    if (m.y < -.5) dive.held = false;
    else player.y = anchor.chain;
  } else if (!anchor.mode && !anchor.lines.length && anchor.phase === 'idle') {
    anchor.trim = toward(anchor.trim, anchor.trimBase || 0, dt * 38);
  }
  const entries = data.explored[anchor.surveyKey];
  if (anchor.floor - player.y < 245 && !entries.some((x) => Math.abs(x - player.x) < 26)) entries.push(Math.round(player.x));
  dive.air -= dt * (Math.hypot(m.x, m.y) > .3 ? 1 : .86);
  if (dive.air <= 0) {
    data.fatigue = clamp(data.fatigue + 25, 0, 100);
    anchor.attached = null;
    surface();
    toast('Out of air. Emergency return to the boat.');
    return;
  }
  camera.y = toward(camera.y, clamp(player.y - H * .48, 0, anchor.floor - H + 85), dt * 205);
}
function craneUpdate(dt) {
  if (!anchor) return;
  const m = movement();
  if (anchor.mode && data.scene === 'deck') {
    if (anchor.phase === 'idle' && !anchor.lines.length) {
      anchor.boom = clamp(anchor.boom - m.x * dt * .93, 0, 1);
      anchor.angle = clamp(anchor.angle - m.y * dt * .7, -.21, .82);
      if (held('jump') && anchor.boom >= .88) anchor.chain = Math.min(anchor.floor - 34, anchor.chain + dt * 267);
      if (held('action')) anchor.chain = Math.max(0, anchor.chain - dt * 248);
      if (!anchor.chain && anchor.boom < .25 && Math.abs(m.x) > .3 && held('down')) {
        anchor.trimBase = clamp((anchor.trimBase || 0) + dt * m.x * 125, -300, 300);
        anchor.trim = anchor.trimBase;
      }
    }
    if (anchor.phase === 'surface') {
      anchor.boom = clamp(anchor.boom - m.x * dt * 1.1, .26, 1);
      if (held('jump') && anchor.boom < .57) {
        anchor.lowering = (anchor.lowering || 0) + dt;
        if (anchor.lowering > (held('down') ? .18 : .62)) {
          if (held('down')) anchor.piece.damage = clamp(anchor.piece.damage + 16, 0, 100);
          anchor.phase = 'onDeck';
          toast('Resting on the deck. Press Action to secure the load.');
        }
      }
      if (anchor.boom >= .73 && held('jump')) anchor.piece.damage = clamp(anchor.piece.damage + dt * 15, 0, 100);
    }
  }
  if (anchor.phase === 'lifting') {
    const item = anchor.piece;
    const h = hookPosition();
    const gap = h.x - item.x;
    anchor.chain = Math.max(-57, anchor.chain - dt * 138);
    item.vx += (gap * 2.1 - item.vx * 1.35) * dt;
    item.x += item.vx * dt;
    item.y = toward(item.y, anchor.chain + 86, dt * 133);
    const attachMean = anchor.lines.reduce((sum, position) => sum + position, 0) / anchor.lines.length;
    item.angle = toward(item.angle, attachMean * .49 + clamp(item.vx * .004, -.8, .8), dt * 1.7);
    if (item.y > anchor.floor - 63 && Math.abs(item.vx) > 15) item.damage += dt * Math.abs(item.vx) * .25;
    if (item.y < 220 && item.y > 20 && (item.x > 498 || Math.abs(item.vx) > 148)) item.damage += dt * 13;
    item.damage = clamp(item.damage, 0, 100);
    if (anchor.chain <= -57) {
      anchor.phase = 'surface';
      anchor.boom = 1;
      data.condition.winch = Math.max(0, data.condition.winch - 4);
      toast('Load at the surface. Retract the boom and lower onto the deck.', 4);
    }
  }
}
function sail(dt) {
  const m = movement();
  const speed = 145 + data.gear.motor * 39 + (data.gear.boat - 1) * 27;
  if (Math.hypot(m.x, m.y) < .02) return;
  const angle = Math.atan2(m.y, m.x);
  const change = Math.atan2(Math.sin(angle - data.boat.angle), Math.cos(angle - data.boat.angle));
  data.boat.angle += clamp(change, -dt * 6, dt * 6);
  const next = { x: clamp(data.boat.x + m.x * speed * dt, 14, WORLD[0] - 14), y: clamp(data.boat.y + m.y * speed * dt, 14, WORLD[1] - 14) };
  if (!landAt(next.x, next.y)) Object.assign(data.boat, next);
  else {
    if (!landAt(data.boat.x, next.y)) data.boat.y = next.y;
    if (!landAt(next.x, data.boat.y)) data.boat.x = next.x;
  }
}

function actionLabel(element, icon, label) {
  const name = icon + label;
  if (element.dataset.label === name) return;
  element.dataset.label = name;
  element.textContent = icon;
  element.title = label;
  element.setAttribute('aria-label', label || 'Action');
  if (!label) return;
  const text = document.createElement('small');
  text.textContent = label;
  element.append(text);
}
function gaugeLabel(label, value, max, center = false) {
  return `<span class="gauge${center ? ' center' : ''}">${label}${max ? ` <meter min="0" max="${max}" value="${clamp(value, 0, max)}"></meter>` : ''}</span>`;
}
function updateHUD() {
  $('location').textContent = dock >= 0 ? ISLANDS[dock].name : 'Open Seas';
  $('balance').textContent = `$${Math.floor(data.cash)}`;
  $('fatigue').value = data.fatigue;
  $('hunger').value = data.hunger;
  $('stick').hidden = data.scene !== 'sea';
  $('dpad').hidden = data.scene === 'sea';
  $('close').disabled = ui === 'bag' && Boolean(pending);
  let gauge = '';
  let utility = ['◒', 'Crouch'];
  let jump = ['↟', 'Jump'];
  let action = ['✋', 'Interact'];
  if (data.scene === 'sea') {
    utility = ['⚓', 'Drop Anchor'];
    jump = ['↟', ''];
    gauge = gaugeLabel(['', 'Shallows', 'Mid-water', 'Deep water'][depthAt(data.boat.x, data.boat.y)]);
  }
  if (data.scene === 'moored') utility = ['⚓', 'Cast Off'];
  if (data.scene === 'land') utility = [data.selected === 'pistol' ? '◈' : '⚔', 'Use Gear'];
  if (data.scene === 'dive') {
    utility = ['↪', anchor.rig ? 'Stow Hooker' : 'Equip Hooker'];
    jump = ['↟', ''];
    gauge = gaugeLabel('Oxygen', dive.air, tubeTime[data.gear.tank])
      + gaugeLabel(`Depth ${(player.y / anchor.floor * METERS[anchor.tier]).toFixed(1)} m`);
  }
  if (data.scene === 'fish') {
    const phase = fishing.phase;
    utility = ['✂', { reel: 'Break Line', caught: 'Release', lift: '', release: '' }[phase] ?? 'Leave'];
    jump = ['↟', ''];
    const names = { ready: 'Cast', casting: 'Casting…', wait: 'Wait', bite: 'Set Hook', jigging: 'Draw Jig', reel: 'Reel In', lift: 'Landing…', caught: choice === 1 ? 'Release' : 'Keep', release: 'Releasing…' };
    action = ['✋', names[phase]];
    if (phase === 'bite') gauge = gaugeLabel('Bite!', fishing.timer, 1.1, true);
    if (phase === 'reel') gauge = gaugeLabel('Tension', fishing.tension, 100, true);
    if (phase === 'caught') gauge = gaugeLabel(fishing.fish.name);
  }
  if (anchor?.mode && data.scene === 'deck') {
    utility = ['×', 'Exit Crane'];
    jump = ['↓', anchor.phase === 'surface' ? 'Lower Load' : 'Pay Out'];
    action = ['↑', anchor.phase === 'onDeck' ? 'Secure' : 'Raise'];
    gauge = gaugeLabel(`Crane · ${Math.max(0, Math.round(anchor.chain / anchor.floor * METERS[anchor.tier]))} m`);
  }
  if (anchor?.piece && ['lifting', 'surface', 'onDeck'].includes(anchor.phase)) gauge += gaugeLabel(`Damage ${Math.round(anchor.piece.damage)}%`, anchor.piece.damage, 100, true);
  if (data.scene === 'cave' && caveDig > 0) gauge += gaugeLabel('Digging', 3.2 / data.gear.shovel - caveDig, 3.2 / data.gear.shovel, true);
  if ($('gauges').innerHTML !== gauge) $('gauges').innerHTML = gauge;
  actionLabel($('utility'), ...utility);
  actionLabel($('jump'), ...jump);
  actionLabel($('action'), ...action);
  activeActions = ui ? [] : getActions();
  const names = activeActions.map((entry) => entry[0]).join('|');
  if (names !== choiceGroup) {
    choiceGroup = names;
    choice = 0;
  }
  const nextKey = `${names}:${choice}`;
  if (nextKey !== activeKey) {
    activeKey = nextKey;
    $('context').replaceChildren(...activeActions.map(([label], idx) =>
      button(label, () => getActions().find((entry) => entry[0] === label)?.[1](), idx === choice ? 'selected' : '')));
  }
  const scene = data.scene;
  let x = player.x - camera.x;
  let y = player.y - 73;
  if (scene === 'sea' || scene === 'moored') {
    x = W / 2;
    y = H * (scene === 'sea' ? .37 : .43);
  }
  if (scene === 'dive') { y = player.y - camera.y - 49; }
  if (scene === 'fish' && fishing.phase === 'caught') {
    x = player.x - camera.x + (returnScene === 'deck' ? -68 + (anchor?.trimBase || 0) * .08 : 75);
    y = (returnScene === 'deck' ? DECK.floor : 309) - 123;
  }
  $('context').style.left = clamp(x / W * 100, activeActions.length > 1 ? 22 : 10, activeActions.length > 1 ? 78 : 90) + '%';
  $('context').style.top = clamp(y / H * 100, 23, 72) + '%';
}

function update(dt) {
  if (noticeTime > 0 && (noticeTime -= dt) <= 0) $('notice').textContent = '';
  if (ui) return;
  if (data.scene === 'sea') sail(dt);
  else if (data.scene === 'dive') diveUpdate(dt);
  else if (data.scene === 'fish') fishUpdate(dt);
  else if (data.scene !== 'moored' && !(data.scene === 'deck' && anchor.mode)) sideUpdate(dt);
  if (data.scene === 'land') landUpdate(dt);
  craneUpdate(dt);
  const active = Math.abs(player.vx) > 20 && !['sea', 'fish', 'moored'].includes(data.scene);
  data.fatigue = clamp(data.fatigue + dt * (active ? .038 : .007), 0, 100);
  data.hunger = clamp(data.hunger + dt * .025, 0, 100);
}
load(true);
if (data.tutorial) {
  data.tutorial = false;
  toast('Sail to Pine Island’s pier or the nearby orange salvage buoy. WASD / left stick to steer; E / X to interact.', 8);
}
let last = performance.now();
function loop(now) {
  const dt = clamp((now - last) / 1000, 0, .04);
  last = now;
  time += dt;
  inputGamepad();
  update(dt);
  render({
    data, player, camera, dock, anchor, dive, fishing, returnScene, time, animals, shots, caveDig,
    caveKey: caveKey(), caveMound: caveMound(), lakeX: lakeX(), caveX: caveX(), townDoors,
    floor: sideFloor, hook: anchor ? hookPosition() : null, moving: movement(),
  });
  if ((debugStep++ & 1) === 0) updateHUD();
  pressed.clear();
  requestAnimationFrame(loop);
}
sceneryReady.then(() => {
  $('loading').hidden = true;
  last = performance.now();
  requestAnimationFrame(loop);
}).catch((error) => {
  console.error(error);
  $('loading').replaceChildren(paragraph('The scenery could not load.'), button('Reload', () => window.location.reload()));
});
