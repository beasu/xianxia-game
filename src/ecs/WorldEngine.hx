package ecs;

// ============================================================
//  WorldEngine.hx - 世界引擎核心
//  自运转修仙世界的心脏：Tick 调度器 + 实体管理 + 事件总线
//  世界不依赖玩家，玩家只是其中一个实体
// ============================================================

import hxd.Math;
import ecs.Entity.Entity;
import ecs.Entity.ISystem;
import ecs.Components;

class WorldEngine {
    // --- 全局静态引用(供 WorldEvent 等使用) ---
    public static var inst:WorldEngine = null;

    // --- 全局时间 ---
    public var worldTime:Float = 0;      // 世界存在时间(秒)
    public var tickCount:Int = 0;        // 总 Tick 数
    public var worldDay:Int = 1;         // 世界日
    public var worldYear:Int = 1;        // 世界年
    public var ticksPerDay:Int = 3600;    // 每天多少 Tick (6分钟/天)
    public var daysPerYear:Int = 360;    // 每年多少天

    // --- 实体管理 ---
    public var entities:Array<Entity> = [];
    public var playerEntity:Entity = null;

    // --- 系统调度 ---
    public var systems:Array<ISystem> = [];

    // --- 玩家指令队列 ---
    public var playerCommandQueue:Array<PlayerCommand> = [];

    // --- 事件总线 ---
    public var eventLog:Array<WorldEvent> = [];
    public var eventSubscribers:Array<WorldEvent -> Void> = [];

    // --- 世界状态快照(供观察者使用) ---
    public var lastSnapshot:WorldSnapshot = null;

    // --- 灵脉系统 ---
    public var spiritVeins:Array<SpiritVein> = [];
    public var globalSpiritDensity:Float = 1.0; // 全局灵气浓度

    // --- 势力系统 ---
    public var factions:Array<Faction> = [];

    // --- 拍卖/交易系统 ---
    public var marketItems:Array<MarketItem> = [];
    public var nextAuctionDay:Int = 30;  // 下次拍卖会日期

    // --- 灵草资源点(CraftingEconomySystem 使用) ---
    public var spiritHerbNodes:Array<SpiritHerbNode> = [];

    // --- 秘境(WorldCataclysmSystem 使用) ---
    public var secretRealms:Array<SecretRealm> = [];

    // --- 进行中的大型世界事件 ---
    public var activeCataclysms:Array<CataclysmEvent> = [];

    // --- 飞升统计(LifecycleAndHeritageSystem 维护) ---
    public var ascendedCount:Int = 0;

    // --- 世界配置 ---
    public var worldWidth:Float;
    public var worldHeight:Float;
    public var maxEntities:Int = 60;
    public var tickRate:Float = 0.1;     // 每 0.1 秒一个 Tick

    // --- 内部状态 ---
    var tickAccumulator:Float = 0;
    var spawnTimer:Float = 0;

    // --- 境界定义(全局共享) ---
    public static var realmList = [
        {name: "练气期", color: 0x66aa66, lifespan: 120},
        {name: "筑基期", color: 0x66aaff, lifespan: 200},
        {name: "金丹期", color: 0xffaa00, lifespan: 500},
        {name: "元婴期", color: 0xff66ff, lifespan: 1000},
        {name: "化神期", color: 0xff3333, lifespan: 2000},
        {name: "炼虚期", color: 0xffffff, lifespan: 5000},
        {name: "合体期", color: 0xffaa44, lifespan: 10000},
        {name: "大乘期", color: 0xaaffff, lifespan: 50000},
        {name: "渡劫期", color: 0xffff00, lifespan: 100000}
    ];

    public function new(width:Float, height:Float) {
        this.worldWidth = width;
        this.worldHeight = height;
        inst = this;
    }

    public function addSystem(s:ISystem):WorldEngine {
        systems.push(s);
        // 按优先级排序
        systems.sort(function(a, b) return a.priority - b.priority);
        return this;
    }

