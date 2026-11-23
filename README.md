# Soundings

Browser playtest of a 2D maritime salvage game. The game is served directly from `docs/` on GitHub Pages and uses Canvas, HTML and CSS. There is no installation or asset build step.

The camera scrolls across continuous scene paintings. The chart is composed once from the depth map, a single sea texture, island art and docks. Gameplay sprites and HTML controls are separate from that artwork.

## Godot shooting test

[Play the Godot test](https://onurozdi.github.io/idlebattle/character-test/). Choose Deer or Bear with 1 / 2 or the target menu. Point and click to fire, or aim with the right stick and fire with RT. Space fires toward the current aim. Move with A/D, the arrow keys, or the left stick. R/Y resets the scene. E/X casts the fishing rod and F/B tests the human ragdoll.

The source project is in `godot/` and uses Godot 4.7, GDScript, and the Compatibility renderer with no add-ons. Shots can deviate to either side of the aim. Every four hits on a live target raises Shooting by one level, up to Lv. 5, and narrows the spread. Scene reset keeps the current skill for that session.

Weapon damage values are defined at full strength within two metres. Damage then falls linearly by one fifteenth of its base value per additional metre, reaching one third at twelve metres and zero at seventeen metres.

The deer has 100 health. A close body hit deals 10 damage and reveals the health bar. A close head hit is lethal. The deer flees on a non-lethal hit or inside twelve metres. The bear charges when it sees the player within twelve metres or survives a bullet hit at any distance. Each connected swipe removes 33% of player health. Close shots deal 2 damage to the bear's body and 34 to its head. Entry marks follow the struck parts, and both animals lose their movement velocity on death and collapse under gravity at that location.

With matching export templates installed, build and test locally from the repository root:

```powershell
New-Item -ItemType Directory -Force godot/build/web
godot --headless --path godot --editor --import
godot --headless --path godot --fixed-fps 60 -- --self-test
godot --headless --path godot --export-release Web build/web/index.html
py -m http.server 8737 --bind 127.0.0.1 --directory godot/build/web
```

## Play

The red-and-white buoy east of the starting location marks a shallow salvage pickup. Pine Island's dock is west of the boat. The other three islands are farther out and can be reached by sailing.

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move or steer | WASD / arrows | Left stick / D-pad |
| Jump or pay out crane chain | Space | A |
| Interact or retrieve chain | E | X |
| Cycle nearby actions | R | RB |
| Secondary action | F | B |
| Inventory | I | Y |
| Settings | Esc | Menu |

The same actions can be operated with touch or mouse. Tap an inventory cell to preview a placement, then tap it again or select Place. Tap the pending item to rotate it. The Deck's trackpad also works for aiming and inventory.

## First recovery

1. Steer east toward the nearby buoy and choose **Start Salvage**.
2. At the crane, select **Crane Controls**. Extend left toward the stern, then hold Jump to unspool the chain. Select **Exit Crane** and move to the stern to dive.
3. Swim down. Equip the Hooker with the secondary action, touch the jar and select **Tie Rope**, then swim to the hook and select **Hook**.
4. Swim up to **Climb Aboard**. Select the crane and hold Interact to lift the load. Retract toward the deck with Right, then hold Jump briefly and press Interact to secure it.
5. Return to Pine Island and sell the recovered cargo at the Shipyard. The price reflects its damage.

The starting boat carries a casting rod, jigging rod, beginner dive gear and one rope. Prices and physics constants are playtest values. Save data lives in the current browser profile and reloads at the last chart position.

## Run locally

```powershell
py -m http.server 8736 --bind 127.0.0.1 --directory docs
```

Open `http://127.0.0.1:8736/` in a browser.
