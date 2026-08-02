# Project 1: Custom Base64 Encoder/Decoder in Pure x86_64 Assembly

## Technical Objective
Implements Base64 encoding and decoding entirely in x86_64 assembly — manual bit-shifting across byte boundaries and direct Linux syscall I/O, with no C runtime or standard library.

**Business Impact Summary:** Base64 shows up constantly in incident response and malware triage — encoded PowerShell commands, staged phishing payloads, and C2 traffic all lean on it because it's trivial to decode but still evades naive string-matching detection. Being able to reason about it at the byte and register level, rather than treating it as a black-box library call, means an analyst can manually recognize, decode, and verify encoded artifacts even without tooling on hand.

## The "Why": Engineering Value & Threat Impact
* **Operational Risk / Threat Model:** Attackers use Base64 specifically because standard tools decode it instantly while naive signature matching often misses it; understanding the encoding at the bit level closes that gap for manual triage.
* **Engineering Mastery:** Proves direct control over general-purpose registers, manual bitwise shifting/masking across byte boundaries, and raw Linux syscall I/O (`read`/`write`/`exit`) with zero standard-library abstraction.
* **Defensive Utility:** Serves as a known-correct reference implementation for validating detection tooling that parses Base64 — confirming edge cases like padding and non-multiple-of-3 input lengths behave per RFC 4648.

## Architecture & System Boundary
* **Language & Toolchain:** x86_64 Assembly (NASM syntax) / NASM + GNU `ld`
* **Operating System Focus:** Linux kernel x86_64 syscalls (no libc, no CRT)
* **Core APIs/Primitives Used:** `syscall` (`read`, `write`, `exit`), raw stack-based argv parsing, static lookup tables

## Technical Execution (What & How)
* **Bit-level encoding:** Each 3-byte input group (24 bits) is split into four 6-bit indices via shifts and masks, then translated through a 64-entry alphabet table.
* **Bit-level decoding:** A 256-byte lookup table maps every possible input byte directly to its 6-bit value (or a sentinel for "invalid"), so decoding each character is a single memory read instead of a branch chain.
* **Padding & boundary handling:** Groups with 1 or 2 leftover bytes are padded per RFC 4648 on encode; decode reconstructs partial final groups correctly and terminates cleanly on `=`.

## Repo Layout
```
src/main.asm   # source
Makefile       # build/test/clean targets
test.sh        # RFC 4648 test vectors
```

## How to Build & Run Locally
```bash
make              # assembles and links ./base64
make test         # runs RFC 4648 test vectors

echo -n "Man" | ./base64        # -> TWFu
echo -n "TWFu" | ./base64 -d    # -> Man
```