    public function addEntity(e:Entity):Entity {
        entities.push(e);
        if (e.isPlayer) playerEntity = e;
        return e;
    }

    public function removeEntity(e:Entity):Void {
        e.alive = false;
    }

    public function getEntity(id:Int):Entity {
        for (e in entities) {
            if (e.id == id && e.alive) return e;
        }
        return null;
    }

    // 获取实体(包括已死亡的, 用于轮回/因果系统)
    public function getEntityIncludingDead(id:Int):Entity {
        for (e in entities) {
            if (e.id == id) return e;
        }
        return null;
    }

    // --- 订阅世界事件 ---
    public function subscribeToEvents(fn:WorldEvent -> Void):Void {
        eventSubscribers.push(fn);
    }

    public function emitEvent(event:WorldEvent):Void {
        eventLog.push(event);
        // 只保留最近 500 条
        if (eventLog.length > 500) eventLog.shift();
        for (sub in eventSubscribers) {
            sub(event);
        }
    }

    // --- 玩家提交指令 ---
    public function submitPlayerCommand(cmd:PlayerCommand):Void {
        playerCommandQueue.push(cmd);
    }

    // --- 世界主循环(由外部 GameScene 调用) ---
    public function update(dt:Float):Void {
        tickAccumulator += dt;

        while (tickAccumulator >= tickRate) {
            tickAccumulator -= tickRate;
            tick();
        }

        // 清理死亡实体
        var i = entities.length;
        while (i-- > 0) {
            if (!entities[i].alive) {
                entities.splice(i, 1);
            }
        }
    }

    // --- 单个 Tick 的执行 ---
    function tick():Void {
        tickCount++;
        worldTime += tickRate;

        // 更新世界日期
        var newDay = Std.int(tickCount / ticksPerDay) + 1;
        if (newDay != worldDay) {
            worldDay = newDay;
            worldYear = Std.int(worldDay / daysPerYear) + 1;
            onNewDay();
        }

        // 执行所有系统(按优先级)
        for (s in systems) {
            if (s.enabled) {
                s.update(this, tickRate);
            }
        }

        // === 全局物理积分: 对所有 NPC 实体统一更新位置 ===
        // (玩家位置由 handleInput 每帧直接更新, 跳过 tick 物理)
        for (e in entities) {
            if (!e.alive) continue;
            if (e.isPlayer) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;

            pos.x += pos.vx * tickRate;
            pos.y += pos.vy * tickRate;
            pos.vx *= 0.85;
            pos.vy *= 0.85;

            // 边界
            pos.x = Math.clamp(pos.x, 0, worldWidth);
            pos.y = Math.clamp(pos.y, 0, worldHeight);
        }

        // 生成快照
        if (tickCount % 5 == 0) {
            lastSnapshot = generateSnapshot();
        }
    }

    // --- 每日事件 ---
    function onNewDay():Void {
        // 灵脉潮汐更新
        for (v in spiritVeins) {
            v.updateTide(worldDay);
        }

        // 更新全局灵气浓度
        var totalDensity = 0.0;
        for (v in spiritVeins) {
            totalDensity += v.currentDensity;
        }
        globalSpiritDensity = spiritVeins.length > 0 ? totalDensity / spiritVeins.length : 1.0;

        // 势力日常更新
        for (f in factions) {
            f.dailyUpdate(this);
        }

        // 定期拍卖会
        if (worldDay >= nextAuctionDay) {
            holdAuction();
            nextAuctionDay = worldDay + Std.int(randRange(20, 40));
        }

        // 实体寿元减少
        for (e in entities) {
            if (!e.alive) continue;
            var cult = e.get(CultivationComp);
            if (cult != null) {
                cult.age += 1.0 / daysPerYear;
                if (cult.age > cult.lifespan) {
                    // 寿元耗尽
                    e.alive = false;
                    emitEvent(new WorldEvent(
                        e.id, -1, "DeathByAge",
                        e.name + " 寿元耗尽,坐化于第" + worldDay + "日"
                    ));
                }
            }
        }

        // 随机生成新实体
        spawnTimer += 1;
        if (entities.length < maxEntities && spawnTimer >= 3) {
            spawnTimer = 0;
            if (Math.random() < 0.6) {
                spawnRandomNPC();
            }
        }
    }

