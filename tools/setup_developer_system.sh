#!/bin/bash
# ============================================================
#  Zoho Robotics — Developer System Setup Script
#  Run once on any developer machine (laptop, desktop,
#  workstation) before working with the repositories.
#  Safe to re-run — checks before installing anything.
#
#  Audience: All developers — interns, engineers, leads
#
#  Versions are read from project.env in the same directory.
#  To upgrade a tool, update project.env — not this script.
# ============================================================

set -e

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass()  { echo -e "  ${GREEN}✔  $1${RESET}"; }
fail()  { echo -e "  ${RED}✖  $1${RESET}"; }
info()  { echo -e "  ${CYAN}→  $1${RESET}"; }
warn()  { echo -e "  ${YELLOW}⚠  $1${RESET}"; }
header(){ echo ""; echo -e "${BOLD}━━━  $1  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# ── Load versions from project.env ──────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FILE="$SCRIPT_DIR/project.env"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo ""
  echo -e "${RED}✖  project.env not found at: $PROJECT_FILE${RESET}"
  echo ""
  echo "  This script requires project.env to be in the same"
  echo "  directory as setup_developer_system.sh."
  echo ""
  echo "  Ask your mentor for the project.env file."
  echo ""
  exit 1
fi

# shellcheck source=project.env
source "$PROJECT_FILE"

# Validate required variables are set
REQUIRED_VARS=(
  ROS2_DISTRO NODE_MAJOR_VERSION GIT_MIN_VERSION
  PRECOMMIT_MIN_VERSION PIPX_MIN_VERSION
  COMMITLINT_CLI_VERSION COMMITLINT_CONFIG_VERSION HUSKY_VERSION
)
MISSING_VARS=false
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo -e "${RED}✖  project.env is missing required variable: $var${RESET}"
    MISSING_VARS=true
  fi
done
if [[ "$MISSING_VARS" == "true" ]]; then
  echo ""
  echo "  project.env is incomplete. Ask your mentor for the correct file."
  exit 1
fi

# ── Intro ─────────────────────────────────────────────────────
clear
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Zoho Robotics — Developer System Setup             ║${RESET}"
echo -e "${BOLD}║   Run once per machine — all developers                  ║${RESET}"
echo -e "${BOLD}║   Reads tool versions from project.env                  ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Configuration loaded from: $PROJECT_FILE"
echo ""
echo -e "  ${CYAN}Tool versions being installed:${RESET}"
echo "    ROS2:       $ROS2_DISTRO"
echo "    Node.js:    v${NODE_MAJOR_VERSION}.x (LTS)"
echo "    Git minimum: $GIT_MIN_VERSION"
echo "    pre-commit: $PRECOMMIT_MIN_VERSION.x minimum"
echo ""
echo -e "  ${YELLOW}Estimated time: 5-10 minutes${RESET}"
echo ""
read -r -p "  Press ENTER to start, or Ctrl+C to cancel... "

# ── STEP 1: Check OS ─────────────────────────────────────────
header "Step 1 of 7 — Checking Operating System"

if ! grep -q "Ubuntu 22" /etc/os-release 2>/dev/null; then
  warn "This script is designed for Ubuntu 22.04."
  warn "You appear to be running a different OS or version."
  warn "Some steps may not work correctly."
  echo ""
  read -r -p "  Continue anyway? (y/N): " CONTINUE
  if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
    echo "  Exiting. Ask your mentor for help setting up on this OS."
    exit 1
  fi
else
  pass "Ubuntu 22.04 detected"
fi

# ── STEP 2: Check and configure Git ──────────────────────────
header "Step 2 of 7 — Git (minimum v${GIT_MIN_VERSION})"

GIT_VERSION=$(git --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
GIT_MAJOR=$(echo "$GIT_VERSION" | cut -d. -f1)
GIT_MINOR=$(echo "$GIT_VERSION" | cut -d. -f2)
GIT_MIN_MAJOR=$(echo "$GIT_MIN_VERSION" | cut -d. -f1)
GIT_MIN_MINOR=$(echo "$GIT_MIN_VERSION" | cut -d. -f2)

if [[ -z "$GIT_VERSION" ]]; then
  fail "Git is not installed"
  info "Installing Git..."
  sudo apt-get update -q
  sudo apt-get install -y git
  pass "Git installed: $(git --version | cut -d' ' -f3)"
elif [[ "$GIT_MAJOR" -lt "$GIT_MIN_MAJOR" ]] || \
     [[ "$GIT_MAJOR" -eq "$GIT_MIN_MAJOR" && "$GIT_MINOR" -lt "$GIT_MIN_MINOR" ]]; then
  fail "Git $GIT_VERSION is too old (need $GIT_MIN_VERSION or higher)"
  info "Upgrading Git..."
  sudo add-apt-repository -y ppa:git-core/ppa
  sudo apt-get update -q
  sudo apt-get install -y git
  pass "Git upgraded to $(git --version | cut -d' ' -f3)"
else
  pass "Git $(git --version | cut -d' ' -f3) meets minimum v${GIT_MIN_VERSION}"
fi

# Configure Git identity
echo ""
CURRENT_NAME=$(git config --global user.name 2>/dev/null || true)
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || true)

if [[ -n "$CURRENT_NAME" && -n "$CURRENT_EMAIL" ]]; then
  pass "Git identity already configured: $CURRENT_NAME <$CURRENT_EMAIL>"
  echo ""
  read -r -p "  Is this correct? (Y/n): " ID_OK
  if [[ "$ID_OK" == "n" || "$ID_OK" == "N" ]]; then
    CURRENT_NAME=""
    CURRENT_EMAIL=""
  fi
fi

if [[ -z "$CURRENT_NAME" ]]; then
  echo ""
  echo -e "  ${CYAN}Your name appears on every commit you make.${RESET}"
  read -r -p "  Enter your full name: " GIT_NAME
  git config --global user.name "$GIT_NAME"
  pass "Name set: $GIT_NAME"
fi

if [[ -z "$CURRENT_EMAIL" ]]; then
  echo ""
  echo -e "  ${CYAN}Must match your GitHub account email exactly.${RESET}"
  read -r -p "  Enter your email: " GIT_EMAIL
  git config --global user.email "$GIT_EMAIL"
  pass "Email set: $GIT_EMAIL"
fi

[[ "$(git config --global pull.rebase 2>/dev/null)" == "true" ]] && \
  pass "pull.rebase already set to true" || \
  { git config --global pull.rebase true && pass "pull.rebase set to true"; }

[[ "$(git config --global init.defaultBranch 2>/dev/null)" == "${DEFAULT_BRANCH_NAME:-main}" ]] && \
  pass "init.defaultBranch already set to ${DEFAULT_BRANCH_NAME:-main}" || \
  { git config --global init.defaultBranch "${DEFAULT_BRANCH_NAME:-main}" && pass "init.defaultBranch set to ${DEFAULT_BRANCH_NAME:-main}"; }

# ── STEP 3: pipx + pre-commit ─────────────────────────────────
header "Step 3 of 7 — pipx and pre-commit (minimum v${PRECOMMIT_MIN_VERSION})"

# pipx
if command -v pipx &>/dev/null; then
  PIPX_VER=$(pipx --version 2>/dev/null | grep -oP '\d+' | head -1)
  if [[ "$PIPX_VER" -ge "$PIPX_MIN_VERSION" ]]; then
    pass "pipx $(pipx --version) meets minimum v${PIPX_MIN_VERSION}"
  else
    warn "pipx $(pipx --version) is too old — upgrading..."
    pipx upgrade pipx
    pass "pipx upgraded to $(pipx --version)"
  fi
else
  info "Installing pipx..."
  sudo apt-get install -y pipx
  pipx ensurepath
  export PATH="$HOME/.local/bin:$PATH"
  pass "pipx installed: $(pipx --version)"
fi

# pre-commit
if command -v pre-commit &>/dev/null; then
  PC_VERSION=$(pre-commit --version | grep -oP '\d+' | head -1)
  if [[ "$PC_VERSION" -ge "$PRECOMMIT_MIN_VERSION" ]]; then
    pass "pre-commit $(pre-commit --version | grep -oP '\d+\.\d+\.\d+') meets minimum v${PRECOMMIT_MIN_VERSION}"
  else
    warn "pre-commit version is too old — upgrading..."
    pipx upgrade pre-commit
    pass "pre-commit upgraded to $(pre-commit --version | grep -oP '\d+\.\d+\.\d+')"
  fi
else
  info "Installing pre-commit via pipx..."
  pipx install pre-commit
  export PATH="$HOME/.local/bin:$PATH"
  pass "pre-commit $(pre-commit --version | grep -oP '\d+\.\d+\.\d+') installed"
fi

# ── STEP 4: Node.js ───────────────────────────────────────────
header "Step 4 of 7 — Node.js (target v${NODE_MAJOR_VERSION}.x LTS)"

# ── Sub-step 4a: Fix any broken apt GPG keys ──────────────────
# Run this regardless of whether Node.js needs installing.
# A broken key blocks ALL apt operations including gh CLI install.
# This must be fixed on the machine even if Node.js is already correct.
info "Checking apt repository GPG keys..."
APT_UPDATE_OUTPUT=$(sudo apt-get update 2>&1 || true)
APT_HAS_ERRORS=false

if echo "$APT_UPDATE_OUTPUT" | grep -qiE "NO_PUBKEY|couldn't be verified|EXPKEYSIG"; then
  APT_HAS_ERRORS=true
  warn "Broken GPG keys detected in apt repositories"

  # Fix Chrome GPG key if broken
  if echo "$APT_UPDATE_OUTPUT" | grep -qiE "google|chrome|FD533C07C264648F"; then
    info "Fixing Chrome GPG key..."
    sudo curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | sudo gpg --dearmor \
      | sudo tee /etc/apt/trusted.gpg.d/google-chrome.gpg > /dev/null 2>&1
    grep -rl '"https://google.com"' /etc/apt/sources.list.d/ \
      | xargs sudo rm -f 2>/dev/null || true
    pass "Chrome GPG key fixed"
  fi

  # Fix NodeSource GPG key if broken
  # Detects by: NO_PUBKEY error mentioning nodesource, or
  # sources list exists but key is missing/expired
  if echo "$APT_UPDATE_OUTPUT" | grep -qiE "nodesource|2F59B5F99B1BE0B4" || \
     [[ -f "/etc/apt/sources.list.d/nodesource.list" ]]; then
    info "Fixing NodeSource GPG key..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | sudo gpg --dearmor \
      | sudo tee /etc/apt/keyrings/nodesource.gpg > /dev/null 2>&1
    # Rewrite sources list in modern signed-by format
    # Preserve the existing Node.js major version in the sources list
    EXISTING_NODE_VER=$(grep -oP 'node_\K[0-9]+' \
      /etc/apt/sources.list.d/nodesource.list 2>/dev/null | head -1 \
      || echo "$NODE_MAJOR_VERSION")
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] \
https://deb.nodesource.com/node_${EXISTING_NODE_VER}.x nodistro main" \
      | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
    pass "NodeSource GPG key fixed (node_${EXISTING_NODE_VER}.x)"
  fi

  # Verify the fixes worked
  APT_RECHECK=$(sudo apt-get update 2>&1 || true)
  if echo "$APT_RECHECK" | grep -qiE "NO_PUBKEY|couldn't be verified|EXPKEYSIG"; then
    warn "Some GPG key issues remain — continuing but apt install may fail"
    warn "Output: $(echo "$APT_RECHECK" | grep -iE 'NO_PUBKEY|error' | head -3)"
  else
    pass "All apt GPG keys are valid"
  fi
