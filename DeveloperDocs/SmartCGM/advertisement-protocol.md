# Smart / LinX advertisement protocol

This document describes the manufacturer payload used by the tested MicroTech
Medical Smart / LinX sensor family. This first contribution is intentionally
limited to parsing and deduplication. It does not register a CGM, scan for a
sensor, connect to Bluetooth services, or deliver glucose to Trio.

## Evidence and privacy

The layout and checksum were verified against controlled physical-device
observations from a Smart GX-01S. Raw captures are not included because they can
contain health data and session timing. The test suite instead uses fixed,
synthetic protocol vectors.

The evidence currently applies only to the tested Smart GX-01S behavior. Other
MicroTech or white-label models and firmware revisions require separate
validation.

## Manufacturer payload

The parser accepts manufacturer data whose first 22 bytes have this layout:

| Offset | Length | Field |
| --- | ---: | --- |
| 0 | 2 | Little-endian company identifier `0x0059` |
| 2 | 2 | Little-endian session minute |
| 4 | 1 | Sensor status |
| 5 | 1 | Calibration/temperature status |
| 6 | 1 | Signed trend value |
| 7 | 2 | Current glucose word |
| 9 | 1 | Current quality |
| 10 | 2 | Previous-minute glucose word |
| 12 | 1 | Previous-minute quality |
| 13 | 2 | Two-minutes-ago glucose word |
| 15 | 1 | Two-minutes-ago quality |
| 16 | 2 | Reserved bytes |
| 18 | 4 | Little-endian checksum |

Each glucose word uses the lower 10 bits for the value and bit 15 as the
validity flag. Bytes after the first 22 are transport-specific and are ignored.

## Checksum

The checksum covers bytes 2 through 17:

1. Read the 16 bytes as four little-endian 32-bit words.
2. Add the words with wrapping 32-bit arithmetic.
3. Reduce the result modulo `0x7FA777`.
4. For each payload byte, XOR it into the high byte of the accumulator and run
   eight MSB-first CRC steps using polynomial `0x04C11DB7`.
5. Compare the resulting 32-bit value with the little-endian checksum at bytes
   18 through 21.

## Delivery boundary

Parsing a valid packet does not make it suitable for therapy. A future direct
CGM contribution must separately validate lifecycle state, data quality,
freshness, restoration, sensor ownership, and failure behavior before admitting
readings to Trio's glucose pipeline.
