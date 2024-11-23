# Falcon

## Implementation-wide parameters

`SIGNATURE_LENGTH` - length of the signature in bytes. See table 3.3 in the specification. Often called `slen` in the algorithms in the specification.

- Recommended value for Falcon-512: 666 bytes
- Recommended value for Falcon-1024: 1280 bytes

`SIGNATURE_LENGTH_WIDTH` - number of bits required to represent the signature length. `ceil(log2(SIGNATURE_LENGTH))`