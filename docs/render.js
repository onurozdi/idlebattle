import { WORLD, ISLANDS, SITES, depthAt, landing, clamp, rng, LEVEL_WIDTH, PINE_ROCK_X, DECK } from './data.js?v=2';
import { loadArt } from './art.js?v=2';

const atlas = {
  0: [46, 43, 588, 556],
  1: [650, 61, 567, 520],
  2: [46, 685, 554, 460],
  3: [644, 684, 570, 455],
};
const fauna = { Rabbit: [0, 37, 27], Deer: [1, 62, 54], Boar: [2, 55, 37], Bear: [3, 68, 52], Snake: [4, 53, 19] };
const finds = { jar: [0, 52, 66], chest: [1, 52, 45], crate: [2, 45, 46], wreck: [3, 96, 53], plane: [4, 104, 51] };

export function createRenderer(canvas) {
  const ctx = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height;
  const world = document.createElement('canvas');
  const mapScale = 2;
  world.width = WORLD[0] / mapScale;
  world.height = WORLD[1] / mapScale;
  const chart = world.getContext('2d');
  const random = rng(512);
  const { images, frames } = loadArt(drawChart);
  const flecks = Array.from({ length: 76 }, () => [random() * W, random() * H, 3 + random() * 10, random() * 10]);
  const silts = Array.from({ length: 74 }, () => [random() * W, random() * H, .4 + random() * 1.5]);
  const fog = document.createElement('canvas');
  fog.width = W;
  fog.height = H;
  const fogCtx = fog.getContext('2d');
  const masked = document.createElement('canvas');
  masked.width = W;
  masked.height = H;
  const maskCtx = masked.getContext('2d');

  function drawChart() {
    const waterArt = images['chart-water'];
    if (waterArt) chart.drawImage(waterArt, 0, 0, world.width, world.height);
    const pixels = chart.getImageData(0, 0, world.width, world.height);
    const colors = [[27, 151, 155], [17, 87, 118], [10, 47, 79]];
    for (let y = 0; y < world.height; y++) {
      for (let x = 0; x < world.width; x++) {
        const offset = (y * world.width + x) * 4;
        const boundaryX = x * mapScale + Math.sin(y * .19) * 5 + Math.sin(y * .47) * 2;
        const boundaryY = y * mapScale + Math.sin(x * .16) * 5;
        const [r, g, b] = colors[depthAt(boundaryX, boundaryY) - 1];
        const luminance = (pixels.data[offset] * .23 + pixels.data[offset + 1] * .57 + pixels.data[offset + 2] * .2);
        const light = pixels.data[offset + 3] ? clamp((luminance - 65) * .91, -24, 145) : 0;
        pixels.data[offset] = r + light;
        pixels.data[offset + 1] = g + light * .83;
        pixels.data[offset + 2] = b + light * .72;
        pixels.data[offset + 3] = 255;
      }
    }
    chart.putImageData(pixels, 0, 0);
    chart.save();
    chart.scale(1 / mapScale, 1 / mapScale);
    chart.imageSmoothingEnabled = false;
    ISLANDS.forEach(islandArt);
    chart.restore();
  }

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
    if (images[name]) ctx.drawImage(images[name], ...source, ...destination);
  }
  function sceneImage(name, x = 0, y = 0, width = W, height = H) {
    if (images[name]) ctx.drawImage(images[name], Math.round(x), Math.round(y), width, height);
  }
  function sprite(name, index, x, y, w, h) {
    const source = frames[name]?.[index];
    if (!source) return;
    crop(name, source, [Math.round(x), Math.round(y), w, h]);
  }
  function gradient(top, bottom, color1, color2) {
    const grad = ctx.createLinearGradient(0, top, 0, bottom);
    grad.addColorStop(0, color1);
    grad.addColorStop(1, color2);
    rect(0, top, W, bottom - top + 1, grad);
  }
  function islandArt(island) {
    const width = island.rx * 2.1;
    const height = island.ry * 2.08;
    if (!images.islands) return;
    chart.drawImage(images.islands, ...atlas[island.art], island.x - width / 2, island.y - height / 2, width, height);
    const end = landing(island);
    const dx = island.dock[0], dy = island.dock[1];
    chart.save();
    chart.translate(end.x, end.y);
    chart.rotate(Math.atan2(dy, dx));
    chart.fillStyle = '#493532'; chart.fillRect(-51, -9, 59, 20);
    chart.fillStyle = '#bf915e'; chart.fillRect(-51, -8, 57, 15);
    chart.fillStyle = '#805b40';
    for (let x = -48; x < 7; x += 5) chart.fillRect(x, -8, 1.5, 15);
    chart.fillStyle = '#443734';
    chart.fillRect(-3, -9, 5, 5);
    chart.fillRect(-3, 4, 5, 5);
    chart.restore();
  }
  function splash(x, y, size, time) {
    for (let i = 0; i < 4; i++) {
      const radius = Math.max(0, (i * 8 + time * 15) % 33);
      ctx.strokeStyle = `rgba(163,225,236,${.69 - radius * .016})`;
      ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.ellipse(x, y, radius * size, radius * .4 * size, 0, 0, 7); ctx.stroke();
    }
  }
  function mapBoat(angle, time, moving, level) {
    ctx.save();
    ctx.translate(W / 2, H / 2);
    ctx.rotate(angle);
    if (moving) {
      for (let i = 0; i < 18; i++) {
        const trail = i * 3.4 + (time * 26 % 3.4);
        const x = -34 - trail;
        const spread = 4 + trail * .36;
        const drift = Math.sin(trail * .62 + time * 4) * 1.5;
        const alpha = Math.max(0, .72 - i * .031);
        line([[x, -spread + drift], [x - 4, -spread - 1]], 1.3, `rgba(195,235,240,${alpha})`);
        line([[x, spread + drift], [x - 4, spread + 1]], 1.3, `rgba(195,235,240,${alpha})`);
      }
    }
    const bounds = frames['map-boat']?.[0];
    if (bounds) {
      const width = 82 + (level - 1) * 8;
      const height = width * bounds[3] / bounds[2];
      sprite('map-boat', 0, -width / 2, -height / 2 - Math.sin(time * 2.1), width, height);
    }
    ctx.restore();
  }
  function sea(frame) {
    const boat = frame.data.boat;
    const sx = boat.x - W / 2, sy = boat.y - H / 2;
    rect(0, 0, W, H, '#124e6d');
    const ax = clamp(sx, 0, WORLD[0]), ay = clamp(sy, 0, WORLD[1]);
    const bx = Math.min(sx + W, WORLD[0]), by = Math.min(sy + H, WORLD[1]);
    if (bx > ax && by > ay) ctx.drawImage(world, ax / mapScale, ay / mapScale, (bx - ax) / mapScale, (by - ay) / mapScale, ax - sx, ay - sy, bx - ax, by - ay);
    for (const [x, y, size, phase] of flecks) {
      const wx = ((x - sx * .45 + frame.time * 4) % W + W) % W;
      const wy = ((y - sy * .55) % H + H) % H;
      if (Math.sin(frame.time * .8 + phase) < -.24) continue;
      line([[wx, wy], [wx + size / 2, wy - 1.4], [wx + size, wy]], 1, '#a2e0e580');
    }
    ctx.save();
    ctx.translate(-sx, -sy);
    for (const [i, item] of SITES.entries()) {
      if (frame.data.completed.includes(i)) continue;
      const y = item.y + Math.sin(frame.time * 2.7 + i) * 1.5;
      splash(item.x, y, .36, frame.time);
      ellipse(item.x, y, 9, 4.8, '#d96a2a');
      rect(item.x + 1, y - 4, 4, 7, '#e5e5cc');
      line([[item.x - 6, y - 3], [item.x, y - 4]], 1, '#ffd288');
    }
    ctx.restore();
    mapBoat(boat.angle, frame.time, Math.hypot(frame.moving.x, frame.moving.y) > .11, frame.data.gear.boat);
  }
  function silhouette(x, y, face, moving, options = {}) {
    const { time = 0, crouch = false, pose = '', range = false, gear = false } = options;
    const source = frames.sailor?.[0];
    if (!source) return;
    const [sx, sy, sw, sh] = source;
    const height = 74;
    const width = height * sw / sh;
    const stride = moving && !pose ? Math.sin(time * 17) : 0;
    const bounce = moving ? Math.abs(stride) * 2 : Math.sin(time * 2.7) * .6;
    const torso = Math.floor(sh * .64);
    const legHeight = height * (sh - torso) / sh;
    ctx.save();
    ctx.translate(Math.round(x), Math.round(y));
    ctx.scale(face, crouch ? .78 : 1);
    ellipse(0, 1, 14, 2, '#06121e45');
    ctx.rotate(moving ? .045 : 0);
    const left = -width * .5;
    const split = Math.floor(sw * .51);
    const leftWidth = width * split / sw;
    if (Math.abs(stride) > .03) {
      crop('sailor', [sx, sy + torso, split, sh - torso], [left - stride * 3, -legHeight - Math.max(0, stride) * 2, leftWidth + 1, legHeight]);
      crop('sailor', [sx + split, sy + torso, sw - split, sh - torso], [left + leftWidth + stride * 3, -legHeight - Math.max(0, -stride) * 2, width - leftWidth, legHeight]);
    } else {
      crop('sailor', [sx, sy + torso, sw, sh - torso], [left, -legHeight, width, legHeight]);
    }
    crop('sailor', [sx, sy, sw, torso], [left, -height - bounce, width, height - legHeight + bounce + 1]);
    if (gear || range || pose === 'fish' || pose === 'crane') {
      line([[7, -40], [12, -30], [18, -34]], 5, '#385675');
      rect(16, -36, 5, 4, '#d49d6d');
    }
    if (gear) {
      rect(16, -32, 8, 10, '#995629');
      rect(17, -29, 6, 6, '#ffcd70');
    }
    if (range) {
      rect(19, -38, 11, 4, '#5f6f7b');
      rect(20, -34, 3, 5, '#272a31');
    }
    ctx.restore();
  }
  function animalArt(animal, x, y) {
    const [index, width, height] = fauna[animal.name];
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(animal.face, 1);
    if (animal.state === 'dead') {
      ctx.translate(0, -height * .21);
      ctx.rotate(animal.spin * .46);
    }
    sprite('wildlife', index, -width / 2, -height, width, height);
    for (const [mx, my] of animal.marks) rect(mx, my, 2, 2, '#782e33');
    ctx.restore();
  }
  function landscape(frame, cave) {
    const { camera, data, player, time } = frame;
    const x = camera.x;
    gradient(0, H, cave ? '#142934' : '#436c74', cave ? '#0d1820' : '#22352d');
    const artwork = cave ? 'cave' : ['pine', 'slate', 'sedge', 'wild'][frame.dock] || 'wild';
    if (cave) sceneImage(artwork, -x, 0, LEVEL_WIDTH.cave, H);
    else if (frame.dock === 0) sceneImage(artwork, -x, -169, LEVEL_WIDTH.pine, 738);
    else sceneImage(artwork, -x, -66, LEVEL_WIDTH.wild, 600);
    if (cave) {
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
      if (frame.dock === 0) for (const [index, [wx]] of frame.townDoors.entries()) {
        if (wx - x > -50 && wx - x < W + 50) {
          const height = 69;
          const source = frames.merchants?.[index];
          if (source) {
            const width = height * source[2] / source[3];
            sprite('merchants', index, wx - x + 24, frame.floor('land', wx) - height, width, height);
          }
        }
      }
      if (frame.dock === 0) {
        const rock = PINE_ROCK_X - x, y1 = frame.floor('land', PINE_ROCK_X);
        sprite('wildlife', 5, rock - 24, y1 - 30, 49, 34);
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
    const fallback = finds.chest;
    const [index, width, height] = finds[item.kind] || fallback;
    ctx.save();
    ctx.translate(x, y + 27 * scale - height * scale / 2);
    ctx.rotate(item.angle || 0);
    ctx.scale(scale, scale);
    sprite('salvage', item.name === 'Sealed Strongbox' ? 5 : index, -width / 2, -height / 2, width, height);
    if (item.damage > 5) line([[-3, -4], [-7, 0], [-5, 7], [-10, 16]], 1.4, '#513231');
    ctx.restore();
  }
  function ocean(time, cameraX) {
    gradient(0, H, '#79a6bf', '#153c5a');
    sceneImage('surface', -35 - cameraX * .25 + Math.sin(time * .45) * 7, -3, W + 70, H + 6);
    for (const [x, y, size, phase] of flecks) {
      if (y < 265 || Math.sin(time + phase) < .25) continue;
      const fx = (x + time * 9) % W;
      line([[fx, y], [fx + size, y - 1]], 1, '#c4e6e46a');
    }
  }
  function vessel(frame) {
    const { camera, anchor, data, player, time, fishing } = frame;
    ocean(time, camera.x);
    ctx.save();
    ctx.translate(-camera.x, 0);
    const deckY = DECK.floor;
    const bob = Math.sin(time * 1.73) * 1.7;
    ctx.translate(0, bob);
    const offset = (anchor?.trimBase || 0) * .08;
    const hullWidth = DECK.bow - DECK.stern + (data.gear.boat - 1) * 20;
    sprite('hull', 0, DECK.stern + offset, deckY - 176, hullWidth, 232);
    const bow = DECK.stern + hullWidth + offset;
    chain([[bow - 8, 314], [bow + 72, 425]], 3.1);
    const boom = anchor?.boom ?? .16;
    const angle = anchor?.angle ?? .26;
    const craneX = 531 + offset;
    const pivotY = 282;
    const reach = 78 + boom * 148;
    const rise = 13 + angle * 70;
    const endX = craneX - reach;
    const endY = pivotY - rise;
    const length = Math.hypot(reach, rise);
    sprite('crane', 0, craneX - 47, 273, 72, 67);
    ctx.save();
    ctx.translate(craneX, pivotY);
    ctx.rotate(Math.atan2(rise, reach));
    sprite('crane', 2, -length - 3, -8, length - 41, 16);
    sprite('crane', 1, -77, -12, 83, 23);
    ctx.restore();
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
    if (fishing) fishingVisual(frame, visibleX + offset, deckY, -1);
    else silhouette(visibleX + offset, deckY - Math.max(0, deckY - player.y), player.face, Math.abs(player.vx) > 12, { time, crouch: player.crouch, pose: anchor?.mode ? 'crane' : '' });
    ctx.restore();
  }
  function fishingVisual(frame, x, y, face) {
    const { fishing, time } = frame;
    silhouette(x, y, face, false, { time, pose: 'fish' });
    const hand = [x + face * 18, y - 34];
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
    sceneImage('lake');
    fishingVisual(frame, 235, 309, 1);
  }
  function diverSprite(frame, x, y) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(frame.player.face, 1);
    ctx.rotate(clamp(frame.player.vy * .0014, -.35, .35));
    const flutter = Math.sin(frame.time * 7) * (Math.abs(frame.player.vy) > 10 ? 2 : .5);
    const bounds = frames.swimmer?.[0];
    if (bounds) {
      const width = 116;
      const height = width * bounds[3] / bounds[2];
      sprite('swimmer', 0, -76, -height * .52 + flutter, width, height);
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
    if (horizon >= -12) line([[0, horizon + 4], [W, horizon + 4]], 2, '#91d1d6');
    const known = data.explored[anchor.surveyKey] || [];
    if (seabedY < H + 195) {
      const alpha = [0, .95, .64, .32][tier];
      ctx.save();
      ctx.globalAlpha = alpha;
      sceneImage('seabed', 0, seabedY - 372, W, 490);
      ctx.restore();
      fogCtx.clearRect(0, 0, W, H);
      const fogStart = seabedY - 260;
      const haze = fogCtx.createLinearGradient(0, fogStart, 0, fogStart + 114);
      haze.addColorStop(0, tier === 3 ? '#0b1b2a00' : '#14506d00');
      haze.addColorStop(1, tier === 3 ? '#0b1b2a' : '#14506d');
      fogCtx.fillStyle = haze;
      fogCtx.fillRect(0, Math.max(0, fogStart), W, H);
      fogCtx.globalCompositeOperation = 'destination-out';
      for (const x of known) {
        const g = fogCtx.createRadialGradient(x, seabedY - 64, 82, x, seabedY - 64, 177);
        g.addColorStop(0, '#000');
        g.addColorStop(.74, '#000');
        g.addColorStop(1, '#0000');
        fogCtx.fillStyle = g;
        fogCtx.fillRect(x - 177, Math.max(0, fogStart), 354, H);
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
      const x = drop.wx - frame.camera.x;
      const y = (scene === 'land' ? frame.floor(scene, drop.wx) : drop.wy || 330) - frame.camera.y;
      rect(x - 4, y - 6, 12, 7, '#d8a663');
      rect(x - 1, y - 8, 5, 3, '#ffe1ad');
    }
  };
}
