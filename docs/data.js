export const WORLD = [3860, 2550];
export const ISLANDS = [
  { name: 'Pine Island', x: 1230, y: 790, rx: 215, ry: 148, dock: [0, 176], art: 0, town: true },
  { name: 'Slate Reach', x: 2760, y: 480, rx: 145, ry: 100, dock: [-171, 0], art: 1 },
  { name: 'Sedge Isle', x: 3090, y: 1770, rx: 155, ry: 107, dock: [183, 0], art: 2 },
  { name: 'Gull Rock', x: 690, y: 1980, rx: 125, ry: 93, dock: [0, -120], art: 3 },
];
export const SITES = [
  { x: 1500, y: 965, depth: 1, name: 'Antique Jar', kind: 'jar', mass: 54, value: 185, offset: 171 },
  { x: 2050, y: 1180, depth: 2, name: 'Cargo Chest', kind: 'chest', mass: 105, value: 360, offset: -175 },
  { x: 2475, y: 755, depth: 1, name: 'Small Crate', kind: 'crate', mass: 28, value: 95, offset: 120 },
  { x: 3200, y: 2110, depth: 2, name: 'Fishing Wreck', kind: 'wreck', mass: 146, value: 515, offset: 225 },
  { x: 1850, y: 1950, depth: 3, name: 'Survey Plane', kind: 'plane', mass: 198, value: 760, offset: -210 },
  { x: 440, y: 1150, depth: 3, name: 'Sealed Strongbox', kind: 'chest', mass: 132, value: 490, offset: 218 },
];
export const FLOOR = [0, 810, 1310, 1840];
export const METERS = [0, 8, 23, 47];
export const KEY = 'soundings.playtest.v1';
export const LEVEL_WIDTH = { pine: 2240, wild: 1595, cave: 1815 };
export const PINE_ROCK_X = 1407;
export const DECK = { stern: 327, bow: 805, walkMin: 344, walkMax: 756, floor: 341 };
export const CAVE_LEDGE = { left: 523, right: 1165, top: 209 };
export const CAVE_FLOOR = [[0, 290], [137, 302], [405, 319], [650, 332], [970, 350], [1160, 368], [1370, 371], [1645, 354], [1815, 338]];
export const SHOP = [
  ['Casting Rod', 'casting', 1, 65], ['Casting Rod', 'casting', 2, 120], ['Casting Rod', 'casting', 3, 235],
  ['Jigging Rod', 'jigging', 1, 80], ['Jigging Rod', 'jigging', 2, 140], ['Jigging Rod', 'jigging', 3, 200],
  ['Pistol', 'pistol', 1, 150],
  ['Fish Catching Net', 'net', 4, 320], ['Knife', 'knife', 1, 55], ['Machete', 'knife', 2, 125],
  ['Ranger Carbine', 'pistol', 2, 295], ['Automatic Carbine', 'pistol', 3, 445],
  ['Work Jacket', 'armor', 1, 55], ['Field Jacket', 'armor', 2, 120],
  ['Lantern', 'lantern', 1, 45], ['Lantern', 'lantern', 2, 95], ['Lantern', 'lantern', 3, 160],
  ['Shovel', 'shovel', 1, 55], ['Shovel', 'shovel', 2, 110], ['Shovel', 'shovel', 3, 170],
  ['Underwater Flashlight', 'light', 1, 110], ['Diving Suit', 'suit', 2, 140], ['Diving Suit', 'suit', 3, 260],
  ['Oxygen Tank', 'tank', 2, 95], ['Oxygen Tank', 'tank', 3, 170], ['Hooker', 'hooker', 2, 105], ['Hooker', 'hooker', 3, 195],
  ['Backpack', 'bag', 2, 105], ['Backpack', 'bag', 3, 180], ['Belt Pouch', 'belt', 1, 60],
];
export const YARD = [
  ['Winch', 'winch', 2, 170], ['Winch', 'winch', 3, 290], ['Engine', 'motor', 2, 120], ['Engine', 'motor', 3, 210],
  ['Crane Remote', 'remote', 1, 170], ['Repair Station', 'repair', 1, 130], ['Coastal Runner', 'boat', 2, 280],
  ['Survey Launch', 'boat', 3, 480],
];
export const ICONS = { fish: '🐟', valve: '⚙', note: '▤', meat: '🥩', hide: '◇', scrap: '▣', lantern: '▥' };
export const clamp = (x, min, max) => Math.max(min, Math.min(max, x));
export const toward = (a, b, step) => a + clamp(b - a, -step, step);
export const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
export const rng = (seed) => () => {
  seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  return seed / 4294967296;
};

