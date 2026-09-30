<h1 align="center">XS-Trucking</h1>

<p align="center">A trucking job you build in game, for <strong>QBox</strong> and <strong>QBCore</strong>. Spots, routes, skills, businesses, co-op and illegal loads.</p>

<p align="center">
  <a href="https://github.com/XyraL/XS-Trucking/releases"><img src="https://img.shields.io/github/v/release/XyraL/XS-Trucking?style=flat-square&color=f5bb55&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/framework-QBox%20%7C%20QBCore-55dcff?style=flat-square" alt="framework">
  <img src="https://img.shields.io/badge/price-free-30d158?style=flat-square" alt="price">
  <a href="https://xyralscripts.dev/docs-xs-trucking"><img src="https://img.shields.io/badge/docs-xyralscripts.dev-a889ff?style=flat-square" alt="docs"></a>
  <a href="https://discord.gg/XRURAw4TM2"><img src="https://img.shields.io/badge/support-discord-5865F2?style=flat-square" alt="support"></a>
</p>

<p align="center">
  <a href="https://xyralscripts.dev/xs-trucking">Website</a> &nbsp;·&nbsp;
  <a href="https://xyralscripts.dev/docs-xs-trucking">Setup guide</a> &nbsp;·&nbsp;
  <a href="https://github.com/XyraL/XS-Trucking/releases">Releases</a> &nbsp;·&nbsp;
  <a href="https://discord.gg/XRURAw4TM2">Discord</a>
</p>

---

It comes with one trucking spot at the Port of Los Santos and a handful of
routes to start with. Everything else is built in game with
`/truckingbuilder`.

## What it is

**Trucking spots.** Place a laptop, truck bays, trailer bays and return bays
anywhere on the map. Every spot gets the same laptop and the same job.

**Routes.** Pickups, drop points, pay, XP, the level and certificate needed, a
timer, fragile cargo, convoys, escorts and illegal loads. The quick route
builder asks for a name, you place the drop, and it suggests the pay from the
distance.

**The laptop.** Loads are pins on a 3D map. Click one to see the load, take it,
or start a crew for it. Your run, your truck, skills, certificates, your
business and the leaderboards are all on the laptop too.

**Your truck.** Buy trucks and trailers, or use the free depot truck. Parts wear
as you drive: engine, tyres, brakes, oil and body. Repair and service them,
refuel, and fit engine, brake, gearbox, suspension and turbo upgrades, paint,
lights, tint and horns. The load always comes on its own trailer; owning one
just pays a bonus.

**Levels, skills and certificates.** 50 levels and a skill tree with five paths:
long haul, precision, heavy haul, business and smuggling. Certificates at set
levels open better loads: reefer, flatbed, car hauler, hazmat and oversize.

**Businesses.** Start one and invite drivers. Ranks with their own pay cut and
permissions, a logo from Imgur or Fivemanage, a bank, perks, business trucks
and fleet runs. Businesses level up from reputation earned on every load.

**Co-op.** Crews form at the laptop.

- **Convoys** — several trucks on one route, with a bonus for every truck that
  delivers close together.
- **Escorts** — a pilot car, paid for staying close to the trucks.
- **Co-drivers** — ride in the cab for a cut of the load.

**Illegal loads.** Someone might call it in, and heat builds with every run.

**Armed guards.** Set on an illegal route in the builder: how many guards,
their weapons, armour and aim. They show up around the trailer when someone
gets close and shoot anyone who comes near. Hit it solo or bring gunners.
Shots bring the police.

**The admin panel.** `/truckingadmin` shows every run live on a map, every
player's level, XP, certificates and heat, every business and its logo, the
fleet, live settings and the logs.

## Requirements

- `qbx_core` or `qb-core`
- `ox_lib`
- `oxmysql`
- `ox_target` or `qb-target`

Everything else is found on its own:

| What | Works with |
| ---- | ---------- |
| Vehicle keys | qbx_vehiclekeys, qb-vehiclekeys, qs-vehiclekeys, wasabi_carlock, Renewed-Vehiclekeys, mk_vehiclekeys, cd_garage, okokGarage, t1ger_keys, vehicles_keys, or your own event |
| Fuel | ox_fuel, LegacyFuel, cdn-fuel, ps-fuel, lj-fuel |
| Police alerts | XS-Dispatch, ps-dispatch, qs-dispatch, cd_dispatch, core_dispatch, rcore_dispatch, linden_outlawalert — or a blip for police |
| Paying illegal loads as an item | ox_inventory, qb-inventory, qs-inventory, ps-inventory |

## Setup

### 1. Install it

Put `XS-Trucking` in your resources and add it to your server.cfg after its
requirements:

```
ensure ox_lib
ensure oxmysql
ensure XS-Trucking
```

The database sets itself up the first time it starts, along with the Port of
Los Santos spot and its routes.

### 2. Give yourself admin

Any one of these works:

```
add_ace group.admin xs.trucking allow
```

or a framework group listed in `Config.Admin.groups` (`god` and `admin` by
default), or your license in `Config.Admin.licenses`.

### 3. Build

Run `/truckingbuilder` in game to move the default spot, add new ones and
make routes.

## Commands

| Command | Who | What |
| ------- | --- | ---- |
| `/truckingbuilder` | Admins | Opens the builder for spots and routes |
| `/truckingadmin` | Admins | Opens the admin panel |

## Updating from 2.x

Replace the whole folder, including `config.lua` — it is new. Levels, trucks,
trailers and companies carry over. Old Cipher-Trucking progress is brought over
too, the first time it starts.

## Your own keys resource

Set `Config.Bridges.keys = 'custom'` and `Config.CustomKeysEvent` to a server
event of yours. It gets `source, plate, netId` for every truck handed over.

## Support

- **Found a bug?** [Open an issue](https://github.com/XyraL/XS-Trucking/issues)
- **Need setup help?** [Join the Discord](https://discord.gg/XRURAw4TM2)

## License

Free to use on your own servers. No redistribution or resale. See `LICENSE`.
