#!/usr/bin/env bash
set -euo pipefail

kernel_version="${1:-}"
kernel_sublevel="${2:-}"
patch_dir="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
rtmutex_file="kernel/locking/rtmutex.c"

if [ -z "$kernel_version" ] || [ -z "$kernel_sublevel" ]; then
  echo "Usage: $0 <kernel-version> <actual-sublevel> [patch-dir]" >&2
  exit 2
fi

if [ ! -f "$rtmutex_file" ]; then
  echo "ERROR: $rtmutex_file not found. Run this from kernel_platform/common." >&2
  exit 1
fi

try_apply_patch() {
  local patch_file="$1"
  local log_file

  log_file="$(mktemp "${TMPDIR:-/tmp}/cve-2026-43499.XXXXXX")"

  # Never let patch auto-reverse a partially matching helper patch.  A
  # partially backported Android tree must use the explicit, idempotent
  # fallback below instead.
  if patch --batch --forward --dry-run -p1 < "$patch_file" >"$log_file" 2>&1; then
    patch --batch --forward -p1 < "$patch_file"
    rm -f "$log_file"
    return 0
  fi

  cat "$log_file" >&2
  rm -f "$log_file"
  return 1
}

replace_proxy_cleanup_condition() {
  local target=""
  local candidate
  local tmp_file

  for candidate in kernel/locking/rtmutex_api.c kernel/locking/rtmutex.c; do
    if [ -f "$candidate" ] &&
       grep -q 'ret = __rt_mutex_start_proxy_lock' "$candidate"; then
      target="$candidate"
      break
    fi
  done

  if [ -z "$target" ]; then
    # Older 5.15-style rtmutex trees have no proxy-lock wrapper, so the
    # ret < 0 follow-up is not applicable there.
    echo "CVE-2026-53163 proxy cleanup path is absent; no change required."
    return 0
  fi

  if grep -q 'if (unlikely(ret < 0))' "$target"; then
    echo "CVE-2026-53163 proxy cleanup fix already present."
    return 0
  fi

  tmp_file="$(mktemp)"
  if ! awk '
    /ret = __rt_mutex_start_proxy_lock/ { in_proxy_start = 1 }
    in_proxy_start && /if \(unlikely\(ret\)\)/ {
      sub(/if \(unlikely\(ret\)\)/, "if (unlikely(ret < 0))")
      replaced++
      in_proxy_start = 0
    }
    { print }
    END { if (replaced != 1) exit 42 }
  ' "$target" > "$tmp_file"; then
    rm -f "$tmp_file"
    echo "ERROR: failed to locate the proxy cleanup condition in $target." >&2
    return 1
  fi

  mv "$tmp_file" "$target"
  echo "Applied CVE-2026-53163 proxy cleanup fix to $target."
}