export function fresh() {
  return {
    cash: 540, fatigue: 8, hunger: 12, boat: { x: 1449, y: 968, angle: 0 }, scene: 'sea',
    gear: { casting: 1, jigging: 1, suit: 1, tank: 1, hooker: 1, winch: 1, motor: 1, boat: 1, bag: 1, knife: 1 },
    condition: { pistol: 100, knife: 100, rods: 100, winch: 100 },
    inventory: [], drops: [], cargo: [], completed: [], read: [], explored: {}, kills: {}, excavated: {},
    shooting: 0, mystery: 0, selected: 'knife', tutorial: true, sound: true, shake: true,
  };
}

export function shapeFor(item) {
  let cells = item.shape || [[0, 0]];
  for (let step = 0; step < (item.rotation || 0); step++) {
    cells = cells.map(([x, y]) => [-y, x]);
    const minX = Math.min(...cells.map(([x]) => x));
    const minY = Math.min(...cells.map(([, y]) => y));
    cells = cells.map(([x, y]) => [x - minX, y - minY]);
  }
  return cells;
}
export function bagSize(gear, bag) {
  return bag === 'belt' ? [3, 2] : [4 + gear.bag, 2 + gear.bag];
}
export function footprint(item, x = item.x, y = item.y) {
  return shapeFor(item).map(([dx, dy]) => [x + dx, y + dy]);
}
export function fits(state, item, bag, x, y) {
  const [w, h] = bagSize(state.gear, bag);
  const occupied = state.inventory.filter((other) => other !== item && other.bag === bag).flatMap((other) => footprint(other));
  return footprint(item, x, y).every(([cx, cy]) =>
    cx >= 0 && cy >= 0 && cx < w && cy < h && !occupied.some(([ox, oy]) => cx === ox && cy === oy));
}
export function landing(island) {
  return { x: island.x + island.dock[0], y: island.y + island.dock[1] };
}
export function landAt(x, y) {
  return ISLANDS.find((i) => ((x - i.x) / i.rx) ** 2 + ((y - i.y) / i.ry) ** 2 < 0.91);
}

function depthScore(x, y) {
  return Math.sin(x / 235 + Math.sin(y / 261)) * 0.9
    + Math.cos(y / 188 + Math.sin(x / 331) * 1.3) * 0.75
    + Math.sin((x + y) / 316) * 0.4 + Math.cos((x - y) / 111) * 0.15;
}
const cells = [];
const cellWidth = Math.ceil(WORLD[0] / 10);
const cellHeight = Math.ceil(WORLD[1] / 10);
const depths = new Uint8Array(cellWidth * cellHeight);
let wet = 0;
for (let row = 0; row < cellHeight; row++) {
  for (let col = 0; col < cellWidth; col++) {
    const x = col * 10 + 5;
    const y = row * 10 + 5;
    const idx = row * cellWidth + col;
    if (landAt(x, y)) continue;
    wet++;
    const nearShore = ISLANDS.some((i) => ((x - i.x) / (i.rx + 88)) ** 2 + ((y - i.y) / (i.ry + 70)) ** 2 <= 1);
    const site = SITES.find((mark) => Math.hypot(x - mark.x, y - mark.y) < 57);
    if (site || nearShore) {
      depths[idx] = site?.depth || 1;
    } else {
      cells.push({ idx, score: depthScore(x, y) });
    }
  }
}
const assignedMid = depths.reduce((count, value) => count + Number(value === 2), 0);
const middle = Math.floor(wet / 2) - assignedMid;
cells.sort((a, b) => a.score - b.score);
const deep = Math.min(cells.length - middle, Math.floor(wet * .29));
for (const [index, cell] of cells.entries()) {
  depths[cell.idx] = index < deep ? 3 : index < deep + middle ? 2 : 1;
}
export function depthAt(x, y) {
  const col = clamp(Math.floor(x / 10), 0, cellWidth - 1);
  const row = clamp(Math.floor(y / 10), 0, cellHeight - 1);
  return depths[row * cellWidth + col] || 1;
}
export function depthCounts() {
  const counts = [0, 0, 0, 0];
  depths.forEach((depth) => counts[depth]++);
  return counts;
}