else
  pass "apt GPG keys are valid"
fi

# ── Sub-step 4b: Install or upgrade Node.js if needed ─────────
NEEDS_NODE=false
NODE_INSTALL_REASON=""

if command -v node &>/dev/null; then
  INSTALLED_MAJOR=$(node --version | grep -oP '\d+' | head -1)
  if [[ "$INSTALLED_MAJOR" -ge "$NODE_MAJOR_VERSION" ]]; then
    pass "Node.js $(node --version) meets target v${NODE_MAJOR_VERSION}"
    # Key fix above is sufficient — no reinstall needed
  else
    warn "Node.js $(node --version) is below target v${NODE_MAJOR_VERSION} — upgrading..."
    NEEDS_NODE=true
    NODE_INSTALL_REASON="upgrade from v${INSTALLED_MAJOR}"
  fi
else
  info "Node.js not found — installing v${NODE_MAJOR_VERSION}..."
  NEEDS_NODE=true
  NODE_INSTALL_REASON="fresh install"
fi

if [[ "$NEEDS_NODE" == "true" ]]; then
  # Remove old installation cleanly before reinstalling
  sudo apt-get remove -y nodejs npm 2>/dev/null || true
  sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true

  # Add NodeSource repository for the target version from project.env
  info "Adding NodeSource repository for Node.js ${NODE_MAJOR_VERSION} LTS ($NODE_INSTALL_REASON)..."
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | sudo gpg --dearmor \
    | sudo tee /etc/apt/keyrings/nodesource.gpg > /dev/null 2>&1
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] \
https://deb.nodesource.com/node_${NODE_MAJOR_VERSION}.x nodistro main" \
    | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
  sudo apt-get update -q
  sudo apt-get install -y nodejs
  pass "Node.js $(node --version) installed"
