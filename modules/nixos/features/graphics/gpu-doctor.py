#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass


GPU_CLASSES = (
    "VGA compatible controller",
    "3D controller",
    "Display controller",
)

VENDORS = {
    "10de": "nvidia",
    "1002": "amd",
    "8086": "intel",
}


@dataclass
class Gpu:
    bus_id: str
    vendor: str
    vendor_id: str
    model: str
    raw: str


def run_lspci() -> list[str]:
    if shutil.which("lspci") is None:
        raise RuntimeError("lspci was not found in PATH")

    result = subprocess.run(
        ["lspci", "-nn"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(stderr or "lspci failed")

    return result.stdout.splitlines()


def parse_gpus(lines: list[str]) -> list[Gpu]:
    gpus: list[Gpu] = []

    for line in lines:
        if not any(gpu_class in line for gpu_class in GPU_CLASSES):
            continue

        bus_id = line.split(maxsplit=1)[0]
        ids = re.findall(r"\[([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\]", line)
        vendor_id = ids[-1][0].lower() if ids else ""
        vendor = VENDORS.get(vendor_id, "unknown")
        model = line.split(":", maxsplit=2)[-1].strip()

        if vendor == "unknown":
            lowered = line.lower()
            if "nvidia" in lowered:
                vendor = "nvidia"
            elif "amd" in lowered or "ati" in lowered or "radeon" in lowered:
                vendor = "amd"
            elif "intel" in lowered:
                vendor = "intel"

        gpus.append(
            Gpu(
                bus_id=bus_id,
                vendor=vendor,
                vendor_id=vendor_id or "unknown",
                model=model,
                raw=line,
            )
        )

    return gpus


def recommend_driver(gpus: list[Gpu]) -> str:
    vendors = {gpu.vendor for gpu in gpus}

    if "nvidia" in vendors:
        return "nvidia"
    if "amd" in vendors:
        return "amd"
    if "intel" in vendors:
        return "intel"
    return "mesa"


def nix_snippet(driver: str) -> str:
    if driver == "nvidia":
        return """features.graphics = {
  enable = true;
  driver = "nvidia";
  enable32Bit = true;

  nvidia = {
    open = false;
  };
};"""

    return f"""features.graphics = {{
  enable = true;
  driver = "{driver}";
  enable32Bit = true;
}};"""


def print_report(gpus: list[Gpu]) -> None:
    if not gpus:
        print("No display controller was detected with lspci.")
        print()
        print("Conservative NixOS recommendation:")
        print(nix_snippet("mesa"))
        return

    print("Detected GPUs:")
    for gpu in gpus:
        print(f"- {gpu.vendor:7} {gpu.bus_id:12} {gpu.model}")

    driver = recommend_driver(gpus)
    print()
    print(f"Recommended graphics driver: {driver}")
    print()
    print("Host configuration snippet:")
    print(nix_snippet(driver))

    vendors = {gpu.vendor for gpu in gpus}
    if "nvidia" in vendors:
        print()
        print("NVIDIA notes:")
        print("- Keep nvidia.open = false for broad compatibility.")
        print("- If your GPU is Turing or newer, you can try nvidia.open = true.")
        if len(vendors - {"nvidia"}) > 0:
            print("- Hybrid graphics may need PRIME bus IDs; these GPUs were detected:")
            for gpu in gpus:
                print(f"  - {gpu.vendor}: {gpu.bus_id}")

    if "amd" in vendors:
        print()
        print("AMD notes:")
        print("- Modern AMD GPUs use amdgpu with Mesa.")
        print("- Very old ATI/Radeon cards may need legacy driver handling.")


def print_json(gpus: list[Gpu]) -> None:
    payload = {
        "gpus": [asdict(gpu) for gpu in gpus],
        "recommendedDriver": recommend_driver(gpus),
    }
    print(json.dumps(payload, indent=2, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Detect local GPUs and recommend a NixOS graphics config."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print machine-readable detection results.",
    )
    args = parser.parse_args()

    try:
        gpus = parse_gpus(run_lspci())
    except RuntimeError as error:
        print(f"gpu-doctor: {error}", file=sys.stderr)
        return 1

    if args.json:
        print_json(gpus)
    else:
        print_report(gpus)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
