package ecs;

// ============================================================
//  WorldCataclysmSystem.hx - 世界大型事件系统
//  priority: 28 (在因果天劫之后, 历史系统之前)
//
//  核心机制:
//  1. 妖潮入侵: 周期性在某区域爆发 8-15 只妖兽, 主动攻击附近修士
//  2. 秘境传承: 随机位置开启秘境, NPC 进入争夺传承(修为/法器/灵根提升)
//  3. 灵气复苏: 全图灵脉浓度临时翻倍, 持续一段时间, 修炼效率暴增
//  4. 宗门大战: 两个对立宗门进入战争, 成员攻击性临时拉满
//
//  事件触发间隔: 每 60-120 天检查一次, 同时进行的事件有上限.
//  让世界有节奏起伏, 避免长期平淡.
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;
import ecs.WorldEngine.SecretRealm;
import ecs.WorldEngine.CataclysmEvent;

class WorldCataclysmSystem implements ISystem {
    public var priority:Int = 28;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var eventCheckInterval:Int = 90;     // 每 N 天检查一次事件
    public var eventTriggerChance:Float = 0.55; // 检查时触发事件概率
    public var maxConcurrentEvents:Int = 2;     // 同时进行的事件上限
    public var beastTideMinBeasts:Int = 8;
    public var beastTideMaxBeasts:Int = 15;
    public var beastTideRadius:Float = 250;     // 妖潮扩散半径
    public var secretRealmDuration:Float = 180; // 秘境存在时间(秒)
    public var secretRealmRadius:Float = 120;
    public var spiritSurgeDuration:Float = 120; // 灵气复苏持续时间(秒)
    public var factionWarDuration:Float = 240;  // 宗门大战持续时间(秒)

    var lastEventCheckDay:Int = 0;
    var spiritSurgeTimer:Float = 0;
    var factionWarTimer:Float = 0;
    var factionWarA:Int = -1;
    var factionWarB:Int = -1;

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 1. 周期性触发事件
        if (world.worldDay - lastEventCheckDay >= eventCheckInterval) {
            lastEventCheckDay = world.worldDay;
            if (Math.random() < eventTriggerChance
                && world.activeCataclysms.length < maxConcurrentEvents) {
                triggerRandomEvent(world);
            }
        }

        // 2. 更新秘境
        updateSecretRealms(world, dt);

        // 3. 灵气复苏计时
        if (spiritSurgeTimer > 0) {
            spiritSurgeTimer -= dt;
            if (spiritSurgeTimer <= 0) {
                endSpiritSurge(world);
            }
        }

        // 4. 宗门大战计时
        if (factionWarTimer > 0) {
            factionWarTimer -= dt;
            if (factionWarTimer <= 0) {
                endFactionWar(world);
            }
        }

