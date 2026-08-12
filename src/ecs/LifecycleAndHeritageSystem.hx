package ecs;

// ============================================================
//  LifecycleAndHeritageSystem.hx - 生命周期与传承系统
//  priority: 12 (在意图系统之后, 生态引擎之前)
//
//  核心机制:
//  1. 道侣生子: 已结道侣双方修为接近且未达人口上限, 概率诞下子嗣
//     - 子嗣继承父母中较高品质的灵根
//     - 父母境界越高, 子嗣血脉越强(凡民/灵裔/仙骨/神裔)
//     - 子嗣天赋 = (父天赋 + 母天赋) / 2 * 血脉倍率
//  2. 师徒传功: 师父死亡时, 将修为/法器传给弟子
//  3. 渡劫飞升: 渡劫期修士, 业障低且气运高者概率飞升
//     - 飞升后离开世界(ascended=true, alive=false)
//     - 飞升时天降异象, 周围灵气暴涨
//  4. 血脉继承: 实体死亡时, 资源/法器按 弟子 > 子女 > 道侣 顺序传承
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class LifecycleAndHeritageSystem implements ISystem {
    public var priority:Int = 12;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var birthCheckInterval:Float = 30.0;  // 生子检查间隔(秒)
    public var birthChance:Float = 0.15;         // 每次检查时道侣生子的概率
    public var minParentAge:Float = 30;          // 最小生育年龄
    public var maxParentAge:Float = 800;         // 最大生育年龄(防止元婴期还在生)
    public var ascensionChancePerDay:Float = 0.02; // 渡劫期每日飞升概率
    public var ascensionMaxSin:Float = 10;       // 飞升所需净业障上限
    public var ascensionMinLuck:Float = 1.5;     // 飞升所需最低气运

    // 血脉等级定义
    public static var bloodlineDefs = [
        {name: "凡民", talentMul: 1.0, color: 0x888888},
        {name: "灵裔", talentMul: 1.2, color: 0x66ccff},
        {name: "仙骨", talentMul: 1.5, color: 0xaa44ff},
        {name: "神裔", talentMul: 2.0, color: 0xffaa00}
    ];

    var birthCheckTimer:Float = 0;

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 1. 渡劫飞升检测(每日)
        if (world.tickCount % world.ticksPerDay == 0) {
            checkAscensions(world);
        }

        // 2. 死亡传承(实时)
        processInheritances(world);

        // 3. 道侣生子(周期检查)
        birthCheckTimer += dt;
        if (birthCheckTimer >= birthCheckInterval) {
            birthCheckTimer = 0;
            checkBirths(world);
        }
    }

    // --- 渡劫飞升 ---
    function checkAscensions(world:WorldEngine):Void {
        for (e in world.entities) {
            if (!e.alive || e.isPlayer) continue;
            var cult = e.get(CultivationComp);
            var karma = e.get(KarmaComp);
            if (cult == null || karma == null) continue;
            // 仅渡劫期可飞升
            if (cult.realmIndex != WorldEngine.realmList.length - 1) continue;
            // 业障与气运门槛
            if (karma.getNetSin() > ascensionMaxSin) continue;
            if (cult.luck < ascensionMinLuck) continue;
            // 概率飞升
            if (Math.random() < ascensionChancePerDay) {
                performAscension(world, e);
            }
        }
    }

    function performAscension(world:WorldEngine, e:Entity):Void {
        var cult = e.get(CultivationComp);
        if (cult == null) return;
        cult.ascended = true;
        e.alive = false;
        world.ascendedCount++;

        world.emitEvent(new WorldEvent(e.id, -1, "Ascension",
            e.name + " 渡过最终天劫, 白日飞升, 离开此界! 天降异象, 灵气潮涌"
        ));
        // 飞升异象: 在世界事件流中额外标记灵气暴涨
        world.emitEvent(new WorldEvent(-1, -1, "AscensionSurge",
            "飞升异象波及方圆千里, 灵气暴涨"
        ));
    }

    // --- 死亡传承 ---
    function processInheritances(world:WorldEngine):Void {
        for (e in world.entities) {
            if (e.alive) continue;
            // 飞升者不参与传承(已带衣钵离去)
            var cult = e.get(CultivationComp);
            if (cult != null && cult.ascended) continue;
            // 仅处理带有 HeritageComp 的实体
            var heritage = e.get(HeritageComp);
            if (heritage == null) continue;
            if (heritage.awaitingInheritance) continue;
            heritage.awaitingInheritance = true;

            var heir = findHeir(world, e);
            if (heir == null) continue;
            transferHeritage(world, e, heir);
        }
    }

    function findHeir(world:WorldEngine, deceased:Entity):Entity {
        var social = deceased.get(SocialComp);
        var heritage = deceased.get(HeritageComp);
        // 1. 师父优先传弟子
        if (social != null && social.disciples.length > 0) {
            for (dId in social.disciples) {
                var d = world.getEntity(dId);
                if (d != null && d.alive) return d;
            }
        }
        // 2. 父母传子女
        if (heritage != null && heritage.childrenIds.length > 0) {
            for (cId in heritage.childrenIds) {
                var c = world.getEntity(cId);
                if (c != null && c.alive) return c;
            }
        }
        // 3. 道侣互传
        if (social != null && social.spouseId != -1) {
            var s = world.getEntity(social.spouseId);
            if (s != null && s.alive) return s;
        }
        return null;
    }

    function transferHeritage(world:WorldEngine, deceased:Entity, heir:Entity):Void {
        var dCult = deceased.get(CultivationComp);
        var dInv = deceased.get(InventoryComp);
        var dHeritage = deceased.get(HeritageComp);
        var hCult = heir.get(CultivationComp);
        var hInv = heir.get(InventoryComp);
        var hHeritage = heir.get(HeritageComp);
        if (hCult == null) return;

        // 修为传功: 继承者获得死者 20% 经验 + 境界 * 30 基础经验
        if (dCult != null) {
            hCult.exp += dCult.exp * 0.2 + dCult.realmIndex * 30;
        }

        // 物品传承
        if (dInv != null && hInv != null) {
            hInv.spiritStones += Std.int(dInv.spiritStones * 0.7);
            hInv.herbs += dInv.herbs;
            hInv.materials += dInv.materials;
            for (pName in dInv.pills.keys()) {
                hInv.addPill(pName, dInv.pills[pName]);
            }
            // 法器: 去重后继承
            for (art in dInv.artifacts) {
                if (hInv.artifacts.indexOf(art) < 0) hInv.artifacts.push(art);
            }
        }

        // 传承计数
        if (hHeritage != null && dHeritage != null) {
            hHeritage.heritageCount = dHeritage.heritageCount + 1;
        }

        // 称号记忆
        var hKarma = heir.get(KarmaComp);
        if (hKarma != null) {
            hKarma.titles.push(deceased.name + "传人");
        }

        world.emitEvent(new WorldEvent(deceased.id, heir.id, "HeritageTransfer",
            heir.name + " 继承了 " + deceased.name + " 的衣钵"
        ));
    }

    // --- 道侣生子 ---
    function checkBirths(world:WorldEngine):Void {
        if (world.entities.length >= world.maxEntities) return;

        var processedSpousePairs:Map<Int, Bool> = [];
        var newChildren:Array<Entity> = [];

        for (e in world.entities) {
            if (!e.alive || e.isPlayer) continue;
            var social = e.get(SocialComp);
            var cult = e.get(CultivationComp);
            var pos = e.get(PositionComp);
            if (social == null || cult == null || pos == null) continue;
            if (social.spouseId == -1) continue;

            // 避免一对道侣被处理两次
            if (processedSpousePairs.exists(social.spouseId)) continue;

            var spouse = world.getEntity(social.spouseId);
            if (spouse == null || !spouse.alive) continue;
            var sCult = spouse.get(CultivationComp);
            var sPos = spouse.get(PositionComp);
            if (sCult == null || sPos == null) continue;

            processedSpousePairs[e.id] = true;
            processedSpousePairs[spouse.id] = true;

            // 年龄检查
            if (cult.age < minParentAge || cult.age > maxParentAge) continue;
            if (sCult.age < minParentAge || sCult.age > maxParentAge) continue;

            // 距离检查(道侣需相近)
            var dx = sPos.x - pos.x;
            var dy = sPos.y - pos.y;
            if (dx * dx + dy * dy > 300 * 300) continue;

            // 概率生子
            if (Math.random() > birthChance) continue;

            // 出生位置: 父母中点附近
            var birthX = (pos.x + sPos.x) * 0.5 + randRange(-30, 30);
            var birthY = (pos.y + sPos.y) * 0.5 + randRange(-30, 30);

            var child = spawnChild(world, e, spouse, birthX, birthY);
            if (child != null) newChildren.push(child);

            // 人口上限二次检查
            if (world.entities.length + newChildren.length >= world.maxEntities) break;
        }

        for (c in newChildren) {
            world.addEntity(c);
        }
    }

    // --- 生成子女实体 ---
    function spawnChild(world:WorldEngine, parentA:Entity, parentB:Entity, x:Float, y:Float):Entity {
        var aCult = parentA.get(CultivationComp);
        var bCult = parentB.get(CultivationComp);
        var aSocial = parentA.get(SocialComp);
        var bSocial = parentB.get(SocialComp);
        if (aCult == null || bCult == null) return null;

        var child = new Entity();

        // 血脉判定: 父母境界越高, 子嗣血脉越强
        var avgRealm = (aCult.realmIndex + bCult.realmIndex) * 0.5;
        var bloodlineIdx = 0;
        if (avgRealm >= 6) bloodlineIdx = 3;       // 神裔
        else if (avgRealm >= 4) bloodlineIdx = 2;  // 仙骨
        else if (avgRealm >= 2) bloodlineIdx = 1;  // 灵裔
        var bloodline = bloodlineDefs[bloodlineIdx];

        // 灵根继承: 取父母中较高品质者
        var inheritingParent:Entity = parentA;
        if (bCult.spiritRootQuality > aCult.spiritRootQuality) inheritingParent = parentB;
        var iPCult = inheritingParent.get(CultivationComp);

        // 位置
        var pos = new PositionComp(x, y);

        // 修仙组件
        var cult = new CultivationComp();
        cult.realmIndex = 0;
        cult.realmName = WorldEngine.realmList[0].name;
        cult.maxHp = 150 + bloodlineIdx * 30;
        cult.hp = cult.maxHp;
        cult.maxMp = 80 + bloodlineIdx * 20;
        cult.mp = cult.maxMp;
        cult.attackPower = 20 + bloodlineIdx * 5;
        cult.expToNext = 100;
        cult.lifespan = WorldEngine.realmList[0].lifespan;
        cult.age = 16;
        cult.spiritRoot = iPCult.spiritRoot;
        cult.spiritRootName = iPCult.spiritRootName;
        // 子嗣灵根品质: 父母品质基础上 + 血脉加成(上限4)
        cult.spiritRootQuality = Std.int(Math.min(4, iPCult.spiritRootQuality + Math.floor(bloodlineIdx * 0.5)));
        var qNames = ["凡品", "良品", "上品", "极品", "天灵根"];
        cult.spiritRootQualityName = qNames[cult.spiritRootQuality];
        // 天赋: 父母均值 * 血脉倍率
        cult.talent = (aCult.talent + bCult.talent) * 0.5 * bloodline.talentMul;
        cult.luck = (aCult.luck + bCult.luck) * 0.5 * 1.05; // 略有气运加成

        // 命名: 取父名首字 + 辈分字
        var aName = parentA.name;
        var surname = aName.length > 0 ? aName.charAt(0) : "玄";
        var genChars = ["元", "天", "真", "玄", "灵", "清", "虚", "无"];
        var genChar = genChars[Std.int(Math.random(genChars.length))];
        var lastChars = ["子", "尘", "渊", "机", "一", "辰"];
        var lastChar = lastChars[Std.int(Math.random(lastChars.length))];
        child.name = surname + genChar + lastChar;

        // 意图
        var intent = new IntentComp();
        intent.aggression = (aCult.attackPower + bCult.attackPower) / 200;
        intent.greed = 0.5;
        intent.wisdom = 0.5;
        intent.currentIntent = Cultivate;

        // 因果: 继承父母部分名声
        var karma = new KarmaComp();
        var aKarma = parentA.get(KarmaComp);
        if (aKarma != null) {
            karma.karma = aKarma.karma * 0.3;
        }

        // 背包: 父母资助一些灵石
        var inv = new InventoryComp();
        var aInv = parentA.get(InventoryComp);
        var bInv = parentB.get(InventoryComp);
        if (aInv != null && aInv.spiritStones > 20) {
            var gift = Std.int(aInv.spiritStones * 0.1);
            aInv.spiritStones -= gift;
            inv.spiritStones += gift;
        }
        if (bInv != null && bInv.spiritStones > 20) {
            var gift = Std.int(bInv.spiritStones * 0.1);
            bInv.spiritStones -= gift;
            inv.spiritStones += gift;
        }

        // 势力: 继承父母势力
        var fac = new FactionComp();
        var aFac = parentA.get(FactionComp);
        if (aFac != null && aFac.factionId != -1) {
            fac.factionId = aFac.factionId;
            fac.factionName = aFac.factionName;
            fac.factionRank = 0;
        }

        // NPC 状态
        var npcState = new NPCStateComp();
        npcState.npcType = "cultivator";
        npcState.homeX = x;
        npcState.homeY = y;
        npcState.aiState = "cultivating";

        // 社交: 记录父母关系(亲缘天然盟友)
        var social = new SocialComp();
        social.ambition = 0.5;
        social.loyalty = 0.7;
        social.charm = 0.5;
        social.masterId = -1;
        social.allies.push(parentA.id);
        social.allies.push(parentB.id);
        var relA = new SocialRelation(parentA.id, 80, "ally");
        relA.trust = 90;
        social.relationships[parentA.id] = relA;
        var relB = new SocialRelation(parentB.id, 80, "ally");
        relB.trust = 90;
        social.relationships[parentB.id] = relB;

        // 血脉传承组件
        var heritage = new HeritageComp();
        heritage.parentIds = [parentA.id, parentB.id];
        heritage.childrenIds = [];
        heritage.bloodline = bloodline.name;
        var aHeritage = parentA.get(HeritageComp);
        var bHeritage = parentB.get(HeritageComp);
        var aGen = aHeritage != null ? aHeritage.generation : 1;
        var bGen = bHeritage != null ? bHeritage.generation : 1;
        heritage.generation = Std.int(Math.max(aGen, bGen)) + 1;
        heritage.birthDay = world.worldDay;

        // 炼制能力: 父母若有炼制能力, 子嗣略有基础
        var crafting = new CraftingComp();
        var aCraft = parentA.get(CraftingComp);
        if (aCraft != null) {
            crafting.alchemySkill = aCraft.alchemySkill * 0.2;
            crafting.smithingSkill = aCraft.smithingSkill * 0.2;
        }

        child.add(pos).add(cult).add(intent).add(karma).add(inv).add(fac)
             .add(npcState).add(social).add(heritage).add(crafting);

        // 父母记录子女ID
        if (aSocial != null && aSocial.allies.indexOf(child.id) < 0) aSocial.allies.push(child.id);
        if (bSocial != null && bSocial.allies.indexOf(child.id) < 0) bSocial.allies.push(child.id);
        if (aHeritage != null) aHeritage.childrenIds.push(child.id);
        if (bHeritage != null) bHeritage.childrenIds.push(child.id);

        world.emitEvent(new WorldEvent(parentA.id, child.id, "Birth",
            child.name + "(" + bloodline.name + "/" + cult.spiritRootName + ") 降生, 父:" + parentA.name + " 母:" + parentB.name
        ));

        return child;
    }

    function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }
}
