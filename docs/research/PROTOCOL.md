# BudsBar protocol notes

Everything here was established by black-box observation of a locally owned
**HUAWEI FreeBuds 6** (model `BTFT0020`, firmware `HarmonyOS 6.1.0.358`) plus
cross-checking against published interoperability documentation. No vendor
source code, assets or animation files were used.

## Transport

The earbuds advertise a classic Bluetooth **Serial Port Profile** service.

```
Service class : 0x1101 (Serial Port)
RFCOMM channel: 1
UUID          : 00001101-0000-1000-8000-00805f9b34fb
```

The SDP record set also contains a vendor "Private COM" service
(`0000fd9a-…`, RFCOMM channel 2) and A2DP/AVRCP/HFP records, but the control
protocol lives on the standard SPP channel.

macOS exposes this through `IOBluetooth`:
`IOBluetoothSDPServiceRecord.getRFCOMMChannelID` → `openRFCOMMChannelAsync`.

> **Run-loop requirement.** `IOBluetoothRFCOMMChannel` delivers its delegate
> callbacks on the **main thread's NSRunLoop**. A tool that blocks the main
> thread (for example with `Thread.sleep` in a command-line probe) receives
> nothing at all — the channel opens and writes succeed, but no data ever
> arrives. Drive the run loop instead, or use a real application run loop.

## Frame format

```
offset  size  field
0       1     0x5A            magic
1       2     length          big-endian; = command body length + 1
3       1     0x00            reserved
4       2     command         big-endian
6       n     TLV fields      tag(1) length(1) value(length)
…       2     CRC-16/XMODEM   big-endian; covers bytes 0 … end-of-body
```

Total frame length is `length + 5`.

**CRC-16/XMODEM**: polynomial `0x1021`, initial value `0x0000`, no reflection,
no final XOR. Check value for `"123456789"` is `0x31C3`.

### TLV fields

Fields are keyed by a one-byte tag. A tag may appear at most once per frame.

| Tag | Meaning |
|-----|---------|
| 1 | left earbud / primary value / mode |
| 2 | right earbud / secondary value / strength |
| 3 | list of supported options |
| 4 | in-call value |
| 5 | status |
| 6 | charging flags |
| 15 | model code |
| 127 | error marker (value `00 01 86 a3` = unsupported command) |

### Worked example

ANC status query:

```
5a 00 07 00 2b 2a 01 00 02 00 1d 33
│  │     │  │     │  │     └── CRC-16/XMODEM
│  │     │  │     │  └── tags 1 and 2, both empty
│  │     │  │     └── command 0x2b2a
│  │     │  └── reserved
│  │     └── length 7
│  └── magic
└── length
```

## Observed commands

Read commands answer on the same command id. Write commands answer on the
write command id and are followed by the device pushing current state.

| Feature | Read | Write | Value location |
|---|---|---|---|
| Device info | `0x0107` | — | 3 = build id (unstable), 7 = firmware, 9 = serial, 10 = product id, 15 = model code, 24 = per-side serials |
| Battery | `0x0108` | — | 2 = `[left, right, case]`, 6 = charging flags |
| Battery push | `0x0127` | — | same layout as `0x0108` |
| Noise mode | `0x2B2A` | `0x2B04` | read: 1 = `[status, mode]`; write: 1 = `[mode, strength]` |
| Equalizer | `0x2B4A` | `0x2B49` | read: 2 = current preset, 3 = available ids; write: 1 = preset id |
| Double tap | `0x0120` | `0x011F` | 1 = left action, 2 = right action, 3 = available actions |
| Triple tap | `0x0126` | `0x0125` | same layout |
| Hold | `0x2B17` | `0x2B16` | same layout |
| Noise cycle | `0x2B19` | `0x2B18` | 1 = left, 2 = right |
| Swipe | `0x2B1F` | `0x2B1E` | 1 = left, 2 = right |
| Auto pause | `0x2B11` | `0x2B10` | 1 = enabled |
| Dual connect | `0x2B2F` | `0x2B2E` | 1 = enabled |
| Low latency | `0x2B6C` | `0x2B6C` | read: 2 = value; write: 1 = value |
| Sound quality | `0x2BA3` | `0x2BA2` | read: 2 = value; write: 1 = value |
| Capabilities | `0x2BAC` | — | 1…9 feature flags |

### Asymmetries worth remembering

