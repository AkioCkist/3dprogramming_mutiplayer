# Untitled Racing Game — Technical Notes on the Multiplayer System

A kart-style racing game built in **Godot 4** using the engine's built-in high-level
multiplayer API (`ENetMultiplayerPeer`, `MultiplayerSpawner`, per-node multiplayer
authority and `@rpc` annotations). The world is a single closed `Path3D` track with
server-placed checkpoints, power-ups and hurdles; vehicles are `VehicleBody3D` racers
driven through a chasing `SpringArm3D` camera.

This document explains how the networking is modelled, how player state stays in sync,
who is allowed to change what, and how the shared game state is kept consistent. It
also records the most interesting problems hit along the way and how they were solved.

---

## A. Networking Model

**Host–client / client–server / peer-hosted.** The game has **no dedicated server
process**. One running instance acts as the *host*: it is simultaneously a network
server and a normal player. This is the classic "listen server" (peer-hosted) topology
used for LAN games and, in this project, also for singleplayer.

There is no real distinction between *singleplayer* and *hosting*:

- Both paths call `start_local_game(true)` and set `GameController.server = true`.
- `GameController` then spins up a real `ENetMultiplayerPeer` server on **port 7777**
  (`init_server`), even in singleplayer.
- The difference is only UI flow: singleplayer sets `GameController.autostart = true`
  and the race scene fires `race_ready` automatically, skipping the lobby "waiting for
  players" panel. A hosted championship keeps the lobby until the host presses
  *START GAME*.
- Clients connect with `create_client(addr, 7777)`. The host address is taken from the
  join menu, or forced to `localhost` when `local_override` is set (used to join a
  lobby hosted on the same machine).

Central coordinator:

- `GameController` (an autoload singleton, `class_name GameControllerClass`) owns the
  network peer, the connection lifecycle, and a registry of connected players
  (`players: Dictionary[int, Dictionary]` keyed by peer id).
- It also acts as a **message bus**: gameplay events (`lap_change`, `race_finished`,
  `race_wrapup`, `position_update`, …) are emitted as *signals* on the singleton so
  the scene HUD, the level logic and any future screens can subscribe without tight
  coupling. RPCs simply forward into these signals.
- Scene switches do not recreate the peer. The peer is checked with `has_peer()` and
  kept alive across `change_scene_to_packed` / `reload_current_scene` calls, so a race
  restart never tears down the connection.

Data flow is fundamentally **client-to-server for intent, server-to-clients for
facts**: clients request actions and read the world; the host validates and broadcasts.

---

## B. Player Synchronisation

Vehicle transform synchronisation relies on Godot's built-in **rigid-body network
replication**, not hand-rolled position/rotation packets:

- A `MultiplayerSpawner` watches a node subtree (`spawn_path = ../Replicated`). When
  the server adds a `TrackVehicle` (or any listed scene) under that root, the spawn is
  replicated to every connected client automatically, including the spawn transform.
- Each `RigidBody3D`/`VehicleBody3D` has a **single authority** that runs its physics
  simulation. The engine replicates that authority's transform to all other peers at
  the configured network tick. Position, orientation, velocity and angular velocity
  are therefore shared with no custom wire code.
- **Ordering / race positions** are not derived from raw transforms. The server runs a
  sort every physics frame in `update_positions()` comparing each vehicle's
  `(lap_count * checkpoint_size) + checkpoint_last`, then sends the resulting rank to
  each owner via `client_notify_position` (marked `unreliable_ordered` — latest
  position beats delivery guarantees).
- **Discrete actions** (things you cannot infer from a moving transform) are sent as
  RPCs, all `reliable` so no action is lost:
  - `remote_allow_input` — the server grants/revokes a driver's controls (countdown start, race end, drift).
  - `remote_restore_vehicle`, `remote_center_impulse`, `remote_drift` — the server asks a vehicle's *owner* to teleport back to a checkpoint, take an impulse, or skid.
  - `remote_remove` — take a vehicle off the track between intermissions.
  - `server_spawn_hurdle` — a driver asks the server to spawn the hurdle they picked up.
- Each vehicle runs `fix_camera()` on every tick, but only the **authority** peer lets
  the camera chase and applies speed-reactive FOV (`lerpf` on `reference_fov..+20`).
  Non-authority copies merely stabilise and do not fight the replicated pose.

Synchronising who-got-what on the UI (lap text, power-up icon, "PLACED #N" message)
goes through the relayed signals in section A, so HUD updates never touch the wire
directly.

---

## C. Network Ownership / Authority