        // 5. 清理已结束事件
        var i = world.activeCataclysms.length;
        while (i-- > 0) {
            if (world.activeCataclysms[i].finished) {
                world.activeCataclysms.splice(i, 1);
            }
        }
    }

    // --- 随机选择一个事件触发 ---
    function triggerRandomEvent(world:WorldEngine):Void {
        var roll = Math.random();
        if (roll < 0.35) triggerBeastTide(world);
        else if (roll < 0.65) triggerSecretRealm(world);
        else if (roll < 0.85) triggerSpiritSurge(world);
        else triggerFactionWar(world);
    }

    // --- 妖潮入侵 ---
    function triggerBeastTide(world:WorldEngine):Void {
        // 选择一个远离玩家的位置
        var px:Float = world.worldWidth / 2;
        var py:Float = world.worldHeight / 2;
        if (world.playerEntity != null) {
            var ppos = world.playerEntity.get(PositionComp);
            if (ppos != null) { px = ppos.x; py = ppos.y; }
        }
        var cx:Float = 0;
        var cy:Float = 0;
        // 尝试在远离玩家处生成
        for (attempt in 0...10) {
            cx = randRange(100, world.worldWidth - 100);
            cy = randRange(100, world.worldHeight - 100);
            var dx = cx - px;
            var dy = cy - py;
            if (dx * dx + dy * dy > 400 * 400) break;
        }

        var count = Std.int(randRange(beastTideMinBeasts, beastTideMaxBeasts + 1));
        var beastsSpawned = 0;
        for (i in 0...count) {
            if (world.entities.length >= world.maxEntities) break;
            var beast = world.spawnNPCOfType("yaoshou",
                cx + randRange(-beastTideRadius, beastTideRadius),
                cy + randRange(-beastTideRadius, beastTideRadius)
            );
            if (beast != null) {
                // 妖潮妖兽更具攻击性
                var intent = beast.get(IntentComp);
                if (intent != null) {
                    intent.aggression = 0.95;
                    intent.currentIntent = Wander;
                    intent.targetX = px + randRange(-200, 200);
                    intent.targetY = py + randRange(-200, 200);
                }
                beastsSpawned++;
            }
        }

        var evt = new CataclysmEvent("BeastTide", world.worldDay);
        evt.x = cx; evt.y = cy;
        evt.desc = "妖潮爆发";
        evt.duration = 60;
        world.activeCataclysms.push(evt);

        world.emitEvent(new WorldEvent(-1, -1, "BeastTide",
            "天地异变! 妖潮于东方爆发, " + beastsSpawned + " 头妖兽肆虐修仙界!"
        ));
    }

    // --- 秘境传承 ---
    function triggerSecretRealm(world:WorldEngine):Void {
        var cx = randRange(150, world.worldWidth - 150);
        var cy = randRange(150, world.worldHeight - 150);

        var realm = new SecretRealm();
        realm.x = cx;
        realm.y = cy;
        realm.radius = secretRealmRadius;
        realm.remainTime = secretRealmDuration;
        realm.heritageValue = Std.int(randRange(30, 100));
        realm.active = true;
        // 随机传承类型: 修为/法器/灵根
        var roll = Math.random();
        realm.heritageType = roll < 0.5 ? "exp" : (roll < 0.8 ? "artifact" : "root");
        world.secretRealms.push(realm);

        var evt = new CataclysmEvent("SecretRealm", world.worldDay);
        evt.x = cx; evt.y = cy;
        evt.desc = "秘境开启";
        evt.duration = secretRealmDuration;
        world.activeCataclysms.push(evt);

        var typeDesc = switch (realm.heritageType) {
            case "exp": "上古修士遗蜕";
            case "artifact": "古仙遗宝";
            case "root": "灵根道韵";
            default: "神秘传承";
        };
        world.emitEvent(new WorldEvent(-1, -1, "SecretRealm",
            typeDesc + "秘境开启! 修仙者趋之若鹜, 争夺传承"
        ));
    }

    function updateSecretRealms(world:WorldEngine, dt:Float):Void {
        var i = world.secretRealms.length;
        while (i-- > 0) {
            var realm = world.secretRealms[i];
            if (!realm.active) {
                world.secretRealms.splice(i, 1);
                continue;
            }
            realm.remainTime -= dt;
            if (realm.remainTime <= 0) {
                realm.active = false;
                world.emitEvent(new WorldEvent(-1, -1, "SecretRealmClose",
                    "秘境之力消散, 隐入虚空"
                ));
                continue;
            }

            // 检测进入秘境的 NPC
            for (e in world.entities) {
                if (!e.alive || e.isPlayer) continue;
                if (realm.benefitedIds.indexOf(e.id) >= 0) continue;
                var pos = e.get(PositionComp);
                if (pos == null) continue;
                var dx = pos.x - realm.x;
                var dy = pos.y - realm.y;
                if (dx * dx + dy * dy > realm.radius * realm.radius) continue;

                // 获得传承
                grantHeritage(world, e, realm);
                realm.benefitedIds.push(e.id);
            }
        }
    }

    function grantHeritage(world:WorldEngine, e:Entity, realm:SecretRealm):Void {
        var cult = e.get(CultivationComp);
        var inv = e.get(InventoryComp);
        if (cult == null) return;
        var value = realm.heritageValue;

        switch (realm.heritageType) {
            case "exp":
                cult.exp += value * 5;
                cult.luck += 0.05;
                world.emitEvent(new WorldEvent(e.id, -1, "HeritageGain",
                    e.name + " 于秘境中获得上古传承, 修为大增!"
                ));
            case "artifact":
                if (inv != null) {
                    // 随机一件法器
                    var artifacts = ["凡器·青锋剑", "灵器·玄铁印", "法宝·定光珠"];
                    var art = artifacts[Std.int(Math.random(artifacts.length))];
                    if (inv.artifacts.indexOf(art) < 0) inv.artifacts.push(art);
                    world.emitEvent(new WorldEvent(e.id, -1, "HeritageGain",
                        e.name + " 于秘境中获得 " + art + "!"
                    ));
                }
            case "root":
                // 灵根品质提升(上限4)
                if (cult.spiritRootQuality < 4) {
                    cult.spiritRootQuality++;
                    var qNames = ["凡品", "良品", "上品", "极品", "天灵根"];
                    cult.spiritRootQualityName = qNames[cult.spiritRootQuality];
                    cult.talent = 1.0 + cult.spiritRootQuality * 0.2;
                    world.emitEvent(new WorldEvent(e.id, -1, "HeritageGain",
                        e.name + " 于秘境中感悟道韵, 灵根晋升为 " + cult.spiritRootQualityName + "!"
                    ));
                } else {
                    cult.exp += value * 3;
                }
        }
    }

    // --- 灵气复苏 ---
    function triggerSpiritSurge(world:WorldEngine):Void {
        spiritSurgeTimer = spiritSurgeDuration;
        // 全图灵脉浓度翻倍
        for (v in world.spiritVeins) {
            v.baseDensity *= 2.0;
        }
        // 网格暴涨
        var ecology = world.getEcologySystem();
        if (ecology != null) {
            for (row in ecology.grid) {
                for (cell in row) {
                    cell.surge = Math.min(1.0, cell.surge + 0.5);
                }
            }
        }

        var evt = new CataclysmEvent("SpiritSurge", world.worldDay);
        evt.desc = "灵气复苏";
        evt.duration = spiritSurgeDuration;
        world.activeCataclysms.push(evt);

        world.emitEvent(new WorldEvent(-1, -1, "SpiritSurge",
            "天地灵气复苏! 万千灵脉同时喷涌, 修仙界进入修炼黄金时代!"
        ));
    }

    function endSpiritSurge(world:WorldEngine):Void {
        for (v in world.spiritVeins) {
            v.baseDensity *= 0.5; // 恢复
        }
        world.emitEvent(new WorldEvent(-1, -1, "SpiritSurgeEnd",
            "灵气复苏之势渐歇, 天地复归平静"
        ));
    }

    // --- 宗门大战 ---
    function triggerFactionWar(world:WorldEngine):Void {
        // 找两个活着的、对立的宗门
        var righteousFactions:Array<Int> = [];
        var demonicFactions:Array<Int> = [];
        for (f in world.factions) {
            if (!f.alive) continue;
            if (f.alignment == "righteous") righteousFactions.push(f.id);
            else if (f.alignment == "demonic") demonicFactions.push(f.id);
        }
        if (righteousFactions.length == 0 || demonicFactions.length == 0) return;

        factionWarA = righteousFactions[Std.int(Math.random(righteousFactions.length))];
        factionWarB = demonicFactions[Std.int(Math.random(demonicFactions.length))];
        factionWarTimer = factionWarDuration;

        // 提升两宗成员的攻击性
        for (e in world.entities) {
            if (!e.alive) continue;
            var fac = e.get(FactionComp);
            var intent = e.get(IntentComp);
            if (fac == null || intent == null) continue;
            if (fac.factionId == factionWarA || fac.factionId == factionWarB) {
                intent.aggression = 0.95;
            }
        }

        var fa = findFactionName(world, factionWarA);
        var fb = findFactionName(world, factionWarB);
        var evt = new CataclysmEvent("FactionWar", world.worldDay);
        evt.desc = "宗门大战";
        evt.duration = factionWarDuration;
        world.activeCataclysms.push(evt);

        world.emitEvent(new WorldEvent(-1, -1, "FactionWar",
            fa + " 与 " + fb + " 爆发宗门大战! 弟子倾巢而出, 修仙界腥风血雨!"
        ));
    }

    function endFactionWar(world:WorldEngine):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            var fac = e.get(FactionComp);
            var intent = e.get(IntentComp);
            if (fac == null || intent == null) continue;
            if (fac.factionId == factionWarA || fac.factionId == factionWarB) {
                intent.aggression = Math.max(0.3, intent.aggression - 0.5);
            }
        }
        var fa = findFactionName(world, factionWarA);
        var fb = findFactionName(world, factionWarB);
        world.emitEvent(new WorldEvent(-1, -1, "FactionWarEnd",
            fa + " 与 " + fb + " 之战暂歇, 各自退兵"
        ));
        factionWarA = -1;
        factionWarB = -1;
    }

    function findFactionName(world:WorldEngine, id:Int):String {
        for (f in world.factions) {
            if (f.id == id) return f.name;
        }
        return "未知宗门";
    }

    function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }
}
