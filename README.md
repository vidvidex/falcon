# Falcon

This implementation supports N = 8 for development and debugging purposes and N = 512 and N = 1024 for actual use.

All reset signals are active high, except in shake256, where they are active low in some cases. TODO: fix this inconsistency.

Coefficients are 15 bits `[14:0]`

Folder `scripts` contains the various scripts used during implementation

## Implementation-wide parameters

`SIGNATURE_LENGTH` - length of the signature in bytes. See table 3.3 in the specification. Often called `slen` or `sbytelen` in the algorithms in the specification.

- "Recommended" value for Falcon-8: 52 bytes
- Recommended value for Falcon-512: 666 bytes
- Recommended value for Falcon-1024: 1280 bytes

`N` - number of coefficients in the polynomial. Often called `n` in the algorithms in the specification.

- Falcon-512: 512
- Falcon-1024: 1024