- **Noise mode**: the write payload is `[mode, strength]` but the read
  response is `[status, mode]`. Strength `0xFF` in a write means "keep the
  current strength"; turning noise control off sends strength `0x00`.
- **Noise mode, first read field**: the value is the *effect the firmware
  reports*, not the cancellation strength — `1` with noise control off, `2`
  with transparency, `3` with noise cancelling. The device never reports how
  strong the cancellation is, so the strength cannot be read back.
- **Noise mode, strength byte**: on the FreeBuds 6 the firmware accepts the
  strength byte but does not apply it. Writing `[1, 1]`, `[1, 2]`, `[1, 0]`,
  `[0xFF, n]`, the strength in a second field, or the strength on its own —
  all leave the reported effect at `3`. The mode in the same payload *is*
  applied. No other command was found that carries a cancellation strength,
  and the device does not advertise its noise-control options, so the set of
  modes and levels a model offers is a property of the model, not something
  the app can ask the device about.
- **Gestures**: the write stores the action code in the field that selects the
  earbud — tag 1 for left, tag 2 for right — not in a separate "action" field.
- **Gesture action codes** are model specific. The FreeBuds 6 reports fifteen
  hold actions (`[0,1,2,3,4,5,6,7,8,9,10,14,15,17,255]`) and is currently on
  action `3`; the codes that are known from other models (`18` volume up,
  `19` volume down) do not even appear in that list. The device publishes the
  codes but not their meaning, so the panel shows the raw number for the
  actions it cannot name.
- **Equalizer**: selecting a built-in preset writes a single field (tag 1)
  holding the preset id. Editing the curve of a custom preset uses a longer
  multi-field payload and is not implemented here.
- **Low latency and sound quality** share one command id for read and write,
  but the value lives in field 2 on read and field 1 on write.

## Observed values on FreeBuds 6

| Item | Value |
|---|---|
| Model code | `BTFT0020` |
| Build id (field 3) | `HL1H6MR_Ver.A` — rotates, see below |
| Firmware | `HarmonyOS 6.1.0.358(F003H003C90)` |
| Product id | `BTFT0020-000155` |
| Equalizer presets | 0, 2, 3, 9, 11, 12 (0 = flat, 2 = bass, 3 = treble, 9 = voices) |
| Tap actions | 1 play/pause, 2 next, 7 previous, 0 assistant, 255 none |
| Hold actions | 10 switch noise mode, 18 volume up, 19 volume down, 0 assistant, 255 none |

### Field 3 is not a product name

Device-info field 3 looks like a product name but is not stable: repeated
reads of the same powered-on device returned `HL1H6MR_Ver.A` and later
`HR1H6MR_Ver.A`. It is a **build id** that rotates. The UI therefore never
shows it as a title — the friendly name is derived from the model code
(field 15), which is stable. See `DeviceIdentity.displayName`.

## Volume

The earbuds do **not** expose a volume command over the control channel — a
sweep of the surrounding command range returned only the "unsupported command"
error marker. The in-ear volume is the volume macOS sends to the Bluetooth
audio sink, so BudsBar drives the CoreAudio output device that matches the
earbuds (`kAudioDevicePropertyVolumeScalar`).

The device-side "sound quality preference" (`0x2BA3`) is a separate setting
that steers the codec preference between connectivity and quality.

## The codec is not a device feature

The earbuds never report their codec over the control channel. A sweep of the
surrounding command range (all `0x01xx` and `0x2Bxx` commands, about forty of
them answered) turned up no codec value, and CoreAudio does not expose one
either: scanning every property selector of the audio device (456 976
requests) found only the internal list identifiers.

The negotiation happens between macOS and the Bluetooth controller, and the
result is written into the system log:

```
… Bluetoothd: GetControllerInfo: … BtRt 192 Kbps, Codc AAC-LC, … DvNm 'HUAWEI FreeBuds 6' …
```

On Android the same choice is exposed as a system setting
(`android.bluetooth.BluetoothCodecConfig`, `SOURCE_CODEC_TYPE_L2HC`), which
is why the vendor app can offer a codec picker. macOS has no equivalent, so
on this platform the codec can be **shown but not changed**. See
`Sources/BudsCore/AudioCodec.swift`.

## Not implemented

- Custom equalizer curves (the multi-field `0x2B49` payload)
- Firmware updates
- Multipoint / device switching
- The "Private COM" RFCOMM channel (channel 2), which exposes the paired
  device list and is not needed for the controls above
