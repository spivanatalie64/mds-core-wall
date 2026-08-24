#!/usr/bin/env bash
# Print thread-sibling pairs for every physical core.
# Use the output to pick whole cores (ALL their threads!) for your walls.
set -euo pipefail

nproc=$(nproc)
echo "logical CPUs: $nproc"
declare -A seen
for cpu in $(seq 0 $((nproc - 1))); do
    f=/sys/devices/system/cpu/cpu${cpu}/topology/thread_siblings_list
    [ -r "$f" ] || continue
    pair=$(<"$f")
    [ -n "${seen[$pair]:-}" ] && continue
    seen[$pair]=1
    printf 'core %2d: threads %s\n' "$cpu" "$pair"
done
echo
echo "Tip: give the LAST k physical cores to untrusted tenants,"
echo "listing every thread of those cores in AllowedCPUs."
