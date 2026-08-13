package ecs;

// ============================================================
//  TerrainSystem.hx - 地形法则系统
//  priority: 14 (天气之后, 生态之前)
//
//  地形类型: mountain(山脉) / water(水域) / plain(平原) / forest(森林) / desert(沙漠)
//  影响:
//    - 移动速度: 山脉0.6, 水域0.5(非冰系), 平原1.0, 森林0.85, 沙漠0.7
//    - 修炼效率: 山脉1.3(灵气充裕), 水域1.1, 平原0.9, 森林1.2, 沙漠0.6
//    - 元素增幅: 山脉->土系, 水域->水系, 森林->木系, 沙漠->火系, 平原->无
//    - 摩擦系数: 山脉0.9(高摩擦/短击退), 冰面0.95, 平原0.85, 沙漠0.7(低摩擦/长击退)
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class TerrainSystem implements ISystem {
    public var priority:Int = 14;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var gridSize:Float = 400;     // 地形网格大小(比灵气网格大)

    // 地形网格
    public var grid:Array<Array<TerrainCell>> = [];
    public var gridCols:Int = 0;
    public var gridRows:Int = 0;

    // 地形配置
    var terrainConfigs:Map<String, {moveMul:Float, cultMul:Float, element:String, elemMul:Float, friction:Float}>;

    public function new() {
        terrainConfigs = [
            "mountain" => {moveMul: 0.6, cultMul: 1.3, element: "earth", elemMul: 1.3, friction: 0.90},
            "water"    => {moveMul: 0.5, cultMul: 1.1, element: "water", elemMul: 1.3, friction: 0.80},
            "plain"    => {moveMul: 1.0, cultMul: 0.9, element: "none",  elemMul: 1.0, friction: 0.85},
            "forest"   => {moveMul: 0.85, cultMul: 1.2, element: "wood",  elemMul: 1.3, friction: 0.88},
            "desert"   => {moveMul: 0.7, cultMul: 0.6, element: "fire",  elemMul: 1.4, friction: 0.70}
        ];
    }

    public function update(world:WorldEngine, dt:Float):Void {
        // 懒初始化
        if (grid.length == 0) {
            initGrid(world.worldWidth, world.worldHeight);
        }

        // 对所有实体应用地形影响
        for (e in world.entities) {
            if (!e.alive) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;

            var cell = getCellAt(pos.x, pos.y);
            if (cell == null) continue;

            // 修炼效率修正
            var cult = e.get(CultivationComp);
            var intent = e.get(IntentComp);
            if (cult != null && intent != null && intent.currentIntent == Cultivate) {
                // 修炼中的实体获得地形修炼加成
                cult.exp += (cell.cultivateMul - 1.0) * cult.talent * 2 * dt * 10;
            }

            // 移动速度修正: 直接调整速度(与 IntentResolutionSystem 配合)
            // 这里只做标记, 实际速度修正由 IntentResolutionSystem 读取
            // 或者直接修正 vx/vy
            if (!e.isPlayer) {
                pos.vx *= cell.moveSpeedMul;
                pos.vy *= cell.moveSpeedMul;
            }
        }

        // 每日: 地形微调(灵脉附近的森林茂盛, 沙漠扩张等)
        if (world.tickCount % world.ticksPerDay == 0) {
            dailyTerrainShift(world);
        }
    }

    function initGrid(worldW:Float, worldH:Float):Void {
        gridCols = Math.ceil(worldW / gridSize);
        gridRows = Math.ceil(worldH / gridSize);
        grid = [];

        // 用柏林噪声风格的地形生成(简化版: 基于距离的多层噪声)
        for (gy in 0...gridRows) {
            var row:Array<TerrainCell> = [];
            for (gx in 0...gridCols) {
                var cell = new TerrainCell(gx, gy);

                // 简化地形生成: 基于坐标的伪噪声
                var n = noise(gx, gy);
                var n2 = noise(gx + 100, gy + 100);

                if (n > 0.6) {
                    cell.type = "mountain";
                } else if (n < 0.25) {
                    cell.type = "water";
                } else if (n2 > 0.65) {
                    cell.type = "forest";
                } else if (n2 < 0.3) {
                    cell.type = "desert";
                } else {
                    cell.type = "plain";
                }

                applyTerrainConfig(cell);
                row.push(cell);
            }
            grid.push(row);
        }
    }

    function applyTerrainConfig(cell:TerrainCell):Void {
        var cfg = terrainConfigs[cell.type];
        if (cfg == null) return;
        cell.moveSpeedMul = cfg.moveMul;
        cell.cultivateMul = cfg.cultMul;
        cell.elementBonus = cfg.element;
        cell.elementMul = cfg.elemMul;
        cell.friction = cfg.friction;
    }

    function dailyTerrainShift(world:WorldEngine):Void {
        // 灵脉附近的平原有概率变成森林
        for (v in world.spiritVeins) {
            var cell = getCellAt(v.x, v.y);
            if (cell != null && cell.type == "plain" && Math.random() < 0.05) {
                cell.type = "forest";
                applyTerrainConfig(cell);
            }
        }
    }

    // 简化版2D噪声
    function noise(x:Float, y:Float):Float {
        var n = Math.sin(x * 0.7 + y * 1.3) * 0.5
              + Math.sin(x * 0.3 - y * 0.5) * 0.3
              + Math.sin(x * 1.1 + y * 0.9) * 0.2;
        return (n + 1.0) * 0.5;
    }

    // --- 外部接口 ---
    public function getCellAt(x:Float, y:Float):TerrainCell {
        var gx = Std.int(x / gridSize);
        var gy = Std.int(y / gridSize);
        if (gy < 0 || gy >= gridRows || gx < 0 || gx >= gridCols) return null;
        return grid[gy][gx];
    }

    public function getTerrainType(x:Float, y:Float):String {
        var cell = getCellAt(x, y);
        return cell != null ? cell.type : "plain";
    }

    public function getMoveSpeedMul(x:Float, y:Float):Float {
        var cell = getCellAt(x, y);
        return cell != null ? cell.moveSpeedMul : 1.0;
    }

    public function getCultivateMul(x:Float, y:Float):Float {
        var cell = getCellAt(x, y);
        return cell != null ? cell.cultivateMul : 1.0;
    }

    public function getElementBonus(x:Float, y:Float):{element:String, mul:Float} {
        var cell = getCellAt(x, y);
        if (cell == null) return {element: "none", mul: 1.0};
        return {element: cell.elementBonus, mul: cell.elementMul};
    }

    public function getFriction(x:Float, y:Float):Float {
        var cell = getCellAt(x, y);
        return cell != null ? cell.friction : 0.85;
    }
}
