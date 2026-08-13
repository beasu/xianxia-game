package ecs;

// ============================================================
//  HeavenlyDaoSystem.hx - 天道意志系统
//  priority: 40 (最终仲裁, 在所有系统之后执行)
//
//  天道不是 NPC, 是世界本身的意志, 会在以下情况干预:
//
//  1. 力量失衡: 某势力过强(>50%总实力) → 天道削弱
//     - 提升该势力成员的业障
//     - 给其他势力成员buff
//     - 极端情况直接降下天罚
//
//  2. 杀戮过度: 短期内大量死亡 → 天道降劫
//     - 死亡率超过阈值 → 天劫降临幸存者
//     - "大劫将至" 预警
//
//  3. 灵气失衡: 灵气浓度极端 → 天道调节
//     - 灵气枯竭区域 → 天道降下灵雨
//     - 灵气过浓区域 → 天道引来灵兽守护
//
//  4. 因果失衡: 世界总业障过高 → 天道清洗
//     - 总业障 > 阈值 → 天道选中业障最高者降劫
//     - "天道之眼" 锁定
//
//  5. 命运编织: 随机给某些NPC命运buff/debuff
//     - "天命之人": 随机给低境界高天赋者气运提升
//     - "天弃之子": 随机给业障高者气运降低
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class HeavenlyDaoSystem implements ISystem {
    public var priority:Int = 40;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var factionImbalanceThreshold:Float = 0.50;  // 势力失衡阈值
    public var massDeathThreshold:Int = 5;              // 短期大量死亡阈值
    public var massDeathWindow:Float = 60;             // 死亡统计窗口(秒)
    public var worldSinThreshold:Float = 500;           // 世界总业障阈值
    public var spiritDepletedThreshold:Float = 0.2;    // 灵气枯竭阈值
    public var spiritOverloadThreshold:Float = 3.0;    // 灵气过浓阈值
    public var destinyCheckInterval:Float = 120;       // 命运检查间隔(秒)
    public var tribulationBaseDamage:Float = 500;      // 天罚基础伤害

    // 内部状态
    var recentDeaths:Array<{tick:Int, time:Float}> = [];
    var destinyTimer:Float = 0;
    var interventionCooldown:Float = 0;

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        if (interventionCooldown > 0) interventionCooldown -= dt;

        // 1. 检测力量失衡
        checkFactionImbalance(world);

        // 2. 检测杀戮过度
        checkMassDeath(world, dt);

        // 3. 检测灵气失衡
        checkSpiritImbalance(world);

        // 4. 检测因果失衡
        checkKarmaImbalance(world);

        // 5. 命运编织
        destinyTimer += dt;
        if (destinyTimer >= destinyCheckInterval) {
            destinyTimer = 0;
            weaveDestiny(world);
        }
    }

    // --- 力量失衡 ---
    function checkFactionImbalance(world:WorldEngine):Void {
        if (interventionCooldown > 0) return;

        var factionPowers = new Map<Int, Float>();
        var totalPower:Float = 0;

        for (e in world.entities) {
            if (!e.alive) continue;
            var fc = e.get(FactionComp);
            var cult = e.get(CultivationComp);
            if (fc == null || cult == null) continue;
            var power = cult.attackPower * cult.maxHp * (1 + cult.realmIndex);
            factionPowers.set(fc.factionId, (factionPowers.get(fc.factionId) ?? 0) + power);
            totalPower += power;
        }

        if (totalPower <= 0) return;

        for (fid => power in factionPowers) {
            if (power / totalPower > factionImbalanceThreshold) {
                // 天道干预: 削弱过强势力
                var fname = "未知势力";
                for (f in world.factions) {
                    if (f.id == fid) { fname = f.name; break; }
                }

                // 给该势力成员增加业障
                var affected = 0;
                for (e in world.entities) {
                    if (!e.alive) continue;
                    var fc = e.get(FactionComp);
                    var karma = e.get(KarmaComp);
                    if (fc != null && fc.factionId == fid && karma != null) {
                        karma.sinValue += 5;
                        affected++;
                    }
                }

                // 给其他势力成员气运提升
                for (e in world.entities) {
                    if (!e.alive) continue;
                    var fc = e.get(FactionComp);
                    var cult = e.get(CultivationComp);
                    if (fc != null && fc.factionId != fid && cult != null) {
                        cult.luck = Math.min(1.0, cult.luck + 0.1);
                    }
                }

                world.emitEvent(new WorldEvent(-1, -1, "HeavenlyIntervention",
                    "天道察觉" + fname + "势力过盛, 降下警兆, " + affected + "名修士业障加重"
                ));
                interventionCooldown = 120;
                return;
            }
        }
    }

    // --- 杀戮过度 ---
    function checkMassDeath(world:WorldEngine, dt:Float):Void {
        if (interventionCooldown > 0) return;

        // 记录死亡事件
        var recentEvents = world.eventLog.slice(-5);
        for (evt in recentEvents) {
            if (evt.type == "Kill" || evt.type == "TribulationDeath") {
                var alreadyLogged = false;
                for (d in recentDeaths) {
                    if (d.tick == evt.tick) { alreadyLogged = true; break; }
                }
                if (!alreadyLogged) {
                    recentDeaths.push({tick: evt.tick, time: 0});
                }
            }
        }

        // 清理过期记录
        var i = recentDeaths.length;
        while (i-- > 0) {
            recentDeaths[i].time += dt;
            if (recentDeaths[i].time > massDeathWindow) {
                recentDeaths.splice(i, 1);
            }
        }

        if (recentDeaths.length >= massDeathThreshold) {
            // 天道降劫: 对幸存者中最强者降下天劫
            var strongest:Entity = null;
            var maxPower:Float = 0;
            for (e in world.entities) {
                if (!e.alive || e.isPlayer) continue;
                var cult = e.get(CultivationComp);
                if (cult == null) continue;
                var power = cult.attackPower * cult.maxHp;
                if (power > maxPower) { maxPower = power; strongest = e; }
            }

            if (strongest != null) {
                var cult = strongest.get(CultivationComp);
                var karma = strongest.get(KarmaComp);
                if (cult != null) {
                    var dmg = tribulationBaseDamage * (1 + (karma != null ? karma.getNetSin() / 100 : 0));
                    cult.hp -= dmg;
                    world.emitEvent(new WorldEvent(strongest.id, -1, "HeavenlyTribulation",
                        "天道震怒! 降下天罚于" + strongest.name + ", 造成" + Math.round(dmg) + "伤害"
                    ));
                    if (cult.hp <= 0) {
                        cult.hp = 0;
                        strongest.alive = false;
                        world.emitEvent(new WorldEvent(strongest.id, -1, "TribulationDeath",
                            strongest.name + " 殒命于天罚"
                        ));
                    }
                }
            }

            recentDeaths = [];
            interventionCooldown = 90;
        }
    }

    // --- 灵气失衡 ---
    function checkSpiritImbalance(world:WorldEngine):Void {
        if (interventionCooldown > 0) return;

        // 检查灵脉系统
        var depletedCount = 0;
        var overloadCount = 0;
        for (vein in world.spiritVeins) {
            if (vein.currentDensity < spiritDepletedThreshold) depletedCount++;
            if (vein.currentDensity > spiritOverloadThreshold) overloadCount++;
        }

        var totalVeins = world.spiritVeins.length;
        if (totalVeins == 0) return;

        if (depletedCount > totalVeins * 0.6) {
            // 天道降灵雨: 恢复所有灵脉
            for (vein in world.spiritVeins) {
                vein.currentDensity = Math.min(vein.baseDensity, vein.currentDensity * 1.5);
            }
            world.emitEvent(new WorldEvent(-1, -1, "SpiritRain",
                "天道降下灵雨, 天地灵气回涌"
            ));
            interventionCooldown = 60;
        } else if (overloadCount > totalVeins * 0.4) {
            // 天道引来灵兽守护(增加NPC)
            world.spawnRandomNPC();
            world.spawnRandomNPC();
            world.emitEvent(new WorldEvent(-1, -1, "SpiritBeastGuardian",
                "灵气过盛之地, 天道引灵兽守护"
            ));
            interventionCooldown = 60;
        }
    }

    // --- 因果失衡 ---
    function checkKarmaImbalance(world:WorldEngine):Void {
        if (interventionCooldown > 0) return;

        var totalSin:Float = 0;
        var maxSin:Float = 0;
        var maxSinEntity:Entity = null;

        for (e in world.entities) {
            if (!e.alive) continue;
            var karma = e.get(KarmaComp);
            if (karma == null) continue;
            var netSin = karma.getNetSin();
            totalSin += netSin;
            if (netSin > maxSin) { maxSin = netSin; maxSinEntity = e; }
        }

        if (totalSin > worldSinThreshold && maxSinEntity != null) {
            // 天道之眼锁定业障最高者
            var cult = maxSinEntity.get(CultivationComp);
            var karma = maxSinEntity.get(KarmaComp);
            if (cult != null && karma != null) {
                // 降下心魔劫
                karma.tribulationType = "heartDemon";
                karma.tribulationPower = 1.0 + maxSin / 100;
                world.emitEvent(new WorldEvent(maxSinEntity.id, -1, "HeavenlyEye",
                    "天道之眼锁定" + maxSinEntity.name + ", 业障深重, 心魔劫将至"
                ));
            }
            interventionCooldown = 150;
        }
    }

    // --- 命运编织 ---
    function weaveDestiny(world:WorldEngine):Void {
        // 天命之人: 给低境界高天赋者气运提升
        var candidates:Array<Entity> = [];
        for (e in world.entities) {
            if (!e.alive || e.isPlayer) continue;
            var cult = e.get(CultivationComp);
            if (cult == null) continue;
            if (cult.realmIndex <= 3 && cult.talent >= 1.5) {
                candidates.push(e);
            }
        }

        if (candidates.length > 0 && Math.random() < 0.3) {
            var chosen = candidates[Math.floor(Math.random() * candidates.length)];
            var cult = chosen.get(CultivationComp);
            if (cult != null) {
                cult.luck = Math.min(1.0, cult.luck + 0.3);
                world.emitEvent(new WorldEvent(chosen.id, -1, "DestinyChosen",
                    chosen.name + " 得天道眷顾, 天命加身, 气运大涨"
                ));
            }
        }

        // 天弃之子: 给业障高者气运降低
        var sinners:Array<Entity> = [];
        for (e in world.entities) {
            if (!e.alive || e.isPlayer) continue;
            var karma = e.get(KarmaComp);
            if (karma == null) continue;
            if (karma.getNetSin() > 40) {
                sinners.push(e);
            }
        }

        if (sinners.length > 0 && Math.random() < 0.4) {
            var chosen = sinners[Math.floor(Math.random() * sinners.length)];
            var cult = chosen.get(CultivationComp);
            if (cult != null) {
                cult.luck = Math.max(0.1, cult.luck - 0.2);
                world.emitEvent(new WorldEvent(chosen.id, -1, "DestinyForsaken",
                    chosen.name + " 为天道所弃, 气运低迷"
                ));
            }
        }
    }
}
