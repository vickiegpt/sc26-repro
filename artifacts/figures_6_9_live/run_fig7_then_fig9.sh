#!/usr/bin/env bash
set -euo pipefail

repo=/home/victoryang00/sc26-repro/Ocean
fig7_base=/home/victoryang00/sc26-repro/artifacts/figures_6_9_live/20260807T_fig7_live
fig9_base=/home/victoryang00/sc26-repro/artifacts/figures_6_9_live/20260807T_fig9_live
fig7_config="$fig7_base/config.fig7-live.toml"
fig9_config="$fig9_base/config.fig9-live.toml"
fig7_run="$fig7_base/collector/full-owner-first-no-alloc-info"
fig9_run="$fig9_base/collector/live-after-fig7"

export MPLCONFIGDIR=/tmp/ocean-figures-mpl
mkdir -p "$MPLCONFIGDIR"
cd "$repo"

python3 script/reproduce_figures_6_9.py collect --fig 7 --config "$fig7_config" --run-id full-owner-first-no-alloc-info
python3 script/reproduce_figures_6_9.py validate --fig 7 --input "$fig7_run/normalized"
python3 script/reproduce_figures_6_9.py plot --fig 7 --input "$fig7_run/normalized" --output "$fig7_run/plots" --format pdf

python3 script/reproduce_figures_6_9.py doctor --fig 9 --config "$fig9_config"
python3 script/reproduce_figures_6_9.py collect --fig 9 --config "$fig9_config" --run-id live-after-fig7
python3 script/reproduce_figures_6_9.py validate --fig 9 --input "$fig9_run/normalized"
python3 script/reproduce_figures_6_9.py plot --fig 9 --input "$fig9_run/normalized" --output "$fig9_run/plots" --format pdf
