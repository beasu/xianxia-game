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
}

// --- 因果/业力组件 ---
class KarmaComp implements IComponent {
    public var karma:Float = 0;          // 业力值(正=善, 负=恶)
    public var notoriety:Float = 0;      // 恶名值
    public var reputation:Float = 0;     // 名声值
    public var titles:Array<String> = []; // 称号列表
    public var bounty:Float = 0;         // 悬赏金额
    public var killCount:Int = 0;        // 击杀数
    public var memories:Map<Int, MemoryRecord> = []; // 对其他实体的记忆

    public function new() {}
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