fi

if ! command -v npm &>/dev/null; then
  fail "npm not found after Node.js install — ask your mentor"
  exit 1
fi
pass "npm $(npm --version) is available"

# ── STEP 5: ROS2 ──────────────────────────────────────────────
header "Step 5 of 7 — ROS2 ($ROS2_DISTRO)"

ROS2_PATH="/opt/ros/$ROS2_DISTRO"

if [[ -d "$ROS2_PATH" ]]; then
  pass "ROS2 $ROS2_DISTRO found at $ROS2_PATH"

  # Source for current session if not already sourced
  if [[ "$ROS_DISTRO" == "$ROS2_DISTRO" ]]; then
    pass "ROS2 $ROS2_DISTRO is already sourced in this session"
  else
    # shellcheck source=/dev/null
    source "$ROS2_PATH/setup.bash"
    pass "ROS2 $ROS2_DISTRO sourced for this session"
  fi

  # Add to .bashrc if not already there
  if grep -q "ros/$ROS2_DISTRO" ~/.bashrc 2>/dev/null; then
    pass "ROS2 $ROS2_DISTRO already in ~/.bashrc"
  else
    echo "source $ROS2_PATH/setup.bash" >> ~/.bashrc
    pass "ROS2 $ROS2_DISTRO added to ~/.bashrc"
  fi

  # Warn if a different ROS2 version is already sourced
  if [[ -n "$ROS_DISTRO" && "$ROS_DISTRO" != "$ROS2_DISTRO" ]]; then
    warn "A different ROS2 version ($ROS_DISTRO) is currently sourced"
    warn "Expected: $ROS2_DISTRO — check ~/.bashrc for conflicting source lines"
  fi
