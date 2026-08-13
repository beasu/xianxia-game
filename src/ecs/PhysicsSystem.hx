package ecs;

// ============================================================
//  PhysicsSystem.hx - 修仙世界物理系统
//  priority: 5 (在所有游戏逻辑系统之前执行)
//
//  修仙世界的"物理"不遵循牛顿力学, 而是灵气动力学:
//
//  ┌─────────────────────────────────────────────────────────┐
//  │  修仙物理法则                                            │
//  ├─────────────────────────────────────────────────────────┤
//  │  1. 灵压场    — 高境界者释放灵压, 压制低境界者移动        │
//  │  2. 境界压制  — 境界差≥2时, 低境界者速度衰减50%           │
//  │  3. 五行物理  — 相生加速/相克减速, 元素环境影响实体       │
//  │  4. 御剑飞行  — 筑基以上可消耗灵力飞行, 忽略地形摩擦      │
//  │  5. 神识力场  — 展开神识可探测隐身/预判, 影响碰撞判定     │
//  │  6. 灵压气流  — 灵脉喷涌产生气流, 推动附近实体            │
//  │  7. 空间折叠  — 金丹以上可扭曲空间, 缩短距离/偏转投射物   │
//  │  8. 因果引力  — 业障重者被牵引向危险区域(灵气枯竭/妖兽巢)  │
//  │  9. 护体灵光  — 灵力护盾抵消击退和伤害                    │
//  │ 10. 状态物理  — 冰冻/燃烧/眩晕/减速/凌空 的物理效果       │
//  │ 11. 天劫物理  — 雷劫产生电磁场, 心魔劫产生精神压力场      │
//  │ 12. 基础物理  — 速度积分/摩擦/碰撞/力场(保留原有功能)    │
//  └─────────────────────────────────────────────────────────┘
//
//  五行相生相克表:
//    相生(加速): 木→火→土→金→水→木
//    相克(减速): 木→土, 土→水, 水→火, 火→金, 金→木
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class PhysicsSystem implements ISystem {
    public var priority:Int = 5;
    public var enabled:Bool = true;

    // === 基础物理参数 ===
    public var globalGravity:Float = 0;
    public var globalDrag:Float = 0.98;
    public var knockbackDecay:Float = 0.85;
    public var minVelocity:Float = 5;
    public var collisionRadius:Float = 25;

    // === 修仙物理参数 ===
    public var pressureSpeedPenalty:Float = 0.5;     // 灵压下的速度衰减(每级境界差)
    public var pressureMaxPenalty:Float = 0.85;      // 最大速度衰减(85%)
    public var flySpeedMul:Float = 2.0;               // 御剑飞行速度倍率
    public var flyMpCostPerSec:Float = 5;             // 飞行灵力消耗
    public var veinAirflowRadius:Float = 200;         // 灵脉气流影响半径
    public var veinAirflowForce:Float = 30;           // 灵脉气流推力
    public var shieldRegenMul:Float = 0.1;            // 护盾恢复倍率(基于最大值)
    public var karmaGravityForce:Float = 15;          // 因果引力基础力度
    public var spaceFoldCostMul:Float = 1.5;          // 空间折叠灵力消耗倍率

    // 五行相生相克表
    static var wuxingGenerate:Map<String, String> = [
        "wood" => "fire", "fire" => "earth", "earth" => "metal",
        "metal" => "water", "water" => "wood"
    ];
    static var wuxingOvercome:Map<String, String> = [
        "wood" => "earth", "earth" => "water", "water" => "fire",
        "fire" => "metal", "metal" => "wood"
    ];

    // 活跃力场列表
    public var forceFields:Array<ForceField> = [];

    // 天劫电磁场(临时, 由 KarmaAndTribulationSystem 设置)
    public var tribulationFields:Array<TribulationField> = [];

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // === 修仙物理(先于基础物理) ===

        // 1. 灵压场计算 — 在实体上记录受到的灵压
        updateSpiritPressure(world, dt);

        // 2. 元素共振 — 计算灵根与环境的共鸣
        updateElementalResonance(world, dt);

        // 3. 因果引力 — 业障牵引
        updateKarmaGravity(world, dt);

        // 4. 状态效果计时器
        updateStatusTimers(world, dt);

        // 5. 御剑飞行/空间折叠/护盾的灵力消耗与维持
        updateSpiritAbilities(world, dt);

        // === 基础物理 ===

        // 6. 速度积分 + 摩擦 + 状态修正
        updateEntityPhysics(world, dt);

        // 7. 灵脉气流
        updateVeinAirflow(world, dt);

        // 8. 天劫电磁场
        updateTribulationFields(world, dt);

        // 9. 力场效果
        updateForceFields(world, dt);

        // 10. 碰撞检测(融入神识/空间折叠)
        checkCollisions(world, dt);
    }

    // ============================================================
    //  1. 灵压场 — 高境界者释放灵压, 压制低境界者
    // ============================================================
    function updateSpiritPressure(world:WorldEngine, dt:Float):Void {
        // 收集所有释放灵压的实体
        var pressureSources:Array<{x:Float, y:Float, radius:Float, power:Float, realm:Int}> = [];
        for (e in world.entities) {
            if (!e.alive) continue;
            var sp = e.get(SpiritPhysicsComp);
            var cult = e.get(CultivationComp);
            var pos = e.get(PositionComp);
            if (sp == null || cult == null || pos == null) continue;
            if (!sp.pressureEnabled) continue;

            // 灵压值 = 基础值 × 境界系数 × (HP比例)
            var power = sp.spiritPressure * (cult.hp / cult.maxHp);
            if (power < 1) continue;

            pressureSources.push({
                x: pos.x, y: pos.y,
                radius: sp.pressureRadius,
                power: power,
                realm: cult.realmIndex
            });
        }

        // 对每个实体计算受到的总灵压
        for (e in world.entities) {
            if (!e.alive) continue;
            var sp = e.get(SpiritPhysicsComp);
            var cult = e.get(CultivationComp);
            var pos = e.get(PositionComp);
            if (sp == null || cult == null || pos == null) continue;

            var totalPressure:Float = 0;
            var maxRealmDiff:Int = 0;

            for (src in pressureSources) {
                var dx = pos.x - src.x;
                var dy = pos.y - src.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist >= src.radius) continue;

                var falloff = 1 - dist / src.radius;
                var realmDiff = src.realm - cult.realmIndex;
                if (realmDiff <= 0) continue; // 只被高境界者压制

                totalPressure += src.power * falloff;
                if (realmDiff > maxRealmDiff) maxRealmDiff = realmDiff;
            }

            // 灵压减速: 境界差越大减速越狠, 但有上限
            if (totalPressure > 0 && maxRealmDiff > 0) {
                var penalty = Math.min(pressureMaxPenalty, pressureSpeedPenalty * maxRealmDiff);
                // 修炼中或飞行中不受灵压影响(自身灵力护体)
                var intent = e.get(IntentComp);
                if (intent != null && intent.currentIntent == Cultivate) penalty *= 0.3;
                if (sp.isFlying) penalty *= 0.2;
                if (sp.shieldActive) penalty *= 0.5;

                sp.slowFactor = 1.0 - penalty;
                sp.slowTimer = 0.2; // 持续0.2秒
            }
        }
    }

    // ============================================================
    //  2. 元素共振 — 灵根与周围环境共鸣
    // ============================================================
    function updateElementalResonance(world:WorldEngine, dt:Float):Void {
        // 获取地形系统
        var terrainSys:TerrainSystem = null;
        for (s in world.systems) {
            var ts = Std.downcast(s, TerrainSystem);
            if (ts != null) { terrainSys = ts; break; }
        }
        // 获取天气系统
        var weatherSys:WeatherSystem = null;
        for (s in world.systems) {
            var ws = Std.downcast(s, WeatherSystem);
            if (ws != null) { weatherSys = ws; break; }
        }

        for (e in world.entities) {
            if (!e.alive) continue;
            var sp = e.get(SpiritPhysicsComp);
            var cult = e.get(CultivationComp);
            var pos = e.get(PositionComp);
            if (sp == null || cult == null || pos == null) continue;

            sp.resonanceElement = cult.spiritRoot;

            // 计算环境元素
            var envElement = "none";
            var envMul:Float = 1.0;

            // 地形元素
            if (terrainSys != null) {
                var bonus = terrainSys.getElementBonus(pos.x, pos.y);
                if (bonus.element != "none") {
                    envElement = bonus.element;
                    envMul = bonus.mul;
                }
            }

            // 天气元素修正
            if (weatherSys != null) {
                switch (weatherSys.state.type) {
                    case "rain":   envElement = envElement == "none" ? "water" : envElement;
                    case "snow":   envElement = envElement == "none" ? "ice" : envElement;
                    case "thunder": envElement = envElement == "none" ? "thunder" : envElement;
                }
            }

            // 计算共振强度
            var myRoot = cult.spiritRoot;
            sp.resonanceStrength = 0;
            sp.resonanceBonus = 1.0;

            if (envElement != "none" && envElement != "ice" && envElement != "thunder") {
                // 相生: 环境生我 → 加速 + 法术增幅
                if (wuxingGenerate.exists(envElement) && wuxingGenerate[envElement] == myRoot) {
                    sp.resonanceStrength = 1.0;
                    sp.resonanceBonus = 1.0 + envMul * 0.15;
                    // 相生加速: 移动速度+10%
                    sp.slowTimer = Math.max(sp.slowTimer, 0.1);
                    sp.slowFactor = Math.max(sp.slowFactor, 1.1);
                }
                // 相克: 环境克我 → 减速 + 法术削弱
                else if (wuxingOvercome.exists(envElement) && wuxingOvercome[envElement] == myRoot) {
                    sp.resonanceStrength = -1.0;
                    sp.resonanceBonus = 1.0 - envMul * 0.12;
                    sp.slowTimer = Math.max(sp.slowTimer, 0.1);
                    sp.slowFactor = Math.min(sp.slowFactor, 0.85);
                }
                // 我克环境 → 无影响但可吸收
                else if (wuxingOvercome.exists(myRoot) && wuxingOvercome[myRoot] == envElement) {
                    sp.resonanceStrength = 0.5;
                    sp.resonanceBonus = 1.0 + envMul * 0.05;
                }
                // 同元素 → 强共振
                else if (envElement == myRoot) {
                    sp.resonanceStrength = 1.0;
                    sp.resonanceBonus = 1.0 + envMul * 0.2;
                }
            }
        }
    }

    // ============================================================
    //  3. 因果引力 — 业障重者被牵引向危险区域
    // ============================================================
    function updateKarmaGravity(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            var sp = e.get(SpiritPhysicsComp);
            var karma = e.get(KarmaComp);
            var pos = e.get(PositionComp);
            if (sp == null || karma == null || pos == null) continue;

            var netSin = karma.getNetSin();
            if (netSin < 20) {
                sp.karmaGravity = 0;
                continue;
            }

            sp.karmaGravity = netSin / 100;

            // 寻找最近的"危险区域" (灵气枯竭的灵脉 或 妖兽巢穴)
            var bestX:Float = 0;
            var bestY:Float = 0;
            var bestDist:Float = 1e9;

            // 灵气最低的灵脉
            for (vein in world.spiritVeins) {
                if (vein.currentDensity < 0.5) {
                    var dx = vein.x - pos.x;
                    var dy = vein.y - pos.y;
                    var d = dx * dx + dy * dy;
                    if (d < bestDist) { bestDist = d; bestX = vein.x; bestY = vein.y; }
                }
            }

            // 妖兽聚集点
            for (other in world.entities) {
                if (!other.alive || other == e) continue;
                var npcState = other.get(NPCStateComp);
                if (npcState == null || npcState.npcType != "yaoshou") continue;
                var opos = other.get(PositionComp);
                if (opos == null) continue;
                var dx = opos.x - pos.x;
                var dy = opos.y - pos.y;
                var d = dx * dx + dy * dy;
                if (d < bestDist) { bestDist = d; bestX = opos.x; bestY = opos.y; }
            }

            if (bestDist < 1e8) {
                var dx = bestX - pos.x;
                var dy = bestY - pos.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist > 1) {
                    sp.karmaPullX = dx / dist;
                    sp.karmaPullY = dy / dist;
                    // 应用牵引力
                    var force = karmaGravityForce * sp.karmaGravity * dt;
                    pos.vx += sp.karmaPullX * force;
                    pos.vy += sp.karmaPullY * force;
                }
            }
        }
    }

    // ============================================================
    //  4. 状态效果计时器
    // ============================================================
    function updateStatusTimers(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            var sp = e.get(SpiritPhysicsComp);
            var cult = e.get(CultivationComp);
            if (sp == null || cult == null) continue;

            // 冰冻
            if (sp.frozenTimer > 0) {
                sp.frozenTimer -= dt;
                // 冰冻中无法移动, 速度归零
                var pos = e.get(PositionComp);
                if (pos != null) { pos.vx = 0; pos.vy = 0; }
            }

            // 燃烧
            if (sp.burnTimer > 0) {
                sp.burnTimer -= dt;
                cult.hp -= sp.burnDps * dt;
                // 燃烧时灵力也消耗(灼烧经脉)
                cult.mp = Math.max(0, cult.mp - sp.burnDps * 0.3 * dt);
            }

            // 眩晕
            if (sp.stunTimer > 0) {
                sp.stunTimer -= dt;
                var pos = e.get(PositionComp);
                if (pos != null) { pos.vx *= 0.1; pos.vy *= 0.1; }
            }

            // 减速
            if (sp.slowTimer > 0) {
                sp.slowTimer -= dt;
            } else {
                sp.slowFactor = 1.0;
            }

            // 凌空
            if (sp.levitateTimer > 0) {
                sp.levitateTimer -= dt;
            }

            // 护盾恢复
            if (sp.shieldActive && sp.shieldStrength < sp.shieldMaxStrength) {
                sp.shieldStrength = Math.min(sp.shieldMaxStrength, sp.shieldStrength + sp.shieldMaxStrength * shieldRegenMul * dt);
            }
        }
    }

    // ============================================================
    //  5. 御剑飞行/空间折叠/护盾 — 灵力消耗与维持
    // ============================================================
    function updateSpiritAbilities(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            var sp = e.get(SpiritPhysicsComp);
            var cult = e.get(CultivationComp);
            if (sp == null || cult == null) continue;

            // 御剑飞行: 消耗灵力, 灵力不足则取消
            if (sp.isFlying) {
                if (cult.mp < flyMpCostPerSec * dt || cult.realmIndex < sp.minFlyRealm) {
                    sp.isFlying = false;
                } else {
                    cult.mp -= flyMpCostPerSec * dt;
                }
            }

            // 空间折叠: 消耗灵力
            if (sp.spaceFoldRadius > 0) {
                if (cult.mp < sp.spaceFoldMpCostPerSec * dt) {
                    sp.spaceFoldRadius = 0;
                    sp.spaceFoldStrength = 0;
                } else {
                    cult.mp -= sp.spaceFoldMpCostPerSec * dt;
                }
            }

            // 护体灵光: 消耗灵力
            if (sp.shieldActive) {
                if (cult.mp < sp.shieldMpCostPerSec * dt) {
                    sp.shieldActive = false;
                    sp.shieldStrength = 0;
                } else {
                    cult.mp -= sp.shieldMpCostPerSec * dt;
                }
            }
        }
    }

    // ============================================================
    //  6. 速度积分 + 摩擦 + 状态修正
    // ============================================================
    function updateEntityPhysics(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            // 玩家位置由 handleInput 每帧直接更新, 跳过物理积分避免双重推进
            if (e.isPlayer) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;
            var sp = e.get(SpiritPhysicsComp);
            var cult = e.get(CultivationComp);

            // 冰冻: 不进行任何物理积分
            if (sp != null && sp.frozenTimer > 0) continue;

            // 确定摩擦系数
            var friction = globalDrag;
            var isFlying = sp != null && sp.isFlying;
            var isLevitating = sp != null && sp.levitateTimer > 0;

            if (!isFlying && !isLevitating) {
                // 获取地形摩擦
                for (s in world.systems) {
                    var ts = Std.downcast(s, TerrainSystem);
                    if (ts != null) {
                        var cell = ts.getCellAt(pos.x, pos.y);
                        if (cell != null) {
                            friction = cell.friction;
                        }
                        break;
                    }
                }
            } else {
                // 飞行/凌空: 无地形摩擦, 使用空气阻力
                friction = 0.99;
            }

            // 减速效果
            var slowMul = sp != null ? sp.slowFactor : 1.0;

            // 飞行加速
            var flyMul = isFlying ? flySpeedMul : 1.0;

            // 应用速度积分(考虑减速和飞行)
            pos.x += pos.vx * dt * slowMul * flyMul;
            pos.y += pos.vy * dt * slowMul * flyMul;

            // 应用阻力/摩擦(飞行时阻力更小)
            pos.vx *= Math.pow(friction, dt * 60);
            pos.vy *= Math.pow(friction, dt * 60);

            // 应用全局重力(如果有, 修仙世界默认无重力)
            if (globalGravity > 0 && !isFlying && !isLevitating) {
                pos.vy += globalGravity * dt;
            }

            // 速度过低则归零
            var speed = Math.sqrt(pos.vx * pos.vx + pos.vy * pos.vy);
            if (speed < minVelocity) {
                pos.vx = 0;
                pos.vy = 0;
            }

            // 世界边界碰撞(弹回)
            if (pos.x < 0) { pos.x = 0; pos.vx = Math.abs(pos.vx) * 0.5; }
            if (pos.x > world.worldWidth) { pos.x = world.worldWidth; pos.vx = -Math.abs(pos.vx) * 0.5; }
            if (pos.y < 0) { pos.y = 0; pos.vy = Math.abs(pos.vy) * 0.5; }
            if (pos.y > world.worldHeight) { pos.y = world.worldHeight; pos.vy = -Math.abs(pos.vy) * 0.5; }
        }
    }

    // ============================================================
    //  7. 灵脉气流 — 灵脉喷涌产生气流推动实体
    // ============================================================
    function updateVeinAirflow(world:WorldEngine, dt:Float):Void {
        for (vein in world.spiritVeins) {
            // 灵气密度越高, 气流越强
            var flowStrength = vein.currentDensity * veinAirflowForce * dt;
            if (flowStrength < 1) continue;

            for (e in world.entities) {
                if (!e.alive) continue;
                var pos = e.get(PositionComp);
                var sp = e.get(SpiritPhysicsComp);
                if (pos == null) continue;

                // 飞行中的实体不受气流影响
                if (sp != null && sp.isFlying) continue;

                var dx = pos.x - vein.x;
                var dy = pos.y - vein.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist >= veinAirflowRadius || dist < 1) continue;

                // 气流从灵脉中心向外推
                var falloff = 1 - dist / veinAirflowRadius;
                pos.vx += (dx / dist) * flowStrength * falloff;
                pos.vy += (dy / dist) * flowStrength * falloff;
            }
        }
    }

    // ============================================================
    //  8. 天劫电磁场 — 雷劫产生电磁场, 心魔劫产生精神压力
    // ============================================================
    function updateTribulationFields(world:WorldEngine, dt:Float):Void {
        var i = tribulationFields.length;
        while (i-- > 0) {
            var field = tribulationFields[i];
            field.lifetime -= dt;
            if (field.lifetime <= 0) {
                tribulationFields.splice(i, 1);
                continue;
            }

            for (e in world.entities) {
                if (!e.alive) continue;
                var pos = e.get(PositionComp);
                var sp = e.get(SpiritPhysicsComp);
                var cult = e.get(CultivationComp);
                if (pos == null || cult == null) continue;

                var dx = pos.x - field.x;
                var dy = pos.y - field.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist >= field.radius) continue;

                var falloff = 1 - dist / field.radius;

                switch (field.type) {
                    case "lightning":
                        // 雷劫电磁场: 随机方向抖动 + 灵力紊乱
                        pos.vx += (Math.random() - 0.5) * field.strength * falloff * dt * 100;
                        pos.vy += (Math.random() - 0.5) * field.strength * falloff * dt * 100;
                        // 灵力紊乱: 消耗额外灵力
                        cult.mp = Math.max(0, cult.mp - field.strength * falloff * dt * 2);
                        // 低境界者被眩晕
                        if (cult.realmIndex < field.minRealm && sp != null) {
                            sp.stunTimer = Math.max(sp.stunTimer, 0.1);
                        }

                    case "heartDemon":
                        // 心魔劫精神压力: 减速 + 攻击性降低
                        if (sp != null) {
                            sp.slowFactor = Math.min(sp.slowFactor, 1 - falloff * 0.5);
                            sp.slowTimer = Math.max(sp.slowTimer, 0.2);
                        }
                        // 精神压力导致灵力流失
                        cult.mp = Math.max(0, cult.mp - field.strength * falloff * dt);

                    case "fire":
                        // 天火劫: 燃烧效果
                        if (sp != null) {
                            sp.burnTimer = Math.max(sp.burnTimer, 0.5);
                            sp.burnDps = Math.max(sp.burnDps, field.strength * falloff * 20);
                        }
                }
            }
        }
    }

    // ============================================================
    //  9. 力场效果 (保留原有功能, 增加修仙力场类型)
    // ============================================================
    function updateForceFields(world:WorldEngine, dt:Float):Void {
        var i = forceFields.length;
        while (i-- > 0) {
            var field = forceFields[i];
            field.lifetime -= dt;
            if (field.lifetime <= 0) {
                forceFields.splice(i, 1);
                continue;
            }

            for (e in world.entities) {
                if (!e.alive) continue;
                var pos = e.get(PositionComp);
                var sp = e.get(SpiritPhysicsComp);
                if (pos == null) continue;

                var dx = pos.x - field.x;
                var dy = pos.y - field.y;
                var dist = Math.sqrt(dx * dx + dy * dy);

                if (dist < field.radius) {
                    var strength = field.strength * (1 - dist / field.radius);

                    // 护体灵光可以抵消力场效果
                    if (sp != null && sp.shieldActive && sp.shieldStrength > 0) {
                        var absorbed = Math.min(sp.shieldStrength, strength * dt);
                        sp.shieldStrength -= absorbed;
                        strength -= absorbed / dt;
                        if (strength <= 0) continue;
                    }

                    switch (field.type) {
                        case "pull":
                            if (dist > 1) {
                                pos.vx -= (dx / dist) * strength * dt;
                                pos.vy -= (dy / dist) * strength * dt;
                            }
                        case "push":
                            if (dist > 1) {
                                pos.vx += (dx / dist) * strength * dt;
                                pos.vy += (dy / dist) * strength * dt;
                            }
                        case "slow":
                            pos.vx *= Math.pow(1 - strength * 0.5, dt * 60);
                            pos.vy *= Math.pow(1 - strength * 0.5, dt * 60);
                        case "lift":
                            pos.vy -= strength * dt;
                        case "freeze":
                            // 冰冻力场
                            if (sp != null && dist < field.radius * 0.5) {
                                sp.frozenTimer = Math.max(sp.frozenTimer, strength * 0.5);
                            }
                        case "burn":
                            // 燃烧力场
                            if (sp != null) {
                                sp.burnTimer = Math.max(sp.burnTimer, strength * 0.3);
                                sp.burnDps = Math.max(sp.burnDps, strength * 30);
                            }
                        case "void":
                            // 虚空力场: 随机传送
                            if (Math.random() < strength * dt * 0.5) {
                                pos.x += (Math.random() - 0.5) * field.radius;
                                pos.y += (Math.random() - 0.5) * field.radius;
                            }
                    }
                }
            }
        }
    }

    // ============================================================
    //  10. 碰撞检测 (融入空间折叠/神识)
    // ============================================================
    function checkCollisions(world:WorldEngine, dt:Float):Void {
        var movingEntities:Array<Entity> = [];
        for (e in world.entities) {
            if (!e.alive) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;
            var sp = e.get(SpiritPhysicsComp);

            // 冰冻/眩晕的实体不参与碰撞推演
            if (sp != null && (sp.frozenTimer > 0 || sp.stunTimer > 0)) continue;

            var speed = Math.sqrt(pos.vx * pos.vx + pos.vy * pos.vy);
            if (speed > minVelocity) {
                movingEntities.push(e);
            }
        }

        for (a in movingEntities) {
            var posA = a.get(PositionComp);
            var spA = a.get(SpiritPhysicsComp);

            for (b in world.entities) {
                if (a == b || !b.alive) continue;
                var posB = b.get(PositionComp);
                if (posB == null) continue;

                // 空间折叠: 折叠区域内的碰撞距离缩小
                var foldMul:Float = 1.0;
                if (spA != null && spA.spaceFoldRadius > 0) {
                    var fdx = posA.x - posB.x;
                    var fdy = posA.y - posB.y;
                    var fdist = Math.sqrt(fdx * fdx + fdy * fdy);
                    if (fdist < spA.spaceFoldRadius) {
                        foldMul = 1.0 - spA.spaceFoldStrength * (1 - fdist / spA.spaceFoldRadius);
                    }
                }

                var dx = posA.x - posB.x;
                var dy = posA.y - posB.y;
                var distSq = dx * dx + dy * dy;
                var minDist = collisionRadius * 2 * foldMul;

                if (distSq < minDist * minDist && distSq > 0.01) {
                    var dist = Math.sqrt(distSq);
                    var overlap = minDist - dist;
                    var nx = dx / dist;
                    var ny = dy / dist;

                    // 护体灵光: 抵消碰撞冲击
                    var spB = b.get(SpiritPhysicsComp);
                    var blockA = spA != null && spA.shieldActive && spA.shieldStrength > 0;
                    var blockB = spB != null && spB.shieldActive && spB.shieldStrength > 0;

                    if (blockA || blockB) {
                        // 有护盾时不进行位置分离, 只消耗护盾
                        var impact = overlap * 2;
                        if (blockA) {
                            var absorbed = Math.min(spA.shieldStrength, impact);
                            spA.shieldStrength -= absorbed;
                        }
                        if (blockB) {
                            var absorbed = Math.min(spB.shieldStrength, impact);
                            spB.shieldStrength -= absorbed;
                        }
                        continue;
                    }

                    // 分离
                    posA.x += nx * overlap * 0.5;
                    posA.y += ny * overlap * 0.5;
                    posB.x -= nx * overlap * 0.5;
                    posB.y -= ny * overlap * 0.5;

                    // 弹性碰撞
                    var vAN = posA.vx * nx + posA.vy * ny;
                    var vBN = posB.vx * nx + posB.vy * ny;
                    posA.vx += (vBN - vAN) * nx * 0.5;
                    posA.vy += (vBN - vAN) * ny * 0.5;
                    posB.vx += (vAN - vBN) * nx * 0.5;
                    posB.vy += (vAN - vBN) * ny * 0.5;
                }
            }
        }
    }

    // ============================================================
    //  公共接口
    // ============================================================

    // 添加力场
    public function addForceField(field:ForceField):Void {
        forceFields.push(field);
    }

    // 添加天劫场
    public function addTribulationField(field:TribulationField):Void {
        tribulationFields.push(field);
    }

    // 施加击退(考虑护盾)
    public function applyKnockback(entity:Entity, fromX:Float, fromY:Float, force:Float):Void {
        var pos = entity.get(PositionComp);
        if (pos == null) return;
        var sp = entity.get(SpiritPhysicsComp);

        // 护体灵光抵消击退
        if (sp != null && sp.shieldActive && sp.shieldStrength > 0) {
            var absorbed = Math.min(sp.shieldStrength, force * 10);
            sp.shieldStrength -= absorbed;
            force -= absorbed / 10;
            if (force <= 0) return;
        }

        // 冰冻状态下击退减半
        if (sp != null && sp.frozenTimer > 0) force *= 0.5;

        var dx = pos.x - fromX;
        var dy = pos.y - fromY;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 1) { dx = 1; dist = 1; }
        pos.vx += (dx / dist) * force;
        pos.vy += (dy / dist) * force;
    }

    // 施加状态效果
    public function applyStatus(entity:Entity, type:String, duration:Float, power:Float = 0):Void {
        var sp = entity.get(SpiritPhysicsComp);
        if (sp == null) return;

        switch (type) {
            case "freeze":  sp.frozenTimer = Math.max(sp.frozenTimer, duration);
            case "burn":    sp.burnTimer = Math.max(sp.burnTimer, duration); sp.burnDps = Math.max(sp.burnDps, power);
            case "stun":    sp.stunTimer = Math.max(sp.stunTimer, duration);
            case "slow":    sp.slowTimer = Math.max(sp.slowTimer, duration); sp.slowFactor = Math.min(sp.slowFactor, power > 0 ? power : 0.5);
            case "levitate": sp.levitateTimer = Math.max(sp.levitateTimer, duration);
        }
    }

    // 激活护体灵光
    public function activateShield(entity:Entity, strength:Float):Void {
        var sp = entity.get(SpiritPhysicsComp);
        var cult = entity.get(CultivationComp);
        if (sp == null || cult == null) return;
        sp.shieldActive = true;
        sp.shieldMaxStrength = strength;
        sp.shieldStrength = strength;
    }

    // 激活御剑飞行
    public function activateFlight(entity:Entity):Bool {
        var sp = entity.get(SpiritPhysicsComp);
        var cult = entity.get(CultivationComp);
        if (sp == null || cult == null) return false;
        if (cult.realmIndex < sp.minFlyRealm) return false;
        if (cult.mp < sp.flyMpCostPerSec) return false;
        sp.isFlying = true;
        return true;
    }

    // 激活空间折叠
    public function activateSpaceFold(entity:Entity, radius:Float, strength:Float):Bool {
        var sp = entity.get(SpiritPhysicsComp);
        var cult = entity.get(CultivationComp);
        if (sp == null || cult == null) return false;
        if (cult.realmIndex < 4) return false; // 金丹期以上
        if (cult.mp < sp.spaceFoldMpCostPerSec) return false;
        sp.spaceFoldRadius = radius;
        sp.spaceFoldStrength = strength;
        return true;
    }

    // 获取实体的物理状态摘要(供 UI/调试使用)
    public function getPhysicsSummary(entity:Entity):String {
        var sp = entity.get(SpiritPhysicsComp);
        if (sp == null) return "";
        var parts:Array<String> = [];
        if (sp.isFlying) parts.push("御剑飞行");
        if (sp.frozenTimer > 0) parts.push("冰冻");
        if (sp.burnTimer > 0) parts.push("燃烧");
        if (sp.stunTimer > 0) parts.push("眩晕");
        if (sp.slowTimer > 0 && sp.slowFactor < 1) parts.push("减速");
        if (sp.levitateTimer > 0) parts.push("凌空");
        if (sp.shieldActive) parts.push("护体灵光(" + Math.round(sp.shieldStrength) + ")");
        if (sp.spaceFoldRadius > 0) parts.push("空间折叠");
        if (sp.resonanceStrength > 0) parts.push("元素共振(+" + Math.round((sp.resonanceBonus - 1) * 100) + "%)");
        if (sp.resonanceStrength < 0) parts.push("元素压制(" + Math.round((sp.resonanceBonus - 1) * 100) + "%)");
        if (sp.karmaGravity > 0.2) parts.push("因果牵引");
        return parts.join(", ");
    }
}

// ============================================================
//  力场定义 (扩展)
// ============================================================
class ForceField {
    public var x:Float;
    public var y:Float;
    public var radius:Float;
    public var type:String;     // pull/push/slow/lift/freeze/burn/void
    public var strength:Float;
    public var lifetime:Float;

    public function new(x:Float, y:Float, radius:Float, type:String, strength:Float, lifetime:Float) {
        this.x = x;
        this.y = y;
        this.radius = radius;
        this.type = type;
        this.strength = strength;
        this.lifetime = lifetime;
    }
}

// ============================================================
//  天劫物理场
// ============================================================
class TribulationField {
    public var x:Float;
    public var y:Float;
    public var radius:Float;
    public var type:String;        // lightning/heartDemon/fire
    public var strength:Float;
    public var lifetime:Float;
    public var minRealm:Int;       // 低于此境界受额外影响

    public function new(x:Float, y:Float, radius:Float, type:String, strength:Float, lifetime:Float, minRealm:Int = 0) {
        this.x = x;
        this.y = y;
        this.radius = radius;
        this.type = type;
        this.strength = strength;
        this.lifetime = lifetime;
        this.minRealm = minRealm;
    }
}
