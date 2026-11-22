const scenes = ['chart-water', 'islands', 'pine', 'wild', 'sedge', 'slate', 'cave', 'lake', 'seabed', 'surface'];
const sprites = ['sailor', 'swimmer', 'hull', 'boat-north', 'boat-east', 'boat-south', 'crane', 'wildlife', 'salvage', 'merchants'];
const regions = {
  'boat-north': { columns: 3, rows: 1 },
  'boat-east': { columns: 3, rows: 1 },
  'boat-south': { columns: 3, rows: 1 },
  crane: { columns: 3, rows: 1 },
  wildlife: { columns: 3, rows: 2 },
  salvage: { columns: 3, rows: 2 },
  merchants: { columns: 3, rows: 2 },
};

function spriteBounds(image, layout = { columns: 1, rows: 1 }) {
  const { naturalWidth: width, naturalHeight: height } = image;
  const surface = document.createElement('canvas');
  surface.width = width;
  surface.height = height;
  const context = surface.getContext('2d', { willReadFrequently: true });
  context.drawImage(image, 0, 0);
  const { data } = context.getImageData(0, 0, width, height);
  const bounds = [];
  const { columns, rows } = layout;
  for (let row = 0; row < rows; row++) {
    for (let column = 0; column < columns; column++) {
      const startX = Math.floor(column * width / columns);
      const endX = Math.floor((column + 1) * width / columns);
      const startY = Math.floor(row * height / rows);
      const endY = Math.floor((row + 1) * height / rows);
      let left = endX, right = startX, top = endY, bottom = startY;
      for (let y = startY; y < endY; y++) {
        for (let x = startX; x < endX; x++) {
          if (data[(y * width + x) * 4 + 3] < 105) continue;
          left = Math.min(left, x);
          right = Math.max(right, x);
          top = Math.min(top, y);
          bottom = Math.max(bottom, y);
        }
      }
      bounds.push(left <= right ? [left, top, right - left + 1, bottom - top + 1] : null);
    }
  }
  return bounds;
}

export function loadArt() {
  const images = {};
  const frames = {};
  const requests = [...scenes, ...sprites].map((name) => new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => {
      images[name] = image;
      if (sprites.includes(name)) frames[name] = spriteBounds(image, regions[name]);
      resolve(name);
    };
    image.onerror = () => reject(new Error(`Scene asset unavailable: ${name}`));
    image.src = name === 'islands' ? 'assets/islands.png' : `assets/repaint/${name}.webp`;
  }));
  return { images, frames, ready: Promise.all(requests) };
}
