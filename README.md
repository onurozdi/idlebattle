# Soundings

Browser playtest of a 2D maritime salvage game. The game is served directly from `docs/` on GitHub Pages and uses Canvas, HTML and CSS. There is no installation or asset build step.

The camera scrolls across continuous scene paintings. The chart is composed once from the depth map, a single sea texture, island art and docks. Gameplay sprites and HTML controls are separate from that artwork.

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
