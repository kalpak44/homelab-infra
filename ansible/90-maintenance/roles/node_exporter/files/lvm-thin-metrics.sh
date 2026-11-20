#!/bin/bash
# Writes LVM-thin pool usage for node_exporter's textfile collector. A thin pool is not a
# mounted filesystem, so the filesystem collector cannot see it filling up.
set -euo pipefail

dir="${1:?textfile directory}"
out="$dir/lvm_thin.prom"
tmp="$(mktemp "$dir/.lvm_thin.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

{
  echo "# HELP lvm_thin_pool_size_bytes Size of the thin pool's data volume."
  echo "# TYPE lvm_thin_pool_size_bytes gauge"
  echo "# HELP lvm_thin_pool_data_used_ratio Fraction of the pool's data space in use."
  echo "# TYPE lvm_thin_pool_data_used_ratio gauge"
  echo "# HELP lvm_thin_pool_metadata_used_ratio Fraction of the pool's metadata space in use."
  echo "# TYPE lvm_thin_pool_metadata_used_ratio gauge"
  lvs --noheadings --separator ';' --units b --nosuffix \
    -o vg_name,lv_name,lv_size,data_percent,metadata_percent -S 'segtype=thin-pool' |
    awk -F';' '{
      gsub(/ /, "", $1)
      l = "{vg=\"" $1 "\",pool=\"" $2 "\"}"
      print "lvm_thin_pool_size_bytes" l, $3
      print "lvm_thin_pool_data_used_ratio" l, $4 / 100
      print "lvm_thin_pool_metadata_used_ratio" l, $5 / 100
    }'

  # Virtual size handed to guests. Above the pool size, the pool is overcommitted and can
  # fill while every guest still reports free space.
  echo "# HELP lvm_thin_pool_provisioned_bytes Sum of the virtual sizes of the pool's thin volumes."
  echo "# TYPE lvm_thin_pool_provisioned_bytes gauge"
  lvs --noheadings --separator ';' --units b --nosuffix \
    -o vg_name,pool_lv,lv_size -S 'segtype=thin' |
    awk -F';' '{ gsub(/ /, "", $1); sum[$1 ";" $2] += $3 }
      END { for (k in sum) { split(k, p, ";")
        print "lvm_thin_pool_provisioned_bytes{vg=\"" p[1] "\",pool=\"" p[2] "\"}", sum[k] } }'
} > "$tmp"

# Atomic, so a scrape never reads a half-written file.
chmod 0644 "$tmp"
mv "$tmp" "$out"
trap - EXIT
