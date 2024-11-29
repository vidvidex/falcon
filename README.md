# Falcon

All reset signals are active low. They are also named `rstn`. SHAKE256 module is an exception. There the reset is active high and called `rst` or `reset`.

## Implementation-wide parameters

`SIGNATURE_LENGTH` - length of the signature in bytes. See table 3.3 in the specification. Often called `slen` in the algorithms in the specification.

- Recommended value for Falcon-512: 666 bytes
- Recommended value for Falcon-1024: 1280 bytes

`N` - number of coefficients in the polynomial. Often called `n` in the algorithms in the specification.

- Falcon-512: 512
- Falcon-1024: 1024