    // --- 举办拍卖会 ---
    function holdAuction():Void {
        var auctionItems = 0;
        for (e in entities) {
            if (!e.alive) continue;
            var inv = e.get(InventoryComp);
            var intent = e.get(IntentComp);
            if (inv == null || intent == null) continue;

            // 高阶修士出售物品
            var cult = e.get(CultivationComp);
            if (cult != null && cult.realmIndex >= 2 && inv.spiritStones > 50) {
                if (Math.random() < 0.3) {
                    var itemName = ["回气丹", "筑基丹", "凝神丹", "金丹", "灵器"][Std.int(Math.random(5))];
                    marketItems.push(new MarketItem(itemName, Std.int(randRange(20, 200)), e.id));
                    auctionItems++;
                }
            }
        }

        // NPC 购买
        for (e in entities) {
            if (!e.alive) continue;
            var inv = e.get(InventoryComp);
            if (inv == null) continue;
            for (item in marketItems) {
                if (inv.spiritStones >= item.price && Math.random() < 0.2) {
                    inv.spiritStones -= item.price;
                    item.sold = true;
                    // 卖家收到灵石
                    var seller = getEntity(item.sellerId);
                    if (seller != null) {
                        var sellerInv = seller.get(InventoryComp);
                        if (sellerInv != null) sellerInv.spiritStones += item.price;
                    }
                }
            }
        }

        // 清理已售出的物品
        marketItems = marketItems.filter(function(m) return !m.sold);

        if (auctionItems > 0) {
            emitEvent(new WorldEvent(-1, -1, "Auction",
                "第" + worldDay + "日, 修仙界举办拍卖会, 上架" + auctionItems + "件宝物"
            ));
        }
    }

