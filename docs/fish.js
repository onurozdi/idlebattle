export const CAST_TIME = { cast: .86, jig: .67 };
export const LIFT_TIME = .52;
export const RELEASE_TIME = .62;

const sea = [
  { id: 'anchovy', name: 'Anchovy', level: 1, weight: 40, length: 26, cells: 1, value: 18, fight: .06, mouth: .60 },
  { id: 'mackerel', name: 'Atlantic Mackerel', level: 1, weight: 30, length: 34, cells: 2, value: 30, fight: .22, mouth: .59 },
  { id: 'bream', name: 'Gilthead Bream', level: 2, weight: 15, length: 40, cells: 2, value: 48, fight: .37, mouth: .62 },
  { id: 'bass', name: 'European Sea Bass', level: 2, weight: 8, length: 49, cells: 3, value: 68, fight: .56, mouth: .56 },
  { id: 'bonito', name: 'Atlantic Bonito', level: 3, weight: 5, length: 58, cells: 3, value: 100, fight: .74, mouth: .56 },
  { id: 'tuna', name: 'Bluefin Tuna', level: 3, weight: 2, length: 69, cells: 4, value: 160, fight: .96, mouth: .57 },
].map((fish, cell) => ({ ...fish, cell, atlas: 'sea-fish' }));

const lake = [
  { id: 'perch', name: 'Lake Perch', level: 1, weight: 55, length: 28, cells: 2, value: 22, fight: .12, mouth: .68 },
  { id: 'trout', name: 'Lake Trout', level: 2, weight: 30, length: 39, cells: 2, value: 38, fight: .32, mouth: .60 },
  { id: 'pike', name: 'Northern Pike', level: 3, weight: 15, length: 51, cells: 3, value: 60, fight: .57, mouth: .55 },
].map((fish, cell) => ({ ...fish, cell, atlas: 'lake-fish' }));

const species = [...sea, ...lake];

export function fishSpecies(item) {
  if (item.kind !== 'fish') return null;
  return species.find((fish) => fish.id === item.species || fish.name === item.name)
    || (item.name === 'Coastal Cod' ? sea[3] : null);
}

export function chooseFish(style, rodLevel, random = Math.random) {
  const pool = (style === 'jig' ? sea : lake).filter((fish) => fish.level <= rodLevel);
  let roll = random() * pool.reduce((sum, fish) => sum + fish.weight, 0);
  for (const fish of pool) {
    roll -= fish.weight;
    if (roll < 0) return fish;
  }
  return pool.at(-1);
}

export function fishItem(fish) {
  return {
    kind: 'fish', species: fish.id, name: fish.name, value: fish.value,
    shape: Array.from({ length: fish.cells }, (_, x) => [x, 0]),
  };
}

export function rodCell(style, level) {
  return (style === 'jig' ? 3 : 0) + level - 1;
}