else
  # Check if any other ROS2 version is installed
  INSTALLED_DISTROS=$(ls /opt/ros/ 2>/dev/null | tr '\n' ' ')
  fail "ROS2 $ROS2_DISTRO not found at $ROS2_PATH"
  if [[ -n "$INSTALLED_DISTROS" ]]; then
    warn "Found other ROS2 versions installed: $INSTALLED_DISTROS"
    warn "If your team is on a different distro, update ROS2_DISTRO in project.env"
  else
    fail "No ROS2 versions found at /opt/ros/"
    fail "ROS2 must be installed before running this script"
    fail "Ask your mentor to install ROS2 $ROS2_DISTRO"
  fi
  exit 1
fi

# ── STEP 6: Git editor ────────────────────────────────────────
header "Step 6 of 7 — Git Editor"

CURRENT_EDITOR=$(git config --global core.editor 2>/dev/null || true)
if [[ -n "$CURRENT_EDITOR" ]]; then
  pass "Git editor already set to: $CURRENT_EDITOR"
else
  if command -v code &>/dev/null; then
    git config --global core.editor "code --wait"
    pass "Git editor set to VS Code"
  elif command -v nano &>/dev/null; then
    git config --global core.editor "nano"
    pass "Git editor set to nano"
  else
    git config --global core.editor "vim"
    pass "Git editor set to vim"
    warn "Consider installing VS Code for a better experience"
  fi
fi

# ── STEP 7: Final verification ────────────────────────────────
header "Step 7 of 7 — Final Verification"

ALL_GOOD=true

echo ""
echo -e "  ${BOLD}Tool versions:${RESET}"

# Git
GIT_VER=$(git --version | cut -d' ' -f3)
GIT_MAJOR_CHECK=$(echo "$GIT_VER" | cut -d. -f1)
GIT_MINOR_CHECK=$(echo "$GIT_VER" | cut -d. -f2)
if [[ "$GIT_MAJOR_CHECK" -gt "$GIT_MIN_MAJOR" ]] || \
   [[ "$GIT_MAJOR_CHECK" -eq "$GIT_MIN_MAJOR" && "$GIT_MINOR_CHECK" -ge "$GIT_MIN_MINOR" ]]; then
  pass "Git $GIT_VER  (need $GIT_MIN_VERSION+)"
