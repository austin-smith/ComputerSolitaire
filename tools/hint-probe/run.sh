#!/bin/bash
# Compiles the hint-quality probe against the UI-free Game sources and runs it.
# Usage: tools/hint-probe/run.sh <yukon|klondike|freecell|spider|pyramid|all> [seeds] [klondike draw count | spider suit count]
set -euo pipefail

cd "$(dirname "$0")/../.."

SOURCES=(
  ComputerSolitaire/Game/Shared/Card.swift
  ComputerSolitaire/Game/Shared/GameState.swift
  ComputerSolitaire/Game/Shared/GameVariant.swift
  ComputerSolitaire/Game/Shared/MoveTypes.swift
  ComputerSolitaire/Game/Shared/GameRulesShared.swift
  ComputerSolitaire/Game/Shared/AutoMoveAdvisor.swift
  ComputerSolitaire/Game/Shared/TapMovePolicy.swift
  ComputerSolitaire/Game/Shared/HintAdvisor.swift
  ComputerSolitaire/Game/Shared/BinaryHeap.swift
  ComputerSolitaire/Game/Klondike/GameStateKlondike.swift
  ComputerSolitaire/Game/Klondike/GameRulesKlondike.swift
  ComputerSolitaire/Game/Klondike/AutoMoveAdvisorKlondike.swift
  ComputerSolitaire/Game/Klondike/KlondikePlanner.swift
  ComputerSolitaire/Game/FreeCell/GameStateFreeCell.swift
  ComputerSolitaire/Game/FreeCell/GameRulesFreeCell.swift
  ComputerSolitaire/Game/FreeCell/AutoMoveAdvisorFreeCell.swift
  ComputerSolitaire/Game/FreeCell/FreeCellSolver.swift
  ComputerSolitaire/Game/Yukon/GameStateYukon.swift
  ComputerSolitaire/Game/Yukon/GameRulesYukon.swift
  ComputerSolitaire/Game/Yukon/AutoMoveAdvisorYukon.swift
  ComputerSolitaire/Game/Yukon/YukonPlanner.swift
  ComputerSolitaire/Game/Spider/GameStateSpider.swift
  ComputerSolitaire/Game/Spider/GameRulesSpider.swift
  ComputerSolitaire/Game/Spider/AutoMoveAdvisorSpider.swift
  ComputerSolitaire/Game/Spider/SpiderPlanner.swift
  ComputerSolitaire/Game/Pyramid/PyramidGeometry.swift
  ComputerSolitaire/Game/Pyramid/GameStatePyramid.swift
  ComputerSolitaire/Game/Pyramid/GameRulesPyramid.swift
  ComputerSolitaire/Game/Pyramid/AutoMoveAdvisorPyramid.swift
  ComputerSolitaire/Game/Pyramid/PyramidPlanner.swift
)

for source in "${SOURCES[@]}"; do
  if [[ ! -f "$source" ]]; then
    echo "error: missing source $source — update SOURCES in tools/hint-probe/run.sh" >&2
    exit 1
  fi
done

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

swiftc -O -o "$BUILD_DIR/hint-probe" "${SOURCES[@]}" tools/hint-probe/main.swift

"$BUILD_DIR/hint-probe" "$@"
