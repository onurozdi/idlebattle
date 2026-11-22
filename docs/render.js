import { WORLD, ISLANDS, SITES, depthAt, landing, clamp, rng } from './data.js';

const assetNames = ['islands', 'terrain', 'deck', 'dive', 'coast'];
const atlas = {
  0: [46, 43, 588, 556],
  1: [650, 61, 567, 520],
  2: [46, 685, 554, 460],
  3: [644, 684, 570, 455],
};
const diveOutline = [[510, 479], [570, 444], [629, 402], [648, 375], [685, 367], [705, 342], [744, 347], [759, 369], [748, 402], [764, 418], [799, 409], [811, 420], [799, 434], [755, 443], [724, 439], [679, 461], [618, 473], [582, 502], [557, 534], [545, 531], [566, 502], [527, 496], [512, 497]];
const deckPerson = [[568, 330], [574, 321], [600, 322], [615, 328], [625, 345], [621, 367], [613, 374], [625, 397], [626, 424], [616, 442], [614, 459], [625, 473], [622, 480], [574, 480], [566, 472], [577, 453], [574, 421], [563, 417], [563, 388], [572, 373], [563, 355]];

export function createRenderer(canvas) {
  const ctx = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height;
  const images = {};
  for (const name of assetNames) {
    const image = new Image();
    image.src = `assets/${name}.png`;
    images[name] = image;
  }
  const artReady = (name) => images[name]?.complete && images[name].naturalWidth;
  const world = document.createElement('canvas');
  world.width = WORLD[0] / 2;
  world.height = WORLD[1] / 2;
  const chart = world.getContext('2d');
  const colors = [[23, 150, 151], [14, 87, 117], [9, 48, 79]];
  const pixels = chart.createImageData(world.width, world.height);
  const random = rng(512);
  for (let y = 0; y < world.height; y++) {
    for (let x = 0; x < world.width; x++) {
      const depth = depthAt(x * 2, y * 2);
      const [r, g, b] = colors[depth - 1];
      const rip = Math.floor(Math.sin(x / 3 + Math.sin(y / 4) * 1.7) * 2 + Math.cos(y * 1.62 + x * .26) * 1.4);
      const light = (random() - .5) * 15 + rip * 2.3;
      const offset = (y * world.width + x) * 4;
      pixels.data.set([r + light, g + light, b + light, 255], offset);
    }
  }
  chart.putImageData(pixels, 0, 0);
  const flecks = Array.from({ length: 115 }, () => [random() * W, random() * H, 3 + random() * 10, random() * 10]);
  const silts = Array.from({ length: 74 }, () => [random() * W, random() * H, .4 + random() * 1.5]);
  const fog = document.createElement('canvas');
  fog.width = W;
  fog.height = H;
  const fogCtx = fog.getContext('2d');
  const masked = document.createElement('canvas');
  masked.width = W;
  masked.height = H;
  const maskCtx = masked.getContext('2d');

  function poly(points, color, target = ctx) {
    target.beginPath();
    for (const [i, xy] of points.entries()) {
      if (i) target.lineTo(...xy);
      else target.moveTo(...xy);
    }
    target.closePath();
    if (color) { target.fillStyle = color; target.fill(); }
  }
  function rect(x, y, w, h, color) {
    ctx.fillStyle = color;
    ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h));
  }
  function line(points, width, color, target = ctx) {
    target.strokeStyle = color;
    target.lineWidth = width;
    target.beginPath();
    points.forEach(([x, y], index) => index ? target.lineTo(x, y) : target.moveTo(x, y));
    target.stroke();
  }
  function ellipse(x, y, rx, ry, color) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  function crop(name, source, destination) {
    if (artReady(name)) ctx.drawImage(images[name], ...source, ...destination);
  }
  function gradient(top, bottom, color1, color2) {
    const grad = ctx.createLinearGradient(0, top, 0, bottom);
    grad.addColorStop(0, color1);
    grad.addColorStop(1, color2);
    rect(0, top, W, bottom - top + 1, grad);
  }
  function outlinePatch(name, bounds, shape, x, y, w, h) {
    if (!artReady(name)) return false;
    const [sx, sy, sw, sh] = bounds;
    ctx.save();
    poly(shape.map(([px, py]) => [x + (px - sx) / sw * w, y + (py - sy) / sh * h]));
    ctx.clip();
    crop(name, bounds, [x, y, w, h]);
    ctx.restore();
    return true;
  }
  function islandArt(island) {
    const width = island.rx * 2.1;
    const height = island.ry * 2.08;
    if (artReady('islands')) {
      crop('islands', atlas[island.art], [island.x - width / 2, island.y - height / 2, width, height]);
    } else {
      ellipse(island.x, island.y, island.rx, island.ry, '#b4a06b');
      ellipse(island.x, island.y - 3, island.rx * .92, island.ry * .86, '#678154');
    }
    const end = landing(island);
    const dx = island.dock[0], dy = island.dock[1];
    ctx.save();
    ctx.translate(end.x, end.y);
    ctx.rotate(Math.atan2(dy, dx));
    rect(-51, -9, 59, 20, '#403936');
    rect(-51, -8, 57, 15, '#b58455');
    for (let x = -48; x < 7; x += 5) rect(x, -8, 1, 15, '#774d37');
    rect(-3, -9, 5, 5, '#213c47');
    rect(-3, 4, 5, 5, '#213c47');
    ctx.restore();
  }
  function splash(x, y, size, time) {
    for (let i = 0; i < 4; i++) {
      const radius = Math.max(0, (i * 8 + time * 15) % 33);
      ctx.strokeStyle = `rgba(163,225,236,${.69 - radius * .016})`;
      ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.ellipse(x, y, radius * size, radius * .4 * size, 0, 0, 7); ctx.stroke();
    }
  }
  function mapBoat(angle, time, moving) {
    ctx.save();
    ctx.translate(W / 2, H / 2);
    ctx.rotate(angle);
    if (moving) {
      for (let i = 0; i < 8; i++) {
        const x = -23 - i * 5 - (time * 18 % 5);
        line([[x, -4 - i * 1.8], [x - 6, -6 - i * 1.8]], 1.3, '#bce5dc88');
        line([[x, 4 + i * 1.8], [x - 6, 6 + i * 1.8]], 1.3, '#bce5dc88');
      }
    }
    poly([[-28, -10], [-8, -15], [20, -11], [31, -1], [22, 9], [-24, 12], [-30, 7]], '#152b40');
    poly([[-26, -9], [-8, -14], [18, -10], [29, -1], [21, 6], [-24, 9], [-28, 5]], '#d36e39');
    poly([[-24, -6], [-9, -10], [17, -8], [25, -1], [17, 4], [-23, 7]], '#916c4e');
    rect(-5, -11, 19, 17, '#f1d6a2');
    rect(-5, 2, 19, 5, '#9b704e');
    rect(9, -8, 6, 11, '#214b61');
    rect(-15, -2, 6, 5, '#425563');
    line([[-4, -5], [8, -5]], 1.5, '#fff1d1');
    ctx.restore();
  }
  function sea(frame) {
    const boat = frame.data.boat;
    const sx = boat.x - W / 2, sy = boat.y - H / 2;
    rect(0, 0, W, H, '#124e6d');
    const ax = clamp(sx, 0, WORLD[0]), ay = clamp(sy, 0, WORLD[1]);
    const bx = Math.min(sx + W, WORLD[0]), by = Math.min(sy + H, WORLD[1]);
    if (bx > ax && by > ay) ctx.drawImage(world, ax / 2, ay / 2, (bx - ax) / 2, (by - ay) / 2, ax - sx, ay - sy, bx - ax, by - ay);
    for (const [x, y, size, phase] of flecks) {
      const wx = ((x - sx * .45 + frame.time * 4) % W + W) % W;
      const wy = ((y - sy * .55) % H + H) % H;
      if (Math.sin(frame.time * .8 + phase) < -.24) continue;
      line([[wx, wy], [wx + size / 2, wy - 1.4], [wx + size, wy]], 1, '#a2e0e580');
    }
    ctx.save();
    ctx.translate(-sx, -sy);
    ISLANDS.forEach(islandArt);
    for (const [i, item] of SITES.entries()) {
      if (frame.data.completed.includes(i)) continue;
      const y = item.y + Math.sin(frame.time * 2.7 + i) * 1.5;
      splash(item.x, y, .36, frame.time);
      ellipse(item.x, y, 9, 4.8, '#d96a2a');
      rect(item.x + 1, y - 4, 4, 7, '#e5e5cc');
      line([[item.x - 6, y - 3], [item.x, y - 4]], 1, '#ffd288');
    }
    ctx.restore();
    mapBoat(boat.angle, frame.time, Math.hypot(frame.moving.x, frame.moving.y) > .11);
  }
  function silhouette(x, y, face, moving, options = {}) {
    const { time = 0, crouch = false, pose = '', npc = false, color = '#294968', range = false, gear = false } = options;
    const step = moving ? Math.sin(time * 22) : 0;
    const idle = moving ? Math.abs(step) * 1.6 : Math.sin(time * 3) * .65;
    const height = crouch ? .77 : 1;
    ctx.save();
    ctx.translate(Math.round(x), Math.round(y));
    ctx.scale(face, height);
    ellipse(0, 0, 13, 2.6, '#06121e66');
    if (!moving && !crouch && !pose && !npc && outlinePatch('deck', [562, 321, 65, 160], deckPerson, -11, -63 - idle, 26, 64)) {
      ctx.restore();
      return;
    }
    const hip = -23 - idle;
    line([[-5, hip], [-6 + step * 8, -11], [-7 + step * 10, -2]], 8, '#111d2b');
    line([[3, hip], [6 - step * 8, -11], [7 - step * 10, -2]], 8, '#283847');
    rect(-10 + step * 10, -5, 10, 5, '#614737');
    rect(3 - step * 10, -5, 11, 5, '#634932');
    poly([[-8, -47 - idle], [4, -48 - idle], [9, -41 - idle], [7, -23 - idle], [-8, -23 - idle], [-10, -37 - idle]], color);
    line([[-8, -27 - idle], [7, -27 - idle]], 3, '#564438');
    rect(3, -28 - idle, 4, 3, '#b18653');
    line([[-4, -43 - idle], [-5 + step * 4, -34], [1 + step * 5, -30]], 5, '#3f657c');
    if (pose === 'crane' || range || pose === 'fish') {
      line([[4, -42], [12, -35], [20, -40]], 5, '#365b73');
      rect(18, -42, 5, 4, '#d49d6d');
      if (range) { rect(22, -43, 11, 4, '#38424a'); rect(21, -42, 3, 8, '#1c242c'); }
    } else {
      line([[5, -43], [7 - step * 5, -35], [6 - step * 5, -26]], 5, '#456980');
      rect(4 - step * 5, -28, 4, 5, '#c9946d');
    }
    ellipse(0, -54 - idle, 9, 10, '#392d29');
    rect(-5, -59 - idle, 13, 12, '#d39e79');
    poly([[-9, -60 - idle], [-3, -66 - idle], [4, -66 - idle], [9, -60 - idle], [4, -56 - idle], [-5, -59 - idle], [-5, -50 - idle], [-9, -53 - idle]], npc ? '#a4968a' : '#43342c');
    rect(2, -55 - idle, 7, 3, '#617576');
    rect(7, -54 - idle, 3, 4, '#eeb487');
    if (gear) {
      line([[4, -41], [10, -34], [13, -28]], 4, '#688292');
      rect(8, -28, 8, 10, '#e4a040');
      rect(10, -26, 4, 7, '#ffd886');
    }
    ctx.restore();
  }
  function backdropRow(row, x, y, width, height) {
    const bounds = [[0, 0, 1536, 276], [0, 288, 1536, 220], [0, 513, 1536, 250], [0, 770, 1536, 235]][row];
    crop('terrain', bounds, [x, y, width, height]);
  }
  function ground(frame, type, x, bottom) {
    const start = Math.floor(x / 14) * 14 - 14;
    const profile = [];
    for (let px = start; px < x + W + 25; px += 14) profile.push([px - x, frame.floor(type, px)]);
    poly([...profile, [W + 14, bottom], [-18, bottom]], type === 'cave' ? '#273744' : '#334337');
    ctx.save();
    ctx.clip();
    if (type === 'cave') {
      for (let k = 0; k < W; k += 290) crop('dive', [101, 582, 408, 115], [k, 291, 298, 229]);
    } else {
      for (let k = 0; k < W; k += 444) crop('terrain', [20, 411, 885, 91], [k, 332, 445, 170]);
    }
    ctx.restore();
    line(profile, 8, type === 'cave' ? '#ad7a50' : '#987347');
    line(profile.map(([px, py]) => [px, py - 2]), 2, '#dbad69');
  }
  function label(text, x, y) {
    ctx.font = 'bold 14px Georgia';
    const width = ctx.measureText(text).width + 13;
    rect(x - width / 2, y - 15, width, 21, '#102035e5');
    ctx.fillStyle = '#f7d197'; ctx.textAlign = 'center'; ctx.fillText(text, x, y);
  }
  function animalArt(animal, x, y) {
    const scale = animal.name === 'Rabbit' ? .53 : animal.name === 'Bear' ? 1.42 : 1;
    ctx.save(); ctx.translate(x, y - 8); ctx.scale(animal.face * scale, scale);
    if (animal.state === 'dead') { ctx.translate(0, 7); ctx.rotate(animal.spin * .47); }
    const dark = animal.name === 'Bear' ? '#332c2c' : '#61503b';
    const light = animal.flash > 0 ? '#b76348' : animal.name === 'Rabbit' ? '#a48259' : '#91714b';
    if (animal.name === 'Snake') {
      line([[-23, 6], [-11, 1], [4, 5], [15, 0], [22, 2]], 5, '#657048');
    } else {
      ellipse(0, -10, 19, 10, dark);
      ellipse(0, -11, 17, 8, light);
      ellipse(16, -15, 8, 6, light);
      rect(19, -16, 3, 2, '#171727');
      line([[-11, -4], [-12, 8], [-7, 8]], 3, dark);
      line([[9, -4], [11, 8], [16, 8]], 3, dark);
      if (animal.name === 'Rabbit' || animal.name === 'Deer') {
        line([[13, -18], [10, -28]], 4, light);
        line([[18, -19], [18, -29]], 3, light);
        if (animal.name === 'Deer') line([[14, -22], [8, -33], [5, -34]], 2, '#cbb193');
      }
    }
    for (const [mx, my] of animal.marks) rect(mx, my, 2, 2, '#782e33');
    ctx.restore();
  }
  function landscape(frame, cave) {
    const { camera, data, player, time } = frame;
    const x = camera.x;
    gradient(0, H, cave ? '#142934' : '#436c74', cave ? '#0d1820' : '#22352d');
    if (cave) {
      for (let px = -x % 1080 - 20; px < W; px += 1060) backdropRow(3, px, 85, 1075, 267);
      crop('terrain', [1, 770, 1530, 81], [-x * .16 % 20, 0, W + 25, 135]);
    } else {
      const town = frame.dock === 0;
      if (town && x < 1360) backdropRow(0, -x, 39, 1400, 318);
      for (let wx = town ? 1370 : 0; wx < 3200; wx += 860) if (wx - x > -860 && wx - x < W) {
        backdropRow(1, wx - x, 37, 876, 325);
      }
      if (frame.lakeX - x > -145 && frame.lakeX - x < W + 145) {
        backdropRow(2, frame.lakeX - x - 230, 117, 485, 231);
      }
    }
    ground(frame, cave ? 'cave' : 'land', x, H);
    if (cave) {
      const platform = [[550 - x, 163], [617 - x, 158], [760 - x, 150], [1120 - x, 160], [1120 - x, 236], [977 - x, 225], [704 - x, 246], [553 - x, 225]];
      poly(platform, '#465363');
      ctx.save(); ctx.clip();
      crop('terrain', [38, 794, 675, 104], [546 - x, 131, 589, 132]);
      ctx.restore();
      line(platform.slice(0, 4), 5, '#d39b61');
      const dug = data.excavated[frame.caveKey];
      if (dug !== 'claimed') {
        const moundX = frame.caveMound - x, moundY = frame.floor('cave', frame.caveMound);
        ellipse(moundX, moundY + .5, 18, 4.5, '#563d31');
        if (!dug) poly([[moundX - 14, moundY], [moundX - 6, moundY - 8], [moundX + 5, moundY - 10], [moundX + 15, moundY]], '#9f6b46');
        else {
          line([[moundX - 6, moundY - 7], [moundX + 4, moundY - 7], [moundX + 4, moundY - 2]], 4, '#e1b163');
          rect(moundX + 3, moundY - 2, 4, 2, '#c4914f');
        }
      }
    } else {
      if (frame.dock === 0) for (const [wx, title] of frame.townDoors) {
        if (wx - x > -50 && wx - x < W + 50) {
          label(title, wx - x, 279);
          silhouette(wx - x + 25, frame.floor('land', wx), -1, false, { time, npc: true, color: '#5f504a' });
        }
      }
      if (frame.caveX - x > -100 && frame.caveX - x < W + 100) {
        const x1 = frame.caveX - x, y1 = frame.floor('land', frame.caveX);
        ellipse(x1, y1 - 38, 53, 66, '#94816a');
        ellipse(x1, y1 - 32, 36, 56, '#1a2328');
        line([[x1 - 52, y1], [x1 - 40, y1 - 67], [x1 - 15, y1 - 97], [x1 + 24, y1 - 91], [x1 + 51, y1 - 4]], 7, '#5c6261');
      }
      if (frame.dock === 0) {
        const rock = 1900 - x, y1 = frame.floor('land', 1900);
        poly([[rock - 23, y1], [rock - 12, y1 - 21], [rock + 8, y1 - 27], [rock + 21, y1]], '#647275');
      }
      for (const animal of frame.animals) if (animal.state !== 'gone') animalArt(animal, animal.x - x, frame.floor('land', animal.x));
      for (const shot of frame.shots) line([[shot.x - x, shot.y], [shot.x - x - shot.vx * .026, shot.y - shot.vy * .026]], 1, '#fff2af');
    }
    const gear = cave && data.gear.lantern;
    silhouette(player.x - x, player.y, player.face, Math.abs(player.vx) > 12, { time, crouch: player.crouch, gear, range: player.attack > 0 && data.selected === 'pistol' });
    if (cave && frame.caveDig > 0) {
      const px = player.x - x, py = player.y - 24;
      const swing = Math.sin(time * 15);
      line([[px + 6, py], [px + 25 + swing * 5, py + 10 + swing * 7]], 3, '#a9774d');
      rect(px + 23 + swing * 5, py + 10 + swing * 7, 11, 5, '#abb8be');
    }
    if (cave) {
      maskCtx.clearRect(0, 0, W, H);
      maskCtx.fillStyle = '#01060bf7';
      maskCtx.fillRect(0, 0, W, H);
      maskCtx.globalCompositeOperation = 'destination-out';
      const lights = [[58 - x, 286, 220]];
      if (gear) lights.push([player.x - x + player.face * 10, player.y - 29, [0, 112, 215, 345][gear]]);
      for (const [lx, ly, r] of lights) {
        const grad = maskCtx.createRadialGradient(lx, ly, r * .15, lx, ly, r);
        grad.addColorStop(0, '#000');
        grad.addColorStop(.52, '#000d');
        grad.addColorStop(1, '#0000');
        maskCtx.fillStyle = grad;
        maskCtx.fillRect(lx - r, ly - r, r * 2, r * 2);
      }
      maskCtx.globalCompositeOperation = 'source-over';
      ctx.drawImage(masked, 0, 0);
    }
  }
  function chain(points, thick) {
    line(points, thick, '#202c36');
    line(points, Math.max(1.4, thick * .46), '#98a8a8');
    const [a, b] = points;
    const size = Math.hypot(b[0] - a[0], b[1] - a[1]);
    for (let t = 3; t < size; t += 6) {
      const dx = a[0] + (b[0] - a[0]) * t / size;
      const dy = a[1] + (b[1] - a[1]) * t / size;
      rect(dx - 1, dy - 1, 2, 3, '#506468');
    }
  }
  function hook(x, y, scale = 1) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(scale, scale);
    line([[0, -4], [0, 6], [3, 11], [7, 11], [10, 8], [10, 4]], 4.6, '#293e47');
    line([[0, -4], [0, 6], [3, 10], [7, 10], [9, 7], [9, 4]], 2.2, '#bfc0ad');
    ctx.restore();
  }
  function artifact(item, x, y, scale = 1) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(item.angle || 0); ctx.scale(scale, scale);
    if (item.kind === 'jar') {
      poly([[-13, -33], [13, -33], [10, -23], [17, -13], [18, 2], [12, 22], [7, 28], [-9, 28], [-16, 18], [-19, -3], [-15, -15], [-10, -24]], '#432f2d');
      ellipse(-15, -15, 9, 12, '#9a654e'); ellipse(-16, -15, 5, 8, '#2d4751');
      ellipse(15, -15, 9, 12, '#a37457'); ellipse(16, -15, 5, 8, '#2d4751');
      ellipse(0, -1, 18, 26, '#aa7654'); ellipse(-5, -4, 9, 22, '#c29369');
      rect(-13, -33, 26, 7, '#c49970'); line([[-16, -8], [0, -4], [16, -8]], 2, '#795c4c');
      line([[-14, 10], [0, 13], [14, 10]], 2, '#ddab78');
    } else if (item.kind === 'plane' || item.kind === 'wreck') {
      poly([[-43, 5], [-26, -11], [10, -9], [36, -2], [48, 9], [20, 24], [-28, 25]], item.kind === 'plane' ? '#737d78' : '#72584a');
      poly([[-6, 5], [7, -26], [15, -26], [17, 3], [47, 14], [37, 19], [-6, 15]], '#9a9979');
      rect(-24, -8, 11, 7, '#253c49'); rect(-4, -8, 11, 7, '#253c49');
    } else {
      rect(-24, -22, 48, 48, '#654d3b'); rect(-21, -20, 42, 41, '#a4784e');
      for (let z = -16; z < 21; z += 9) rect(-21, z, 42, 1, '#694837');
      rect(-17, -21, 5, 43, '#465660'); rect(13, -21, 5, 43, '#465660'); rect(-4, -5, 8, 8, '#d5a454');
    }
    if (item.damage > 5) line([[-3, -4], [-7, 0], [-5, 7], [-10, 16]], 1.6, '#513231');
    ctx.restore();
  }
  function ocean(time) {
    gradient(0, 228, '#5f94bc', '#b0c3c7');
    for (let x = 0; x < 1080; x += 275) crop('deck', [36 + x * .21, 60, 340, 210], [x, 0, 275, 239]);
    gradient(228, H, '#125278', '#093554');
    for (let x = -22; x < W; x += 533) crop('coast', [600, 576, 640, 221], [x + Math.sin(time * .75) * 12, 229, 549, 278]);
    for (const [x, y, size, phase] of flecks) {
      if (y < 245 || Math.sin(time + phase) < .2) continue;
      const fx = (x + time * 10) % W;
      line([[fx, y], [fx + size, y - 1]], 1, '#c4e6e4a0');
    }
  }
  function vessel(frame) {
    const { camera, anchor, data, player, time, fishing } = frame;
    ocean(time);
    ctx.save();
    ctx.translate(-camera.x, 0);
    const deckY = 341;
    const bob = Math.sin(time * 1.73) * 1.7;
    ctx.translate(0, bob);
    const offset = (anchor?.trimBase || 0) * .08;
    poly([[294 + offset, deckY - 5], [857 + offset, deckY - 20], [833 + offset, 366], [789 + offset, 385], [327 + offset, 385], [299 + offset, 365]], '#152e48');
    ctx.save();
    ctx.clip();
    crop('deck', [458, 478, 1020, 88], [292 + offset, deckY - 18, 569, 63]);
    ctx.restore();
    rect(300 + offset, 330, 443, 13, '#a67a50');
    for (let x = 306; x < 746; x += 9) rect(x + offset, 335 + x % 3, 24, 1, '#614730');
    line([[302 + offset, 342], [822 + offset, 340], [854 + offset, 324]], 3, '#dd8245');
    outlinePatch('deck', [981, 94, 437, 387], [[987, 247], [1124, 238], [1153, 205], [1183, 202], [1184, 102], [1197, 102], [1205, 133], [1223, 147], [1223, 187], [1241, 239], [1372, 240], [1381, 266], [1357, 276], [1417, 438], [1372, 461], [1366, 478], [990, 478]], 592 + offset, 130, 216, 211);
    for (const x of [307, 838]) {
      rect(x + offset, 327, 13, 6, '#625647'); rect(x + offset + 3, 322, 8, 6, '#ac906c');
    }
    chain([[842 + offset, 328], [940 + offset, 446]], 3.5);
    const boom = anchor?.boom ?? .16;
    const angle = anchor?.angle ?? .26;
    const craneX = 555 + offset;
    rect(craneX - 24, 318, 48, 17, '#a94a25');
    rect(craneX - 20, 314, 41, 7, '#e47d40');
    rect(craneX - 15, 290, 25, 25, '#b65529');
    ellipse(craneX + 14, 306, 12, 10, '#333f46');
    for (let ring = 6; ring <= 18; ring += 3) rect(craneX + ring, 299, 1, 13, '#969694');
    const endX = craneX - 70 - boom * 203;
    const endY = 266 - angle * 70;
    line([[craneX - 6, 292], [craneX - 39, 264], [endX + 9, endY]], 8, '#89412a');
    line([[craneX - 5, 283], [craneX - 32, 262], [endX, endY]], 7, '#dc7139');
    line([[craneX - 51, 263], [endX, endY]], 4, '#aeb3a5');
    ellipse(craneX - 8, 281, 5, 5, '#df924d');
    const phase = anchor?.phase || 'idle';
    const hasLoad = anchor?.piece && ['surface', 'onDeck'].includes(phase);
    if (hasLoad) {
      const float = phase === 'onDeck' ? 0 : Math.sin(time * 2) * 7;
      const y = phase === 'onDeck' ? 319 : 289 + (anchor.lowering || 0) * 45;
      const x = endX + float;
      chain([[endX, endY], [x, y - 41]], 3);
      hook(x, y - 41, .62);
      line([[x + 2, y - 33], [x - 11, y - 12]], 1.8, '#d0a777');
      line([[x + 2, y - 33], [x + 11, y - 12]], 1.8, '#d0a777');
      artifact(anchor.piece, x, y, .76);
    } else {
      const ey = anchor?.chain > 0 ? 508 : endY + 27;
      chain([[endX, endY], [endX, ey]], 2.9);
      if (ey < H) hook(endX, ey, .65);
    }
    if (data.cargo.length) {
      data.cargo.slice(0, 3).forEach((item, i) => artifact(item, 360 + i * 42, 321, .57));
    }
    if (data.gear.repair) { rect(696, 316, 36, 5, '#ad784e'); rect(700, 321, 4, 11, '#594531'); rect(724, 321, 4, 11, '#594531'); }
    const visibleX = data.scene === 'moored' ? 489 : player.x;
    if (fishing) fishingVisual(frame, visibleX, deckY, -1);
    else silhouette(visibleX + offset, deckY - Math.max(0, deckY - player.y), player.face, Math.abs(player.vx) > 12, { time, crouch: player.crouch, pose: anchor?.mode ? 'crane' : '' });
    ctx.restore();
  }
  function fishingVisual(frame, x, y, face) {
    const { fishing, time } = frame;
    silhouette(x, y, face, false, { time, pose: 'fish' });
    const hand = [x + face * 18, y - 39];
    const tip = [x + face * 91, y - (fishing.phase === 'reel' ? 108 : 98)];
    line([hand, [x + face * 47, y - 91], [x + face * 69, y - 111], tip], 3, '#95704c');
    if (fishing.phase === 'ready') return;
    const slide = fishing.progress * 61;
    const at = [x + face * (205 - slide), y + (face === -1 ? 17 : 44) + Math.sin(time * 3) * 2];
    line([tip, at], 1.15, '#e0ded3');
    if (fishing.style === 'cast' && fishing.phase !== 'reel') ellipse(at[0], at[1], 4.5, 3.2, '#db795b');
    if (fishing.phase === 'bite' || fishing.phase === 'reel') splash(at[0], at[1], .8, time);
  }
  function lake(frame) {
    gradient(0, H, '#7094a7', '#286874');
    backdropRow(2, -3, -5, W + 7, H + 10);
    rect(0, 313, 264, 16, '#9b8057');
    fishingVisual(frame, 239, 316, 1);
  }
  function diverSprite(frame, x, y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(frame.player.face, 1);
    ctx.rotate(clamp(frame.player.vy * .0014, -.35, .35));
    const flutter = Math.sin(frame.time * 7) * (Math.abs(frame.player.vy) > 10 ? 2 : .5);
    if (!outlinePatch('dive', [509, 340, 304, 197], diveOutline, -79, -34 + flutter, 122, 79)) {
      rect(-26, -11, 47, 16, '#303f54'); rect(19, -13, 13, 12, '#d4a47a'); rect(26, -12, 12, 6, '#a6d4cf');
      line([[-20, 1], [-43, 14], [-58, 19]], 6, '#bb9b4c');
    }
    if (frame.anchor.rig) {
      line([[24, 3], [60, 4]], 3, '#aec1bd');
      ctx.strokeStyle = '#b7c7c5'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(62, 4, 3, 0, 7); ctx.stroke();
    }
    if (frame.dive.lit) rect(24, -2, 9, 4, '#d19d57');
    ctx.restore();
  }
  function water(frame) {
    const { anchor, camera, player, data, time, dive } = frame;
    const seabedY = anchor.floor - camera.y;
    const playerY = player.y - camera.y;
    const tier = anchor.tier;
    const horizon = -camera.y;
    gradient(0, H, ['#286e8b', '#286e8b', '#154462', '#101d36'][tier], ['#144562', '#144562', '#142e47', '#13192d'][tier]);
    if (horizon >= -40) {
      crop('dive', [5, 62, 1510, 86], [0, horizon, W, 79]);
      line([[0, horizon + 4], [W, horizon + 4]], 2, '#c3f7e8');
    }
    const known = data.explored[anchor.surveyKey] || [];
    if (seabedY < H + 195) {
      const alpha = [0, .95, .64, .32][tier];
      ctx.save();
      ctx.globalAlpha = alpha;
      for (let x = -45; x < W; x += 379) {
        crop('dive', [6, 323, 486, 435], [x, seabedY - 197, 385, 290]);
      }
      ctx.restore();
      rect(0, seabedY + 1, W, H - seabedY, '#304451');
      fogCtx.clearRect(0, 0, W, H);
      fogCtx.fillStyle = tier === 3 ? '#0b1b2a' : '#14506d';
      fogCtx.fillRect(0, Math.max(0, seabedY - 204), W, H);
      fogCtx.globalCompositeOperation = 'destination-out';
      for (const x of known) {
        const g = fogCtx.createRadialGradient(x, seabedY - 64, 82, x, seabedY - 64, 177);
        g.addColorStop(0, '#000');
        g.addColorStop(.74, '#000');
        g.addColorStop(1, '#0000');
        fogCtx.fillStyle = g;
        fogCtx.fillRect(x - 177, seabedY - 240, 354, 317);
      }
      fogCtx.globalCompositeOperation = 'source-over';
      ctx.drawImage(fog, 0, 0);
    }
    const h = frame.hook;
    const hy = h.y - camera.y;
    const item = anchor.piece;
    const visible = item && (known.some((x) => Math.abs(x - item.x) < 135) || anchor.phase === 'lifting') && (tier < 3 || (dive.lit && Math.hypot(item.x - player.x, item.y - player.y) < 275));
    if (anchor.chain > 0) { chain([[h.x, horizon], [h.x, hy]], 3.6); hook(h.x, hy, .78); }
    if (visible) {
      for (const lineAt of anchor.lines) line([[h.x + 5, hy + 6], [item.x + lineAt * 14, item.y - camera.y - 15]], 1.8, '#c7a874');
      if (anchor.attached !== null) line([[player.x + player.face * 62, playerY + 4], [item.x + anchor.attached * 14, item.y - camera.y - 15]], 1.8, '#c7a874');
      artifact(item, item.x, item.y - camera.y);
    }
    if (tier === 3) {
      maskCtx.clearRect(0, 0, W, H);
      maskCtx.fillStyle = '#01050ce9'; maskCtx.fillRect(0, 0, W, H);
      if (dive.lit) {
        maskCtx.globalCompositeOperation = 'destination-out';
        const lx = player.x + player.face * 58, ly = playerY;
        const glow = maskCtx.createRadialGradient(lx, ly, 33, lx, ly, 248);
        glow.addColorStop(0, '#000'); glow.addColorStop(.5, '#000e'); glow.addColorStop(1, '#0000');
        maskCtx.fillStyle = glow; maskCtx.fillRect(lx - 248, ly - 248, 496, 496);
        maskCtx.globalCompositeOperation = 'source-over';
      }
      ctx.drawImage(masked, 0, 0);
    }
    for (const [x, y, size] of silts) ellipse(x, ((y - time * 8) % H + H) % H, size, size, '#b0e5ed44');
    diverSprite(frame, player.x, playerY);
    for (let i = 0; i < 4; i++) {
      const age = (time * .9 + i * .37) % 1.6;
      ellipse(player.x + player.face * 36 + age * 5, playerY - 15 - age * 33, 1 + age * 1.4, 1 + age * 1.3, '#b8e7e78e');
    }
  }
  return (frame) => {
    ctx.imageSmoothingEnabled = false;
    const scene = frame.data.scene;
    if (scene === 'sea') sea(frame);
    else if (scene === 'dive') water(frame);
    else if (scene === 'fish' && frame.returnScene === 'land') lake(frame);
    else if (['deck', 'moored', 'fish'].includes(scene)) vessel(frame);
    else landscape(frame, scene === 'cave');
    for (const drop of frame.data.drops) if (drop.scene === scene && drop.island === frame.dock && scene !== 'sea') {
      const x = drop.wx - frame.camera.x, y = (drop.wy || 330) - frame.camera.y;
      rect(x - 4, y - 6, 12, 7, '#d8a663');
      rect(x - 1, y - 8, 5, 3, '#ffe1ad');
    }
  };
}
