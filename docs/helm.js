const HEADING_COUNT = 16;
const HEADING_STEP = Math.PI * 2 / HEADING_COUNT;

function pose(art, cell, cx, cy, sternX, sternY) {
  return { art: `boat-${art}`, cell, cx, cy, sternX: sternX - cx, sternY: sternY - cy, flip: false };
}

// Positions are in atlas pixels. The pivot is centered along the hull's waterline.
const east = pose('east', 1, 1086, 391, 802, 408);
const eastSoutheast = pose('east', 2, 1807, 395, 1537, 358);
const southeast = pose('south', 0, 421, 358, 192, 174);
const southSoutheast = pose('south', 1, 1114, 379, 1011, 129);
const south = pose('south', 2, 1810, 373, 1810, 97);
const north = pose('north', 0, 365, 366, 365, 619);
const northNortheast = pose('north', 1, 1086, 368, 982, 609);
const northeast = pose('north', 2, 1822, 372, 1667, 587);
const eastNortheast = pose('east', 0, 369, 393, 115, 474);

function mirror(view) {
  return { ...view, sternX: -view.sternX, flip: true };
}

const headings = [
  east, eastSoutheast, southeast, southSoutheast, south,
  mirror(southSoutheast), mirror(southeast), mirror(eastSoutheast), mirror(east),
  mirror(eastNortheast), mirror(northeast), mirror(northNortheast),
  north, northNortheast, northeast, eastNortheast,
];

export function helm(angle) {
  const sector = ((angle / HEADING_STEP) % HEADING_COUNT + HEADING_COUNT) % HEADING_COUNT;
  const lower = Math.floor(sector);
  const fraction = sector - lower;
  const a = headings[lower];
  const b = headings[(lower + 1) % HEADING_COUNT];
  const view = headings[Math.round(sector) % HEADING_COUNT];
  return {
    view,
    sternX: a.sternX + (b.sternX - a.sternX) * fraction,
    sternY: a.sternY + (b.sternY - a.sternY) * fraction,
  };
}
