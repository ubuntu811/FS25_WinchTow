# FS25_WinchTow

The winch rope can be attached to the **attacher joints of other vehicles**, not only to trees and logs: pull a stuck tractor out, drag a trailer by its drawbar eye, move a vehicle a few metres without driving it. It works with every winch in the game (also other mods' winches): nothing in a winch's XML or model needs to change.

## Use
Stand at the winch, start the attach mode as usual, and look at an attacher joint of a vehicle (a tractor's rear or front hitch, a trailer's drawbar eye, an implement's link point): the **green ring** shows the joint, the attach key ties the rope to it. The winch's own limits apply: the vehicle's mass against `maxTreeMass` of the rope, the rope length. Single player only. `wtProbe` (console) lists the attacher joints in front of you and how far each is from your view ray, which says why a joint is or is not picked.

## How it works (read from the game's scripts, 28 Oct 2026 archive)
Vanilla only ever targets trees: in attach mode `Winch:onPostUpdate` casts the player's view ray with `CollisionFlag.TREE`, `Winch:onWinchTreeRaycastCallback` accepts shapes with `getSplitType() ~= 0` and stores the target in `spec.treeRaycast` (`lastValidTree`, `treeTargetPos`, `treeCenterPos`, `treeUp`, `treeRadius`), the target marker (the green ring, `TargetTreeMarker`) and the attach prompt are driven from that, and `attachTreeToWinch` hooks onto the tree (`ForestryHook:mountToTree`) and makes the engine's physics rope between the winch and the tree's rigid body. This mod, in the same shape:

1. **Detect:** while a rope is in attach mode and no tree is targeted, the attacher joint (`spec_attacherJoints.attacherJoints[].jointTransform`, `spec_attachable.inputAttacherJoints[].node`) nearest to the view ray, within 0.35 m, of a vehicle in *another group* than the winch's, within the rope's reach and 5 m of the player, is injected as the valid target: `lastValidTree` is the vehicle's component node (a rigid body, so `getMass` and the physics rope work on it). Vanilla then draws the ring, makes the rope green and enables the prompt. While a joint is picked the tree raycast is held back, because its callback would reset the target every frame; looking away lets go.
2. **Attach:** `ForestryHook:mountToTree` is wrapped: for one of our targets the hook is linked to the joint node (a tree would get a belt). Everything else in `attachTreeToWinch` (the physics rope, the winch's joint limits, sounds, the mass limit) is vanilla.
3. **Save:** vehicle attachments cannot be restored from a split shape id, so `Winch:saveToXMLFile` leaves them out: after a reload the rope is not attached.

## Not known until it has run in the game
The tests are offline (a fake engine, 29 checks). In the game these are untested: whether the ring shows round a joint, whether the hook looks right on the joint node (its orientation is the joint's), whether a parked vehicle moves when the rope pulls (a vehicle may hold its brakes), and how a pulled vehicle behaves. Log lines `[WinchTow] ...` say what was picked and attached.

## Files
`scripts/WinchTow.lua` (everything), `tests/winchtow_test.lua` (`lua5.1 tests/winchtow_test.lua`), `build/deploy.sh` (zip, unzip to `~/fs25/mods/FS25_WinchTow`).

## The hand winch (a hand tool, no winch vehicle needed)

You want to nudge a heavy thing 30 cm because somebody has to get past, and fetching a tractor with a winch on it is silly. So: the **Hand winch** (shop, hand tools, miscellaneous, 150) hooks onto the attacher joint you look at (the same joints the winch rope can take, within 6 m): the tool's action key hooks, the same key lets go. A hooked vehicle creeps towards YOU at up to **2 km/h** while you stand more than 1.2 m from its joint, and stops when you stand near it: walk to where you want it. 30 cm is a hook, one step back, one step forward.

How it pulls: a force on the joint's body towards you, applied at the joint (a speed controller: force = mass x acceleration, at most 3 m/s2, no more once it moves at 2 km/h), so a pulled trailer swings round on its own wheels. A vehicle nobody sits in has its brake pedal down (the first test: a 12 t trailer did not move under 22 kN, the log said so), so the hand winch lets the brake off (`vehicle:brake(0)`: it also takes the standstill auto-hold with it) while it pulls, and puts it back when you stand near it or let go, so the vehicle stops where it is. Pulling for 2 s without moving is still written to the log once, with the mass and the force (`[WinchHand]`). The rope lets go when the tool is put away, at 15 m, or when the vehicle is gone. The rope is a green debug line from your hand for now, the tool has no model yet (as the leash has none), and the shop image is the leash's, a placeholder.

Open (to try in the game): whether the brake release is enough (a vehicle attached to something, or on a slope), whether it should pull towards a fixed anchor instead of towards you, a rope model.

## The support leg

A trailer standing unhitched rests on a support leg (a landing gear: the peg under the drawbar). The game pulls it up when the trailer is attached to a tractor, by playing the trailer's support animation backwards (`Attachable:onPostAttach`), and puts it down when it is detached. A rope is no attachment, so the leg stayed down and dragged. Now a vehicle held by a winch rope, or by the hand winch, has its leg pulled up (the same animation, backwards) and put down again when the rope lets go. A vehicle that is attached to another one is left alone. Vehicles without a support animation do nothing (`[WinchTow]` says in the log when a leg moves).