else
  fail "Git $GIT_VER is below minimum $GIT_MIN_VERSION"
  ALL_GOOD=false
fi

# Node.js
NODE_VER=$(node --version 2>/dev/null || echo "not found")
NODE_VER_MAJOR=$(echo "$NODE_VER" | grep -oP '\d+' | head -1)
if [[ "$NODE_VER_MAJOR" -ge "$NODE_MAJOR_VERSION" ]]; then
  pass "Node.js $NODE_VER  (need v${NODE_MAJOR_VERSION}+)"
else
  fail "Node.js $NODE_VER is below target v${NODE_MAJOR_VERSION}"
  ALL_GOOD=false
fi

# npm
NPM_VER=$(npm --version 2>/dev/null || echo "not found")
if [[ "$NPM_VER" != "not found" ]]; then
  pass "npm $NPM_VER"
else
  fail "npm not found"; ALL_GOOD=false
fi

# pre-commit
PC_VER=$(pre-commit --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "not found")
PC_MAJOR_CHECK=$(echo "$PC_VER" | cut -d. -f1)
if [[ "$PC_MAJOR_CHECK" -ge "$PRECOMMIT_MIN_VERSION" ]]; then
  pass "pre-commit $PC_VER  (need $PRECOMMIT_MIN_VERSION+)"
else
  fail "pre-commit $PC_VER is below minimum v${PRECOMMIT_MIN_VERSION}"
  ALL_GOOD=false
fi

# pipx
PIPX_VER=$(pipx --version 2>/dev/null || echo "not found")
if [[ "$PIPX_VER" != "not found" ]]; then
  pass "pipx $PIPX_VER"
else
  fail "pipx not found"; ALL_GOOD=false
fi

# ROS2
if [[ "$ROS_DISTRO" == "$ROS2_DISTRO" ]]; then
  pass "ROS2 $ROS_DISTRO  (configured for $ROS2_DISTRO)"
else
  fail "ROS2 sourced distro '$ROS_DISTRO' does not match expected '$ROS2_DISTRO'"
  ALL_GOOD=false
fi

echo ""
echo -e "  ${BOLD}Git configuration:${RESET}"

GIT_NAME_CHECK=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL_CHECK=$(git config --global user.email 2>/dev/null || echo "")
REBASE_CHECK=$(git config --global pull.rebase 2>/dev/null || echo "")
BRANCH_CHECK=$(git config --global init.defaultBranch 2>/dev/null || echo "")

[[ -n "$GIT_NAME_CHECK" ]]       && pass "Name:                $GIT_NAME_CHECK"   || { fail "Git name not set"; ALL_GOOD=false; }
[[ -n "$GIT_EMAIL_CHECK" ]]      && pass "Email:               $GIT_EMAIL_CHECK"  || { fail "Git email not set"; ALL_GOOD=false; }
[[ "$REBASE_CHECK" == "true" ]]  && pass "pull.rebase:         true"               || { fail "pull.rebase not set"; ALL_GOOD=false; }
[[ "$BRANCH_CHECK" == "${DEFAULT_BRANCH_NAME:-main}" ]] && pass "init.defaultBranch: ${DEFAULT_BRANCH_NAME:-main}"               || { fail "init.defaultBranch not set"; ALL_GOOD=false; }

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

if [[ "$ALL_GOOD" == "true" ]]; then
  echo -e "${GREEN}${BOLD}  ✔  Your laptop is fully set up!${RESET}"
  echo ""
  echo "  Versions installed:"
  echo "    Git:         $(git --version | cut -d' ' -f3)"
  echo "    Node.js:     $(node --version)"
  echo "    npm:         $(npm --version)"
  echo "    pre-commit:  $(pre-commit --version | grep -oP '\d+\.\d+\.\d+')"
  echo "    ROS2:        $ROS_DISTRO"
  echo ""
  echo -e "${CYAN}  Next: clone a repository and run tools/setup_repo_hooks.sh${RESET}"
else
  echo -e "${RED}${BOLD}  ✖  Some items need attention — see failures above${RESET}"
  echo ""
  echo "  Fix the failed items and run this script again."
  echo "  Ask your mentor if you are not sure how to fix something."
  exit 1
fi

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
