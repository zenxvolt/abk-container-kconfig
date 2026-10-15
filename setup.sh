#!/usr/bin/env bash
# ABK custom external module: menambahkan beberapa opsi Kconfig ke gki_defconfig.
# Dijalankan oleh workflow ABK dengan working directory = root repo ini.
#
# Catatan dependensi (umumnya, bisa beda per versi kernel):
#   - CONFIG_IP6_NF_NAT membutuhkan CONFIG_IP6_NF_IPTABLES, CONFIG_NF_CONNTRACK
#     dan CONFIG_NETFILTER_ADVANCED.
#   - CONFIG_IP6_NF_TARGET_MASQUERADE membutuhkan CONFIG_IP6_NF_NAT.
#   - CONFIG_CFS_BANDWIDTH membutuhkan CONFIG_FAIR_GROUP_SCHED dan CONFIG_CGROUP_SCHED.
#   - CONFIG_CGROUP_PIDS membutuhkan CONFIG_CGROUPS.
# Kalau suatu opsi hilang setelah build, cek dependensinya di /proc/config.gz.
set -euo pipefail

OPTIONS=(
  "CONFIG_MACVLAN=y"
  "CONFIG_IP6_NF_NAT=y"
  "CONFIG_IP6_NF_TARGET_MASQUERADE=y"
  "CONFIG_USER_NS=y"
)

: "${DEFCONFIG:?DEFCONFIG tidak diset - skrip ini harus dijalankan oleh workflow ABK}"

if [[ ! -f "$DEFCONFIG" ]]; then
  echo "ERROR: defconfig tidak ditemukan: $DEFCONFIG" >&2
  exit 1
fi

echo "== custom-kconfig: stage=${CUSTOM_EXTERNAL_MODULE_STAGE:-unknown}, CONFIG=${CONFIG:-unknown}"
echo "== defconfig: $DEFCONFIG"

for entry in "${OPTIONS[@]}"; do
  key="${entry%%=*}"
  # Hapus nilai lama (=y/=m/=n) dan bentuk "# CONFIG_X is not set", lalu tulis ulang.
  # Dengan begitu skrip aman dijalankan berulang (idempotent).
  sed -i -e "/^${key}=/d" -e "/^# ${key} is not set\$/d" "$DEFCONFIG"
  echo "$entry" >> "$DEFCONFIG"
  echo "  set: $entry"
done

# Verifikasi: gagal dengan jelas kalau ada opsi yang tidak masuk.
missing=0
for entry in "${OPTIONS[@]}"; do
  if ! grep -qxF "$entry" "$DEFCONFIG"; then
    echo "ERROR: gagal menerapkan $entry" >&2
    missing=1
  fi
done

exit "$missing"
