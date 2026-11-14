# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Solo rider with their own smart trainer (Wahoo KICKR Core, FTMS over BLE), riding indoors with a laptop, tablet, phone, or desktop screen nearby. Mid-effort they glance at power, cadence, and speed; before and after they pick workouts, review history, and export rides.

## Product Purpose

Indoor cycling training app: connect to a trainer over BLE, show live metrics, run ERG workouts (manual target first, structured workouts next), record rides, and keep a local history. World/sim riding is a later phase. Success is a rider who can start a ride quickly and trust the numbers.

## Positioning

Open, local-first, no account: direct BLE to the trainer, rides stored and exported on the device, runs on web, Windows, macOS, and Android. Customizable: the rider arranges the dashboard tiles to suit their screen and what they watch.

## Operating Context

Flutter app (Riverpod, universal_ble). A simulated trainer allows hardware-free development. Web needs Chrome/Edge over HTTPS or localhost, and pairing needs a user click. Used on wide desktop layouts and smaller screens, often at arm's length or on a stand while exerting hard.

## Capabilities and Constraints

- Connect, live power/cadence/speed, manual ERG target
- Recording, ride history, export, rider profile, unit preferences
- Rearrangeable dashboard layout (in progress)
- Domain terms live in GLOSSARY.md (not yet written); issues in GitHub ldmichae/speedy
- Workout plans (ERG, FTP, ramps, repeats) and drawn routes on an OpenStreetMap map (a position dot, not a ride sim)
- Undecided: world sim, accounts/sync (none planned)

## Evidence on Hand

No testimonials, customers, or benchmarks exist. Do not fabricate any.

## Product Principles

- Glanceable under effort: key numbers readable at distance, mid-ride, with no hunting.
- Local-first and account-free: the rider's data stays theirs.
- The rider shapes their dashboard; defaults are good, customization is optional.
- Works the same across web, desktop, and Android without feeling foreign on any.
- Trust the trainer data: show connection and data state honestly.