**Every player owns exactly one vehicle; the host owns everything else.**

- When the server starts the race (`setup_race`) it instantiates one `TrackVehicle`
  per registered player, names it with that peer's id (`veh.name = str(k_id)`) and
  immediately hands over authority:
  `vehicle_spawned()` → `node.set_multiplayer_authority(node.name.to_int())`.
- Only the owner peer may steer: input is read inside
  `if is_multiplayer_authority():` in `_physics_process`, and only once
  `input_allowed` is true. The chasing camera is likewise authority-gated
  (`fix_camera`, `_post_ready`).
- The **host is authority over all game/world state**:
  - Checkpoint `Area3D`s exist **only server-side** (`place_checkpoints`); clients never
    hold or simulate them.
  - Lap counters, last checkpoint, and carried power-up id are declared
    "managed by SERVER ONLY".
  - Trip/fall-over arbitration runs under `if multiplayer.is_server():`. The server
    decides a car has crashed, then must *ask the car's owner to fix itself* —
    `remote_restore_vehicle.rpc_id(name.to_int(), ...)` — because the server does not
    have authority over another peer's body and cannot legally move it directly.
  - Race completion is decided server-side: first car(s) push into `winners`; when
    enough cars finish, the server broadcasts `race_wrapup`, and after a 20 s grace
    the whole scene is restarted for everyone.
  - Hurdles and power-ups belong to the host: pickups are spawned under the replicated
    tree by the server, and a driver fires its picked-up weapon by RPC to peer 1
    (`server_spawn_hurdle.rpc_id(1)`), where the server instantiates the hurdle.

One subtlety baked into the flow: the host must also register **itself** as a player.
`race_level` forces this with `multiplayer.peer_connected.emit(1)` after scene load so
the normal "peer connected → request connect args" handshake runs for the local player
too, giving peer id 1 a slot and a colour/username.

---

## D. Shared Game State

All authoritative state lives on the host and converges through a small handshake +
replication protocol:

1. **Player registry.** When a peer connects, the server calls
   `client_request_connect_args` on it; the peer replies via `server_send_connect_args`
   with its chosen `username` and `color`. The server records
   `players[id] = {username, color}` (keyed by the *real sender id* from
   `get_remote_sender_id()`, never the forged payload) and rebroadcasts the whole list
   with `client_send_player_list`. Clients are deliberately forbidden from overwriting
   the server's copy (`if not multiplayer.is_server():`). Colour/name therefore appear
   on every lobby slot and vehicle label consistently.
2. **Race clock / start.** The host triggers `race_ready`. Server-side this launches
   `setup_race` (vehicles spawn, and after a **4.2 s** timer each driver is granted
   input via `remote_allow_input(true)`); client-side the HUD plays the "3…2…1…GO!"
   countdown and hides the lobby. Input gating on every vehicle guarantees nobody can
   drive before the shared green light, keeping all starts identical.
3. **Progression.** Checkpoints update lap/cp counters on the server only. The server
   fans results out per-owner: `client_notify_lap_change`, `client_notify_race_finished`
   (to the winner), `client_notify_race_wrapup` and `client_notify_powerup_pickup` —
   all through the signal relays so the GUI and audio react on the right machine.
4. **End of race.** When `winners.size() >= min(3, players.size())` the server starts a
   20 s wrap-up, then broadcasts `client_restart` and reloads the scene. Because the
   network peer survives the reload (`has_peer()`), a single fresh `ENetMultiplayerPeer`
   is never re-created and replication continues across the restart.
5. **Persistence.** Player preferences (name, colour, address, max players) are dumped
   into a `GameConfig` singleton and saved to disk on shutdown, so lobby fields are
   pre-filled on the next launch.

"Points / health" as such do not exist — the game's shared state is position
progress, carried power-ups and finish order, and all of it is arbitrated and
broadcast by the host as described above.

---

## E. Problems Encountered and How They Were Solved

### 1. Duplicate vehicles after every scene reload
**Symptom.** Restarting the race spawned two copies of each car on the host, and
remote cars multiplied across clients.
**Root cause.** On each `reload_current_scene` the server re-ran its setup *and* the
client-side spawn handler also instantiated bodies, so ownership of who-spawns became
ambiguous; the freshly re-created peer then duplicated every replicated spawn.
**Fix.** Spawning is now strictly server-side and one-shot: the server connects
`race_ready → setup_race` with `CONNECT_ONE_SHOT`, adds cars only under the
replicated tree (`MultiplayerSpawner`), and guards peer creation with `has_peer()` so
the ENet peer is created exactly once and survives reloads. Clients never instantiate
vehicles themselves — they receive them through replication.

