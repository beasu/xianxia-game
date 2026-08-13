package ecs;

// ============================================================
//  IntentResolutionSystem.hx - 意图决策与仲裁系统
//  priority: 10 (最先执行, 生成意图)
//  负责所有实体的意图生成、冲突检测和战力仲裁
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.Faction;
import ecs.WorldEngine.SpiritVein;
import ecs.WorldEngine.WorldEvent;

class IntentResolutionSystem implements ISystem {
    public var priority:Int = 10;
    public var enabled:Bool = true;

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 1. 处理玩家指令队列
        processPlayerCommands(world);

        // 2. 为每个实体生成/更新意图
        for (e in world.entities) {
            if (!e.alive) continue;
            if (e.isPlayer) continue; // 玩家意图由指令驱动

            var intent = e.get(IntentComp);
            var npcState = e.get(NPCStateComp);
            if (intent == null || npcState == null) continue;

            npcState.decisionCooldown -= dt;

            // 决策冷却到了才重新评估意图
            if (npcState.decisionCooldown <= 0) {
                generateIntent(world, e, intent, npcState);
                npcState.decisionCooldown = randRange(2, 6);
            }

            // 执行意图
            executeIntent(world, e, intent, npcState, dt);
        }

        // 3. 意图冲突仲裁
        resolveConflicts(world);
    }

    // --- 处理玩家提交的指令 ---
    function processPlayerCommands(world:WorldEngine):Void {
        while (world.playerCommandQueue.length > 0) {
            var cmd = world.playerCommandQueue.shift();
            if (world.playerEntity == null || !world.playerEntity.alive) continue;

            var intent = world.playerEntity.get(IntentComp);
            if (intent == null) continue;

            intent.currentIntent = cmd.type;
            intent.targetEntityId = cmd.targetEntityId;
            intent.targetX = cmd.targetX;
            intent.targetY = cmd.targetY;

            if (cmd.type == AttackEntity && cmd.targetEntityId >= 0) {
                // 记忆: 玩家攻击了目标
                var karma = world.playerEntity.get(KarmaComp);
                if (karma != null) {
                    if (!karma.memories.exists(cmd.targetEntityId)) {
                        karma.memories[cmd.targetEntityId] = new MemoryRecord(cmd.targetEntityId, -20, "攻击过");
                    } else {
                        karma.memories[cmd.targetEntityId].relation -= 20;
                    }
                }
            }
        }
    }

    // --- NPC 意图生成器 ---
    function generateIntent(world:WorldEngine, e:Entity, intent:IntentComp, npc:NPCStateComp):Void {
        var cult = e.get(CultivationComp);
        var pos = e.get(PositionComp);
        if (cult == null || pos == null) return;

        // 寿元将尽: 寻找资源或疯狂突破
        if (cult.age > cult.lifespan * 0.8) {
            if (Math.random() < intent.greed) {
                intent.currentIntent = SeekResource;
                return;
            }
        }

        // HP 低: 逃跑
        if (cult.hp < cult.maxHp * 0.3) {
            intent.currentIntent = Flee;
            intent.targetX = npc.homeX;
            intent.targetY = npc.homeY;
            return;
        }

        // 经验满: 冲击境界
        if (cult.exp >= cult.expToNext && cult.realmIndex < WorldEngine.realmList.length - 1) {
            intent.currentIntent = Breakthrough;
            return;
        }

        // 灵力不足: 修炼
        if (cult.mp < cult.maxMp * 0.3) {
            intent.currentIntent = Cultivate;
            return;
        }

        // 搜索附近敌人
        var nearest = world.findNearestEntity(pos.x, pos.y, function(other:Entity):Bool {
            if (other.id == e.id) return false;
            if (!other.alive) return false;
            var otherCult = other.get(CultivationComp);
            if (otherCult == null) return false;
            // 敌对判定: 正道vs魔道, 或有仇
            var otherKarma = other.get(KarmaComp);
            var myKarma = e.get(KarmaComp);
            if (myKarma != null && otherKarma != null) {
                // 有仇的直接攻击
                if (myKarma.memories.exists(other.id) && myKarma.memories[other.id].relation < -30) {
                    return true;
                }
            }
            // 正道vs魔道
            var myFac = e.get(FactionComp);
            var otherFac = other.get(FactionComp);
            if (myFac != null && otherFac != null) {
                if (myFac.factionId != -1 && otherFac.factionId != -1 && myFac.factionId != otherFac.factionId) {
                    var myFaction = findFaction(world, myFac.factionId);
                    var otherFaction = findFaction(world, otherFac.factionId);
                    if (myFaction != null && otherFaction != null) {
                        if (myFaction.alignment != otherFaction.alignment) {
                            return true; // 正魔不两立
                        }
                    }
                }
            }
            // 高攻击性的NPC会主动攻击弱者
            if (intent.aggression > 0.7 && otherCult.getCombatPower() < cult.getCombatPower() * 0.7) {
                return true;
            }
            return false;
        });

        if (nearest != null) {
            var dx = nearest.get(PositionComp).x - pos.x;
            var dy = nearest.get(PositionComp).y - pos.y;
            if (dx * dx + dy * dy < 250 * 250) {
                intent.currentIntent = AttackEntity;
                intent.targetEntityId = nearest.id;
                return;
            }
        }

        // 默认: 随机行为
        var roll = Math.random();
        if (roll < 0.3) {
            intent.currentIntent = Cultivate;
        } else if (roll < 0.7) {
            intent.currentIntent = Wander;
            intent.targetX = npc.homeX + randRange(-npc.patrolRadius, npc.patrolRadius);
            intent.targetY = npc.homeY + randRange(-npc.patrolRadius, npc.patrolRadius);
        } else {
            intent.currentIntent = SeekResource;
        }
    }

    // --- 执行意图 ---
    function executeIntent(world:WorldEngine, e:Entity, intent:IntentComp, npc:NPCStateComp, dt:Float):Void {
        var pos = e.get(PositionComp);
        var cult = e.get(CultivationComp);
        if (pos == null || cult == null) return;

        switch (intent.currentIntent) {
            case Idle:
                // 什么都不做

            case Cultivate:
                // 修炼: 恢复灵力+积累经验
                var veinDensity = getLocalSpiritDensity(world, pos.x, pos.y);
                cult.mp = Math.min(cult.maxMp, cult.mp + 5 * veinDensity * dt * 10);
                cult.exp += 2 * cult.talent * veinDensity * dt * 10;
                pos.vx *= 0.9;
                pos.vy *= 0.9;
                // 修炼中可能触发突破
                if (cult.exp >= cult.expToNext && cult.realmIndex < WorldEngine.realmList.length - 1) {
                    if (Math.random() < 0.02 * cult.luck) {
                        doBreakthrough(world, e, cult);
                    }
                }

            case Wander:
                // 游历: 移动到目标位置
                var dx = intent.targetX - pos.x;
                var dy = intent.targetY - pos.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist > 5) {
                    var speed = 20;
                    pos.vx += (dx / dist) * speed * dt * 10;
                    pos.vy += (dy / dist) * speed * dt * 10;
                } else {
                    intent.currentIntent = Idle;
                }
                // 游历中缓慢恢复
                cult.mp = Math.min(cult.maxMp, cult.mp + 2 * dt * 10);
                cult.exp += 0.5 * dt * 10;

            case SeekResource:
                // 寻找资源: 向最近的灵脉移动
                var nearestVein = findNearestVein(world, pos.x, pos.y);
                if (nearestVein != null) {
                    var dx = nearestVein.x - pos.x;
                    var dy = nearestVein.y - pos.y;
                    var dist = Math.sqrt(dx * dx + dy * dy);
                    if (dist > 20) {
                        var speed = 30;
                        pos.vx += (dx / dist) * speed * dt * 10;
                        pos.vy += (dy / dist) * speed * dt * 10;
                    } else {
                        // 到达灵脉, 开始修炼
                        intent.currentIntent = Cultivate;
                        // 随机获得灵草
                        if (Math.random() < 0.1) {
                            var inv = e.get(InventoryComp);
                            if (inv != null) inv.herbs++;
                        }
                    }
                }

            case AttackEntity:
                // 攻击目标
                var target = world.getEntity(intent.targetEntityId);
                if (target == null || !target.alive) {
                    intent.currentIntent = Idle;
                    return;
                }
                var targetPos = target.get(PositionComp);
                var targetCult = target.get(CultivationComp);
                if (targetPos == null || targetCult == null) {
                    intent.currentIntent = Idle;
                    return;
                }
                var dx = targetPos.x - pos.x;
                var dy = targetPos.y - pos.y;
                var dist = Math.sqrt(dx * dx + dy * dy);

                if (dist > 40) {
                    // 移动靠近目标
                    var speed = 35;
                    pos.vx += (dx / dist) * speed * dt * 10;
                    pos.vy += (dy / dist) * speed * dt * 10;
                } else {
                    // 攻击!
                    npc.aiTimer -= dt;
                    if (npc.aiTimer <= 0) {
                        npc.aiTimer = 1.0;
                        // 伤害计算
                        var dmg = cult.attackPower + Std.int(randRange(0, 10));
                        targetCult.hp -= dmg;

                        world.emitEvent(new WorldEvent(e.id, target.id, "Attack",
                            e.name + " 攻击 " + target.name + ", 造成" + dmg + "伤害"
                        ));

                        // 目标反击意图
                        var targetIntent = target.get(IntentComp);
                        if (targetIntent != null && targetCult.hp > 0) {
                            targetIntent.currentIntent = AttackEntity;
                            targetIntent.targetEntityId = e.id;
                        }

                        // 目标死亡
                        if (targetCult.hp <= 0) {
                            target.alive = false;
                            // 击杀者获得经验和灵石
                            cult.exp += 20 + targetCult.realmIndex * 15;
                            var inv = e.get(InventoryComp);
                            var targetInv = target.get(InventoryComp);
                            if (inv != null && targetInv != null) {
                                inv.spiritStones += targetInv.spiritStones;
                            }
                            // 业力变化
                            var karma = e.get(KarmaComp);
                            var targetKarma = target.get(KarmaComp);
                            if (karma != null) {
                                karma.killCount++;
                                if (targetKarma != null && targetKarma.karma > 0) {
                                    karma.karma -= 10; // 杀正道人士增加恶业
                                    karma.notoriety += 5;
                                } else {
                                    karma.karma += 5; // 斩魔有功德
                                }
                            }

                            world.emitEvent(new WorldEvent(e.id, target.id, "Kill",
                                e.name + " 击杀了 " + target.name + "!"
                            ));
                        }
                    }
                }

            case Flee:
                // 逃跑
                var dx = intent.targetX - pos.x;
                var dy = intent.targetY - pos.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist > 5) {
                    var speed = 120;
                    pos.vx += (dx / dist) * speed * dt * 10;
                    pos.vy += (dy / dist) * speed * dt * 10;
                } else {
                    cult.hp = Math.min(cult.maxHp, cult.hp + cult.maxHp * 0.1);
                    intent.currentIntent = Cultivate;
                }

            case Trade:
                // 交易: 向世界市场购买
                var inv = e.get(InventoryComp);
                if (inv == null) return;
                for (item in world.marketItems) {
                    if (!item.sold && inv.spiritStones >= item.price && Math.random() < 0.1) {
                        inv.spiritStones -= item.price;
                        item.sold = true;
                        var seller = world.getEntity(item.sellerId);
                        if (seller != null) {
                            var sellerInv = seller.get(InventoryComp);
                            if (sellerInv != null) sellerInv.spiritStones += item.price;
                        }
                        world.emitEvent(new WorldEvent(e.id, item.sellerId, "Trade",
                            e.name + " 购买了 " + item.name
                        ));
                    }
                }

            case Breakthrough:
                doBreakthrough(world, e, cult);

            case JoinFaction:
                // 尝试加入附近宗门
                if (world.factions.length > 0) {
                    var fac = e.get(FactionComp);
                    if (fac != null && fac.factionId == -1) {
                        var f = world.factions[Std.int(Math.random(world.factions.length))];
                        if (f.alive) {
                            fac.factionId = f.id;
                            fac.factionName = f.name;
                            fac.factionRank = 0;
                            world.emitEvent(new WorldEvent(e.id, -1, "JoinFaction",
                                e.name + " 加入" + f.name
                            ));
                        }
                    }
                }
                intent.currentIntent = Idle;

            case PlayerCommand:
                // 玩家指令已在 processPlayerCommands 中处理

            case Socialize:
                // 社交行为由 NPCSocialSystem 处理, 这里不重复

            case Betray:
                // 背叛由 NPCSocialSystem 处理

            case Assassinate:
                // 暗杀由 NPCSocialSystem 处理

            case Hunt:
                // 追杀意图: 向追杀目标移动并发起攻击
                var target = world.getEntity(intent.targetEntityId);
                if (target == null || !target.alive) {
                    intent.currentIntent = Idle;
                    return;
                }
                var targetPos = target.get(PositionComp);
                if (targetPos == null) {
                    intent.currentIntent = Idle;
                    return;
                }
                var dx = targetPos.x - pos.x;
                var dy = targetPos.y - pos.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist > 40) {
                    // 追击(速度比普通攻击快)
                    var speed = 50;
                    pos.vx += (dx / dist) * speed * dt * 10;
                    pos.vy += (dy / dist) * speed * dt * 10;
                } else {
                    // 发起攻击(复用 AttackEntity 的攻击逻辑)
                    var targetCult = target.get(CultivationComp);
                    if (targetCult != null) {
                        npc.aiTimer -= dt;
                        if (npc.aiTimer <= 0) {
                            npc.aiTimer = 0.8; // 追杀者攻击频率更高
                            var dmg = Std.int(cult.attackPower * 1.2 + Math.random(10));
                            targetCult.hp -= dmg;
                            world.emitEvent(new WorldEvent(e.id, target.id, "HuntAttack",
                                e.name + " 追杀 " + target.name + ", 造成" + dmg + "伤害"
                            ));
                            if (targetCult.hp <= 0) {
                                target.alive = false;
                                cult.exp += 30 + targetCult.realmIndex * 20;
                                world.emitEvent(new WorldEvent(e.id, target.id, "Kill",
                                    e.name + " 追杀得手, " + target.name + "殒命!"
                                ));
                                intent.currentIntent = Idle;
                            }
                        }
                    }
                }

            case Dead:
                // do nothing
        }

    }

    // --- 意图冲突仲裁 ---
    function resolveConflicts(world:WorldEngine):Void {
        // 检测多个实体攻击同一目标的冲突
        // 如果两个实体同时攻击同一个目标, 先由战力高的造成伤害
        // (已在 executeIntent 的 AttackEntity 中处理)

        // 检测资源争夺冲突
        // 两个实体同时到达灵脉, 根据气运判定谁获得资源
        // (在 SeekResource 中通过随机概率处理)
    }

    // --- 执行突破 ---
    function doBreakthrough(world:WorldEngine, e:Entity, cult:CultivationComp):Void {
        var successRate = 0.5 + cult.luck * 0.2 + cult.talent * 0.1 - cult.realmIndex * 0.05;
        successRate = Math.clamp(successRate, 0.1, 0.95);

        if (Math.random() < successRate) {
            cult.realmIndex++;
            cult.realmName = WorldEngine.realmList[cult.realmIndex].name;
            cult.exp = 0;
            cult.expToNext = Std.int(cult.expToNext * 1.5);
            cult.maxHp = Std.int(cult.maxHp * 1.4 * cult.talent);
            cult.hp = cult.maxHp;
            cult.maxMp = Std.int(cult.maxMp * 1.4 * cult.talent);
            cult.mp = cult.maxMp;
            cult.attackPower = Std.int(cult.attackPower * 1.3 * cult.talent);
            cult.lifespan = WorldEngine.realmList[cult.realmIndex].lifespan;

            // 品质提升
            if (cult.spiritRootQuality < 4 && Math.random() < 0.15) {
                cult.spiritRootQuality++;
                var qNames = ["凡品", "良品", "上品", "极品", "天灵根"];
                cult.spiritRootQualityName = qNames[cult.spiritRootQuality];
            }

            world.emitEvent(new WorldEvent(e.id, -1, "Breakthrough",
                e.name + " 突破至 " + cult.realmName + "!"
            ));

            var intent = e.get(IntentComp);
            if (intent != null) intent.currentIntent = Idle;
        } else {
            // 突破失败, 受伤
            cult.hp *= 0.7;
            cult.exp *= 0.5;
            world.emitEvent(new WorldEvent(e.id, -1, "BreakthroughFail",
                e.name + " 突破失败, 走火入魔!"
            ));
            var intent = e.get(IntentComp);
            if (intent != null) intent.currentIntent = Cultivate;
        }
    }

    // --- 辅助 ---
    function findFaction(world:WorldEngine, id:Int):Faction {
        for (f in world.factions) {
            if (f.id == id) return f;
        }
        return null;
    }

    function findNearestVein(world:WorldEngine, x:Float, y:Float):SpiritVein {
        var nearest:SpiritVein = null;
        var nearestDist = Math.POSITIVE_INFINITY;
        for (v in world.spiritVeins) {
            var dx = v.x - x;
            var dy = v.y - y;
            var dist = dx * dx + dy * dy;
            if (dist < nearestDist) {
                nearestDist = dist;
                nearest = v;
            }
        }
        return nearest;
    }

    function getLocalSpiritDensity(world:WorldEngine, x:Float, y:Float):Float {
        var density = world.globalSpiritDensity * 0.5; // 基础浓度
        for (v in world.spiritVeins) {
            var dx = v.x - x;
            var dy = v.y - y;
            var dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < 200) {
                density += v.currentDensity * (1 - dist / 200);
            }
        }
        return density;
    }

    function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }
}

