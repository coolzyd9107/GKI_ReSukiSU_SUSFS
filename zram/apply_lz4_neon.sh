#!/bin/bash
# ================================================================
# apply_lz4_neon.sh
# 为 LZ4 解压缩调用添加 ARM64 NEON 加速条件编译
# 替代原来 4 个版本特定的 patch 文件，使用正则匹配而非固定行号
#
# 用法: 在内核源码根目录（common/）执行
#   bash /path/to/apply_lz4_neon.sh
# ================================================================
set -euo pipefail

PATCHED=0
SKIPPED=0
FAILED=0

# 检查是否已修补
already_patched() {
  grep -q "LZ4_arm64_decompress_safe" "$1" 2>/dev/null
}

# ---- 1. crypto/lz4.c 和 crypto/lz4hc.c ----
# 模式一致：int out_len = LZ4_decompress_safe(src, dst, slen, *dlen);
for file in crypto/lz4.c crypto/lz4hc.c; do
  if [ ! -f "$file" ]; then
    echo "跳过（不存在）: $file"; ((SKIPPED++)) || true; continue
  fi
  if already_patched "$file"; then
    echo "跳过（已修补）: $file"; ((SKIPPED++)) || true; continue
  fi

  perl -i -pe '
    if (/int out_len = LZ4_decompress_safe\(src, dst, slen, \*dlen\);/) {
      $_ = "\tint out_len;\n\n"
         . "#if defined(CONFIG_ARM64) && defined(CONFIG_KERNEL_MODE_NEON)\n"
         . "\tout_len = LZ4_arm64_decompress_safe(src, dst, slen, *dlen, false);\n"
         . "#else\n"
         . "\tout_len = LZ4_decompress_safe(src, dst, slen, *dlen);\n"
         . "#endif\n";
    }
  ' "$file"

  if already_patched "$file"; then
    echo "已修补: $file"; ((PATCHED++)) || true
  else
    echo "::error::修补失败: $file"; ((FAILED++)) || true
  fi
done

# ---- 2. fs/f2fs/compress.c ----
# 将 LZ4_decompress_safe(dic->cbuf->cdata, ...) 替换为条件编译版本
file="fs/f2fs/compress.c"
if [ ! -f "$file" ]; then
  echo "跳过（不存在）: $file"; ((SKIPPED++)) || true
elif already_patched "$file"; then
  echo "跳过（已修补）: $file"; ((SKIPPED++)) || true
else
  perl -i -0777 -pe '
    s{(\t)ret = LZ4_decompress_safe\(dic->cbuf->cdata, dic->rbuf,\s*\n\s*dic->clen, dic->rlen\);}
     {#if defined(CONFIG_ARM64) && defined(CONFIG_KERNEL_MODE_NEON)\n${1}ret = LZ4_arm64_decompress_safe(dic->cbuf->cdata, dic->rbuf,\n\t\t\t\t\t\tdic->clen, dic->rlen, false);\n#else\n${1}ret = LZ4_decompress_safe(dic->cbuf->cdata, dic->rbuf,\n\t\t\t\t\t\tdic->clen, dic->rlen, false);\n#endif}
  ' "$file"

  if already_patched "$file"; then
    echo "已修补: $file"; ((PATCHED++)) || true
  else
    echo "::error::修补失败: $file"; ((FAILED++)) || true
  fi
fi

# ---- 3. fs/incfs/data_mgmt.c（部分内核版本才有） ----
file="fs/incfs/data_mgmt.c"
if [ ! -f "$file" ]; then
  echo "跳过（不存在）: $file"; ((SKIPPED++)) || true
elif already_patched "$file"; then
  echo "跳过（已修补）: $file"; ((SKIPPED++)) || true
else
  perl -i -0777 -pe '
    s{(\t+)result = LZ4_decompress_safe\(src\.data, dst\.data, src\.len,\s*\n\s*dst\.len\);}
     {#if defined(CONFIG_ARM64) && defined(CONFIG_KERNEL_MODE_NEON)\n${1}result = LZ4_arm64_decompress_safe(src.data, dst.data, src.len, dst.len, false);\n#else\n${1}result = LZ4_decompress_safe(src.data, dst.data, src.len, dst.len);\n#endif}
  ' "$file"

  if already_patched "$file"; then
    echo "已修补: $file"; ((PATCHED++)) || true
  else
    echo "::error::修补失败: $file"; ((FAILED++)) || true
  fi
fi

echo ""
echo "=== LZ4 NEON 补丁完成: ${PATCHED} 成功, ${SKIPPED} 跳过, ${FAILED} 失败 ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
