package ecs;

// ============================================================
//  Components.hx - 所有纯数据组件定义
//  修仙世界的"物质基础"——所有数据都在这里
// ============================================================

import ecs.Entity.IComponent;

// --- 位置组件 ---
class PositionComp implements IComponent {
    public var x:Float;
    public var y:Float;
    public var vx:Float = 0;
    public var vy:Float = 0;

    public function new(x:Float = 0, y:Float = 0) {
        this.x = x;
        this.y = y;
    }
}

// --- 修仙组件 ---
class CultivationComp implements IComponent {
    public var realmIndex:Int = 0;      // 境界索引
    public var realmName:String = "练气期";
    public var hp:Float = 100;
    public var maxHp:Float = 100;
    public var mp:Float = 50;
    public var maxMp:Float = 50;
    public var exp:Float = 0;
    public var expToNext:Float = 100;
    public var attackPower:Int = 20;
    public var spiritRoot:String = "fire";
    public var spiritRootName:String = "火灵根";
    public var spiritRootQuality:Int = 0;
    public var spiritRootQualityName:String = "凡品";
    public var lifespan:Float = 100;     // 寿元(年)
    public var age:Float = 16;           // 当前年龄
    public var talent:Float = 1.0;       // 天赋倍率
    public var luck:Float = 1.0;         // 气运值

    public function new() {}

    public function getRootColor():Int {
        return switch (spiritRoot) {
            case "fire": 0xff4400;
            case "water": 0x0066ff;
            case "wood": 0x22aa44;
            case "metal": 0xddaa00;
            case "earth": 0x886644;
            case "thunder": 0xcc88ff;
            case "ice": 0x88ddff;
            case "dark": 0x8800ff;
            default: 0xff4400;
        };
    }

    public function getSpellMultiplier(spellId:String):Float {
        var bonuses:Map<String, Float> = switch (spiritRoot) {
            case "fire": ["fireball" => 1.5, "thunderstorm" => 1.3, "lotus" => 1.2];
            case "water": ["ice" => 1.5, "lotus" => 1.3];
            case "wood": ["lotus" => 1.6, "clone" => 1.3];
            case "metal": ["swordqi" => 1.6, "thunder" => 1.2];
            case "earth": ["pocket" => 1.5, "voidshift" => 1.3];
            case "thunder": ["thunder" => 1.6, "thunderstorm" => 1.4, "bigdipper" => 1.2];
            case "ice": ["ice" => 1.6, "thunderstorm" => 1.2];
            case "dark": ["pocket" => 1.4, "voidshift" => 1.4, "clone" => 1.3];
            default: [];
        };
        var base = bonuses.exists(spellId) ? bonuses[spellId] : 1.0;
        return base * (1.0 + spiritRootQuality * 0.1);
    }

    public function getCombatPower():Float {
        return (attackPower * (1 + realmIndex * 0.5)) * (hp / maxHp) * talent * luck;
    }
}

// --- 意图组件 ---
class IntentComp implements IComponent {
    public var currentIntent:IntentType = Idle;
    public var targetEntityId:Int = -1;  // 意图目标实体ID
    public var targetX:Float = 0;        // 移动目标坐标
    public var targetY:Float = 0;
    public var intentTimer:Float = 0;    // 意图持续时间
    public var aggression:Float = 0.5;   // 攻击性(0-1)
    public var greed:Float = 0.5;        // 贪婪度(0-1)
    public var wisdom:Float = 0.5;       // 智慧(0-1)

    public function new() {}
}

enum abstract IntentType(Int) from Int to Int {
    var Idle = 0;           // 闲置
    var Cultivate = 1;      // 打坐修炼
    var Wander = 2;         // 游历
    var SeekResource = 3;   // 寻找资源
    var AttackEntity = 4;   // 攻击实体
    var Flee = 5;           // 逃跑
    var Trade = 6;          // 交易
    var Breakthrough = 7;   // 冲击境界
    var JoinFaction = 8;    // 加入宗门
    var PlayerCommand = 9;  // 玩家指令
    var Dead = 10;          // 死亡
    // === NPCSocialSystem 新增意图 ===
    var Socialize = 11;     // 社交(结盟/联姻/拜访)
    var Betray = 12;        // 背叛
    var Assassinate = 13;   // 暗杀
}

// --- 因果/业力组件 ---
// (已有 KarmaComp, 此处扩展业障值字段, 用于天道与天劫系统)
class KarmaComp implements IComponent {
    public var karma:Float = 0;          // 业力值(正=善, 负=恶)
    public var notoriety:Float = 0;      // 恶名值
    public var reputation:Float = 0;     // 名声值
    public var titles:Array<String> = []; // 称号列表
    public var bounty:Float = 0;         // 悬赏金额
    public var killCount:Int = 0;        // 击杀数
    public var memories:Map<Int, MemoryRecord> = []; // 对其他实体的记忆

    // === 天道与业障系统新增字段 ===
    public var sinValue:Float = 0;       // 业障值(0-100, 越高越易招天劫)
    public var meritValue:Float = 0;     // 功德值(正数, 可抵消业障)
    public var tribulationPending:Bool = false; // 是否有待降临的天劫
    public var tribulationType:String = "";     // "heartDemon" | "lightning" | ""
    public var tribulationPower:Float = 0;      // 天劫威力基数
    public var lastTribulationDay:Int = 0;      // 上次天劫日期(冷却用)
    public var heartDemonDefeated:Bool = false; // 心魔是否已被克服
    public var lastProcessedEventTick:Int = -1; // 最后处理过的事件tick(去重用)

