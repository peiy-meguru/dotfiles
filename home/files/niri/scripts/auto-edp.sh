#!/bin/bash
# auto-edp.sh — 有外接 DP-1 时关闭笔记本内屏；没有外接屏时自动开启内屏。
#
# niri 不支持条件化 output 配置，所以用这个守护脚本每 2 秒幂等地校正一次：
#   DP-1 已连接且已启用  -> 关闭 eDP-1
#   否则                 -> 开启 eDP-1
# 由 niri spawn-at-startup 启动；niri 退出后脚本自动结束。
set -u

INTERVAL=2
fails=0

while :; do
    if ! out=$(niri msg --json outputs 2>/dev/null); then
        # niri 不在运行（重启中/已退出）：连续失败 3 次就退出
        fails=$((fails + 1))
        [ "$fails" -ge 3 ] && exit 0
        sleep "$INTERVAL"
        continue
    fi
    fails=0

    dp_on=$(printf '%s' "$out"  | jq -r 'if .["DP-1"]  and .["DP-1"].logical  then 1 else 0 end' 2>/dev/null)
    edp_on=$(printf '%s' "$out" | jq -r 'if .["eDP-1"] and .["eDP-1"].logical then 1 else 0 end' 2>/dev/null)

    if [ "$dp_on" = "1" ] && [ "$edp_on" = "1" ]; then
        niri msg output eDP-1 off >/dev/null 2>&1
    elif [ "$dp_on" = "0" ] && [ "$edp_on" = "0" ]; then
        niri msg output eDP-1 on >/dev/null 2>&1
    fi

    sleep "$INTERVAL"
done