    // --- 生成随机 NPC ---
    // forcedType/forcedX/forcedY 可选, 用于妖潮等系统指定生成参数
    public function spawnRandomNPC(?forcedType:String, ?forcedX:Float, ?forcedY:Float):Entity {
        var e = new Entity();
        var npcState = new NPCStateComp();

        // 随机类型(或外部指定)
        if (forcedType != null) {
            npcState.npcType = forcedType;
        } else {
            var roll = Math.random(100);
            if (roll < 40) npcState.npcType = "moxiu";
            else if (roll < 60) npcState.npcType = "yaoshou";
            else if (roll < 75) npcState.npcType = "mojiang";
            else if (roll < 85) npcState.npcType = "xiexian";
            else npcState.npcType = "cultivator"; // 正道修士
        }

        // 位置
        var pos = new PositionComp();
        if (forcedX != null && forcedY != null) {
            pos.x = forcedX;
            pos.y = forcedY;
        } else {
            var side = Std.int(Math.random(4));
            switch (side) {
                case 0: pos.x = Math.random(worldWidth); pos.y = -30;
                case 1: pos.x = worldWidth + 30; pos.y = Math.random(worldHeight);
                case 2: pos.x = Math.random(worldWidth); pos.y = worldHeight + 30;
                case 3: pos.x = -30; pos.y = Math.random(worldHeight);
            }
        }
        npcState.homeX = pos.x;
        npcState.homeY = pos.y;

        // 修仙
        var cult = new CultivationComp();
        cult.realmIndex = Std.int(Math.random(4)); // 0-3
        cult.realmName = realmList[cult.realmIndex].name;
        var baseHp = 200 + cult.realmIndex * 200;
        cult.maxHp = baseHp;
        cult.hp = baseHp;
        cult.maxMp = 100 + cult.realmIndex * 100;
        cult.mp = cult.maxMp;
        cult.attackPower = 15 + cult.realmIndex * 20;
        cult.lifespan = realmList[cult.realmIndex].lifespan;
        cult.age = Math.random(cult.lifespan * 0.7) + 10;

        // 随机灵根
        var rootRoll = Math.random(100);
        if (rootRoll < 30) cult.spiritRoot = "fire";
        else if (rootRoll < 50) cult.spiritRoot = "water";
        else if (rootRoll < 65) cult.spiritRoot = "wood";
        else if (rootRoll < 78) cult.spiritRoot = "metal";
        else if (rootRoll < 88) cult.spiritRoot = "earth";
        else if (rootRoll < 94) cult.spiritRoot = "thunder";
        else if (rootRoll < 98) cult.spiritRoot = "ice";
        else cult.spiritRoot = "dark";

        var rootNames = [
            "fire" => "火灵根", "water" => "水灵根", "wood" => "木灵根",
            "metal" => "金灵根", "earth" => "土灵根", "thunder" => "雷灵根",
            "ice" => "冰灵根", "dark" => "暗灵根"
        ];
        cult.spiritRootName = rootNames[cult.spiritRoot];
        var qRoll = Math.random(100);
        if (qRoll < 50) cult.spiritRootQuality = 0;
        else if (qRoll < 78) cult.spiritRootQuality = 1;
        else if (qRoll < 92) cult.spiritRootQuality = 2;
        else if (qRoll < 98) cult.spiritRootQuality = 3;
        else cult.spiritRootQuality = 4;
        var qNames = ["凡品", "良品", "上品", "极品", "天灵根"];
        cult.spiritRootQualityName = qNames[cult.spiritRootQuality];
        cult.talent = 1.0 + cult.spiritRootQuality * 0.2;
        cult.luck = randRange(0.5, 1.5);

        // 名称
        var namePrefixes = ["玄", "紫", "青", "赤", "白", "黑", "金", "玉", "灵", "天"];
        var nameSuffixes = ["虚", "尘", "渊", "冥", "极", "玄", "真", "一", "机", "妙"];
        e.name = namePrefixes[Std.int(Math.random(10))] + nameSuffixes[Std.int(Math.random(10))] + (npcState.npcType == "yaoshou" ? "兽" : npcState.npcType == "mojiang" ? "将" : "子");

        // 意图
        var intent = new IntentComp();
        intent.aggression = randRange(0.2, 0.9);
        intent.greed = randRange(0.2, 0.9);
        intent.wisdom = randRange(0.3, 0.9);
        intent.currentIntent = Wander;

        // 因果
        var karma = new KarmaComp();
        if (npcState.npcType == "moxiu" || npcState.npcType == "mojiang") {
            karma.karma = -randRange(10, 50);
            karma.notoriety = randRange(10, 30);
        } else if (npcState.npcType == "cultivator") {
            karma.karma = randRange(10, 30);
            karma.reputation = randRange(5, 20);
        }

        // 背包
        var inv = new InventoryComp();
        inv.spiritStones = Std.int(randRange(0, 100));

        // 势力
        var fac = new FactionComp();
        if (npcState.npcType == "cultivator" && factions.length > 0 && Math.random() < 0.5) {
            var f = factions[Std.int(Math.random(factions.length))];
            fac.factionId = f.id;
            fac.factionName = f.name;
            fac.factionRank = Std.int(Math.random(2));
        }

        // 社交组件
        var social = new SocialComp();
        social.ambition = randRange(0.2, 0.9);
        social.loyalty = randRange(0.3, 0.9);
        social.charm = randRange(0.3, 0.9);
        // 根据NPC类型分配社交角色
        if (npcState.npcType == "mojiang" || npcState.npcType == "xiexian") {
            social.socialRole = "schemer"; // 阴谋家
            social.ambition = randRange(0.6, 0.95);
        } else if (npcState.npcType == "cultivator") {
            social.socialRole = Math.random() < 0.3 ? "leader" : "diplomat";
        } else {
            social.socialRole = "loner";
        }

        // 血脉传承组件: 自然诞生的 NPC 默认凡民血脉
        var heritage = new HeritageComp();
        heritage.bloodline = "凡民";
        heritage.generation = 1;
        heritage.birthDay = worldDay;
        // 少数天选者出生即有仙骨/灵裔血脉
        var bloodRoll = Math.random();
        if (bloodRoll > 0.97) {
            heritage.bloodline = "神裔";
            cult.talent *= 2.0;
        } else if (bloodRoll > 0.9) {
            heritage.bloodline = "仙骨";
            cult.talent *= 1.5;
        } else if (bloodRoll > 0.75) {
            heritage.bloodline = "灵裔";
            cult.talent *= 1.2;
        }

        // 炼制能力组件: 一部分 NPC 天生有炼制天赋
        var crafting = new CraftingComp();
        if (npcState.npcType == "cultivator") {
            // 正道修士更可能擅长炼丹
            crafting.alchemySkill = Math.random() < 0.4 ? randRange(10, 40) : 0;
            crafting.smithingSkill = Math.random() < 0.3 ? randRange(5, 25) : 0;
        } else if (npcState.npcType == "mojiang") {
            // 魔将更可能擅长炼器
            crafting.smithingSkill = Math.random() < 0.5 ? randRange(15, 50) : 0;
            crafting.alchemySkill = Math.random() < 0.2 ? randRange(5, 20) : 0;
        } else {
            crafting.alchemySkill = Math.random() < 0.2 ? randRange(0, 15) : 0;
            crafting.smithingSkill = Math.random() < 0.2 ? randRange(0, 15) : 0;
        }

        // 灵力物理组件
        var spiritPhys = new SpiritPhysicsComp();
        spiritPhys.spiritPressure = 10 * Math.pow(3, cult.realmIndex);
        spiritPhys.pressureRadius = 80 + cult.realmIndex * 40;
        spiritPhys.spiritSenseRange = 200 + cult.realmIndex * 100;
        spiritPhys.resonanceElement = cult.spiritRoot;

        e.add(pos).add(cult).add(intent).add(karma).add(inv).add(fac).add(npcState).add(social).add(heritage).add(crafting).add(new KarmaChainComp()).add(spiritPhys);

        addEntity(e);

        emitEvent(new WorldEvent(e.id, -1, "Spawn",
            e.name + "(" + cult.realmName + "/" + cult.spiritRootName + ") 出现在修仙界"
        ));

        return e;
    }