    public function new() {}

    // 获取净业障值(扣除功德后的有效值)
    public function getNetSin():Float {
        return Math.max(0, sinValue - meritValue * 0.5);
    }
}

// 记忆记录
class MemoryRecord {
    public var entityId:Int;
    public var relation:Float;     // 关系值(-100 到 100)
    public var lastInteraction:Int; // 最后互动的世界日
    public var note:String;        // 备注

    public function new(entityId:Int, relation:Float = 0, note:String = "") {
        this.entityId = entityId;
        this.relation = relation;
        this.note = note;
        this.lastInteraction = 0;
    }
}

// --- 背包/物品组件 ---
class InventoryComp implements IComponent {
    public var spiritStones:Int = 0;     // 灵石(通用货币)
    public var pills:Map<String, Int> = []; // 丹药库存
    public var artifacts:Array<String> = []; // 法器
    public var herbs:Int = 0;            // 灵草数量
    public var materials:Int = 0;        // 炼器材料

    public function new() {}
}

// --- 势力/宗门组件 ---
class FactionComp implements IComponent {
    public var factionId:Int = -1;       // 所属宗门ID(-1=散修)
    public var factionName:String = "散修";
    public var factionRank:Int = 0;      // 在宗门中的等级(0=弟子, 1=内门, 2=长老, 3=掌门)
    public var factionContribution:Float = 0; // 贡献值

    public function new() {}
}

// --- NPC 行为状态组件 ---
class NPCStateComp implements IComponent {
    public var npcType:String = "moxiu"; // moxiu/yaoshou/mojiang/xiexian/cultivator
    public var aiState:String = "idle";  // idle/cultivating/wandering/fighting/fleeing/trading
    public var aiTimer:Float = 0;        // AI 状态计时器
    public var aiTargetId:Int = -1;      // AI 目标实体
    public var homeX:Float = 0;          // 巢穴/驻地坐标
    public var homeY:Float = 0;
    public var patrolRadius:Float = 200; // 巡逻半径
    public var decisionCooldown:Float = 0; // 决策冷却

    public function new() {}
}

// --- 渲染组件(连接 ECS 和 Heaps 渲染) ---
class RenderComp implements IComponent {
    public var cultivator:Cultivator;    // 引用 Heaps 渲染对象
    public var visible:Bool = true;
    public var needsRedraw:Bool = false;

    public function new(cultivator:Cultivator) {
        this.cultivator = cultivator;
    }
}

// ============================================================
//  === 世界生态与天道系统 新增组件 ===
// ============================================================

// --- 社交组件 (NPCSocialSystem 使用) ---
class SocialComp implements IComponent {
    public var relationships:Map<Int, SocialRelation> = []; // 对其他实体的社交关系
    public var socialRole:String = "loner";   // social角色: loner/leader/follower/diplomat/schemer
    public var ambition:Float = 0.5;          // 野心值(0-1, 高则倾向背叛/夺权)
    public var loyalty:Float = 0.5;           // 忠诚度(0-1, 低则易被策反)
    public var charm:Float = 0.5;             // 魅力值(影响结盟/联姻成功率)
    public var socialCooldown:Float = 0;      // 社交行为冷却
    public var allies:Array<Int> = [];        // 盟友实体ID列表
    public var enemies:Array<Int> = [];       // 仇敌实体ID列表
    public var spouseId:Int = -1;             // 道侣ID(-1=无)
    public var masterId:Int = -1;             // 师父ID(-1=无)
    public var disciples:Array<Int> = [];     // 弟子ID列表

    public function new() {}
}

// 社交关系记录
class SocialRelation {
    public var entityId:Int;
    public var affinity:Float;       // 好感度(-100 到 100)
    public var trust:Float;          // 信任度(0-100)
    public var relationType:String;  // neutral/ally/enemy/spouse/disciple/master/rival
    public var lastInteractionDay:Int; // 最后互动日
    public var interactionCount:Int;   // 互动次数

    public function new(entityId:Int, affinity:Float = 0, relationType:String = "neutral") {
        this.entityId = entityId;
        this.affinity = affinity;
        this.trust = 50;
        this.relationType = relationType;
        this.lastInteractionDay = 0;
        this.interactionCount = 0;
    }
}

// --- 生态区域组件 (挂载到世界, 非实体组件, 由 WorldEcologySystem 管理) ---
// 注意: 这是一个数据类, 不是 IComponent, 因为它挂载到世界网格而非实体
class EcologyGridCell {
    public var gridX:Int;
    public var gridY:Int;
    public var centerX:Float;
    public var centerY:Float;
    public var spiritDensity:Float;     // 当前灵气浓度
    public var baseDensity:Float;       // 基础灵气浓度
    public var cultivatorCount:Int;     // 当前格子内修士数量
    public var deathCount:Int;          // 累计死亡数
    public var recentDeaths:Int;        // 近期死亡数(用于灵气暴涨)
    public var tidePhase:Float;         // 潮汐相位
    public var depleted:Float;          // 灵气枯竭度(0-1, 修士密度过高时增加)
    public var surge:Float;             // 灵气暴涨度(0-1, 大量死亡时增加)

    public function new(gx:Int, gy:Int, cx:Float, cy:Float) {
        gridX = gx;
        gridY = gy;
        centerX = cx;
        centerY = cy;
        spiritDensity = 1.0;
        baseDensity = 1.0;
        cultivatorCount = 0;
        deathCount = 0;
        recentDeaths = 0;
        tidePhase = 0;
        depleted = 0;
        surge = 0;
    }
}