### 2. The server could not move another player's car
**Symptom.** Fall-recovery code that set a car's transform directly was silently
ignored; the tipped car stayed glued to its last checkpoint-facing pose until it fell
out of the world again.
**Root cause.** Transform writes on a physics body are only legal for that body's
authority. The host tries to "fix" a car it does not own, which the engine discards.
**Fix.** Rule made explicit: the server *detects* the crash and then *asks the owner to
perform the fix* via `remote_restore_vehicle` / `remote_center_impulse` /
`remote_drift`, all `@rpc("any_peer", "call_local", "reliable")`. Requests to flick,
nudge or drift go to the owning peer; the owner applies them locally where authority
lives.

### 3. Camera on the wrong car / wrong FOV
**Symptom.** Early versions made every client's chase camera track the first car it
saw, so on the host the camera always followed *your own* car — but on clients it
sometimes followed the host's car, or the FOV pulsed erratically at high speed.
**Root cause.** Camera logic was attached to "any replicated vehicle" instead of "the
vehicle I own".
**Fix.** Each client keeps one dedicated `CameraRig` (a `SpringArm3D`) per owned
vehicle. `fix_camera()` only chases when `is_multiplayer_authority()`, and FOV is
derived from the owner's `linear_velocity` relative to its own top speed. During
drift/roll the `correct_camera` flag stops the rig snapping back too early.

### 4. Players driving before the countdown finished
**Symptom.** Occasionally a car would lurch forward right as the scene loaded, or a
fast player could steal a lead during the "3…2…1".
**Root cause.** Input was read as soon as the vehicle spawned, before the shared start
was signalled; clients with faster load times effectively started early.
**Fix.** `input_allowed` gates all steering. The server spawns every vehicle in
`setup_race`, waits a fixed **4.2 s** timer, then grants input per driver with
`remote_allow_input(true)`. The GUI's 3-2-1-GO countdown is cosmetic and aligned to
that window; `race_finished` revokes input again so finished drivers cannot keep
driving into the wrap-up.

### 5. Connect-order races: host missing from its own lobby
**Symptom.** After starting a local/hosted game the player list sometimes showed only
remote clients, never the host — so if nobody else joined, the race could not start.
**Root cause.** The host never "connects" to itself, so the normal
`peer_connected → request connect args` path never ran for peer id 1, and
`GameController.players` stayed empty on the server.
**Fix.** After the level is ready the server emits `multiplayer.peer_connected.emit(1)`
for itself, driving the exact same handshake a remote peer would. The reply is keyed by
`get_remote_sender_id()` so it can never impersonate another peer.

### 6. Position ranking glitching at start / after a crash
**Symptom.** The "#2 / #3" ticker jittered during the first seconds and briefly showed
wrong ranks right after a car was teleported back to a checkpoint.
**Root cause.** Ranking compared raw checkpoint numbers while cars were still being
spawned (all at checkpoint 0), and the fallback teleport reset `checkpoint_last` in a
frame that still counted for ranking.
**Fix.** Ranking uses the composite score `lap_count * checkpoint_size +
checkpoint_last` so a lap is never worth less than a checkpoint, is computed every
physics frame server-side, and teleports set the checkpoint state *before* the next
rank pass. Position updates are sent `unreliable_ordered` — the freshest rank wins.

### 7. Restart desync across machines
**Symptom.** One client restarted into the next race while another was still showing
the finish banner.
**Root cause.** Each peer restarted its own scene on its own local timer, so reloads
drifted apart frame by frame.
**Fix.** Restart is orchestrated: the server waits for enough winners, keeps the
world in a 20 s wrap-up (`%FinishWrapUpText`), then broadcasts `client_restart` and
reloads. Clients reload only when told, keeping every screen on the same race.

### 8. Replicated hurdles appearing at the origin for a split second
**Symptom.** A spawned oil-spill or rocket flashed at `(0,0,0)` on remote clients
before jumping to its real spot.
**Root cause.** The node was added to the replicated tree and the *transform then*
set, so the initial replication packet carried the default transform.
**Fix.** Set the transform **before/at** adding the node under the spawner's watched
path (e.g. power-ups are positioned with `global_position = collision point` right
after `add_child(..., true)`), so the first replicated state is already correct.

---

*Note: singleplayer and "host of a championship" share the same server code path. The
only difference is that singleplayer sets `GameController.autostart` and the race scene
then auto-fires `race_ready`, bypassing the lobby — see section A.*
