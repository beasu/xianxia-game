package ecs;

// ============================================================
//  CraftingEconomySystem.hx - 造物与经济流转系统
//  priority: 22 (在生态之后, 因果天劫之前)
//
//  核心机制:
//  1. 灵草资源点: 灵脉附近随机分布, 持续生长灵草
//  2. NPC 采集: 进入资源点范围的 NPC 可采集灵草
//  3. 炼丹: 有 alchemySkill 的 NPC, 灵草+灵石足够时按配方炼丹
//     - 回气丹(恢复MP)/疗伤丹(恢复HP)/筑基丹(突破加成)/凝神丹(临时天赋)
//  4. 炼器: 有 smithingSkill 的 NPC, 材料+灵石足够时按配方炼器
//     - 凡器(+5%)/灵器(+15%)/法宝(+30%) 战力倍率
//  5. 丹药使用: HP/MP 低时自动用丹, 突破前用筑基丹
//  6. 法器装备: 自动装备最强法器, 更新 externalPowerMul
//
//  本系统激活了 InventoryComp 的 pills/herbs/materials/artifacts 字段,
//  让世界形成 "采集→炼制→使用→战力提升" 的完整闭环.
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;
import ecs.WorldEngine.SpiritHerbNode;

class CraftingEconomySystem implements ISystem {
    public var priority:Int = 22;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var herbGrowthRate:Float = 0.05;     // 灵草点每秒生长量
    public var herbGatherRange:Float = 60;      // 采集范围
    public var herbGatherAmount:Int = 1;        // 每次采集数量
    public var gatherCooldown:Float = 5.0;      // 采集冷却(秒)
    public var craftCheckInterval:Float = 15.0; // 炼制检查间隔
    public var alchemyCooldownTime:Float = 30.0; // 炼丹冷却
    public var smithingCooldownTime:Float = 60.0; // 炼器冷却
    public var alchemySkillGain:Float = 0.5;    // 每次炼丹熟练度提升
    public var smithingSkillGain:Float = 0.4;   // 每次炼器熟练度提升
    public var herbPerVein:Int = 5;             // 每个灵脉附近的灵草点数

    // === 丹药配方 ===
    public static var alchemyRecipes = [
        {name: "回气丹",   herbs: 5,  stones: 20,  difficulty: 10, effect: "mp",       value: 100},
        {name: "疗伤丹",   herbs: 8,  stones: 30,  difficulty: 20, effect: "hp",       value: 200},
        {name: "凝神丹",   herbs: 15, stones: 80,  difficulty: 40, effect: "talent",   value: 0.15},
        {name: "筑基丹",   herbs: 20, stones: 100, difficulty: 50, effect: "breakthrough", value: 0.25},
        {name: "九转金丹", herbs: 50, stones: 300, difficulty: 80, effect: "realmup",  value: 1}
    ];

    // === 法器配方 ===
    public static var smithingRecipes = [
        {name: "凡器·青锋剑", materials: 5,  stones: 30,  difficulty: 15, powerBonus: 0.05},
        {name: "灵器·玄铁印", materials: 20, stones: 100, difficulty: 40, powerBonus: 0.15},
        {name: "法宝·定光珠", materials: 50, stones: 300, difficulty: 70, powerBonus: 0.30},
        {name: "仙器·混元鼎", materials: 100, stones: 800, difficulty: 90, powerBonus: 0.50}
    ];

    var craftCheckTimer:Float = 0;

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 1. 灵草资源点生长
        updateHerbNodes(world, dt);

        // 2. NPC 采集(实时, 由 NPCStateComp.decisionCooldown 控制)
        processGathering(world, dt);

        // 3. 每日更新: 法器装备 + 丹药使用
        if (world.tickCount % world.ticksPerDay == 0) {
            dailyAlchemyAndSmithing(world);
        }

        // 4. 实时: 战斗中自动用丹
        processPillUsage(world, dt);

        // 5. 周期: 炼制行为
        craftCheckTimer += dt;
        if (craftCheckTimer >= craftCheckInterval) {
            craftCheckTimer = 0;
            processCrafting(world);
        }