    // --- 生成世界快照 ---
    function generateSnapshot():WorldSnapshot {
        var snap = new WorldSnapshot();
        snap.tickCount = tickCount;
        snap.worldDay = worldDay;
        snap.worldYear = worldYear;
        snap.globalSpiritDensity = globalSpiritDensity;
        snap.entityCount = entities.length;
        snap.aliveCount = 0;
        snap.deadCount = 0;

        for (e in entities) {
            if (e.alive) snap.aliveCount++; else snap.deadCount++;
        }

        snap.factionCount = factions.length;
        snap.recentEvents = eventLog.slice(-Std.int(Math.min(10, eventLog.length)));

        return snap;
    }

    // --- 初始化灵脉 ---
    public function initSpiritVeins():Void {
        for (i in 0...5) {
            var v = new SpiritVein(i);
            v.x = randRange(100, worldWidth - 100);
            v.y = randRange(100, worldHeight - 100);
            v.baseDensity = randRange(1.0, 3.0);
            v.currentDensity = v.baseDensity;
            spiritVeins.push(v);
        }
    }

    // --- 初始化势力 ---
    public function initFactions():Void {
        var factionNames = [
            "天剑宗", "万法门", "太虚宫", "血魔宗", "丹鼎阁",
            "御兽山庄", "星辰观", "幽冥教"
        ];
        for (i in 0...factionNames.length) {
            var f = new Faction(i, factionNames[i]);
            f.strength = randRange(50, 200);
            f.alignment = i < 4 ? "righteous" : "demonic"; // 前4个正道, 后4个魔道
            factions.push(f);
        }
    }

