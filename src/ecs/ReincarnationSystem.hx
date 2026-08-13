package ecs;

// ============================================================
//  ReincarnationSystem.hx - 轮回转世系统
//  priority: 35 (历史系统之后, 处理死亡残魂)
//
//  机制:
//    1. 实体死亡时(检测 Kill/DeathByAge 事件), 生成残魂记录
//    2. 残魂保留: 10%经验, 天赋加成(递减), 业障(保留80%), 部分记忆
//    3. 延迟一段时间后, 在世界随机位置转世为新实体
//    4. 转世实体携带 ReincarnationComp, 初始境界有前世加成
//    5. 高境界死亡转世保留更多, 低境界几乎不保留
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class ReincarnationSystem implements ISystem {
    public var priority:Int = 35;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var expRetainRatio:Float = 0.10;       // 经验保留比例
    public var talentRetainRatio:Float = 0.30;    // 天赋保留比例
    public var sinRetainRatio:Float = 0.80;       // 业障保留比例
    public var memoryRetainCount:Int = 3;         // 保留记忆数量
    public var reincarnationDelay:Float = 30;     // 转世延迟(秒)
    public var maxReincarnations:Int = 9;         // 最大转世次数(九转)
    public var reincarnationChance:Float = 0.4;   // 死亡后触发转世的概率

    // 待转世残魂队列
    var pendingSouls:Array<PendingSoul> = [];

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 1. 检测死亡事件
        var recentEvents = world.eventLog.slice(-10);
        for (evt in recentEvents) {
            if (evt.type == "Kill" || evt.type == "DeathByAge" || evt.type == "TribulationDeath") {
                // 检查是否已处理(用 tick 去重)
                var alreadyProcessed = false;
                for (soul in pendingSouls) {
                    if (soul.sourceEventTick == evt.tick && soul.pastLifeId == evt.targetId) {
                        alreadyProcessed = true;
                        break;
                    }
                }
                if (!alreadyProcessed) {
                    processDeath(world, evt);
                }
            }
        }

        // 2. 处理待转世残魂
        var i = pendingSouls.length;
        while (i-- > 0) {
            var soul = pendingSouls[i];
            soul.timer -= dt;
            if (soul.timer <= 0) {
                reincarnate(world, soul);
                pendingSouls.splice(i, 1);
            }
        }
    }

    function processDeath(world:WorldEngine, evt:WorldEvent):Void {
        var victim = world.getEntityIncludingDead(evt.targetId);
        if (victim == null) return;

        var cult = victim.get(CultivationComp);
        var karma = victim.get(KarmaComp);
        var social = victim.get(SocialComp);
        var heritage = victim.get(HeritageComp);
        if (cult == null) return;

        // 概率触发转世
        if (Math.random() > reincarnationChance) return;

        // 高境界者更容易留下残魂
        var realmBonus = cult.realmIndex * 0.08;
        if (Math.random() > reincarnationChance + realmBonus) return;

        var soul = new PendingSoul();
        soul.pastLifeId = victim.id;
        soul.pastLifeName = victim.name;
        soul.pastLifeRealm = cult.realmIndex;
        soul.sourceEventTick = evt.tick;
        soul.timer = reincarnationDelay + Math.random(60);

        // 保留经验
        soul.retainedExp = cult.exp * expRetainRatio * (1 + cult.realmIndex * 0.05);

        // 保留天赋(递减)
        var talentBonus = (cult.talent - 1.0) * talentRetainRatio;
        soul.retainedTalent = talentBonus;

        // 保留业障
        if (karma != null) {
            soul.retainedSin = karma.getNetSin() * sinRetainRatio;
        }

        // 保留记忆(最强的几段关系)
        if (social != null) {
            var mems:Array<{rel:Float, id:Int, note:String}> = [];
            for (id => rel in social.relationships) {
                mems.push({rel: rel.affinity, id: id, note: rel.relationType});
            }
            mems.sort(function(a, b) return Std.int(Math.abs(b.rel) - Math.abs(a.rel)));
            var count = Std.int(Math.min(memoryRetainCount, mems.length));
            for (i in 0...count) {
                soul.retainedMemories.push({id: mems[i].id, rel: mems[i].rel, note: mems[i].note});
            }
        }

        // 转世次数
        var prevReinc = victim.get(ReincarnationComp);
        soul.reincarnationCount = prevReinc != null ? prevReinc.reincarnationCount + 1 : 1;

        if (soul.reincarnationCount > maxReincarnations) {
            // 超过九转, 魂飞魄散
            world.emitEvent(new WorldEvent(-1, -1, "SoulDissipate",
                soul.pastLifeName + " 已历" + maxReincarnations + "世轮回, 残魂消散于天地间"
            ));
            return;
        }

        pendingSouls.push(soul);

        world.emitEvent(new WorldEvent(-1, -1, "SoulPending",
            soul.pastLifeName + " 残魂不散, 将于" + Math.round(soul.timer) + "秒后转世重修"
        ));
    }

    function reincarnate(world:WorldEngine, soul:PendingSoul):Void {
        // 生成转世新实体
        var e = world.spawnRandomNPC();

        // 应用前世保留
        var cult = e.get(CultivationComp);
        if (cult != null) {
            // 保留经验
            cult.exp += soul.retainedExp;
            // 保留天赋加成
            cult.talent += soul.retainedTalent;
            // 转世者初始境界不低于练气(但也不超过前世的一半)
            var minRealm = Std.int(Math.min(Math.floor(soul.pastLifeRealm * 0.5), 2));
            if (cult.realmIndex < minRealm) {
                cult.realmIndex = minRealm;
                cult.realmName = WorldEngine.realmList[minRealm].name;
                cult.maxHp = 200 + cult.realmIndex * 200;
                cult.hp = cult.maxHp;
                cult.maxMp = 100 + cult.realmIndex * 100;
                cult.mp = cult.maxMp;
                cult.attackPower = 15 + cult.realmIndex * 20;
            }
        }

        // 保留业障
        var karma = e.get(KarmaComp);
        if (karma != null) {
            karma.sinValue = soul.retainedSin;
        }

        // 添加轮回组件
        var reinc = new ReincarnationComp();
        reinc.pastLifeId = soul.pastLifeId;
        reinc.pastLifeName = soul.pastLifeName;
        reinc.pastLifeRealm = soul.pastLifeRealm;
        reinc.retainedExp = soul.retainedExp;
        reinc.retainedTalent = soul.retainedTalent;
        reinc.retainedSin = soul.retainedSin;
        reinc.retainedMemories = soul.retainedMemories;
        reinc.reincarnationCount = soul.reincarnationCount;
        reinc.hasPastLife = true;
        e.add(reinc);

        // 添加因果链组件
        e.add(new KarmaChainComp());

        world.emitEvent(new WorldEvent(e.id, -1, "Reincarnation",
            e.name + " 乃" + soul.pastLifeName + "之转世, 已历" + soul.reincarnationCount + "世轮回"
            + (soul.retainedExp > 50 ? ", 前世修为犹存" : "")
            + (soul.retainedSin > 30 ? ", 业障缠身" : "")
        ));
    }
}

// 待转世残魂
class PendingSoul {
    public var pastLifeId:Int;
    public var pastLifeName:String;
    public var pastLifeRealm:Int;
    public var sourceEventTick:Int;
    public var timer:Float;
    public var retainedExp:Float;
    public var retainedTalent:Float;
    public var retainedSin:Float;
    public var retainedMemories:Array<{id:Int, rel:Float, note:String}>;
    public var reincarnationCount:Int;

    public function new() {
        retainedMemories = [];
    }
}