ensure_remove_waiter_null_guard() {
  local tmp_file

  if grep -q 'if (!waiter_task) /\* never enqueued \*/' "$rtmutex_file"; then
    echo "CVE-2026-53163 remove_waiter() NULL guard already present."
    return 0
  fi

  tmp_file="$(mktemp)"
  if ! awk '
    /^static .*remove_waiter\(/ { in_remove_waiter = 1 }
    {
      print
      if (in_remove_waiter && /lockdep_assert_held\(&lock->wait_lock\);/) {
        match($0, /^[[:space:]]*/)
        indent = substr($0, RSTART, RLENGTH)
        print ""
        print indent "if (!waiter_task) /* never enqueued */"
        print indent "\treturn;"
        inserted++
        in_remove_waiter = 0
      }
    }
    END { if (inserted != 1) exit 42 }
  ' "$rtmutex_file" > "$tmp_file"; then
    rm -f "$tmp_file"
    echo "ERROR: failed to locate remove_waiter() in $rtmutex_file." >&2
    return 1
  fi

  mv "$tmp_file" "$rtmutex_file"
  echo "Applied CVE-2026-53163 remove_waiter() NULL guard."
}

ensure_followup_fixes() {
  ensure_remove_waiter_null_guard
  replace_proxy_cleanup_condition
}

append_file() {
  local target="$1"
  local insert_file="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  awk -v insert_file="$insert_file" '
    { print }
    END {
      while ((getline line < insert_file) > 0)
        print line
      close(insert_file)
    }
  ' "$target" > "$tmp_file"
  mv "$tmp_file" "$target"
}

insert_file_before_last_endif() {
  local target="$1"
  local insert_file="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  awk -v insert_file="$insert_file" '
    { lines[NR] = $0; if ($0 ~ /^#endif/) last_endif = NR }
    function emit() {
      while ((getline line < insert_file) > 0)
        print line
      close(insert_file)
    }
    END {
      for (i = 1; i <= NR; i++) {
        if (i == last_endif)
          emit()
        print lines[i]
      }
      if (!last_endif)
        emit()
    }
  ' "$target" > "$tmp_file"
  mv "$tmp_file" "$target"
}

install_scoped_guard_support() {
  local tmp_file

  if [ ! -f "$patch_dir/scoped_guard_cleanup.h" ]; then
    echo "ERROR: scoped_guard cleanup header not found." >&2
    return 1
  fi

  if [ ! -f include/linux/cleanup.h ] ||
     ! grep -q 'scoped_guard' include/linux/cleanup.h; then
    cp "$patch_dir/scoped_guard_cleanup.h" include/linux/cleanup.h
  fi

  if [ -f include/linux/compiler_attributes.h ]; then
    if ! grep -q '^#define __cleanup(func)' include/linux/compiler_attributes.h; then
      insert_file_before_last_endif include/linux/compiler_attributes.h "$patch_dir/scoped_guard_compiler_cleanup.txt"
    fi
  elif [ -f include/linux/compiler.h ]; then
    if ! grep -q '^#define __cleanup(func)' include/linux/compiler.h; then
      append_file include/linux/compiler.h "$patch_dir/scoped_guard_compiler_cleanup.txt"
    fi
  else
    echo "ERROR: neither compiler_attributes.h nor compiler.h found." >&2
    return 1
  fi

  if [ -f include/linux/compiler-clang.h ] &&
     ! grep -q 'Clang prior to 17' include/linux/compiler-clang.h; then
    append_file include/linux/compiler-clang.h "$patch_dir/scoped_guard_compiler_clang.txt"
  fi

  if ! grep -q '#include <linux/cleanup.h>' include/linux/spinlock.h; then
    tmp_file="$(mktemp)"
    awk '
      { print }
      !done && /^#include <linux\/lockdep.h>/ {
        print "#include <linux/cleanup.h>"
        done = 1
      }
      !done && /^#include <linux\/bottom_half.h>/ {
        print "#include <linux/cleanup.h>"
        done = 1
      }
      END {
        if (!done)
          print "#include <linux/cleanup.h>"
      }
    ' include/linux/spinlock.h > "$tmp_file"
    mv "$tmp_file" include/linux/spinlock.h
  fi

  if ! grep -q 'DEFINE_LOCK_GUARD_1(raw_spinlock' include/linux/spinlock.h; then
    tmp_file="$(mktemp)"
    awk -v insert_file="$patch_dir/scoped_guard_spinlock_guards.txt" '
      function emit() {
        while ((getline line < insert_file) > 0)
          print line
        close(insert_file)
      }
      !done && /^#undef __LINUX_INSIDE_SPINLOCK_H/ {
        emit()
        done = 1
      }
      !done && /^#endif .*__LINUX_SPINLOCK_H/ {
        emit()
        done = 1
      }
      { print }
      END {
        if (!done)
          emit()
      }
    ' include/linux/spinlock.h > "$tmp_file"
    mv "$tmp_file" include/linux/spinlock.h
  fi
}

ensure_scoped_guard_support() {
  if grep -qs 'DEFINE_LOCK_GUARD_1(raw_spinlock' include/linux/spinlock.h &&
     grep -qs 'scoped_guard' include/linux/cleanup.h; then
    return 0
  fi

  local guard_patch="$patch_dir/cve-2026-43499-guards.patch"
  if [ ! -f "$guard_patch" ]; then
    echo "ERROR: scoped_guard helper patch not found: $guard_patch" >&2
    return 1
  fi

  echo "Applying scoped_guard/raw_spinlock helper backport..."
  if try_apply_patch "$guard_patch"; then
    return 0
  fi

  echo "Patch helper did not match; installing scoped_guard support directly..."
  install_scoped_guard_support
}