    // --- 初始化灵草资源点(在每个灵脉附近撒若干点) ---
    public function initSpiritHerbNodes():Void {
        for (v in spiritVeins) {
            for (i in 0...5) {
                var node = new SpiritHerbNode(spiritHerbNodes.length);
                var angle = Math.random() * Math.PI * 2;
                var dist = randRange(50, 200);
                node.x = v.x + Math.cos(angle) * dist;
                node.y = v.y + Math.sin(angle) * dist;
                node.x = Math.clamp(node.x, 50, worldWidth - 50);
                node.y = Math.clamp(node.y, 50, worldHeight - 50);
                node.maxHerbs = Std.int(randRange(5, 15));
                node.herbs = node.maxHerbs;
                node.alive = true;
                spiritHerbNodes.push(node);
            }
        }
    }

    // --- 按类型生成 NPC(妖潮/秘境等系统使用) ---
    public function spawnNPCOfType(type:String, x:Float, y:Float):Entity {
        return spawnRandomNPC(type, x, y);
    }

    // --- 获取生态引擎引用(供其他系统查询网格灵气浓度) ---
    public function getEcologySystem():WorldEcologySystem {
        for (s in systems) {
            if (Type.getClass(s) == WorldEcologySystem) {
                return cast s;
            }
        }
        return null;
    }

    // --- 辅助 ---
    public static function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }

    public function findNearestEntity(x:Float, y:Float, ?filter:Entity -> Bool):Entity {
        var nearest:Entity = null;
        var nearestDist = Math.POSITIVE_INFINITY;
        for (e in entities) {
            if (!e.alive) continue;
            if (e.isPlayer) continue;
            if (filter != null && !filter(e)) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;
            var dx = pos.x - x;
            var dy = pos.y - y;
            var dist = dx * dx + dy * dy;
            if (dist < nearestDist) {
                nearestDist = dist;
                nearest = e;
            }
        }
        return nearest;
    }
}

// ============================================================
//  世界事件
// ============================================================
class WorldEvent {
    public var sourceId:Int;
    public var targetId:Int;
    public var type:String;
    public var desc:String;
    public var day:Int;
    public var tick:Int;

    public function new(sourceId:Int, targetId:Int, type:String, desc:String) {
        this.sourceId = sourceId;
        this.targetId = targetId;
        this.type = type;
        this.desc = desc;
        this.day = WorldEngine.inst != null ? WorldEngine.inst.worldDay : 0;
        this.tick = WorldEngine.inst != null ? WorldEngine.inst.tickCount : 0;
    }
}

// ============================================================
//  世界快照
// ============================================================
class WorldSnapshot {
    public var tickCount:Int;
    public var worldDay:Int;
    public var worldYear:Int;
    public var globalSpiritDensity:Float;
    public var entityCount:Int;
    public var aliveCount:Int;
    public var deadCount:Int;
    public var factionCount:Int;
    public var recentEvents:Array<WorldEvent>;

    public function new() {}
}

// ============================================================
//  灵脉
// ============================================================
class SpiritVein {
    public var id:Int;
    public var x:Float;
    public var y:Float;
    public var baseDensity:Float;
    public var currentDensity:Float;
    public var tidePhase:Float = 0;

    public function new(id:Int) {
        this.id = id;
    }

    public function updateTide(day:Int):Void {
        tidePhase += 0.05;
        currentDensity = baseDensity * (0.7 + Math.sin(tidePhase) * 0.3);
    }
}