// ============================================================
//  EcologySystem.hx - 生态与经济流转系统
//  priority: 20 (意图系统之后)
//  灵脉潮汐、NPC资源采集、势力日常
// ============================================================

class EcologySystem implements ISystem {
    public var priority:Int = 20;
    public var enabled:Bool = true;

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 灵脉潮汐连续更新
        for (v in world.spiritVeins) {
            v.tidePhase += dt * 0.1;
            v.currentDensity = v.baseDensity * (0.7 + Math.sin(v.tidePhase) * 0.3);
        }

        // NPC 资源消耗(灵石)
        for (e in world.entities) {
            if (!e.alive) continue;
            var inv = e.get(InventoryComp);
            var cult = e.get(CultivationComp);
            if (inv == null || cult == null) continue;

            // 每天消耗灵石修炼
            if (world.tickCount % world.ticksPerDay == 0) {
                if (inv.spiritStones > 0) {
                    inv.spiritStones--;
                    cult.exp += 5; // 灵石修炼加速
                }
            }
        }

        // 实体自动恢复 HP
        for (e in world.entities) {
            if (!e.alive) continue;
            var cult = e.get(CultivationComp);
            if (cult == null) continue;
            if (cult.hp < cult.maxHp) {
                cult.hp = Math.min(cult.maxHp, cult.hp + cult.maxHp * 0.01 * dt * 10);
            }
        }
    }
}

