#!/usr/bin/env python3
"""Emit SHA-256 known-answer vectors for tb/tb_sha256.sv.

Two files are written, both golden:
  sha256_vectors.txt  human-readable  "<msg_hex|-> <len_bytes> <digest>"
  sha256_blocks.txt   simulator-friendly: for each message, a line
      "<nblk> <expected_64hex>"  followed by <nblk> lines of 128 hex digits,
      each a fully FIPS-180-4-padded 512-bit block.
Padding is mechanical and done here so the RTL core is the only thing the bench
exercises; the digest column is the golden answer. hashlib is the reference,
and the two FIPS 180-2 published constants (empty, "abc") are asserted against
their standard values so the generator is itself checked against the standard.
Drop a real CAVP SHA256ShortMsg.rsp / SHA256LongMsg.rsp here to append it.
"""
import hashlib, os, random, re

HERE = os.path.dirname(os.path.abspath(__file__))
FIPS = {
    "":    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "abc": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
}

def pad(msg: bytes) -> bytes:
    nbits = len(msg) * 8
    p = msg + b"\x80"
    while len(p) % 64 != 56:
        p += b"\x00"
    p += nbits.to_bytes(8, "big")
    return p

def main():
    msgs = []
    for s, want in FIPS.items():
        b = s.encode()
        assert hashlib.sha256(b).hexdigest() == want, "reference disagrees with FIPS"
        msgs.append(b)
    for n in (1, 55, 56, 57, 63, 64, 65, 119, 120, 128):
        msgs.append(bytes((i * 37 + 11) & 0xff for i in range(n)))
    rng = random.Random(0xC0FFEE)
    for n in (3, 20, 100, 200, 300):
        msgs.append(bytes(rng.randrange(256) for _ in range(n)))
    for name in ("SHA256ShortMsg.rsp", "SHA256LongMsg.rsp"):
        p = os.path.join(HERE, name)
        if not os.path.exists(p):
            continue
        cur = None
        for ln in open(p):
            m = re.match(r"Msg\s*=\s*([0-9a-fA-F]*)", ln)
            if m:
                cur = b"" if m.group(1) in ("", "00") else bytes.fromhex(m.group(1))
            if re.match(r"MD\s*=", ln) and cur is not None:
                msgs.append(cur); cur = None

    vec, blk = [], []
    for m in msgs:
        md = hashlib.sha256(m).hexdigest()
        vec.append(f"{m.hex() or '-'} {len(m)} {md}")
        padded = pad(m)
        nblk = len(padded) // 64
        blk.append(f"{nblk} {md}")
        for i in range(nblk):
            blk.append(padded[i*64:(i+1)*64].hex())
    with open(os.path.join(HERE, "sha256_vectors.txt"), "w") as f:
        f.write("# msg_hex(- empty)  len_bytes  expected_sha256\n" + "\n".join(vec) + "\n")
    with open(os.path.join(HERE, "sha256_blocks.txt"), "w") as f:
        f.write("\n".join(blk) + "\n")
    # measured-boot chain: pcr0=0, pcr_{n+1}=SHA256(pcr_n||stage_n)
    stages=[bytes([b]*32) for b in (0x11,0x22,0x33)]
    pcr=bytes(32); mc=[]
    for st in stages:
        pcr=hashlib.sha256(pcr+st).digest()
        mc.append(f"{st.hex()} {pcr.hex()}")
    with open(os.path.join(HERE,"measure_chain.txt"),"w") as f:
        f.write("\n".join(mc)+"\n")
    print(f"wrote {len(msgs)} messages ({sum(1 for l in blk if len(l.split())==2)} vectors)")

if __name__ == "__main__":
    main()
