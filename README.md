# Falcon

This implementation supports N = 8 for development and debugging purposes and N = 512 and N = 1024 for actual use.

All reset signals are active high, except in shake256, where they are active low in some cases. TODO: fix this inconsistency.

Coefficients are 15 bits `[14:0]` in signed decimal representation

Folder `scripts` contains the various scripts used during implementation

## Implementation-wide parameters

`SBYTELEN` - length of the signature in bytes. See table 3.3 in the specification.

- Falcon-8: 52 bytes
- Falcon-512: 666 bytes
- Falcon-1024: 1280 bytes

`N` - number of coefficients in the polynomial. Often called `n` in the algorithms in the specification.

- Falcon-8: 8
- Falcon-512: 512
- Falcon-1024: 1024

# TODO:

verify module: it seems like the high resource usage is due to strange access patterns of the "polynomial" array.
For example mod_mult in verify is using very little resources while mod_mult in ntt_negative is using a lot, probably due to strange access patterns in ntt_negative. 
Try using an explicit BRAM module inside ntt_negative, which should make the accesses simpler to understand to Vivado.
In each clock cycle we're doing 2 reads and 2 writes (I think) so it would make sense to use 2 banks of dual port BRAM and exchange them: in one stage of NTT we read from bank A and write to bank B, in the next stage we read from bank B and write to bank A.
The BRAM approach could be used elsewhere as well: in hash_to_point we could write the results into BRAM, then read them in verify module.
Same for decompress and everything else. If we used enough banks we could make everything work (I mean we're already using the verify_buffer1 and verify_buffer2 in a similar way so we just need to make the BRAM explicit)
