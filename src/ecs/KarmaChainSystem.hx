package ecs;

// ============================================================
//  KarmaChainSystem.hx - 因果链系统
//  priority: 28 (在 KarmaAndTribulation 之后)
//
//  机制:
//    1. 每次击杀建立因果链: 杀人者 → 被杀者
//    2. 被杀者的亲友/宗门成员会接到"追杀令"
//    3. 追杀者获得 "BloodPursuit" 意图, 主动寻找仇人
//    4. 因果链可传递: A杀B → B的师傅追杀A → A的师傅反击B的师傅
//    5. 因果链随时间衰减(但很慢)
//    6. 因果链深度影响天劫威力: 杀人越多, 天劫越猛
//
//  因果闭环:
//    A杀B → B转世 → B(新)有前世记忆 → B(新)追杀A
//    这形成了一个闭环, 与 ReincarnationSystem 联动
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class KarmaChainSystem implements ISystem {
    public var priority:Int = 28;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var chainDecayRate:Float = 0.0001;      // 因果链衰减速率(per tick)
    public var chainTriggerRange:Float = 600;      // 追杀触发范围
    public var maxChainDepth:Int = 5;              // 最大因果链深度
    public var pursuitDuration:Float = 300;        // 追杀持续时间(秒)
    public var pursuitAggressionBoost:Float = 0.8; // 追杀者攻击性提升

    // 全局因果链记录: killerId -> [{targetId, targetName, tick, depth}]
    var karmaChains:Map<Int, Array<KarmaChainEntry>> = [];

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 1. 检测击杀事件, 建立因果链
        var recentEvents = world.eventLog.slice(-5);
        for (evt in recentEvents) {
            if (evt.type == "Kill") {
                var alreadyProcessed = false;
                if (karmaChains.exists(evt.sourceId)) {
                    for (entry in karmaChains[evt.sourceId]) {
                        if (entry.targetId == evt.targetId && entry.tick == evt.tick) {
                            alreadyProcessed = true;
                            break;
                        }
                    }
                }
                if (!alreadyProcessed) {
                    createKarmaChain(world, evt);
                }
            }
        }

        // 2. 更新因果链: 衰减 + 过期清理
        for (killerId => entries in karmaChains) {
            var i = entries.length;
            while (i-- > 0) {
                entries[i].intensity -= chainDecayRate * dt * 60;
                entries[i].age += dt;
                if (entries[i].intensity <= 0 || entries[i].age > pursuitDuration * 3) {
                    entries.splice(i, 1);
                }
            }
            if (entries.length == 0) {
                karmaChains.remove(killerId);
            }
        }

        // 3. 触发追杀: 被杀者的亲友/同门追杀杀人者
        triggerPursuits(world, dt);

        // 4. 影响天劫: 因果链深度增加天劫威力
        amplifyTribulation(world);
    }

    function createKarmaChain(world:WorldEngine, evt:WorldEvent):Void {
        var killer = world.getEntity(evt.sourceId);
        var victim = world.getEntity(evt.targetId);

        if (killer == null || victim == null) return;

        var entry = new KarmaChainEntry();
        entry.killerId = evt.sourceId;
        entry.killerName = killer.name;
        entry.targetId = evt.targetId;
        entry.targetName = victim.name;
        entry.tick = evt.tick;
        entry.intensity = 1.0;
        entry.age = 0;

        if (!karmaChains.exists(evt.sourceId)) {
            karmaChains.set(evt.sourceId, []);
        }
        karmaChains[evt.sourceId].push(entry);

        // 查找被杀者的亲友和同门
        var victimSocial = victim.get(SocialComp);
        var victimFaction = victim.get(FactionComp);

        var avengers:Array<Entity> = [];

        // 亲友
        if (victimSocial != null) {
            for (id => rel in victimSocial.relationships) {
                if (rel.affinity > 30) {
                    var avenger = world.getEntity(id);
                    if (avenger != null && avenger.alive) {
                        avengers.push(avenger);
                    }
                }
            }
        }

        // 同门
        if (victimFaction != null) {
            for (e in world.entities) {
                if (!e.alive || e.id == evt.sourceId) continue;
                var fc = e.get(FactionComp);
                if (fc != null && fc.factionId == victimFaction.factionId) {
                    if (avengers.indexOf(e) == -1) {
                        // 同门有概率追杀
                        if (Math.random() < 0.3) {
                            avengers.push(e);
                        }
                    }
                }
            }
        }

        // 设置追杀意图
        for (avenger in avengers) {
            setPursuitIntent(avenger, evt.sourceId, killer.name);
        }

        // 检查转世联动: 如果被杀者有前世记忆指向杀人者, 形成因果闭环
        var victimReinc = victim.get(ReincarnationComp);
        if (victimReinc != null && victimReinc.hasPastLife) {
            for (mem in victimReinc.retainedMemories) {
                if (mem.id == evt.sourceId && mem.rel < -20) {
                    // 前世仇人! 强化因果链
                    entry.intensity = 2.0;
                    world.emitEvent(new WorldEvent(-1, -1, "KarmaLoop",
                        victim.name + " 乃转世之身, 前世与" + killer.name + "有血海深仇, 因果闭环!"
                    ));
                    break;
                }
            }
        }

        if (avengers.length > 0) {
            world.emitEvent(new WorldEvent(evt.sourceId, -1, "KarmaChain",
                killer.name + " 击杀" + victim.name + ", " + avengers.length + "人立下追杀令, 因果缠身"
            ));
        }

        // 给杀人者添加因果链组件(如果还没有)
        var chainComp = killer.get(KarmaChainComp);
        if (chainComp == null) {
            chainComp = new KarmaChainComp();
            killer.add(chainComp);
        }
        chainComp.killCount++;
        chainComp.totalKarmaWeight += entry.intensity;
    }

    function setPursuitIntent(avenger:Entity, targetId:Int, targetName:String):Void {
        var intent = avenger.get(IntentComp);
        if (intent == null) return;

        intent.currentIntent = Hunt;
        intent.targetEntityId = targetId;
        intent.aggression = Math.min(1.0, intent.aggression + pursuitAggressionBoost);

        var chainComp = avenger.get(KarmaChainComp);
        if (chainComp == null) {
            chainComp = new KarmaChainComp();
            avenger.add(chainComp);
        }
        chainComp.isPursuing = true;
        chainComp.pursuitTargetId = targetId;
        chainComp.pursuitTargetName = targetName;
        chainComp.pursuitTimer = pursuitDuration;
    }

    function triggerPursuits(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive || e.isPlayer) continue;
            var chainComp = e.get(KarmaChainComp);
            var intent = e.get(IntentComp);
            if (chainComp == null || intent == null) continue;

            if (chainComp.isPursuing) {
                chainComp.pursuitTimer -= dt;

                // 检查目标是否还活着
                var target = world.getEntity(chainComp.pursuitTargetId);
                if (target == null || !target.alive || chainComp.pursuitTimer <= 0) {
                    // 追杀结束
                    chainComp.isPursuing = false;
                    chainComp.pursuitTargetId = -1;
                    if (intent.currentIntent == Hunt) {
                        intent.currentIntent = Idle;
                        intent.targetEntityId = -1;
                    }
                    continue;
                }

                // 确保追杀意图持续
                if (intent.currentIntent != Hunt) {
                    intent.currentIntent = Hunt;
                    intent.targetEntityId = chainComp.pursuitTargetId;
                }

                // 靠近目标时提高攻击性
                var myPos = e.get(PositionComp);
                var targetPos = target.get(PositionComp);
                if (myPos != null && targetPos != null) {
                    var dx = myPos.x - targetPos.x;
                    var dy = myPos.y - targetPos.y;
                    var dist = Math.sqrt(dx * dx + dy * dy);
                    if (dist < chainTriggerRange) {
                        intent.aggression = Math.min(1.0, intent.aggression + dt * 0.5);
                    }
                }
            }
        }
    }

    function amplifyTribulation(world:WorldEngine):Void {
        // 因果链深度影响天劫威力
        for (e in world.entities) {
            if (!e.alive) continue;
            var chainComp = e.get(KarmaChainComp);
            var karma = e.get(KarmaComp);
            if (chainComp == null || karma == null) continue;

            if (chainComp.killCount > 0 && karma.tribulationType != null && karma.tribulationType != "") {
                // 每条因果链增加10%天劫威力
                var bonus = 1.0 + chainComp.killCount * 0.1;
                if (karma.tribulationPower < bonus) {
                    karma.tribulationPower = bonus;
                }
            }
        }
    }

    // 外部接口: 获取某实体的因果链
    public function getKarmaChain(entityId:Int):Array<KarmaChainEntry> {
        return karmaChains.exists(entityId) ? karmaChains[entityId] : [];
    }

    // 外部接口: 获取因果链总数
    public function getTotalChains():Int {
        var count = 0;
        for (entries in karmaChains) {
            count += entries.length;
        }
        return count;
    }
}

class KarmaChainEntry {
    public var killerId:Int;
    public var killerName:String;
    public var targetId:Int;
    public var targetName:String;
    public var tick:Int;
    public var intensity:Float;
    public var age:Float;

    public function new() {}
}
