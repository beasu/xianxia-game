package ecs;

// ============================================================
//  WorldEcologySystem.hx - 世界生态引擎
//  priority: 15 (在意图系统之后, 生态系统之前)
//
//  核心机制:
//  1. 将世界划分为网格, 每个格子跟踪灵气浓度
//  2. 修士密度过高 -> 灵气枯竭(depleted 增加, 灵气产出降低)
//  3. 大规模死亡事件 -> 灵气暴涨(surge 增加, 灵气浓度临时升高)
//  4. 灵气潮汐: 基于正弦波的周期性波动
//  5. 修士修炼速度受所在格子的灵气浓度影响
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class WorldEcologySystem implements ISystem {
    public var priority:Int = 15;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var gridSize:Float = 300;          // 每个网格格子的大小(像素)
    public var maxCultivatorsPerCell:Int = 5;  // 超过此数开始灵气枯竭
    public var depletionRate:Float = 0.02;     // 每tick枯竭度增速
    public var depletionRecovery:Float = 0.008; // 每tick枯竭度恢复
    public var deathSurgePerDeath:Float = 0.15; // 每次死亡带来的暴涨量
    public var surgeDecay:Float = 0.005;       // 每tick暴涨衰减
    public var tideAmplitude:Float = 0.3;      // 潮汐振幅
    public var tideFrequency:Float = 0.003;    // 潮汐频率

    // 网格
    public var grid:Array<Array<EcologyGridCell>> = [];
    public var gridCols:Int = 0;
    public var gridRows:Int = 0;

    // 死亡事件追踪
    var lastAliveCount:Int = 0;
    var deathEventThreshold:Int = 3; // 单次tick内死亡超过此数视为"大规模死亡"

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 1. 懒初始化网格
        if (grid.length == 0) {
            initGrid(world.worldWidth, world.worldHeight);
        }

        // 2. 统计每个格子的修士数量
        countCultivators(world);

        // 3. 检测大规模死亡事件
        var currentAlive = 0;
        for (e in world.entities) {
            if (e.alive) currentAlive++;
        }
        var deaths = lastAliveCount - currentAlive;
        if (deaths > 0) {
            handleDeaths(world, deaths);
        }
        lastAliveCount = currentAlive;

        // 4. 更新每个格子的灵气浓度
        updateGridSpiritDensity(dt);

        // 5. 将网格灵气浓度影响应用到修士修炼
        applySpiritDensityToCultivators(world, dt);

        // 6. 每日更新: 重置近期死亡计数
        if (world.tickCount % world.ticksPerDay == 0) {
            for (row in grid) {
                for (cell in row) {
                    cell.recentDeaths = 0;
                }
            }
        }
    }

    // --- 初始化网格 ---
    function initGrid(worldW:Float, worldH:Float):Void {
        gridCols = Math.ceil(worldW / gridSize);
        gridRows = Math.ceil(worldH / gridSize);
        grid = [];
        for (gy in 0...gridRows) {
            var row:Array<EcologyGridCell> = [];
            for (gx in 0...gridCols) {
                var cx = (gx + 0.5) * gridSize;
                var cy = (gy + 0.5) * gridSize;
                var cell = new EcologyGridCell(gx, gy, cx, cy);
                // 基础灵气浓度: 越靠近世界中心越高(模拟灵脉汇聚)
                var distFromCenter = Math.sqrt(
                    Math.pow(cx - worldW / 2, 2) + Math.pow(cy - worldH / 2, 2)
                );
                var maxDist = Math.sqrt(Math.pow(worldW / 2, 2) + Math.pow(worldH / 2, 2));
                cell.baseDensity = 1.5 - (distFromCenter / maxDist) * 0.8;
                cell.baseDensity = Math.max(0.3, cell.baseDensity);
                cell.spiritDensity = cell.baseDensity;
                // 随机潮汐相位
                cell.tidePhase = Math.random() * Math.PI * 2;
                row.push(cell);
            }
            grid.push(row);
        }
    }

    // --- 统计每个格子的修士数量 ---
    function countCultivators(world:WorldEngine):Void {
        // 清零
        for (row in grid) {
            for (cell in row) {
                cell.cultivatorCount = 0;
            }
        }
        // 统计
        for (e in world.entities) {
            if (!e.alive) continue;
            var pos = e.get(PositionComp);
            var cult = e.get(CultivationComp);
            if (pos == null || cult == null) continue;
            var cell = getCellAt(pos.x, pos.y);
            if (cell != null) {
                cell.cultivatorCount++;
            }
        }
    }

    // --- 处理死亡事件: 找到死亡位置, 增加该区域灵气暴涨 ---
    function handleDeaths(world:WorldEngine, deathCount:Int):Void {
        // 遍历所有实体, 找到最近死亡的(通过事件日志)
        var recentDeathEvents = world.eventLog.filter(function(e)
            return e.type == "Kill" || e.type == "DeathByAge"
        );
        // 取最近 deathCount 条
        var startIdx:Int = Std.int(Math.max(0, recentDeathEvents.length - deathCount));
        for (i in startIdx...recentDeathEvents.length) {
            var evt = recentDeathEvents[i];
            var victim = world.getEntity(evt.targetId);
            var x:Float = 0;
            var y:Float = 0;
            if (victim != null) {
                var pos = victim.get(PositionComp);
                if (pos != null) { x = pos.x; y = pos.y; }
            } else {
                // 实体可能已被清理, 使用事件中的模糊位置
                continue;
            }
            // 增加死亡位置周围的灵气暴涨
            var cell = getCellAt(x, y);
            if (cell != null) {
                cell.recentDeaths++;
                cell.surge = Math.min(1.0, cell.surge + deathSurgePerDeath);
                // 大规模死亡: 周围格子也受影响
                if (deathCount >= deathEventThreshold) {
                    for (dy in -1...2) {
                        for (dx in -1...2) {
                            if (dx == 0 && dy == 0) continue;
                            var nx = cell.gridX + dx;
                            var ny = cell.gridY + dy;
                            if (ny >= 0 && ny < gridRows && nx >= 0 && nx < gridCols) {
                                grid[ny][nx].surge = Math.min(1.0, grid[ny][nx].surge + deathSurgePerDeath * 0.5);
                            }
                        }
                    }
                    // 发出世界事件
                    world.emitEvent(new WorldEvent(-1, -1, "SpiritSurge",
                        "天道感应: 大规模陨落引发灵气潮涌, 方圆千里灵气浓度暴涨!"
                    ));
                }
            }
        }
    }

    // --- 更新网格灵气浓度 ---
    function updateGridSpiritDensity(dt:Float):Void {
        for (row in grid) {
            for (cell in row) {
                // 潮汐波动
                cell.tidePhase += tideFrequency;
                var tide = 1.0 + Math.sin(cell.tidePhase) * tideAmplitude;

                // 修士密度过高 -> 灵气枯竭
                if (cell.cultivatorCount > maxCultivatorsPerCell) {
                    cell.depleted = Math.min(1.0, cell.depleted + depletionRate * (cell.cultivatorCount - maxCultivatorsPerCell));
                } else {
                    cell.depleted = Math.max(0, cell.depleted - depletionRecovery);
                }

                // 灵气暴涨衰减
                cell.surge = Math.max(0, cell.surge - surgeDecay);

                // 最终灵气浓度 = 基础 * 潮汐 * (1 - 枯竭) * (1 + 暴涨)
                cell.spiritDensity = cell.baseDensity * tide * (1.0 - cell.depleted * 0.7) * (1.0 + cell.surge * 2.0);
                cell.spiritDensity = Math.max(0.05, cell.spiritDensity);
            }
        }
    }

    // --- 将灵气浓度应用到修士修炼 ---
    function applySpiritDensityToCultivators(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            if (e.isPlayer) continue; // 玩家修炼由 GameScene 处理
            var pos = e.get(PositionComp);
            var cult = e.get(CultivationComp);
            var intent = e.get(IntentComp);
            if (pos == null || cult == null) continue;

            var cell = getCellAt(pos.x, pos.y);
            if (cell == null) continue;

            // 灵气浓度影响被动恢复(所有实体)
            var densityMul = cell.spiritDensity;
            cult.mp = Math.min(cult.maxMp, cult.mp + 2 * densityMul * dt * 10);
            cult.hp = Math.min(cult.maxHp, cult.hp + cult.maxHp * 0.005 * densityMul * dt * 10);

            // 修炼中的实体获得额外经验加成
            if (intent != null && intent.currentIntent == Cultivate) {
                cult.exp += 2 * cult.talent * densityMul * dt * 10;
                // 灵气暴涨时修炼效率翻倍
                if (cell.surge > 0.3) {
                    cult.exp += 3 * cult.talent * cell.surge * dt * 10;
                }
            }

            // 灵气枯竭区域的修士有概率受伤(灵气逆流)
            if (cell.depleted > 0.7 && Math.random() < 0.001) {
                cult.hp -= cult.maxHp * 0.02;
                if (e.isPlayer == false) {
                    world.emitEvent(new WorldEvent(e.id, -1, "SpiritDepletion",
                        e.name + " 在灵气枯竭之地修炼, 遭灵气逆流反噬!"
                    ));
                }
            }
        }
    }

    // --- 获取坐标所在的网格格子 ---
    public function getCellAt(x:Float, y:Float):EcologyGridCell {
        var gx = Std.int(x / gridSize);
        var gy = Std.int(y / gridSize);
        if (gy < 0 || gy >= gridRows || gx < 0 || gx >= gridCols) return null;
        return grid[gy][gx];
    }

    // --- 获取坐标处的灵气浓度(供外部系统查询) ---
    public function getSpiritDensityAt(x:Float, y:Float):Float {
        var cell = getCellAt(x, y);
        if (cell == null) return 1.0;
        return cell.spiritDensity;
    }
}
