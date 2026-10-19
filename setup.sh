#!/usr/bin/env bash
# ABK custom external module: CPU + PID cgroup limits for GKI android12-5.10
#
# Applies fix_cgroup_limits_kabi_5.10.236.patch to $KERNEL_ROOT/common and
# enables these options in the GKI defconfig:
#   - CONFIG_CFS_BANDWIDTH, CONFIG_CGROUP_PIDS   (required by the patch)
#   - CONFIG_MACVLAN, CONFIG_USER_NS             (extra)
#   - CONFIG_IP6_NF_NAT, CONFIG_IP6_NF_TARGET_MASQUERADE (extra, IPv6 NAT)
# Use it with the stage "after_patch" (before_build also works).
#
#   https://github.com/<you>/<this-repo>;after_patch
#
# The script is idempotent: if the patch is already applied it is skipped, and
# options that are already =y are left alone.
#
# Dependency notes (can differ per kernel version). The defconfig is later
# expanded by Kconfig, which silently drops an option whose dependencies are
# not met:
#   - CONFIG_IP6_NF_NAT needs CONFIG_IP6_NF_IPTABLES, CONFIG_NF_CONNTRACK and
#     CONFIG_NETFILTER_ADVANCED.
#   - CONFIG_IP6_NF_TARGET_MASQUERADE needs CONFIG_IP6_NF_NAT.
#   - CONFIG_CFS_BANDWIDTH needs CONFIG_FAIR_GROUP_SCHED and CONFIG_CGROUP_SCHED.
#   - CONFIG_CGROUP_PIDS needs CONFIG_CGROUPS.
# If an option is missing after the build, check /proc/config.gz.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$HERE/fix_cgroup_limits_kabi_5.10.236.patch"

# Options that must end up as "=y" in the defconfig.
CONFIG_OPTIONS=(
  # required by the cgroup limits patch
  CONFIG_CFS_BANDWIDTH
  CONFIG_CGROUP_PIDS
  # extra options
  CONFIG_MACVLAN
  CONFIG_IP6_NF_NAT
  CONFIG_IP6_NF_TARGET_MASQUERADE
  CONFIG_USER_NS
)

: "${KERNEL_ROOT:?KERNEL_ROOT is not set - run this as an ABK custom external module}"
SRC="$KERNEL_ROOT/common"
DEFCONFIG="${DEFCONFIG:-$SRC/arch/arm64/configs/gki_defconfig}"

fail() {
  echo "::error::cgroup-limits: $*"
  exit 1
}

[ -f "$PATCH_FILE" ] || fail "patch file not found: $PATCH_FILE"
[ -f "$SRC/Makefile" ] || fail "kernel source not found: $SRC"
[ -f "$DEFCONFIG" ] || fail "defconfig not found: $DEFCONFIG"

# --- only for the 5.10 tree this patch was ported and verified against -------
VERSION="$(awk -F' *= *' '$1=="VERSION"{print $2; exit}' "$SRC/Makefile")"
PATCHLEVEL="$(awk -F' *= *' '$1=="PATCHLEVEL"{print $2; exit}' "$SRC/Makefile")"
SUBLEVEL="$(awk -F' *= *' '$1=="SUBLEVEL"{print $2; exit}' "$SRC/Makefile")"
echo "cgroup-limits: kernel is $VERSION.$PATCHLEVEL.$SUBLEVEL, stage=${CUSTOM_EXTERNAL_MODULE_STAGE:-unknown}"
if [ "$VERSION.$PATCHLEVEL" != "5.10" ]; then
  fail "this patch is only for Linux 5.10 (found $VERSION.$PATCHLEVEL); use the matching patch for 5.15/6.1/6.6 instead"
fi
if [ "$SUBLEVEL" != "236" ]; then
  echo "::warning::cgroup-limits: patch was verified on 5.10.236, this tree is 5.10.$SUBLEVEL; the dry-run below decides"
fi

# --- apply the patch (idempotent) ---------------------------------------------
cd "$SRC"
# -F0: no fuzz. A hunk must match its context exactly, otherwise it could end
# up in the wrong place of a modified tree. The dry-run makes it all-or-nothing.
PATCH_OPTS=(-p1 -F0 --no-backup-if-mismatch)
if patch "${PATCH_OPTS[@]}" --reverse --dry-run -s < "$PATCH_FILE" >/dev/null 2>&1; then
  echo "cgroup-limits: patch already applied, skipping"
elif patch "${PATCH_OPTS[@]}" --forward --dry-run -s < "$PATCH_FILE" >/dev/null 2>&1; then
  patch "${PATCH_OPTS[@]}" --forward < "$PATCH_FILE"
  echo "cgroup-limits: patch applied"
else
  echo "---- dry-run output ----"
  patch "${PATCH_OPTS[@]}" --forward --dry-run < "$PATCH_FILE" || true
  fail "patch does not apply. Another step changed kernel/cgroup, kernel/sched or include/linux/cgroup*.h, or task_group KABI reserve 2 is already in use. Nothing was modified."
fi

grep -q "CGROUP_SUBSYS_KABI_COUNT" include/linux/cgroup-defs.h || fail "marker missing after applying the patch"
grep -q "cfs_bandwidth_state" kernel/sched/sched.h || fail "marker missing after applying the patch"

# --- enable the options (same method ABK uses for its features) ---------------
enable_config() {
  local cfg="$1"
  if grep -qxF "${cfg}=y" "$DEFCONFIG"; then
    echo "cgroup-limits: $cfg already enabled"
  elif grep -qxF "# ${cfg} is not set" "$DEFCONFIG"; then
    sed -i "s/^# ${cfg} is not set$/${cfg}=y/" "$DEFCONFIG"
    echo "cgroup-limits: switched on $cfg"
  elif grep -q "^${cfg}=" "$DEFCONFIG"; then
    # currently =m / =n / another value: replace it, never leave a duplicate
    sed -i "s/^${cfg}=.*$/${cfg}=y/" "$DEFCONFIG"
    echo "cgroup-limits: changed $cfg to =y"
  else
    echo "${cfg}=y" >> "$DEFCONFIG"
    echo "cgroup-limits: added $cfg"
  fi
}

for cfg in "${CONFIG_OPTIONS[@]}"; do
  enable_config "$cfg"
done

# --- verify: fail clearly if an option did not make it in ---------------------
missing=0
for cfg in "${CONFIG_OPTIONS[@]}"; do
  if ! grep -qxF "${cfg}=y" "$DEFCONFIG"; then
    echo "::error::cgroup-limits: failed to set ${cfg}=y"
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

echo "cgroup-limits: done"
