const DISTANCE_BETWEEN_SAMPLES = 4;
const FOAM_LIFE = .76;
const FOAM_COLORS = ['#f4ffed', '#c0e6df', '#83c6cd'];
const FOAM_PATCHES = [
  [[-4, 0, 3, 1], [-2, -1, 6, 2], [3, 1, 3, 1], [-6, 1, 2, 1]],
  [[-5, 1, 2, 1], [-3, 0, 7, 1], [-1, -1, 3, 1], [3, 1, 2, 1]],
  [[-4, -1, 3, 1], [-2, 0, 6, 2], [4, 0, 2, 1], [-5, 1, 2, 1]],
  [[-3, -1, 4, 1], [-5, 0, 7, 1], [2, 1, 3, 1], [5, 0, 2, 1]],
];

export function createWake() {
  const samples = [];
  let last = null;
  let remainder = 0;
  let serial = 0;

  function reset() {
    samples.length = 0;
    last = null;
    remainder = 0;
  }

  function update(boat, time, stern) {
    while (samples.length && time - samples[0].time > FOAM_LIFE) samples.shift();
    const current = { x: boat.x, y: boat.y, time, stern };
    if (!last) {
      last = current;
      return;
    }
    const dx = boat.x - last.x;
    const dy = boat.y - last.y;
    const distance = Math.hypot(dx, dy);
    if (distance > 75 || time - last.time > .25) {
      reset();
      last = current;
      return;
    }
    if (distance > .12) {
      const vx = dx / distance;
      const vy = dy / distance;
      const facing = vx * Math.cos(boat.angle) + vy * Math.sin(boat.angle);
      if (facing > .48) {
        for (let p = DISTANCE_BETWEEN_SAMPLES - remainder; p <= distance; p += DISTANCE_BETWEEN_SAMPLES) {
          const t = p / distance;
          samples.push({
            x: last.stern.x + (stern.x - last.stern.x) * t,
            y: last.stern.y + (stern.y - last.stern.y) * t,
            time: last.time + (time - last.time) * t,
            serial: serial++,
            vx,
            vy,
          });
        }
        remainder = (remainder + distance) % DISTANCE_BETWEEN_SAMPLES;
      } else {
        remainder = 0;
      }
    }
    last = current;
  }

  function draw(ctx, time, left, top) {
    ctx.save();
    for (const sample of samples) {
      const age = (time - sample.time) / FOAM_LIFE;
      const fade = (1 - age) ** 1.8;
      const noise = ((sample.serial * 17) % 19) / 18;
      const drift = Math.sin(sample.serial * 2.1) * (1.4 + age * 2.6);
      const x = sample.x - left - sample.vy * drift;
      const y = sample.y - top + sample.vx * drift;
      const halfWidth = 4 + age * 9;
      ctx.save();
      ctx.translate(Math.round(x), Math.round(y));
      ctx.transform(sample.vx, sample.vy, -sample.vy, sample.vx, 0, 0);

      ctx.globalAlpha = .19 * fade;
      ctx.fillStyle = '#74c4cd';
      ctx.beginPath();
      ctx.ellipse(0, 0, 9, halfWidth, 0, 0, Math.PI * 2);
      ctx.fill();

      const side = sample.serial % 2 === 0 ? -1 : 1;
      const scattered = side * halfWidth * (.43 + noise * .42);
      ctx.globalAlpha = fade * (.49 + noise * .32);
      ctx.fillStyle = FOAM_COLORS[sample.serial % FOAM_COLORS.length];
      const patch = FOAM_PATCHES[sample.serial % FOAM_PATCHES.length];
      for (const [px, py, width, height] of patch) ctx.fillRect(px, scattered + py, width, height);

      if (age < .47 && sample.serial % 3 !== 1) {
        ctx.globalAlpha = .34 * fade;
        ctx.fillStyle = '#f2f7d8';
        ctx.fillRect(-4, -1, 7, 2);
      }
      ctx.restore();
    }
    ctx.restore();
  }

  return { update, draw, reset };
}