ensure_rtmutex_c99() {
  case "$kernel_version" in
    5.10|5.15)
      ;;
    *)
      return 0
      ;;
  esac

  local makefile="kernel/locking/Makefile"
  if [ ! -f "$makefile" ]; then
    echo "ERROR: $makefile not found." >&2
    return 1
  fi

  local objects=(
    rtmutex.o
    rtmutex_api.o
    rwsem.o
    ww_rt_mutex.o
    spinlock_rt.o
  )
  local additions_file
  local object
  local escaped_object
  additions_file="$(mktemp)"

  for object in "${objects[@]}"; do
    escaped_object="${object//./\\.}"
    if ! grep -q "^CFLAGS_REMOVE_${escaped_object} .*std=gnu89" "$makefile"; then
      echo "CFLAGS_REMOVE_${object} += -std=gnu89" >> "$additions_file"
    fi
    if ! grep -q "^CFLAGS_${escaped_object} .*std=gnu99" "$makefile"; then
      echo "CFLAGS_${object} += -std=gnu99" >> "$additions_file"
    fi
  done

  if [ ! -s "$additions_file" ]; then
    rm -f "$additions_file"
    return 0
  fi

  echo "Forcing rtmutex include units to gnu99 for scoped_guard on 5.x..."
  local tmp_makefile
  tmp_makefile="$(mktemp)"
  awk -v insert_file="$additions_file" '
    function emit() {
      while ((getline line < insert_file) > 0)
        print line
      close(insert_file)
    }
    !done && /^obj-\$\(CONFIG_RT_MUTEXES\).*rtmutex/ {
      emit()
      done = 1
    }
    { print }
    END {
      if (!done)
        emit()
    }
  ' "$makefile" > "$tmp_makefile"
  mv "$tmp_makefile" "$makefile"
  rm -f "$additions_file"
}

patch_chain_is_required() {
  # The second threshold includes CVE-2026-53163, which fixes the regression
  # introduced by the original CVE-2026-43499 backport.
  case "$kernel_version" in
    5.10|5.15)
      # Neither maintained Android 5.x line received the upstream backport.
      return 0
      ;;
    6.1)
      (( kernel_sublevel < 177 ))
      ;;
    6.6)
      (( kernel_sublevel < 144 ))
      ;;
    6.12)
      (( kernel_sublevel < 95 ))
      ;;
    *)
      return 1
      ;;
  esac
}

case "$kernel_version" in
  5.10|5.15)
    ;;
  6.1|6.6|6.12)
    if [[ ! "$kernel_sublevel" =~ ^[0-9]+$ ]]; then
      echo "ERROR: non-numeric SUBLEVEL for $kernel_version: $kernel_sublevel" >&2
      exit 2
    fi
    ;;
  *)
    echo "CVE-2026-43499: $kernel_version is outside this repository's supported GKI lines; skipping."
    exit 0
    ;;
esac

if ! patch_chain_is_required; then
  echo "CVE-2026-43499/CVE-2026-53163 fix chain is upstream in $kernel_version.$kernel_sublevel; skipping."
  exit 0
fi

case "$kernel_version" in
  5.10)
    primary_patch="$patch_dir/cve-2026-43499-rtmutex-5.10.patch"
    fallback_patch="$patch_dir/cve-2026-43499-rtmutex-5.15.patch"
    ;;
  5.15)
    primary_patch="$patch_dir/cve-2026-43499-rtmutex-5.15.patch"
    fallback_patch=""
    ;;
  6.1|6.6)
    primary_patch="$patch_dir/cve-2026-43499-rtmutex-6.1-6.6.patch"
    fallback_patch=""
    ;;
  6.12)
    primary_patch="$patch_dir/cve-2026-43499-rtmutex-6.12.patch"
    fallback_patch=""
    ;;
  *)
    echo "ERROR: unsupported kernel version for CVE-2026-43499 patch: $kernel_version" >&2
    exit 1
    ;;
esac

if [ ! -f "$primary_patch" ]; then
  echo "ERROR: patch file not found: $primary_patch" >&2
  exit 1
fi

echo "Applying the CVE-2026-43499 rtmutex fix chain for kernel $kernel_version..."

if grep -q 'struct task_struct \*waiter_task = waiter->task;' "$rtmutex_file"; then
  echo "CVE-2026-43499 rtmutex fix already present."
  if grep -q 'scoped_guard(raw_spinlock' "$rtmutex_file"; then
    ensure_scoped_guard_support
    ensure_rtmutex_c99
  fi
  ensure_followup_fixes
  echo "CVE-2026-43499/CVE-2026-53163 fix chain is complete."
  exit 0
fi

ensure_scoped_guard_support
ensure_rtmutex_c99

if try_apply_patch "$primary_patch"; then
  echo "CVE-2026-43499 rtmutex fix applied."
  ensure_followup_fixes
  echo "CVE-2026-43499/CVE-2026-53163 fix chain is complete."
  exit 0
fi

if [ -n "${fallback_patch:-}" ] && [ -f "$fallback_patch" ]; then
  echo "Primary patch did not match; trying fallback shape: $(basename "$fallback_patch")"
  if try_apply_patch "$fallback_patch"; then
    echo "CVE-2026-43499 rtmutex fix applied with fallback patch."
    ensure_followup_fixes
    echo "CVE-2026-43499/CVE-2026-53163 fix chain is complete."
    exit 0
  fi
fi

echo "ERROR: failed to apply CVE-2026-43499 rtmutex fix." >&2
exit 1
