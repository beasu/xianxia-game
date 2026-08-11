# 修仙演义 · Xianxia Game

基于 **Heaps.io** + **HaxeUI** 开发的 2D 修仙动作游戏。

## 特性

- **10 种法术**：三昧真火、九天玄雷、玄冰诀、万剑归宗、天雷破、袖里乾坤、莲花绽放、天罡北斗、分影术、乾坤大挪移
- **5 种中国阵法**：八卦阵、五行阵、太极图、天罡北斗阵、九宫格阵
- **境界修炼体系**：练气期 → 筑基期 → 金丹期 → 元婴期 → 化神期
- **4 种敌人**：魔修、妖兽、魔将、邪仙
- 粒子特效系统，动漫风格法术表现

## 环境要求

- [Haxe](https://haxe.org/) 4.x
- [Heaps](https://heaps.io) 2.1.0
- HaxeUI

## 编译运行

```bash
# 安装依赖
haxelib install heaps
haxelib install haxeui-core
haxelib install haxeui-heaps

# 编译
haxe compile-js.hxml

# 运行（在 bin/ 目录启动 HTTP 服务器）
cd bin
python -m http.server 4567
# 浏览器访问 http://127.0.0.1:4567
```

## 操作

| 按键 | 功能 |
|------|------|
| WASD | 移动 |
| Q-P | 释放法术 |
| 1-5 | 切换阵法 |
| 鼠标左键 | 施放九天玄雷 |
