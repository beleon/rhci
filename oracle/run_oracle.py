"""Run probe inputs through real GHCi (in a container) and record exact output.

Probe file format:
  ## Title        starts a new section, run in a fresh GHCi session
  -- text         a note, copied to the golden file
  :{ ... :}       a multi-line input, sent as one probe
  anything else   one GHCi input line

Usage: uv run --no-project python run_oracle.py probes.txt [--files DIR] > golden.txt

With --files, DIR is mounted as GHCi's working directory (for :load).
"""
import subprocess
import sys

IMAGE = "docker.io/library/haskell:9.6"
SEP = "@@PROBE-SEP@@"


def parse(path):
    sections, cur, block = [], None, None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if block is not None:
            block.append(line)
            if line.strip() == ":}":
                cur["items"].append(("in", "\n".join(block)))
                block = None
            continue
        if line.startswith("## "):
            cur = {"title": line[3:], "items": []}
            sections.append(cur)
        elif not line.strip():
            continue
        elif line.startswith("--"):
            cur["items"].append(("note", line))
        elif line.strip() == ":{":
            block = [line]
        else:
            cur["items"].append(("in", line))
    return sections


FILES = None


def run_section(inputs):
    script = []
    for inp in inputs:
        script.append(inp)
        script.append(f":! echo {SEP}")
    mount = ["-v", f"{FILES}:/w:Z", "-w", "/w"] if FILES else []
    proc = subprocess.run(
        # A runaway probe (4 ^ (2 ^ 127)) must not take the machine with it:
        # GHC's heap limit makes it a "heap overflow" exception for that
        # probe (below the container's cap, which would kill the section),
        # and the time limit kills (GHCi survived a TERM).
        ["podman", "run", "--rm", "-i", "--memory", "8g", *mount, IMAGE, "sh", "-c",
         "timeout -s KILL 120 ghci -ignore-dot-ghci -v0 -fdiagnostics-color=never +RTS -M6g -RTS 2>&1"],
        input="\n".join(script) + "\n", capture_output=True, text=True,
    )
    outs = proc.stdout.split(SEP + "\n")
    return [o.rstrip("\n") for o in outs[: len(inputs)]] + [""] * (len(inputs) - len(outs))


def main():
    global FILES
    if "--files" in sys.argv:
        import os
        FILES = os.path.abspath(sys.argv[sys.argv.index("--files") + 1])
    for sec in parse(sys.argv[1]):
        inputs = [t for k, t in sec["items"] if k == "in"]
        outs = iter(run_section(inputs))
        print(f"## {sec['title']}\n")
        for kind, text in sec["items"]:
            if kind == "note":
                print(text)
                continue
            for i, l in enumerate(text.split("\n")):
                print(("ghci> " if i == 0 else "ghci| ") + l)
            out = next(outs)
            if out:
                print(out)
        print()
        sys.stdout.flush()


main()
