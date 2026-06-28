#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


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

MANAGED_START = "# >>> gpu-doctor graphics"
MANAGED_END = "# <<< gpu-doctor graphics"


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


def nix_bool(value: bool) -> str:
    return "true" if value else "false"


def nix_snippet(driver: str, enable_32_bit: bool) -> str:
    if driver == "nvidia":
        return f"""features.graphics = {{
  enable = true;
  driver = "nvidia";
  enable32Bit = {nix_bool(enable_32_bit)};

  nvidia = {{
    open = false;
  }};
}};"""

    return f"""features.graphics = {{
  enable = true;
  driver = "{driver}";
  enable32Bit = {nix_bool(enable_32_bit)};
}};"""


def managed_snippet(driver: str, enable_32_bit: bool, indent: str) -> str:
    lines = [
        f"{indent}{MANAGED_START}",
        *[f"{indent}{line}" for line in nix_snippet(driver, enable_32_bit).splitlines()],
        f"{indent}{MANAGED_END}",
    ]
    return "\n".join(lines)


def print_report(gpus: list[Gpu], enable_32_bit: bool) -> None:
    if not gpus:
        print("No display controller was detected with lspci.")
        print()
        print("Conservative NixOS recommendation:")
        print(nix_snippet("mesa", enable_32_bit))
        return

    print("Detected GPUs:")
    for gpu in gpus:
        print(f"- {gpu.vendor:7} {gpu.bus_id:12} {gpu.model}")

    driver = recommend_driver(gpus)
    print()
    print(f"Recommended graphics driver: {driver}")
    print()
    print("Host configuration snippet:")
    print(nix_snippet(driver, enable_32_bit))

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


def print_json(gpus: list[Gpu], enable_32_bit: bool) -> None:
    payload = {
        "gpus": [asdict(gpu) for gpu in gpus],
        "enable32Bit": enable_32_bit,
        "recommendedDriver": recommend_driver(gpus),
    }
    print(json.dumps(payload, indent=2, sort_keys=True))


def find_repo_root(start: Path) -> Path | None:
    for path in (start, *start.parents):
        if (path / "flake.nix").is_file() and (path / "modules" / "hosts").is_dir():
            return path
    return None


def apply_recommendation(
    repo: Path,
    host: str,
    driver: str,
    enable_32_bit: bool,
) -> Path:
    host_config = repo / "modules" / "hosts" / host / "default.nix"
    if not host_config.is_file():
        raise RuntimeError(f"host config not found: {host_config}")

    text = host_config.read_text()

    managed_pattern = re.compile(
        rf"(?ms)^([ \t]*){re.escape(MANAGED_START)}\n.*?^\1{re.escape(MANAGED_END)}"
    )
    managed_match = managed_pattern.search(text)
    if managed_match:
        indent = managed_match.group(1)
        replacement = managed_snippet(driver, enable_32_bit, indent)
        updated = text[: managed_match.start()] + replacement + text[managed_match.end() :]
    else:
        single_line_pattern = re.compile(
            r"(?m)^([ \t]*)features\.graphics\.enable\s*=\s*true;\s*$"
        )
        single_line_match = single_line_pattern.search(text)

        if single_line_match:
            indent = single_line_match.group(1)
            replacement = managed_snippet(driver, enable_32_bit, indent)
            updated = (
                text[: single_line_match.start()]
                + replacement
                + text[single_line_match.end() :]
            )
        elif re.search(r"(?m)^\s*features\.graphics\s*=\s*\{", text):
            raise RuntimeError(
                "found an unmanaged features.graphics block; update it manually "
                f"or wrap it with {MANAGED_START!r} markers"
            )
        else:
            anchor_pattern = re.compile(
                r"(?m)^([ \t]*)features\.nodejs\.enable\s*=\s*true;\s*$"
            )
            anchor_match = anchor_pattern.search(text)
            if not anchor_match:
                raise RuntimeError(
                    "could not find a safe place to insert features.graphics"
                )

            indent = anchor_match.group(1)
            replacement = "\n" + managed_snippet(driver, enable_32_bit, indent)
            updated = text[: anchor_match.end()] + replacement + text[anchor_match.end() :]

    if updated != text:
        host_config.write_text(updated)

    return host_config


def stage_file(repo: Path, path: Path) -> None:
    try:
        relative = path.relative_to(repo)
    except ValueError as error:
        raise RuntimeError(f"{path} is not inside {repo}") from error

    result = subprocess.run(
        ["git", "-C", str(repo), "add", str(relative)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(stderr or "git add failed")


def run_rebuild(repo: Path, host: str) -> int:
    command = ["sudo", "nixos-rebuild", "switch", "--flake", f".#{host}"]
    print()
    print("Running: " + " ".join(command))
    return subprocess.run(command, cwd=repo, check=False).returncode


def ask_yes_no(question: str) -> bool:
    if not sys.stdin.isatty():
        return False

    answer = input(f"{question} [y/N] ").strip().lower()
    return answer in {"y", "yes", "s", "si"}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Detect local GPUs and recommend a NixOS graphics config."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print machine-readable detection results.",
    )
    parser.add_argument(
        "--host",
        default="desktop",
        help="NixOS host to update when applying the recommendation.",
    )
    parser.add_argument(
        "--repo",
        type=Path,
        help="Path to the nixos-config repo. Defaults to searching from cwd.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Apply the recommendation without prompting.",
    )
    parser.add_argument(
        "--no-prompt",
        action="store_true",
        help="Only print the recommendation.",
    )
    parser.add_argument(
        "--no-rebuild",
        action="store_true",
        help="Apply the recommendation but do not run nixos-rebuild.",
    )
    parser.add_argument(
        "--enable-32-bit",
        "--gaming",
        dest="enable_32_bit",
        action="store_true",
        help="Recommend 32-bit graphics libraries for Steam, Wine or older games.",
    )
    args = parser.parse_args()

    try:
        gpus = parse_gpus(run_lspci())
    except RuntimeError as error:
        print(f"gpu-doctor: {error}", file=sys.stderr)
        return 1

    driver = recommend_driver(gpus)

    if args.json:
        print_json(gpus, args.enable_32_bit)
        return 0

    print_report(gpus, args.enable_32_bit)

    repo = args.repo.resolve() if args.repo else find_repo_root(Path.cwd())
    if repo is None:
        if not args.no_prompt:
            print()
            print("Run gpu-doctor from the nixos-config repo to apply changes.")
        return 0

    if args.no_prompt and not args.yes:
        return 0

    target = repo / "modules" / "hosts" / args.host / "default.nix"
    question = f"Apply recommendation to {target}"
    if not args.no_rebuild:
        question += " and run nixos-rebuild now"
    question += "?"

    if not args.yes and not ask_yes_no(question):
        return 0

    try:
        host_config = apply_recommendation(repo, args.host, driver, args.enable_32_bit)
        stage_file(repo, host_config)
    except RuntimeError as error:
        print(f"gpu-doctor: {error}", file=sys.stderr)
        return 1

    print()
    print(f"Updated and staged {host_config}")

    if args.no_rebuild:
        return 0

    return run_rebuild(repo, args.host)


if __name__ == "__main__":
    raise SystemExit(main())
