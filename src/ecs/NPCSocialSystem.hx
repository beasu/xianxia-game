package ecs;

// ============================================================
//  NPCSocialSystem.hx - NPC 社会行为系统
//  priority: 18 (在意图系统之后, 生态引擎之前)
//
//  核心机制:
//  1. 为 NPC 增加 SocialComp 组件, 跟踪社交关系网
//  2. 基于好感度(affinity)和信任度(trust)决定社交行为:
//     - 高好感 + 同境界 -> 结盟
//     - 高好感 + 异性 + 修为相当 -> 联姻(结为道侣)
//     - 低忠诚 + 高野心 + 有盟友 -> 背叛
//     - 低好感 + 高攻击性 -> 暗杀
//     - 师徒关系: 高境界收低境界为弟子
//  3. 社交行为影响业障(暗杀/背叛增加 sinValue)
//  4. 结盟后共享部分资源和战斗支援
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class NPCSocialSystem implements ISystem {
    public var priority:Int = 18;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var socialCheckInterval:Float = 5.0;    // 社交决策间隔(秒)
    public var socialRange:Float = 500;            // 社交检测范围(像素)
    public var allyThreshold:Float = 40;           // 结盟所需好感度
    public var marriageThreshold:Float = 60;       // 联姻所需好感度
    public var betrayThreshold:Float = -30;        // 背叛触发好感度(负值)
    public var assassinateThreshold:Float = -50;   // 暗杀触发好感度
    public var masterDiscipleRealmGap:Int = 3;     // 师徒所需境界差
    public var maxAllies:Int = 5;                  // 最大盟友数

    // 社交行为枚举
    static inline var ACT_ALLY:String = "Ally";
    static inline var ACT_BETRAY:String = "Betray";
    static inline var ACT_MARRY:String = "Marry";
    static inline var ACT_ASSASSINATE:String = "Assassinate";
    static inline var ACT_TAKE_DISCIPLE:String = "TakeDisciple";

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            if (e.isPlayer) continue;

            var social = e.get(SocialComp);
            if (social == null) continue;

            social.socialCooldown -= dt;
            if (social.socialCooldown > 0) continue;

            social.socialCooldown = socialCheckInterval + randRange(0, 3);

            // 执行社交决策
            makeSocialDecision(world, e, social);
        }

        // 每日更新: 关系衰减
        if (world.tickCount % world.ticksPerDay == 0) {
            dailyRelationDecay(world);
        }
    }

    // --- 社交决策: 评估周围实体, 选择最高优先级的社交行为 ---
    function makeSocialDecision(world:WorldEngine, entity:Entity, social:SocialComp):Void {
        var pos = entity.get(PositionComp);
        var cult = entity.get(CultivationComp);
        var intent = entity.get(IntentComp);
        if (pos == null || cult == null || intent == null) return;

        // 搜索附近实体
        var bestTarget:Entity = null;
        var bestAction:String = "";
        var bestScore:Float = 0;

        for (other in world.entities) {
            if (!other.alive || other.id == entity.id) continue;
            var otherPos = other.get(PositionComp);
            var otherCult = other.get(CultivationComp);
            if (otherPos == null || otherCult == null) continue;

            // 距离检查
            var dx = otherPos.x - pos.x;
            var dy = otherPos.y - pos.y;
            var dist = Math.sqrt(dx * dx + dy * dy);
            if (dist > socialRange) continue;

            var rel = getOrCreateRelation(social, other.id);
            var otherSocial = other.get(SocialComp);

            // 评估各种社交行为的优先级
            var actions = evaluateActions(world, entity, other, social, rel, cult, otherCult, dist);

            for (a in actions) {
                if (a.score > bestScore) {
                    bestScore = a.score;
                    bestTarget = other;
                    bestAction = a.action;
                }
            }
        }

        // 执行最高优先级的社交行为
        if (bestTarget != null && bestAction != "") {
            executeSocialAction(world, entity, bestTarget, bestAction, social);
        }
    }

    // --- 评估可执行的社交行为 ---
    function evaluateActions(world:WorldEngine, me:Entity, other:Entity,
        social:SocialComp, rel:SocialRelation, cult:CultivationComp, otherCult:CultivationComp, dist:Float
    ):Array<{action:String, score:Float}> {
        var actions:Array<{action:String, score:Float}> = [];

        // 1. 暗杀: 低好感 + 高攻击性 + 对方有宝物或高修为
        if (rel.affinity < assassinateThreshold) {
            var score = -rel.affinity * 0.5 + intent_aggression(me) * 30;
            if (otherCult.getCombatPower() < cult.getCombatPower() * 1.3) {
                score += 20; // 弱者优先
            }
            actions.push({action: ACT_ASSASSINATE, score: score});
        }

        // 2. 背叛: 低忠诚 + 高野心 + 有盟友关系
        if (rel.relationType == "ally" && social.loyalty < 0.4 && social.ambition > 0.6) {
            var score = (social.ambition - social.loyalty) * 50 + (otherCult.realmIndex < cult.realmIndex ? 20 : 0);
            actions.push({action: ACT_BETRAY, score: score});
        }

        // 3. 联姻: 高好感 + 修为相当 + 双方无道侣
        if (rel.affinity > marriageThreshold && social.spouseId == -1) {
            var otherSocial = other.get(SocialComp);
            if (otherSocial != null && otherSocial.spouseId == -1) {
                var realmDiff = Math.abs(cult.realmIndex - otherCult.realmIndex);
                if (realmDiff <= 1) {
                    var score = rel.affinity * 0.4 + social.charm * 20;
                    actions.push({action: ACT_MARRY, score: score});
                }
            }
        }

        // 4. 结盟: 高好感 + 非盟友 + 未满盟友上限
        if (rel.affinity > allyThreshold && rel.relationType != "ally" && social.allies.length < maxAllies) {
            var score = rel.affinity * 0.3 + (otherCult.getCombatPower() > cult.getCombatPower() ? 10 : 5);
            actions.push({action: ACT_ALLY, score: score});
        }

        // 5. 收徒: 高境界 + 对方低境界 + 无师徒关系
        if (cult.realmIndex - otherCult.realmIndex >= masterDiscipleRealmGap) {
            var otherSocial = other.get(SocialComp);
            if (otherSocial != null && otherSocial.masterId == -1 && social.disciples.length < 3) {
                var score = 15 + rel.affinity * 0.2;
                actions.push({action: ACT_TAKE_DISCIPLE, score: score});
            }
        }

        return actions;
    }

    // --- 执行社交行为 ---
    function executeSocialAction(world:WorldEngine, me:Entity, target:Entity, action:String, social:SocialComp):Void {
        var myName = me.name;
        var targetName = target.name;
        var rel = getOrCreateRelation(social, target.id);
        var targetSocial = target.get(SocialComp);
        var intent = me.get(IntentComp);

        switch (action) {
            case ACT_ALLY:
                social.allies.push(target.id);
                rel.relationType = "ally";
                rel.affinity += 10;
                rel.trust += 15;
                // 双向建立关系
                if (targetSocial != null) {
                    targetSocial.allies.push(me.id);
                    var tRel = getOrCreateRelation(targetSocial, me.id);
                    tRel.relationType = "ally";
                    tRel.affinity += 10;
                    tRel.trust += 15;
                }
                world.emitEvent(new WorldEvent(me.id, target.id, "Ally",
                    myName + " 与 " + targetName + " 结为盟友"
                ));

            case ACT_BETRAY:
                // 移除盟友关系
                social.allies.remove(target.id);
                rel.relationType = "rival";
                rel.affinity = -50;
                rel.trust = 0;
                if (targetSocial != null) {
                    targetSocial.allies.remove(me.id);
                    var tRel = getOrCreateRelation(targetSocial, me.id);
                    tRel.relationType = "enemy";
                    tRel.affinity = -60;
                    tRel.trust = 0;
                }
                // 背叛者获得对方的灵石
                var myInv = me.get(InventoryComp);
                var targetInv = target.get(InventoryComp);
                if (myInv != null && targetInv != null) {
                    var stolen = Std.int(targetInv.spiritStones * 0.5);
                    targetInv.spiritStones -= stolen;
                    myInv.spiritStones += stolen;
                }
                // 发出背叛事件(KarmaAndTribulationSystem 会增加业障)
                world.emitEvent(new WorldEvent(me.id, target.id, "Betray",
                    myName + " 背叛了盟友 " + targetName + ", 窃取半数灵石!"
                ));
                // 被背叛者产生攻击意图
                var targetIntent = target.get(IntentComp);
                if (targetIntent != null) {
                    targetIntent.currentIntent = AttackEntity;
                    targetIntent.targetEntityId = me.id;
                }

            case ACT_MARRY:
                social.spouseId = target.id;
                rel.relationType = "spouse";
                rel.affinity += 30;
                rel.trust = 100;
                if (targetSocial != null) {
                    targetSocial.spouseId = me.id;
                    var tRel = getOrCreateRelation(targetSocial, me.id);
                    tRel.relationType = "spouse";
                    tRel.affinity += 30;
                    tRel.trust = 100;
                }
                // 双修加成: 双方修为提升
                var myCult = me.get(CultivationComp);
                var targetCult = target.get(CultivationComp);
                if (myCult != null && targetCult != null) {
                    myCult.exp += 50;
                    targetCult.exp += 50;
                    myCult.maxMp = Std.int(myCult.maxMp * 1.05);
                    targetCult.maxMp = Std.int(targetCult.maxMp * 1.05);
                }
                world.emitEvent(new WorldEvent(me.id, target.id, "Marry",
                    myName + " 与 " + targetName + " 结为道侣, 共证大道"
                ));

            case ACT_ASSASSINATE:
                var myCult = me.get(CultivationComp);
                var targetCult = target.get(CultivationComp);
                var targetPos = target.get(PositionComp);
                if (myCult == null || targetCult == null || targetPos == null) return;

                // 暗杀成功率: 基于修为差 + 智慧
                var successRate = 0.3 + (myCult.getCombatPower() / (myCult.getCombatPower() + targetCult.getCombatPower())) * 0.4;
                var myIntent = me.get(IntentComp);
                if (myIntent != null) {
                    successRate += myIntent.wisdom * 0.15;
                }

                if (Math.random() < successRate) {
                    // 暗杀成功
                    var dmg = myCult.attackPower * 3 + randRange(0, 50);
                    targetCult.hp -= dmg;

                    world.emitEvent(new WorldEvent(me.id, target.id, "Assassinate",
                        myName + " 暗杀了 " + targetName + ", 造成" + Std.int(dmg) + "暗伤!"
                    ));

                    if (targetCult.hp <= 0) {
                        target.alive = false;
                        // 获得战利品
                        var myInv = me.get(InventoryComp);
                        var targetInv = target.get(InventoryComp);
                        if (myInv != null && targetInv != null) {
                            myInv.spiritStones += targetInv.spiritStones;
                        }
                        myCult.exp += 30 + targetCult.realmIndex * 20;
                        world.emitEvent(new WorldEvent(me.id, target.id, "Kill",
                            myName + " 暗杀得手, " + targetName + " 殒命!"
                        ));
                    }
                } else {
                    // 暗杀失败
                    world.emitEvent(new WorldEvent(me.id, target.id, "AssassinateFail",
                        myName + " 暗杀 " + targetName + " 失败, 暴露行踪!"
                    ));
                    rel.relationType = "enemy";
                    rel.affinity = -80;
                    // 目标反击
                    var targetIntent = target.get(IntentComp);
                    if (targetIntent != null) {
                        targetIntent.currentIntent = AttackEntity;
                        targetIntent.targetEntityId = me.id;
                    }
                }

            case ACT_TAKE_DISCIPLE:
                social.disciples.push(target.id);
                rel.relationType = "disciple";
                rel.affinity += 15;
                rel.trust += 20;
                if (targetSocial != null) {
                    targetSocial.masterId = me.id;
                    var tRel = getOrCreateRelation(targetSocial, me.id);
                    tRel.relationType = "master";
                    tRel.affinity += 15;
                    tRel.trust += 20;
                }
                // 师徒传功: 弟子获得经验加成
                var targetCult = target.get(CultivationComp);
                if (targetCult != null) {
                    targetCult.exp += 30;
                    targetCult.talent += 0.1; // 师父指点提升天赋
                }
                world.emitEvent(new WorldEvent(me.id, target.id, "TakeDisciple",
                    myName + " 收 " + targetName + " 为弟子, 传道授业"
                ));
        }

        rel.lastInteractionDay = WorldEngine.inst.worldDay;
        rel.interactionCount++;
    }

    // --- 每日关系衰减 ---
    function dailyRelationDecay(world:WorldEngine):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            var social = e.get(SocialComp);
            if (social == null) continue;

            for (relId in social.relationships.keys()) {
                var rel = social.relationships[relId];
                var daysSince = world.worldDay - rel.lastInteractionDay;
                if (daysSince > 50) {
                    // 长期未互动, 好感度衰减
                    rel.affinity *= 0.98;
                    rel.trust *= 0.98;
                    if (Math.abs(rel.affinity) < 1 && rel.relationType == "neutral") {
                        social.relationships.remove(relId);
                    }
                }
            }
        }
    }

    // --- 获取或创建关系 ---
    function getOrCreateRelation(social:SocialComp, entityId:Int):SocialRelation {
        if (!social.relationships.exists(entityId)) {
            social.relationships[entityId] = new SocialRelation(entityId, 0, "neutral");
        }
        return social.relationships[entityId];
    }

    // --- 获取实体的攻击性 ---
    function intent_aggression(e:Entity):Float {
        var intent = e.get(IntentComp);
        return intent != null ? intent.aggression : 0.5;
    }

    function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }
}
