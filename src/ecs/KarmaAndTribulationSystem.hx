package ecs;

// ============================================================
//  KarmaAndTribulationSystem.hx - 天道与业障系统
//  priority: 25 (在意图系统之后, 历史系统之前)
//
//  核心机制:
//  1. 追踪每个实体的业障值(sinValue)和功德值(meritValue)
//  2. 杀戮、背叛、暗杀等行为增加业障
//  3. 斩妖除魔、行善积累功德
//  4. 突破境界时, 如果业障过高, 强制触发天劫:
//     - 业障 30-60: 心魔劫 (精神试炼, 失败则走火入魔)
//     - 业障 60+:   雷劫 (天降神雷, 威力随业障值动态计算)
//  5. 雷劫威力 = 基础威力 * (1 + 业障/50) * 境界系数
//  6. 渡过天劫后业障值大幅降低(天道宽恕)
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class KarmaAndTribulationSystem implements ISystem {
    public var priority:Int = 25;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var sinThresholdHeartDemon:Float = 30;  // 心魔劫触发的业障阈值
    public var sinThresholdLightning:Float = 60;   // 雷劫触发的业障阈值
    public var tribulationCooldownDays:Int = 30;   // 天劫冷却天数
    public var baseLightningDamage:Float = 200;    // 雷劫基础伤害
    public var maxLightningStrikes:Int = 9;        // 最大雷击次数(九九天劫)
    public var heartDemonSuccessRate:Float = 0.5;  // 心魔劫基础成功率
    public var sinDecayPerDay:Float = 0.5;         // 每天自然消退的业障值
    public var killSinGain:Float = 8;              // 每次杀戮增加的业障
    public var killMeritGain:Float = 5;            // 斩魔获得的功德
    public var betraySinGain:Float = 20;           // 背叛增加的业障
    public var assassinateSinGain:Float = 25;      // 暗杀增加的业障

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 1. 处理事件: 从事件总线中检测杀戮/背叛等行为, 更新业障
        processSinEvents(world);

        // 2. 每日处理: 业障自然消退 + 天劫冷却
        if (world.tickCount % world.ticksPerDay == 0) {
            dailyUpdate(world);
        }

        // 3. 检测有待降临天劫的实体, 执行天劫
        processPendingTribulations(world, dt);

        // 4. 检测正在突破的实体, 判定是否需要触发天劫
        checkBreakthroughTribulations(world);
    }

    // --- 从事件总线处理业障变化 ---
    function processSinEvents(world:WorldEngine):Void {
        // 检查最近的事件(取最近5条, 避免重复处理)
        var recentEvents = world.eventLog.slice(-5);
        for (evt in recentEvents) {
            if (evt.type == "Kill" || evt.type == "Assassinate") {
                var killer = world.getEntity(evt.sourceId);
                var victim = world.getEntity(evt.targetId);
                if (killer == null) continue;
                var karma = killer.get(KarmaComp);
                if (karma == null) continue;

                // 避免重复处理: 检查事件tick是否已被处理过
                if (karma.lastProcessedEventTick >= evt.tick) continue;
                karma.lastProcessedEventTick = evt.tick;

                if (evt.type == "Kill") {
                    // 杀正道人士增加业障, 斩魔获得功德
                    if (victim != null) {
                        var victimKarma = victim.get(KarmaComp);
                        if (victimKarma != null && victimKarma.karma > 0) {
                            // 杀正道
                            karma.sinValue += killSinGain;
                            karma.karma -= 10;
                            karma.notoriety += 5;
                        } else {
                            // 斩魔
                            karma.meritValue += killMeritGain;
                            karma.karma += 5;
                            karma.reputation += 3;
                        }
                    }
                } else if (evt.type == "Assassinate") {
                    karma.sinValue += assassinateSinGain;
                    karma.notoriety += 10;
                }

                karma.sinValue = Math.min(100, karma.sinValue);
            }

            if (evt.type == "Betray") {
                var traitor = world.getEntity(evt.sourceId);
                if (traitor == null) continue;
                var karma = traitor.get(KarmaComp);
                if (karma != null) {
                    karma.sinValue += betraySinGain;
                    karma.notoriety += 15;
                    karma.sinValue = Math.min(100, karma.sinValue);
                }
            }
        }
    }

    // --- 每日更新 ---
    function dailyUpdate(world:WorldEngine):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            var karma = e.get(KarmaComp);
            if (karma == null) continue;

            // 业障自然消退(缓慢)
            karma.sinValue = Math.max(0, karma.sinValue - sinDecayPerDay);

            // 功德自然积累(正道修士每天积累微量功德)
            var cult = e.get(CultivationComp);
            if (cult != null && karma.karma > 20) {
                karma.meritValue += 0.1;
            }

            // 天劫冷却递减
            if (karma.tribulationPending && world.worldDay - karma.lastTribulationDay > tribulationCooldownDays) {
                // 天劫冷却结束, 标记为待降临
                var netSin = karma.getNetSin();
                if (netSin > sinThresholdHeartDemon) {
                    karma.tribulationPending = true;
                    karma.tribulationType = netSin > sinThresholdLightning ? "lightning" : "heartDemon";
                    karma.tribulationPower = calculateTribulationPower(e, netSin);
                } else {
                    karma.tribulationPending = false;
                    karma.tribulationType = "";
                }
            }
        }
    }

    // --- 计算天劫威力 ---
    function calculateTribulationPower(entity:Entity, netSin:Float):Float {
        var cult = entity.get(CultivationComp);
        if (cult == null) return baseLightningDamage;

        var realmMul = 1.0 + cult.realmIndex * 0.3;  // 境界越高, 天劫越强
        var sinMul = 1.0 + netSin / 50;              // 业障越高, 天劫越强
        var luckMul = 1.0 / Math.max(0.3, cult.luck); // 气运越低, 天劫越强(气运高者有天眷)

        return baseLightningDamage * realmMul * sinMul * luckMul;
    }

    // --- 处理待降临的天劫 ---
    function processPendingTribulations(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            if (e.isPlayer) continue; // 玩家天劫由 GameScene 处理(需要特效)
            var karma = e.get(KarmaComp);
            var cult = e.get(CultivationComp);
            if (karma == null || cult == null) continue;

            if (!karma.tribulationPending) continue;
            if (karma.tribulationType == "") continue;

            // 有概率触发天劫降临
            if (Math.random() < 0.002) {
                executeTribulation(world, e, karma, cult);
            }
        }
    }

    // --- 检测突破时的天劫 ---
    function checkBreakthroughTribulations(world:WorldEngine):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            if (e.isPlayer) continue; // 玩家突破由 GameScene 触发
            var intent = e.get(IntentComp);
            var karma = e.get(KarmaComp);
            var cult = e.get(CultivationComp);
            if (intent == null || karma == null || cult == null) continue;

            // 如果实体正在突破且业障过高
            if (intent.currentIntent == Breakthrough) {
                var netSin = karma.getNetSin();
                if (netSin > sinThresholdHeartDemon) {
                    // 突破前先渡劫
                    var tribType = netSin > sinThresholdLightning ? "lightning" : "heartDemon";
                    karma.tribulationType = tribType;
                    karma.tribulationPower = calculateTribulationPower(e, netSin);
                    executeTribulation(world, e, karma, cult);

                    // 如果渡劫成功, 允许继续突破
                    // 如果渡劫失败, 意图改为 Cultivate
                }
            }
        }
    }

    // --- 执行天劫 ---
    function executeTribulation(world:WorldEngine, entity:Entity, karma:KarmaComp, cult:CultivationComp):Void {
        var netSin = karma.getNetSin();
        karma.tribulationPending = false;
        karma.lastTribulationDay = world.worldDay;

        if (karma.tribulationType == "heartDemon") {
            // === 心魔劫 ===
            var successRate = heartDemonSuccessRate + cult.luck * 0.15 + cult.talent * 0.1 - netSin * 0.005;
            successRate = Math.clamp(successRate, 0.1, 0.9);

            world.emitEvent(new WorldEvent(entity.id, -1, "HeartDemonTribulation",
                entity.name + " 突破之际, 心魔丛生! 业障值 " + Math.round(netSin) + ", 心魔劫降临..."
            ));

            if (Math.random() < successRate) {
                // 渡过心魔劫
                karma.sinValue *= 0.4; // 业障大幅降低
                karma.heartDemonDefeated = true;
                karma.tribulationType = "";
                world.emitEvent(new WorldEvent(entity.id, -1, "TribulationSuccess",
                    entity.name + " 斩灭心魔, 道心通明! 天道宽恕其 " + Math.round(netSin * 0.6) + " 点业障"
                ));
            } else {
                // 心魔劫失败: 走火入魔
                cult.hp = cult.maxHp * 0.2; // 重伤
                cult.exp *= 0.3;
                karma.sinValue += 5; // 失败增加业障
                var intent = entity.get(IntentComp);
                if (intent != null) intent.currentIntent = Cultivate;
                world.emitEvent(new WorldEvent(entity.id, -1, "TribulationFail",
                    entity.name + " 心魔劫失败, 走火入魔! 气血逆流, 修为大损!"
                ));
            }
        } else if (karma.tribulationType == "lightning") {
            // === 雷劫 ===
            var totalStrikes = Math.ceil(Math.min(maxLightningStrikes, 3 + netSin / 10));
            var strikeDamage = karma.tribulationPower / totalStrikes;

            world.emitEvent(new WorldEvent(entity.id, -1, "LightningTribulation",
                entity.name + " 业障滔天(" + Math.round(netSin) + "), 天降雷劫! 共" + totalStrikes + "道天雷, 每道造成" + Math.round(strikeDamage) + "伤害"
            ));

            // 计算总伤害
            var totalDamage = strikeDamage * totalStrikes;
            // 气运可减免部分伤害
            var mitigated = totalDamage * (1.0 - Math.min(0.5, cult.luck * 0.3));
            cult.hp -= mitigated;

            if (cult.hp > 0) {
                // 渡过雷劫
                karma.sinValue *= 0.3; // 业障大幅降低
                karma.tribulationType = "";
                // 渡劫后实力提升(破而后立)
                cult.maxHp = Std.int(cult.maxHp * 1.15);
                cult.hp = cult.maxHp;
                cult.attackPower = Std.int(cult.attackPower * 1.1);
                world.emitEvent(new WorldEvent(entity.id, -1, "TribulationSuccess",
                    entity.name + " 渡过九重雷劫, 破而后立, 修为大进! 业障消散" + Math.round(netSin * 0.7) + "点"
                ));
            } else {
                // 雷劫失败: 灰飞烟灭
                entity.alive = false;
                world.emitEvent(new WorldEvent(entity.id, -1, "TribulationDeath",
                    entity.name + " 未能渡过天雷, 灰飞烟灭! 天道昭昭, 业报不爽"
                ));
            }
        }
    }

    // --- 外部接口: 为玩家触发天劫判定 ---
    public function checkPlayerTribulation(world:WorldEngine, player:Entity):Bool {
        var karma = player.get(KarmaComp);
        var cult = player.get(CultivationComp);
        if (karma == null || cult == null) return false;

        var netSin = karma.getNetSin();
        if (netSin <= sinThresholdHeartDemon) return false;

        // 冷却检查
        if (world.worldDay - karma.lastTribulationDay < tribulationCooldownDays) return false;

        // 触发天劫
        karma.tribulationType = netSin > sinThresholdLightning ? "lightning" : "heartDemon";
        karma.tribulationPower = calculateTribulationPower(player, netSin);
        executeTribulation(world, player, karma, cult);
        return true;
    }
}
