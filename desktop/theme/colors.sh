#!/usr/bin/env bash
# SparrowOS Canonical Color Definitions
# Cyberpunk "Hackers" aesthetic palette
#
# Source this file in scripts that need the SparrowOS color palette:
#   source /etc/sparrow/theme/colors.sh

# ---------------------------------------------------------------------------
# Hex color values
# ---------------------------------------------------------------------------
export SPARROW_BG="#0a0a0a"         # Near-black background
export SPARROW_FG="#e0e0e0"         # Light gray primary text
export SPARROW_GREEN="#00ff00"      # Neon green — strings, success
export SPARROW_CYAN="#00ffff"       # Cyan — keywords, accents, focus
export SPARROW_MAGENTA="#ff00ff"    # Magenta — types, highlights
export SPARROW_ORANGE="#ff6600"     # Orange — warnings, urgent
export SPARROW_RED="#ff0055"        # Red — errors
export SPARROW_YELLOW="#ffcc00"     # Yellow — constants, info
export SPARROW_BLUE="#0088ff"       # Blue — functions, links
export SPARROW_DIM="#333333"        # Dim — unfocused, inactive
export SPARROW_DARK="#1a1a1a"       # Slightly lighter than background

# ---------------------------------------------------------------------------
# ANSI escape sequences (for use in shell prompts / printf)
# ---------------------------------------------------------------------------
export SPARROW_ANSI_RESET="\033[0m"
export SPARROW_ANSI_GREEN="\033[38;2;0;255;0m"
export SPARROW_ANSI_CYAN="\033[38;2;0;255;255m"
export SPARROW_ANSI_MAGENTA="\033[38;2;255;0;255m"
export SPARROW_ANSI_ORANGE="\033[38;2;255;102;0m"
export SPARROW_ANSI_RED="\033[38;2;255;0;85m"
export SPARROW_ANSI_YELLOW="\033[38;2;255;204;0m"
export SPARROW_ANSI_BLUE="\033[38;2;0;136;255m"
export SPARROW_ANSI_DIM="\033[38;2;51;51;51m"
export SPARROW_ANSI_FG="\033[38;2;224;224;224m"
