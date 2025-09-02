#!/bin/bash

set -euo pipefail
set -x

# Allow overriding the GCS (legacy Redis) port via:
#   1) Env var RAY_GCS_PORT
#   2) First CLI argument
# Default: 6379, but if occupied will probe subsequent ports.
BASE_PORT="${RAY_GCS_PORT:-${1:-6379}}"
PORT="$BASE_PORT"

is_port_free() {
	# Returns 0 if free
	! (ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":$1$")
}

if ! is_port_free "$PORT"; then
	echo "Port $PORT is in use; searching for a free port..." >&2
	for delta in $(seq 1 20); do
		cand=$((BASE_PORT+delta))
		if is_port_free "$cand"; then
			PORT=$cand
			echo "Using alternative GCS port $PORT" >&2
			break
		fi
	done
fi

if ! is_port_free "$PORT"; then
	echo "Failed to find a free port starting from $BASE_PORT" >&2
	exit 1
fi

echo "Starting Ray head on GCS port $PORT" >&2

ray stop -v --force --grace-period 60 || true
ps aux | head -n 50
env RAY_DEBUG=legacy HYDRA_FULL_ERROR=1 VLLM_USE_V1=1 \
	ray start --head --port="$PORT" --dashboard-host=0.0.0.0

echo "Ray started. Worker nodes can join with: ray start --address='$(hostname -I | awk '{print $1}'):$PORT'" >&2