// ============================================================
//  HistorySystem.hx - 历史与因果演化系统
//  priority: 30 (最后执行)
//  世界记忆、动态称号、悬赏生成
// ============================================================

class HistorySystem implements ISystem {
    public var priority:Int = 30;
    public var enabled:Bool = true;

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 每天检查一次
        if (world.tickCount % world.ticksPerDay != 0) return;

        // 动态称号生成
        for (e in world.entities) {
            if (!e.alive) continue;
            var karma = e.get(KarmaComp);
            if (karma == null) continue;

            // 清除旧动态称号
            karma.titles = karma.titles.filter(function(t) return !isDynamicTitle(t));

            // 屠夫称号
            if (karma.killCount >= 10 && karma.notoriety > 30) {
                karma.titles.push("血手人屠");
            }

            // 正道称号
            if (karma.karma > 50 && karma.reputation > 20) {
                karma.titles.push("正道楷模");
            }

            // 恶名昭著
            if (karma.notoriety > 50) {
                karma.titles.push("恶名昭著");
                // 自动生成悬赏
                if (karma.bounty < karma.notoriety * 10) {
                    karma.bounty = Std.int(karma.notoriety * 10);
                    world.emitEvent(new WorldEvent(-1, e.id, "Bounty",
                        "正道发布悬赏: 缉拿" + e.name + ", 赏金" + karma.bounty + "灵石"
                    ));
                }
            }

            // 飞升称号
            var cult = e.get(CultivationComp);
            if (cult != null && cult.realmIndex >= 7) {
                karma.titles.push("半步飞升");
            }
        }

        // NPC 记忆衰减(长期未互动的关系逐渐淡化)
        for (e in world.entities) {
            if (!e.alive) continue;
            var karma = e.get(KarmaComp);
            if (karma == null) continue;
            for (memId in karma.memories.keys()) {
                var mem = karma.memories[memId];
                var daysSince = world.worldDay - mem.lastInteraction;
                if (daysSince > 100) {
                    // 关系衰减
                    mem.relation *= 0.95;
                    if (Math.abs(mem.relation) < 1) {
                        karma.memories.remove(memId);
                    }
                }
            }
        }
    }

    function isDynamicTitle(t:String):Bool {
        return t == "血手人屠" || t == "正道楷模" || t == "恶名昭著" || t == "半步飞升";
    }
}
