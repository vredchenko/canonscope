# Power

Two stages: a working battery to prove the camera lives, then a mains-fed dummy
battery for the permanent rig.

## 1. Replacement battery (the quick fix)

**Buy:** DuraPro 2x NB-5L + LCD USB-C charger, ~£15.99, sold by DuraPro,
dispatched by Amazon — <https://www.amazon.co.uk/dp/B07T7TTPXQ>

- Names the SX200 IS explicitly. Cells 1400 mAh 3.7 V. Charger takes 5 V in,
  outputs 4.2 V / 0.6 A.
- 4.2 stars over ~250 reviews, including a UK SX200 IS owner who had lost the
  original charger and reports it works. No reports of the camera refusing the
  battery.
- Expect less runtime than the original Canon cell.

**Avoid:** XintecUK 2-pack (`B07YDJRFW2`). A reviewer reports the cells are
undersized for the SX200 and the camera cuts out. Micro-USB charger.

**No off-the-shelf NB-5L USB dummy battery is listed on Amazon UK.** The only
ACK-DC30 kits (BTBAI, £26-30) don't name the SX200, have no reviews, and ship
from China. Try eBay or AliExpress for `NB-5L USB dummy battery` or `DR-30 USB`,
or build one.

*Researched. Prices and listings were current when the notes were written and
should be re-checked before ordering.*

## 2. DIY dummy battery

About £3 in parts plus a scrap USB cable.

The NB-5L is a **single Li-ion cell: 3.7 V nominal, 4.2 V fully charged.**

### Electrical

- **Adjustable buck converter** (e.g. an MP1584 board) set to **4.0 V**,
  measured with a multimeter *before* anything is connected.
  **Never feed 5 V directly. Never exceed 4.2 V.**
- **470-1000 uF capacitor** across the output, close to the camera. The lens and
  flash draw 1.5-2 A bursts; without the reservoir the sag reads to the camera
  as a flat battery.
- **Supply:** any 5 V phone charger rated 2 A or more. USB-C PD chargers are
  fine — they fall back to plain 5 V without negotiation.

### The three contacts

The middle contact is **not** a dummy. Canon uses it as a temperature-sensor
input, and **an open circuit there is the usual reason a dummy battery gets
rejected.** Measure middle-to-minus on a real NB-5L (expect roughly 10k) and fit
that value as a fixed resistor. Check the polarity markings on the real battery
before wiring plus and minus.

> **Trade-off to decide before potting the dummy.** On this camera that middle
> terminal is also a CHDK remote input. `platform_camera.h` carries
> `CAM_REMOTE_AtoD_CHANNEL 5`, commented *"Camera supports using 3rd battery
> terminal as well as USB for remote - value = A/D channel to poll"*. A fixed
> 10k resistor keeps the firmware happy but gives up a free hardware trigger
> input. If you might want it, bring that contact out to a header rather than
> soldering the resistor permanently.
>
> *Verified 2026-10-30 against `platform/sx200is/platform_camera.h`.*

### Shell

Options, roughly in order of effort:

- 3D-print one — search Thingiverse or Printables for `NB-5L dummy`.
- Cut a block of wood or plastic to size.
- Gut a dead, **fully discharged** NB-5L. **Never open a live cell.**

The battery door must still close and latch. It has a rubber flap for the
coupler cable to pass through.

## 3. Dummy-load test, before the camera goes anywhere near it

Stand a power resistor in for the camera and confirm the supply holds up.
`I = V/R`, `P = V^2/R`. At 4.0 V:

| Resistor | Current | Dissipation | Rating to use | Stands in for |
| --- | --- | --- | --- | --- |
| 10 ohm | 0.4 A | 1.6 W | 3 W+ | roughly camera idle |
| 4.7 ohm | 0.85 A | 3.4 W | 5 W+ | moderate load |
| 2 ohm | 2 A | 8 W | 10 W+ | worst-case peak, short tests only |

Use wirewound or cement resistors. Parallel smaller ones if needed — five
10 ohm 2 W parts make 2 ohm at 10 W.

Procedure:

1. **No load:** set the output to 4.0 V.
2. **10 ohm:** should still read ~4.0 V.
3. **2 ohm for 10-20 s:** a drop of up to ~0.15 V is fine. Below ~3.7 V means
   the converter or the charger can't keep up — check the input with a USB power
   meter, since a cheap cable is a common cause.
4. **Touch-test the buck board.** Warm is fine. Too hot to hold means add a
   heatsink or derate.

Then repeat steps 2-3 **at the finished dummy's contacts**, so the wiring and
the middle-pin resistor are included in the measurement.

Resistors get genuinely hot at 2 A. Put them on a ceramic tile; don't hold them.

## Powering the rig

**Do not power the camera from the Raspberry Pi's 5 V rail.** Lens and flash
current spikes will brown out the Pi. The camera gets its own supply.

**The camera cannot power itself on.** Either press the power button once by
hand and disable auto-power-off in the Canon menu, or wire a relay / optocoupler
across the power button (a servo also works). See
[04-remote-control.md](04-remote-control.md).
