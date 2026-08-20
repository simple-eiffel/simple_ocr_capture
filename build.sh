#!/bin/bash
# build.sh - Build script for simple_ocr_capture
#
# Usage: ./build.sh [options]
#
# Options:
#   -c, --check      Melt only - fast syntax/type check, no C compile
#   -a, --app        Finalize the shipped GUI application (default)
#   -l, --cli        Finalize the headless CLI (--worker / --shot)
#   -r, --release    Finalize both lean and fat binaries of the app
#   -i, --installer  Build the Inno Setup installer (implies --app)
#   -t, --tests      Finalize and run the test suite
#   -h, --help       Show this help
#
# Examples:
#   ./build.sh            # Finalize the GUI application
#   ./build.sh -c         # Just type-check
#   ./build.sh -i         # Finalize, then build the installer
#
# ---------------------------------------------------------------------------
# This deliberately differs from the older simple_* build.sh scripts, which
# call ec.exe directly with -batch/-freeze/-c_compile and run from W_code.
# All four are now blocked by the ecosystem build standards: they bypass
# F_code enforcement and produce bloated W_code binaries. Everything here
# goes through /d/prod/ec.sh, which is the only supported entry point, and
# every binary lands in EIFGENs/<target>/F_code/.
#
# The test target covers the pure-logic classes only. The rest of this
# application is a window, a Win32 hotkey, a screen grab or an HTTP call to a
# local model, none of which a unit-test runner can assert about.
# ---------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EC_SH="/d/prod/ec.sh"
ECF="$SCRIPT_DIR/simple_ocr_capture.ecf"
ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

MODE="app"

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--check)     MODE="check";     shift ;;
        -a|--app)       MODE="app";       shift ;;
        -l|--cli)       MODE="cli";       shift ;;
        -r|--release)   MODE="release";   shift ;;
        -i|--installer) MODE="installer"; shift ;;
        -t|--tests)     MODE="tests";     shift ;;
        -h|--help)      sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ ! -f "$ECF" ]; then
    echo -e "${RED}ERROR: $ECF not found${NC}"
    exit 1
fi

# Needed by the ECF's $SIMPLE_EIFFEL library locations.
export SIMPLE_EIFFEL="${SIMPLE_EIFFEL:-/d/prod}"
echo -e "${BLUE}[simple_ocr_capture]${NC} SIMPLE_EIFFEL=$SIMPLE_EIFFEL"

cd "$SCRIPT_DIR"

case $MODE in
    check)
        echo -e "${BLUE}Type-checking...${NC}"
        "$EC_SH" check -config "$ECF" -target ocr_capture
        ;;
    app)
        echo -e "${BLUE}Finalizing the GUI application...${NC}"
        "$EC_SH" test -config "$ECF" -target ocr_capture
        ;;
    cli)
        echo -e "${BLUE}Finalizing the headless CLI...${NC}"
        "$EC_SH" test -config "$ECF" -target ocr_cli
        ;;
    tests)
        echo -e "${BLUE}Building the test runner...${NC}"
        "$EC_SH" test -config "$ECF" -target simple_ocr_capture_tests
        EXE="$SCRIPT_DIR/EIFGENs/simple_ocr_capture_tests/F_code/simple_ocr_capture.exe"
        if [ ! -f "$EXE" ]; then
            echo -e "${RED}ERROR: test runner not found at $EXE${NC}"
            exit 1
        fi
        echo -e "${BLUE}Running tests...${NC}"
        "$EXE"
        ;;

    release)
        echo -e "${BLUE}Building lean and fat binaries...${NC}"
        "$EC_SH" release -config "$ECF" -target ocr_capture
        ;;
    installer)
        echo -e "${BLUE}Finalizing the GUI application...${NC}"
        "$EC_SH" test -config "$ECF" -target ocr_capture
        if [ ! -f "$ISCC" ]; then
            echo -e "${RED}ERROR: Inno Setup not found at $ISCC${NC}"
            exit 1
        fi
        echo -e "${BLUE}Building the installer...${NC}"
        "$ISCC" "$SCRIPT_DIR/installer/simple_ocr_capture.iss"
        ;;
esac

echo -e "${GREEN}Done.${NC}"
