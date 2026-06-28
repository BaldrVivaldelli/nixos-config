from __future__ import annotations

import os
from pathlib import Path


HOME = Path.home()
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
HOLODECK_DIR = CONFIG_HOME / "holodeck"
PROFILES_DIR = HOLODECK_DIR / "profiles"
GIT_PROFILES_DIR = HOLODECK_DIR / "git"
PUBLIC_KEYS_DIR = HOLODECK_DIR / "public-keys"
GITCONFIG_FILE = HOME / ".gitconfig"
SSH_CONFIG_FILE = HOME / ".ssh" / "config"

GIT_BEGIN = "# >>> holodeck git"
GIT_END = "# <<< holodeck git"
SSH_BEGIN = "# >>> holodeck ssh"
SSH_END = "# <<< holodeck ssh"

DEFAULT_GITHUB_HOST = os.environ.get("HOLODECK_DEFAULT_GITHUB_HOST", "github.com")
DEFAULT_GITLAB_HOST = os.environ.get("HOLODECK_DEFAULT_GITLAB_HOST", "gitlab.com")
DEFAULT_PERSONAL_DIR = os.environ.get(
    "HOLODECK_DEFAULT_PERSONAL_DIR",
    "$HOME/projects/personal",
)
DEFAULT_WORK_DIR = os.environ.get("HOLODECK_DEFAULT_WORK_DIR", "$HOME/projects/work")