// ============================================================
//  势力
// ============================================================
class Faction {
    public var id:Int;
    public var name:String;
    public var strength:Float;          // 综合实力
    public var memberCount:Int = 0;     // 成员数
    public var alignment:String;        // righteous/demonic/neutral
    public var alive:Bool = true;
    public var treasury:Int = 0;        // 宗库灵石

    public function new(id:Int, name:String) {
        this.id = id;
        this.name = name;
    }

    public function dailyUpdate(world:WorldEngine):Void {
        // 统计成员
        memberCount = 0;
        var totalPower = 0.0;
        for (e in world.entities) {
            if (!e.alive) continue;
            var fac = e.get(FactionComp);
            if (fac != null && fac.factionId == id) {
                memberCount++;
                var cult = e.get(CultivationComp);
                if (cult != null) totalPower += cult.getCombatPower();
            }
        }

        strength = totalPower;

        // 势力覆灭检测
        if (memberCount == 0 && alive) {
            alive = false;
            world.emitEvent(new WorldEvent(-1, -1, "FactionFall",
                name + " 因弟子凋零,宗门覆灭!"
            ));
        }

        // 势力扩张: 如果实力足够强, 自动招收新弟子
        if (alive && memberCount > 5 && Math.random() < 0.1) {
            // 找一个散修, 尝试招入
            for (e in world.entities) {
                if (!e.alive) continue;
                var fac = e.get(FactionComp);
                if (fac != null && fac.factionId == -1) {
                    var cult = e.get(CultivationComp);
                    if (cult != null && cult.realmIndex >= 1) {
                        fac.factionId = id;
                        fac.factionName = name;
                        fac.factionRank = 0;
                        world.emitEvent(new WorldEvent(e.id, -1, "JoinFaction",
                            e.name + " 加入" + name
                        ));
                        break;
                    }
                }
            }
        }
    }
}

// ============================================================
//  市场物品
// ============================================================
class MarketItem {
    public var name:String;
    public var price:Int;
    public var sellerId:Int;
    public var sold:Bool = false;

    public function new(name:String, price:Int, sellerId:Int) {
        this.name = name;
        this.price = price;
        this.sellerId = sellerId;
    }
}

// ============================================================
//  玩家指令
// ============================================================
class PlayerCommand {
    public var type:IntentType;
    public var targetEntityId:Int;
    public var targetX:Float;
    public var targetY:Float;
    public var spellId:String;
    public var formationId:String;

    public function new(type:IntentType) {
        this.type = type;
    }
}

// ============================================================
//  灵草资源点 (CraftingEconomySystem 使用)
// ============================================================
class SpiritHerbNode {
    public var id:Int;
    public var x:Float;
    public var y:Float;
    public var herbs:Float;          // 当前灵草储量(连续值, 采集时取整)
    public var maxHerbs:Float;       // 最大储量
    public var alive:Bool = true;
    public var growthTimer:Float = 0;
    public var depletedTimer:Float = 0;

    public function new(id:Int) {
        this.id = id;
    }
}

// ============================================================
//  秘境 (WorldCataclysmSystem 使用)
// ============================================================
class SecretRealm {
    public var x:Float;
    public var y:Float;
    public var radius:Float;
    public var remainTime:Float;     // 剩余存在时间(秒)
    public var heritageValue:Int;    // 传承价值
    public var heritageType:String;  // exp/artifact/root
    public var active:Bool = true;
    public var benefitedIds:Array<Int> = []; // 已获得传承的实体ID

    public function new() {}
}

// ============================================================
//  进行中的大型世界事件 (WorldCataclysmSystem 使用)
// ============================================================
class CataclysmEvent {
    public var type:String;          // BeastTide/SecretRealm/SpiritSurge/FactionWar
    public var startDay:Int;
    public var duration:Float;       // 持续时间(秒)
    public var desc:String;
    public var x:Float = 0;
    public var y:Float = 0;
    public var finished:Bool = false;

    public function new(type:String, startDay:Int) {
        this.type = type;
        this.startDay = startDay;
    }
}
