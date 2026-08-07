#!/usr/bin/env bash
set -euo pipefail

repo=/home/victoryang00/sc26-repro/Ocean
fig6_base=/home/victoryang00/sc26-repro/artifacts/figures_6_9_live/20260807T_fig6_live
fig7_base=/home/victoryang00/sc26-repro/artifacts/figures_6_9_live/20260807T_fig7_live
fig9_base=/home/victoryang00/sc26-repro/artifacts/figures_6_9_live/20260807T_fig9_live
fig6_config="$fig6_base/config.fig6-live.toml"
fig7_config="$fig7_base/config.fig7-live.toml"
fig9_config="$fig9_base/config.fig9-live.toml"
fig6_run="$fig6_base/collector/sweep-fail-closed"
fig7_run="$fig7_base/collector/full-fail-closed"
fig9_run="$fig9_base/collector/live-fail-closed"

export MPLCONFIGDIR=/tmp/ocean-figures-mpl
mkdir -p "$MPLCONFIGDIR"
cd "$repo"

python3 script/reproduce_figures_6_9.py collect --fig 7 --config "$fig7_config" --run-id full-fail-closed
python3 script/reproduce_figures_6_9.py validate --fig 7 --input "$fig7_run/normalized"
python3 script/reproduce_figures_6_9.py plot --fig 7 --input "$fig7_run/normalized" --output "$fig7_run/plots" --format pdf

python3 script/reproduce_figures_6_9.py doctor --fig 9 --config "$fig9_config"
python3 script/reproduce_figures_6_9.py collect --fig 9 --config "$fig9_config" --run-id live-fail-closed
python3 script/reproduce_figures_6_9.py validate --fig 9 --input "$fig9_run/normalized"
python3 script/reproduce_figures_6_9.py plot --fig 9 --input "$fig9_run/normalized" --output "$fig9_run/plots" --format pdf

python3 script/reproduce_figures_6_9.py collect --fig 6 --config "$fig6_config" --run-id sweep-fail-closed
python3 script/reproduce_figures_6_9.py validate --fig 6 --input "$fig6_run/normalized"
python3 script/reproduce_figures_6_9.py plot --fig 6 --input "$fig6_run/normalized" --output "$fig6_run/plots" --format pdf
