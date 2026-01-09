#!/bin/bash
# =====================================================
# 机场服务检测脚本 - 本地版 v8.4
# 用于检测当前服务器是否会被识别为"机场服务"
# =====================================================

SEARCH_PATHS="/etc /opt /usr/local/etc /root"

# ===== 强实体定义 =====
NODE_CONTROLLERS="XrayR|V2bX|soga|sspanel-node"
PANEL_CONTROLLERS="v2board|xboard|ppanel|sspanel|xb"

# ===== 只认"对接级别字段" =====
LINK_FIELDS="panel_url|node_id|webapi|backend_url|api_key|token"

# ===== 明确排除 =====
EXCLUDE_UI="x-ui|3x-ui|hiddify|v2ray-ui"
EXCLUDE_FILES="geoip.dat|geosite.dat|\.mmdb$"

echo "======================================================"
echo " 机场服务检测脚本 - 本地版 v8.4"
echo "======================================================"
echo
echo "🔍 正在检测当前服务器..."
echo

# -------- 机场节点程序 --------
echo "📋 检测节点程序..."
NODE_BIN=$(ls /usr/bin /usr/local/bin /opt /etc 2>/dev/null \
  | grep -Ei "$NODE_CONTROLLERS" | head -n 1)

# -------- 机场面板程序 --------
echo "📋 检测面板程序..."
PANEL_BIN=$(ls /var/www /opt /usr/share 2>/dev/null \
  | grep -Ei "$PANEL_CONTROLLERS" | head -n 1)

# -------- 对接配置文件（只列文件） --------
echo "📋 检测对接配置文件..."
CONFIG_FILES=$(grep -R -I -l -E "$LINK_FIELDS" $SEARCH_PATHS 2>/dev/null \
  | grep -Ev "$EXCLUDE_FILES" \
  | grep -Ev "$EXCLUDE_UI" \
  | sort -u | head -n 10)

# -------- V2bX 文件内容检测 --------
# 搜索范围包括：基础路径 + 节点程序目录 + 面板程序目录
V2BX_SEARCH_PATHS="$SEARCH_PATHS /usr/bin /usr/local/bin /var/www /usr/share"
SELF_SCRIPT=$(realpath "$0" 2>/dev/null || echo "$0")
echo "📋 检测文件内容中的 V2bX 特征..."
V2BX_FILES=$(grep -R -I -l -i "v2bx" $V2BX_SEARCH_PATHS 2>/dev/null \
  | grep -Ev "$EXCLUDE_FILES" \
  | grep -v "$SELF_SCRIPT" \
  | sort -u | head -n 10)

RESULT="CLEAN"

# -------- 判定逻辑（极度收敛） --------
if [ -n "$V2BX_FILES" ]; then
  RESULT="CONFIRMED"
elif [ -n "$PANEL_BIN" ]; then
  RESULT="CONFIRMED"
elif [ -n "$NODE_BIN" ] && [ -n "$CONFIG_FILES" ]; then
  RESULT="CONFIRMED"
elif [ -n "$NODE_BIN" ]; then
  RESULT="SUSPECT"
fi

echo
echo "======================================================"
echo "                    检测结果"
echo "======================================================"
echo

# -------- 输出 --------
case "$RESULT" in
  CONFIRMED)
    echo "🚨 结论：确定 - 机场服务"
    echo "   ⚠️  当前服务器会被检测脚本识别为机场服务！"
    ;;
  SUSPECT)
    echo "⚠️ 结论：可疑 - 疑似机场服务"
    echo "   节点程序存在，但未发现对接配置"
    ;;
  CLEAN)
    echo "✅ 结论：安全 - 未发现机场服务特征"
    echo "   当前服务器不会被检测脚本识别为机场服务"
    ;;
esac

echo
echo "======================================================"
echo "                    详细信息"
echo "======================================================"

if [ -n "$NODE_BIN" ]; then
  echo
  echo "🧩 检测到的节点程序："
  echo "   $NODE_BIN"
else
  echo
  echo "🧩 节点程序：未检测到"
fi

if [ -n "$PANEL_BIN" ]; then
  echo
  echo "🖥 检测到的面板程序："
  echo "   $PANEL_BIN"
else
  echo
  echo "🖥 面板程序：未检测到"
fi

if [ -n "$CONFIG_FILES" ]; then
  echo
  echo "📂 检测到的对接配置文件："
  echo "$CONFIG_FILES" | sed 's/^/   - /'
else
  echo
  echo "📂 对接配置文件：未检测到"
fi

if [ -n "$V2BX_FILES" ]; then
  echo
  echo "🔴 检测到包含 V2bX 特征的文件："
  echo "$V2BX_FILES" | sed 's/^/   - /'
else
  echo
  echo "🔴 V2bX 特征文件：未检测到"
fi

echo
echo "======================================================"
echo " 检测完成 (本地版 v8.4)"
echo "======================================================"