        // 6. 实时: 法器装备更新(影响战力)
        updateArtifactEquipment(world);
    }

    // --- 灵草资源点生长 ---
    function updateHerbNodes(world:WorldEngine, dt:Float):Void {
        for (node in world.spiritHerbNodes) {
            if (!node.alive) continue;
            node.growthTimer += dt;
            if (node.growthTimer >= 1.0) {
                node.growthTimer = 0;
                // 灵气浓度影响生长速度
                var densityMul = 1.0;
                var ecology = world.getEcologySystem();
                if (ecology != null) {
                    densityMul = ecology.getSpiritDensityAt(node.x, node.y);
                }
                node.herbs = Math.min(node.maxHerbs, node.herbs + herbGrowthRate * densityMul);
            }
            // 灵草点耗尽后冷却重生
            if (node.herbs < 0.1 && node.depletedTimer <= 0) {
                node.depletedTimer = 60; // 60 秒后恢复
            }
            if (node.depletedTimer > 0) {
                node.depletedTimer -= dt;
                if (node.depletedTimer <= 0) {
                    node.herbs = node.maxHerbs * 0.3;
                    node.alive = true;
                }
            }
        }
    }

    // --- NPC 采集 ---
    function processGathering(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive || e.isPlayer) continue;
            var pos = e.get(PositionComp);
            var npcState = e.get(NPCStateComp);
            var inv = e.get(InventoryComp);
            var intent = e.get(IntentComp);
            if (pos == null || npcState == null || inv == null || intent == null) continue;

            npcState.decisionCooldown -= dt; // 复用决策冷却字段
            // 修炼/寻找资源时才采集
            if (intent.currentIntent != SeekResource && intent.currentIntent != Cultivate) continue;

            // 查找最近的灵草点
            var nearestNode:SpiritHerbNode = null;
            var nearestDist = Math.POSITIVE_INFINITY;
            for (node in world.spiritHerbNodes) {
                if (!node.alive || node.herbs < 1) continue;
                var dx = node.x - pos.x;
                var dy = node.y - pos.y;
                var dist = dx * dx + dy * dy;
                if (dist < nearestDist && dist < 250 * 250) {
                    nearestDist = dist;
                    nearestNode = node;
                }
            }

            if (nearestNode == null) continue;

            // 移动到灵草点
            var dx = nearestNode.x - pos.x;
            var dy = nearestNode.y - pos.y;
            var dist = Math.sqrt(dx * dx + dy * dy);
            if (dist > herbGatherRange) {
                if (dist > 1) {
                    var speed = 25;
                    pos.vx += (dx / dist) * speed * dt * 10;
                    pos.vy += (dy / dist) * speed * dt * 10;
                }
            } else {
                // 采集
                if (nearestNode.herbs >= herbGatherAmount) {
                    nearestNode.herbs -= herbGatherAmount;
                    inv.herbs += herbGatherAmount;
                    // 顺便捡到材料
                    if (Math.random() < 0.3) {
                        inv.materials += 1;
                    }
                }
            }
        }
    }

    // --- 每日炼制行为 ---
    function dailyAlchemyAndSmithing(world:WorldEngine):Void {
        // 留空, 炼制主要在 processCrafting 中处理
    }

    // --- 战斗中自动用丹 ---
    function processPillUsage(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            var cult = e.get(CultivationComp);
            var inv = e.get(InventoryComp);
            var intent = e.get(IntentComp);
            if (cult == null || inv == null) continue;

            // HP 低: 用疗伤丹
            if (cult.hp < cult.maxHp * 0.4 && inv.pills.exists("疗伤丹") && inv.pills["疗伤丹"] > 0) {
                if (inv.usePill("疗伤丹")) {
                    cult.hp = Math.min(cult.maxHp, cult.hp + cult.maxHp * 0.3);
                    if (!e.isPlayer) {
                        world.emitEvent(new WorldEvent(e.id, -1, "UsePill",
                            e.name + " 服下疗伤丹, 气血回流"
                        ));
                    }
                }
            }

            // MP 低: 用回气丹
            if (cult.mp < cult.maxMp * 0.3 && inv.pills.exists("回气丹") && inv.pills["回气丹"] > 0) {
                if (inv.usePill("回气丹")) {
                    cult.mp = Math.min(cult.maxMp, cult.mp + cult.maxMp * 0.4);
                }
            }

            // 突破前: 用筑基丹
            if (intent != null && intent.currentIntent == Breakthrough
                && inv.pills.exists("筑基丹") && inv.pills["筑基丹"] > 0) {
                if (inv.usePill("筑基丹")) {
                    // 临时气运加成(模拟突破成功率提升)
                    cult.luck += 0.25;
                    if (!e.isPlayer) {
                        world.emitEvent(new WorldEvent(e.id, -1, "UsePill",
                            e.name + " 服下筑基丹, 冲击境界!"
                        ));
                    }
                }
            }
        }
    }

    // --- 周期性炼制 ---
    function processCrafting(world:WorldEngine):Void {
        for (e in world.entities) {
            if (!e.alive || e.isPlayer) continue;
            var crafting = e.get(CraftingComp);
            var inv = e.get(InventoryComp);
            var cult = e.get(CultivationComp);
            if (crafting == null || inv == null || cult == null) continue;

            // 冷却递减
            crafting.alchemyCooldown = Math.max(0, crafting.alchemyCooldown - craftCheckInterval);
            crafting.smithingCooldown = Math.max(0, crafting.smithingCooldown - craftCheckInterval);

            // 炼丹
            if (crafting.alchemyCooldown <= 0 && cult.realmIndex >= 1) {
                tryAlchemy(world, e, crafting, inv, cult);
            }

            // 炼器
            if (crafting.smithingCooldown <= 0 && cult.realmIndex >= 2) {
                trySmithing(world, e, crafting, inv, cult);
            }
        }
    }

    // --- 尝试炼丹 ---
    function tryAlchemy(world:WorldEngine, e:Entity, crafting:CraftingComp, inv:InventoryComp, cult:CultivationComp):Void {
        // 选择一个能负担且难度合适的配方
        var bestRecipe = null;
        for (r in alchemyRecipes) {
            if (r.difficulty > crafting.alchemySkill + 30) continue;
            if (inv.herbs < r.herbs || inv.spiritStones < r.stones) continue;
            // 优先选可负担的最高难度配方
            if (bestRecipe == null || r.difficulty > bestRecipe.difficulty) {
                bestRecipe = r;
            }
        }
        if (bestRecipe == null) return;

        // 消耗材料
        inv.herbs -= bestRecipe.herbs;
        inv.spiritStones -= bestRecipe.stones;

        // 成功率: 熟练度/难度
        var successRate = Math.min(0.95, 0.4 + crafting.alchemySkill / bestRecipe.difficulty * 0.5);
        crafting.alchemySkill = Math.min(100, crafting.alchemySkill + alchemySkillGain);
        crafting.alchemyCooldown = alchemyCooldownTime;

        if (Math.random() < successRate) {
            // 成品品质: 熟练度越高, 出产数量越多
            var yield = 1;
            if (crafting.alchemySkill > 60 && Math.random() < 0.3) yield = 2;
            inv.addPill(bestRecipe.name, yield);
            world.emitEvent(new WorldEvent(e.id, -1, "Alchemy",
                e.name + " 炼制 " + bestRecipe.name + " x" + yield + " 成功"
            ));
        } else {
            // 失败: 损失材料, 极小概率走火(受伤)
            world.emitEvent(new WorldEvent(e.id, -1, "AlchemyFail",
                e.name + " 炼丹失败, 损耗灵草"
            ));
            if (Math.random() < 0.1) {
                cult.hp -= cult.maxHp * 0.05;
            }
        }
    }

    // --- 尝试炼器 ---
    function trySmithing(world:WorldEngine, e:Entity, crafting:CraftingComp, inv:InventoryComp, cult:CultivationComp):Void {
        var bestRecipe = null;
        for (r in smithingRecipes) {
            if (r.difficulty > crafting.smithingSkill + 30) continue;
            if (inv.materials < r.materials || inv.spiritStones < r.stones) continue;
            // 已拥有该法器则跳过(不重复炼制同名)
            if (inv.artifacts.indexOf(r.name) >= 0) continue;
            if (bestRecipe == null || r.difficulty > bestRecipe.difficulty) {
                bestRecipe = r;
            }
        }
        if (bestRecipe == null) return;

        inv.materials -= bestRecipe.materials;
        inv.spiritStones -= bestRecipe.stones;

        var successRate = Math.min(0.95, 0.35 + crafting.smithingSkill / bestRecipe.difficulty * 0.55);
        crafting.smithingSkill = Math.min(100, crafting.smithingSkill + smithingSkillGain);
        crafting.smithingCooldown = smithingCooldownTime;

        if (Math.random() < successRate) {
            inv.artifacts.push(bestRecipe.name);
            world.emitEvent(new WorldEvent(e.id, -1, "Smithing",
                e.name + " 炼成 " + bestRecipe.name + "!"
            ));
        } else {
            world.emitEvent(new WorldEvent(e.id, -1, "SmithingFail",
                e.name + " 炼器失败, 材料尽毁"
            ));
        }
    }

    // --- 法器装备更新 ---
    function updateArtifactEquipment(world:WorldEngine):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            var inv = e.get(InventoryComp);
            var cult = e.get(CultivationComp);
            if (inv == null || cult == null) continue;

            // 找出最强的法器
            var bestName = "";
            var bestBonus = 0.0;
            for (art in inv.artifacts) {
                var bonus = getArtifactBonus(art);
                if (bonus > bestBonus) {
                    bestBonus = bonus;
                    bestName = art;
                }
            }

            // 装备更强法器
            if (bestBonus > inv.equippedArtifactBonus) {
                inv.equippedArtifact = bestName;
                inv.equippedArtifactBonus = bestBonus;
                cult.externalPowerMul = 1.0 + bestBonus;
                if (!e.isPlayer && bestName != "") {
                    world.emitEvent(new WorldEvent(e.id, -1, "EquipArtifact",
                        e.name + " 装备 " + bestName + ", 战力倍增"
                    ));
                }
            }
        }
    }

    // --- 查询法器战力加成 ---
    public static function getArtifactBonus(name:String):Float {
        for (r in smithingRecipes) {
            if (r.name == name) return r.powerBonus;
        }
        return 0.0;
    }

    // --- 查询丹药价值(用于交易) ---
    public static function getPillValue(name:String):Int {
        for (r in alchemyRecipes) {
            if (r.name == name) return r.stones + r.herbs * 2;
        }
        return 10;
    }

    function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }
}
