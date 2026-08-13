import h2d.Scene;
import h2d.Object;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Text;
import hxd.Key;
import hxd.Math;
import hxd.Window;

#if js
import js.Browser;
#end

import haxe.ui.core.Screen;
import haxe.ui.core.Component;
import haxe.ui.components.Button;
import haxe.ui.components.HorizontalProgress;
import haxe.ui.components.Label;
import haxe.ui.containers.Box;
import haxe.ui.containers.HBox;
import haxe.ui.containers.VBox;
import haxe.ui.containers.ScrollView;
import haxe.ui.Toolkit;
import haxe.ui.events.MouseEvent;

import ecs.Entity.Entity;
import ecs.Entity.ISystem;
import ecs.Components;
import ecs.WorldEngine;
import ecs.Systems;
import ecs.WorldEcologySystem;
import ecs.KarmaAndTribulationSystem;
import ecs.NPCSocialSystem;
import ecs.LifecycleAndHeritageSystem;
import ecs.CraftingEconomySystem;
import ecs.WorldCataclysmSystem;
import ecs.WeatherSystem;
import ecs.TerrainSystem;
import ecs.DayNightSystem;
import ecs.ReincarnationSystem;
import ecs.HeavenlyDaoSystem;
import ecs.KarmaChainSystem;
import ecs.PhysicsSystem;

/**
    GameScene - 修仙世界观察者
    不再直接管理游戏逻辑, 而是订阅 WorldEngine 的状态快照来渲染画面。
    玩家输入通过 PlayerCommandQueue 提交给 WorldEngine。
**/
class GameScene extends Scene {
    public static var inst:GameScene;

    // --- 世界引擎(核心) ---
    public var engine:WorldEngine;
    public static var inst2:WorldEngine;

    // --- 渲染层 ---
    public var worldCamera:Object;      // 镜头容器: 所有世界元素挂在此节点下, 平移它实现镜头跟随
    public var fxLayer:Object;
    public var formationLayer:Object;
    public var bgLayer:Object;
    public var entityLayer:Object;
    public var uiLayer:Object;          // UI 层不挂在 worldCamera 下, 始终固定在屏幕上

    // --- 镜头 ---
    public var camX:Float = 0;          // 镜头左上角在世界坐标中的 X
    public var camY:Float = 0;          // 镜头左上角在世界坐标中的 Y
    public var viewW:Float;             // 可视区域宽(屏幕宽)
    public var viewH:Float;             // 可视区域高(屏幕高)

    // --- 阵法 ---
    public var activeFormation:Formation;

    // --- 粒子 ---
    public var particles:Array<Particle> = [];
    public var particlePool:Array<Particle> = [];

    // --- 实体渲染映射 (Entity.id -> Cultivator) ---
    public var renderMap:Map<Int, Cultivator> = [];

    // --- 鼠标(世界坐标) ---
    public var camMouseX:Float = 0;  // 已转换为世界坐标
    public var camMouseY:Float = 0;

    // --- 时间 ---
    public var elapsed:Float = 0;
    public var spawnTimer:Float = 0;
    public var killCount:Int = 0;
    public var breakthroughFlash:Float = 0;

    // --- 背景 ---
    var bgClouds:Array<{g:h2d.Graphics, x:Float, y:Float, vx:Float, alpha:Float}> = [];
    var bgSpiritParticles:Array<{bmp:Bitmap, x:Float, y:Float, vy:Float, alpha:Float, phase:Float}> = [];
    var bgTime:Float = 0;

    // --- HaxeUI ---
    var uiHpBar:HorizontalProgress;
    var uiMpBar:HorizontalProgress;
    var uiExpBar:HorizontalProgress;
    var uiInfo:Label;
    var uiHpNum:Label;
    var uiMpNum:Label;
    var uiKillLabel:Label;
    var uiRealmLabel:Label;
    var uiExpLabel:Label;
    var uiRootLabel:Label;
    var uiRootDetail:Label;
    var uiSkillButtons:Array<Button> = [];
    var uiFormationButtons:Array<Button> = [];
    var uiSpeedButtons:Array<Button> = []; // 时间速度按钮
    var uiActiveEvent:Label;         // 当前进行中的世界事件
    var uiStatusInfo:Label;          // 物理状态/天气/昼夜信息条

    // --- Tab 按钮的 Heaps 原生 Interactive (绕过 HaxeUI 事件系统) ---
    var tabInteractives:Array<h2d.Interactive> = [];

    // --- 时间控制 ---
    public var timeScale:Float = 1.0; // 0=暂停, 1=正常, 2/4=加速
    public var paused:Bool = false;

    // --- 世界元素渲染对象 ---
    var herbNodeGraphics:Array<h2d.Graphics> = [];
    var secretRealmGraphics:Array<h2d.Graphics> = [];

    // --- NPC 详情浮窗 ---
    var npcDetailPanel:VBox;
    var npcDetailLabel:Label;
    var npcDetailCloseBtn:Button;
    var selectedNpcEntity:Entity;

    // --- 右侧 Tab 容器(合并天道/宗门/编年史) ---
    var rightTabBar:HBox;
    var tabWorldBtn:Button;
    var tabFactionBtn:Button;
    var tabChronicleBtn:Button;
    var currentRightTab:String = "world"; // world / faction / chronicle
    // 单 Label 方案: 避免组件增删导致 HaxeUI validateData 崩溃
    var uiTabContent:Label;
    var worldTabText:String = "";
    var factionTabText:String = "";
    var chronicleTabText:String = "";

    // --- 小地图 ---
    var minimapGraphics:h2d.Graphics;
    var minimapBorder:h2d.Graphics;

    // --- 鼠标右键自动移动 ---
    var moveTargetX:Float = 0;
    var moveTargetY:Float = 0;
    var isAutoMoving:Bool = false;

    // === 仙侠水墨风样式常量 ===
    // 配色: 墨黑底 + 金棕卷轴边 + 金红标题 + 米黄正文
    static var SX_PANEL = "background-color:#0a0a14dd;border:2px solid #8b6914;border-radius:4px;padding:6px;";
    static var SX_TITLE = "font-size:16px;color:#d4a04c;font-weight:bold;";
    static var SX_SUBTITLE = "font-size:14px;color:#c8442a;font-weight:bold;";
    static var SX_TEXT = "font-size:13px;color:#e8d8a8;";
    static var SX_TEXT_DIM = "font-size:13px;color:#8a7a5c;";
    static var SX_TEXT_HOT = "font-size:13px;color:#e8a04c;";
    static var SX_BTN = "font-size:13px;background-color:#1a1410;border:1px solid #8b6914;color:#e8d8a8;border-radius:3px;";
    static var SX_BTN_HOT = "font-size:13px;background-color:#4a3a1a;border:1px solid #d4a04c;color:#ffe8a8;border-radius:3px;font-weight:bold;";
    static var SX_BTN_DANGER = "font-size:13px;background-color:#2a1410;border:1px solid #c8442a;color:#ff8866;border-radius:3px;";
    static var SX_BAR_HP = "background-color:#2a0a08;border:1px solid #8b2418;";
    static var SX_BAR_MP = "background-color:#081a2a;border:1px solid #2a5a8b;";
    static var SX_BAR_EXP = "background-color:#0a1a0a;border:1px solid #4a7a3a;";
    static var SX_SCROLL_BORDER = "border:2px solid #8b6914;border-radius:4px;background-color:#0a0a14ee;";

    // --- 技能冷却 ---
    public var cooldowns:Map<String, Float> = [];

    // --- 玩家采集灵草 ---
    var playerGatherCd:Float = 0;

    // --- 法术目标选择系统 ---
    // 按下技能键后进入瞄准模式, 左键选择释放位置, Tab 自动锁定最近敌人
    var pendingSpell:String = null;       // 待释放的法术ID (null=未在瞄准)
    var pendingSpellMpCost:Int = 0;       // 待释放法术的灵力消耗
    var pendingSpellCd:Float = 0;         // 待释放法术的冷却时间
    var targetingTimer:Float = 0;         // 瞄准模式超时计时(秒, 0=未在瞄准)
    var targetingMaxTime:Float = 3.0;     // 瞄准模式最大持续时间
    var targetingIndicator:h2d.Graphics;  // 瞄准指示器(范围圈)

    // --- 天气视觉层 ---
    var weatherOverlay:h2d.Graphics;      // 天气覆盖层(挂在 uiLayer 下, 固定屏幕)
    var weatherParticles:Array<{x:Float, y:Float, vx:Float, vy:Float, type:String, life:Float}> = [];
    var weatherFlash:Float = 0;           // 雷暴闪光计时

    // --- 昼夜 ---
    var dayNightOverlay:h2d.Bitmap;       // 昼夜暗化覆盖层
    var dayNightAlpha:Float = 0;          // 当前暗化透明度(0=白天, 0.6=夜晚)

    // --- 六大世界规则系统可视化 ---
    var terrainLayer:h2d.Graphics;        // 地形网格颜色层(挂在 bgLayer 上)
    var terrainInitialized:Bool = false;  // 地形是否已初始化渲染
    var divineFxLayer:h2d.Graphics;       // 天道特效层(金光/天罚/天道之眼)
    var karmaFxLayer:h2d.Graphics;        // 因果链特效层(追杀红线/悬赏标记)
    var reincarnationFxLayer:h2d.Graphics;// 轮回特效层(残魂/转世光柱)
    var divineFlash:Float = 0;            // 天道干预闪光计时
    var tribulationFlash:Float = 0;       // 天罚闪光计时

    // --- 物理状态信息(供 UI 显示) ---
    var playerPhysStatus:String = "";     // 玩家物理状态摘要

    // --- 玩家引用(渲染对象) ---
    public var player:Cultivator;
    public var playerEntity:Entity;

    static var skillDefs = [
        {key: "Q", name: "Q\n三昧真火", skill: "fireball", cd: 1.5, mpCost: 30},
        {key: "F", name: "F\n九天玄雷", skill: "thunder", cd: 2.0, mpCost: 50},
        {key: "E", name: "E\n玄冰诀", skill: "ice", cd: 1.8, mpCost: 35},
        {key: "R", name: "R\n万剑归宗", skill: "swordqi", cd: 3.0, mpCost: 60},
        {key: "T", name: "T\n天雷破", skill: "thunderstorm", cd: 5.0, mpCost: 100},
        {key: "Y", name: "Y\n袖里乾坤", skill: "pocket", cd: 6.0, mpCost: 80},
        {key: "U", name: "U\n莲花绽放", skill: "lotus", cd: 4.0, mpCost: 70},
        {key: "I", name: "I\n天罡北斗", skill: "bigdipper", cd: 5.0, mpCost: 90},
        {key: "O", name: "O\n分影术", skill: "clone", cd: 4.5, mpCost: 60},
        {key: "P", name: "P\n乾坤挪移", skill: "voidshift", cd: 3.0, mpCost: 50}
    ];

    static var formationDefs = [
        {name: "八卦阵", id: "bagua", key: "1"},
        {name: "五行阵", id: "wuxing", key: "2"},
        {name: "太极图", id: "taiji", key: "3"},
        {name: "北斗阵", id: "beidou", key: "4"},
        {name: "九宫格", id: "jiugong", key: "5"}
    ];

    static inline function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }

    public function new() {
        super();
        inst = this;
        initLayers();
        initWorldEngine();
        initBackground();
        initHaxeUI();
        castFormation("bagua");
    }

    function initLayers() {
        // worldCamera 是所有"世界元素"的父节点, 平移它实现镜头跟随
        worldCamera = new Object(this);

        bgLayer = new Object(worldCamera);
        formationLayer = new Object(worldCamera);
        entityLayer = new Object(worldCamera);
        fxLayer = new Object(worldCamera);

        // 地形网格颜色层(在背景之上, 阵法之下)
        terrainLayer = new h2d.Graphics(bgLayer);

        // 天道/因果/轮回 特效层(在实体之上)
        divineFxLayer = new h2d.Graphics(worldCamera);
        karmaFxLayer = new h2d.Graphics(worldCamera);
        reincarnationFxLayer = new h2d.Graphics(worldCamera);

        // 法术瞄准指示器(默认隐藏)
        targetingIndicator = new h2d.Graphics(worldCamera);
        targetingIndicator.visible = false;

        // UI 层直接挂在 Scene 下, 不受镜头移动影响
        uiLayer = new Object(this);

        // 天气覆盖层(固定在屏幕上, 不随镜头移动)
        weatherOverlay = new h2d.Graphics(uiLayer);

        // 昼夜光照覆盖层(全屏暗化) — 使用 Alpha blend 而非 Multiply,
        // Multiply 会直接把整个画面乘以深色, 即使 alpha 很低也会让画面全黑
        var dnTile = h2d.Tile.fromColor(0x000033, 1, 1);
        dayNightOverlay = new h2d.Bitmap(dnTile, uiLayer);
        dayNightOverlay.scaleX = 3000;
        dayNightOverlay.scaleY = 3000;
        dayNightOverlay.alpha = 0;
        dayNightOverlay.blendMode = Alpha;
    }

    // ============================================================
    //  世界引擎初始化
    // ============================================================
    function initWorldEngine() {
        // 世界尺寸 = 屏幕的 3 倍, 玩家可以在广阔世界中探索
        viewW = width;
        viewH = height;
        var worldW = width * 3;
        var worldH = height * 3;
        engine = new WorldEngine(worldW, worldH);
        inst2 = engine;

        // 注册系统
        engine.addSystem(new PhysicsSystem());           // priority 5
        engine.addSystem(new IntentResolutionSystem());   // priority 10
        engine.addSystem(new DayNightSystem());           // priority 11
        engine.addSystem(new WeatherSystem());            // priority 12
        engine.addSystem(new TerrainSystem());            // priority 14
        engine.addSystem(new NPCSocialSystem());          // priority 18
        engine.addSystem(new LifecycleAndHeritageSystem());
        engine.addSystem(new WorldEcologySystem());
        engine.addSystem(new EcologySystem());
        engine.addSystem(new CraftingEconomySystem());
        engine.addSystem(new KarmaAndTribulationSystem());
        engine.addSystem(new KarmaChainSystem());         // priority 28
        engine.addSystem(new WorldCataclysmSystem());
        engine.addSystem(new ReincarnationSystem());      // priority 35
        engine.addSystem(new HeavenlyDaoSystem());        // priority 40
        engine.addSystem(new HistorySystem());

        // 初始化灵脉
        engine.initSpiritVeins();

        // 初始化势力
        engine.initFactions();

        // 初始化灵草资源点
        engine.initSpiritHerbNodes();

        // 订阅世界事件(用于 UI 显示)
        engine.subscribeToEvents(onWorldEvent);

        // 创建玩家实体
        playerEntity = new Entity("青云道长");
        playerEntity.isPlayer = true;

        var pos = new PositionComp(engine.worldWidth * 0.5, engine.worldHeight * 0.5);
        var cult = new CultivationComp();
        cult.maxHp = 1000; cult.hp = 1000;
        cult.maxMp = 500; cult.mp = 500;
        cult.attackPower = 80;
        cult.expToNext = 100;
        cult.realmName = "练气期";

        // 随机灵根(玩家至少良品)
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
        cult.spiritRootQuality = 1; // 至少良品
        var qNames = ["凡品", "良品", "上品", "极品", "天灵根"];
        cult.spiritRootQualityName = qNames[cult.spiritRootQuality];
        cult.talent = 1.0 + cult.spiritRootQuality * 0.2;

        var intent = new IntentComp();
        var karma = new KarmaComp();
        var inv = new InventoryComp();
        inv.spiritStones = 100;
        var fac = new FactionComp();
        var npc = new NPCStateComp();
        var social = new SocialComp(); // 玩家也参与社交系统
        social.charm = 0.8; // 玩家魅力较高

        // 玩家血脉与炼制能力(玩家作为天命之子, 出生即仙骨血脉)
        var heritage = new HeritageComp();
        heritage.bloodline = "仙骨";
        heritage.generation = 1;
        heritage.birthDay = 1;
        var crafting = new CraftingComp();
        crafting.alchemySkill = 30; // 玩家初始有一定炼丹基础
        crafting.smithingSkill = 20;

        // 玩家灵力物理组件(天命之子, 灵压和神识更强)
        var spiritPhys = new SpiritPhysicsComp();
        spiritPhys.spiritPressure = 10 * Math.pow(3, cult.realmIndex);
        spiritPhys.pressureRadius = 120 + cult.realmIndex * 40;
        spiritPhys.spiritSenseRange = 400 + cult.realmIndex * 100;
        spiritPhys.resonanceElement = cult.spiritRoot;
        spiritPhys.shieldMaxStrength = 100;
        spiritPhys.shieldRegenRate = 10;

        playerEntity.add(pos).add(cult).add(intent).add(karma).add(inv).add(fac).add(npc).add(social).add(heritage).add(crafting).add(new KarmaChainComp()).add(spiritPhys);
        engine.addEntity(playerEntity);

        // 创建玩家渲染对象
        player = new Cultivator(entityLayer);
        player.charName = "青云道长";
        player.isPlayer = true;
        player.syncFromComp(pos, cult);
        player.redraw();
        player.nameText.visible = false;
        renderMap[playerEntity.id] = player;

        // 生成初始 NPC
        for (i in 0...5) {
            var npcEntity = engine.spawnRandomNPC();
            createRenderFor(npcEntity);
        }
    }

    // --- 为实体创建渲染对象 ---
    function createRenderFor(e:Entity):Cultivator {
        var pos = e.get(PositionComp);
        var cult = e.get(CultivationComp);
        var npcState = e.get(NPCStateComp);
        if (pos == null || cult == null) return null;

        var c = new Cultivator(entityLayer);
        c.isPlayer = false;
        c.charName = e.name;
        if (npcState != null) c.enemyType = npcState.npcType;
        c.syncFromComp(pos, cult);
        c.redraw();
        renderMap[e.id] = c;
        return c;
    }

    // --- 世界事件回调 ---
    function onWorldEvent(event:WorldEvent):Void {
        // 事件会在 UI 的事件日志中显示
    }

    // ============================================================
    //  背景渲染(保留之前的升级版)
    // ============================================================
    function initBackground() {
        var ww = engine.worldWidth;
        var wh = engine.worldHeight;
        for (i in 0...40) {
            var t = i / 40.0;
            var r = Std.int(0x08 + (0x18 - 0x08) * t);
            var g = Std.int(0x0a + (0x1a - 0x0a) * t);
            var b = Std.int(0x14 + (0x38 - 0x14) * t);
            var color = (r << 16) | (g << 8) | b;
            var tile = Tile.fromColor(color, 1, 1);
            var bmp = new Bitmap(tile, bgLayer);
            bmp.scaleX = ww;
            bmp.scaleY = wh / 40 + 1;
            bmp.y = i * (wh / 40);
        }

        for (i in 0...120) {
            var starSize = Math.random(2) + 1;
            var star = new Bitmap(Tile.fromColor(0xffffff, Std.int(starSize), Std.int(starSize)), bgLayer);
            star.x = Math.random(ww);
            star.y = Math.random(wh * 0.6);
            star.alpha = randRange(0.2, 0.8);
        }

        var moonG = new h2d.Graphics(bgLayer);
        var moonX = ww * 0.82;
        var moonY = wh * 0.15;
        for (i in 0...5) {
            var t = i / 5.0;
            moonG.beginFill(0xfff8e0, (1.0 - t) * 0.06);
            moonG.drawCircle(moonX, moonY, 20 + i * 12);
            moonG.endFill();
        }
        moonG.beginFill(0xfff8e0, 0.95);
        moonG.drawCircle(moonX, moonY, 18);
        moonG.endFill();
        moonG.beginFill(0xdde0c0, 0.3);
        moonG.drawCircle(moonX - 5, moonY - 3, 5);
        moonG.drawCircle(moonX + 6, moonY + 4, 3);
        moonG.drawCircle(moonX - 2, moonY + 6, 2);
        moonG.endFill();

        drawMountainLayer(wh * 0.5, 0x1a1a3a, 0.15, 0.7);
        drawMountainLayer(wh * 0.65, 0x2a2a4a, 0.25, 0.5);
        drawMountainLayer(wh * 0.8, 0x1a1a3a, 0.4, 0.3);

        for (i in 0...18) {
            var cloud = new h2d.Graphics(bgLayer);
            var cy = randRange(wh * 0.3, wh * 0.7);
            var cx = Math.random(ww);
            cloud.alpha = randRange(0.04, 0.1);
            bgClouds.push({g: cloud, x: cx, y: cy, vx: randRange(3, 8), alpha: cloud.alpha});
            drawCloud(cloud, 0, 0, randRange(60, 120));
        }

        for (i in 0...75) {
            var size = Math.random(3) + 2;
            var colors = [0x66aaff, 0x88ffaa, 0xffaa66, 0xaaff88];
            var c = colors[Std.int(Math.random(colors.length))];
            var p = new Bitmap(Tile.fromColor(c, Std.int(size), Std.int(size)), bgLayer);
            p.x = Math.random(ww);
            p.y = Math.random(wh);
            p.alpha = randRange(0.2, 0.5);
            bgSpiritParticles.push({bmp: p, x: p.x, y: p.y, vy: randRange(-15, -5), alpha: p.alpha, phase: Math.random(Math.PI * 2)});
        }
    }

    function drawMountainLayer(baseY:Float, color:Int, alpha:Float, variation:Float) {
        var ww = engine.worldWidth;
        var wh = engine.worldHeight;
        var g = new h2d.Graphics(bgLayer);
        g.alpha = alpha;
        g.beginFill(color);
        g.moveTo(0, wh);
        g.lineTo(0, baseY);
        var peaks = 24;
        for (i in 0...peaks) {
            var t = i / peaks;
            var x = ww * t;
            var peakHeight = randRange(30, 80) * variation;
            g.lineTo(x, baseY - peakHeight);
            var nextT = (i + 1) / peaks;
            var valleyY = baseY + randRange(10, 30);
            g.lineTo(ww * (t + nextT) * 0.5, valleyY);
        }
        g.lineTo(ww, baseY);
        g.lineTo(ww, wh);
        g.lineTo(0, wh);
        g.endFill();
        g.beginFill(0xffffff, 0.03);
        for (i in 0...8) {
            g.drawCircle(randRange(0, ww), baseY - randRange(20, 60), randRange(40, 80));
        }
        g.endFill();
    }

    function drawCloud(g:h2d.Graphics, x:Float, y:Float, size:Float) {
        g.beginFill(0xffffff, 0.3);
        g.drawCircle(x, y, size);
        g.drawCircle(x + size * 0.6, y - size * 0.2, size * 0.7);
        g.drawCircle(x - size * 0.6, y + size * 0.1, size * 0.6);
        g.drawCircle(x + size * 0.3, y + size * 0.3, size * 0.5);
        g.drawCircle(x - size * 0.3, y - size * 0.2, size * 0.55);
        g.endFill();
        g.beginFill(0xffffff, 0.15);
        g.drawCircle(x, y, size * 1.3);
        g.endFill();
    }

    function updateBackground(dt:Float) {
        var ww = engine.worldWidth;
        var wh = engine.worldHeight;
        for (c in bgClouds) {
            c.x += c.vx * dt;
            if (c.x > ww + 150) c.x = -150;
            c.g.x = c.x;
            c.g.y = c.y + Math.sin(bgTime * 0.5 + c.x * 0.01) * 5;
            c.g.alpha = c.alpha * (0.7 + Math.sin(bgTime * 0.8 + c.x * 0.02) * 0.3);
        }
        for (p in bgSpiritParticles) {
            p.y += p.vy * dt;
            p.phase += dt * 2;
            p.bmp.x = p.x + Math.sin(p.phase) * 10;
            p.bmp.y = p.y;
            p.bmp.alpha = p.alpha * (0.5 + Math.sin(p.phase * 0.7) * 0.5);
            if (p.y < -10) { p.y = wh + 10; p.x = Math.random(ww); }
        }
    }

    // ============================================================
    //  HaxeUI
    // ============================================================
    function initHaxeUI() {
        Screen.instance.root = this;

        // === 顶部状态栏 ===
        var topBar = new VBox();
        topBar.width = width - 290; // 缩短, 给右侧 Tab 按钮留空间
        topBar.paddingTop = 8;
        topBar.paddingLeft = 12;
        topBar.verticalSpacing = 3;

        var nameRow = new HBox();
        nameRow.horizontalSpacing = 8;
        uiRealmLabel = new Label();
        var cult = playerEntity.get(CultivationComp);
        uiRealmLabel.text = playerEntity.name + "  [" + cult.realmName + "]";
        uiRealmLabel.styleString = SX_TITLE;
        uiRealmLabel.width = 200;
        nameRow.addComponent(uiRealmLabel);

        uiRootLabel = new Label();
        uiRootLabel.text = cult.spiritRootName + "·" + cult.spiritRootQualityName;
        uiRootLabel.styleString = "font-size:16px;color:#" + StringTools.hex(cult.getRootColor() & 0xffffff, 6) + ";font-weight:bold;";
        uiRootLabel.width = 130;
        nameRow.addComponent(uiRootLabel);

        uiKillLabel = new Label();
        uiKillLabel.text = "击杀: 0";
        uiKillLabel.styleString = SX_TEXT_HOT;
        uiKillLabel.width = 100;
        nameRow.addComponent(uiKillLabel);
        topBar.addComponent(nameRow);

        // 灵根详情
        var rootDescRow = new HBox();
        rootDescRow.horizontalSpacing = 6;
        uiRootDetail = new Label();
        uiRootDetail.text = "天赋:" + cult.talent + "  气运:" + cult.luck;
        uiRootDetail.styleString = SX_TEXT;
        uiRootDetail.width = 400;
        rootDescRow.addComponent(uiRootDetail);
        topBar.addComponent(rootDescRow);

        // HP/MP/EXP bars
        var hpRow = new HBox();
        hpRow.horizontalSpacing = 6;
        var hpText = new Label(); hpText.text = "气血"; hpText.styleString = "font-size:14px;color:#c8442a;width:35px;font-weight:bold;";
        hpRow.addComponent(hpText);
        uiHpBar = new HorizontalProgress(); uiHpBar.width = 220; uiHpBar.height = 16; uiHpBar.min = 0; uiHpBar.max = cult.maxHp; uiHpBar.pos = cult.hp;
        uiHpBar.styleString = SX_BAR_HP;
        hpRow.addComponent(uiHpBar);
        uiHpNum = new Label(); uiHpNum.text = Std.string(cult.hp) + "/" + Std.string(cult.maxHp); uiHpNum.styleString = "font-size:13px;color:#e8a08c;"; uiHpNum.width = 100;
        hpRow.addComponent(uiHpNum);
        topBar.addComponent(hpRow);

        var mpRow = new HBox();
        mpRow.horizontalSpacing = 6;
        var mpText = new Label(); mpText.text = "灵力"; mpText.styleString = "font-size:14px;color:#4a9ec8;width:35px;font-weight:bold;";
        mpRow.addComponent(mpText);
        uiMpBar = new HorizontalProgress(); uiMpBar.width = 220; uiMpBar.height = 16; uiMpBar.min = 0; uiMpBar.max = cult.maxMp; uiMpBar.pos = cult.mp;
        uiMpBar.styleString = SX_BAR_MP;
        mpRow.addComponent(uiMpBar);
        uiMpNum = new Label(); uiMpNum.text = Std.string(cult.mp) + "/" + Std.string(cult.maxMp); uiMpNum.styleString = "font-size:13px;color:#8acce8;"; uiMpNum.width = 100;
        mpRow.addComponent(uiMpNum);
        topBar.addComponent(mpRow);

        var expRow = new HBox();
        expRow.horizontalSpacing = 6;
        var expText = new Label(); expText.text = "修为"; expText.styleString = "font-size:14px;color:#7ab85a;width:35px;font-weight:bold;";
        expRow.addComponent(expText);
        uiExpBar = new HorizontalProgress(); uiExpBar.width = 220; uiExpBar.height = 12; uiExpBar.min = 0; uiExpBar.max = cult.expToNext; uiExpBar.pos = cult.exp;
        uiExpBar.styleString = SX_BAR_EXP;
        expRow.addComponent(uiExpBar);
        uiExpLabel = new Label(); uiExpLabel.text = "0/100"; uiExpLabel.styleString = "font-size:13px;color:#8acc6a;"; uiExpLabel.width = 100;
        expRow.addComponent(uiExpLabel);
        topBar.addComponent(expRow);

        Screen.instance.addComponent(topBar);

        // === 右侧 Tab: 按钮栏和内容分开为独立 Screen 组件 ===
        // 先添加内容 Label(底层), 再添加按钮栏(顶层), 确保按钮可点击
        uiTabContent = new Label();
        uiTabContent.text = "第1年 第1日\n灵气浓度: 1.0\n修仙者: 6\n宗门: 8";
        uiTabContent.styleString = SX_TEXT;
        uiTabContent.width = 260;
        uiTabContent.height = 400;
        uiTabContent.left = width - 270;
        uiTabContent.top = 34;
        Screen.instance.addComponent(uiTabContent);

        // 按钮栏 — 后添加, 在 z-order 顶层, 确保点击不被遮挡
        rightTabBar = new HBox();
        rightTabBar.horizontalSpacing = 2;
        rightTabBar.left = width - 270;
        rightTabBar.top = 4;
        rightTabBar.width = 260;
        tabWorldBtn = new Button();
        tabWorldBtn.text = "天道";
        tabWorldBtn.width = 80; tabWorldBtn.height = 26;
        tabWorldBtn.styleString = SX_BTN;
        tabWorldBtn.onClick = function(_) {
            #if js Browser.console.log("[TAB] 天道 onClick fired"); #end
            switchRightTab("world");
        };
        #if js tabWorldBtn.registerEvent(MouseEvent.MOUSE_OVER, function(_) { Browser.console.log("[TAB] 天道 mouseover"); }); #end
        #if js tabWorldBtn.registerEvent(MouseEvent.MOUSE_DOWN, function(_) { Browser.console.log("[TAB] 天道 mousedown"); }); #end
        rightTabBar.addComponent(tabWorldBtn);
        tabFactionBtn = new Button();
        tabFactionBtn.text = "宗门";
        tabFactionBtn.width = 80; tabFactionBtn.height = 26;
        tabFactionBtn.styleString = SX_BTN;
        tabFactionBtn.onClick = function(_) {
            #if js Browser.console.log("[TAB] 宗门 onClick fired"); #end
            switchRightTab("faction");
        };
        rightTabBar.addComponent(tabFactionBtn);
        tabChronicleBtn = new Button();
        tabChronicleBtn.text = "编年";
        tabChronicleBtn.width = 80; tabChronicleBtn.height = 26;
        tabChronicleBtn.styleString = SX_BTN;
        tabChronicleBtn.onClick = function(_) {
            #if js Browser.console.log("[TAB] 编年 onClick fired"); #end
            switchRightTab("chronicle");
        };
        rightTabBar.addComponent(tabChronicleBtn);
        Screen.instance.addComponent(rightTabBar);

        #if js Browser.console.log("[TAB] rightTabBar added to Screen, buttons:", tabWorldBtn, tabFactionBtn, tabChronicleBtn); #end

        // === Heaps 原生 Interactive: 覆盖在 Tab 按钮上方, 绕过 HaxeUI 事件系统 ===
        // HaxeUI 事件系统可能无法检测到这些按钮, 用 h2d.Interactive 直接捕获点击
        var tabLabels = ["world", "faction", "chronicle"];
        var tabNames = ["天道", "宗门", "编年"];
        var btnW = 82; // 80 + 2 spacing
        var tabX = width - 270;
        var tabY = 4;
        for (i in 0...3) {
            var inter = new h2d.Interactive(80, 26, this);
            inter.x = tabX + i * btnW;
            inter.y = tabY;
            // Heaps 中后添加的 Interactive 在事件处理中优先级更高, 这些 Interactive 在所有 HaxeUI 组件之后添加
            var tabId = tabLabels[i];
            var tabName = tabNames[i];
            inter.onClick = function(e:hxd.Event) {
                #if js Browser.console.log("[TAB-HEAPS] " + tabName + " clicked at", e.relX, e.relY); #end
                switchRightTab(tabId);
            };
            #if js inter.onOver = function(e:hxd.Event) { Browser.console.log("[TAB-HEAPS] " + tabName + " mouseover"); }; #end
            tabInteractives.push(inter);
        }
        #if js Browser.console.log("[TAB-HEAPS] 3 Interactive objects created at x:", tabX, "y:", tabY); #end

        // 初始化 Tab 状态
        switchRightTab("world");

        // === 底部技能栏 ===
        var skillContainer = new VBox();
        skillContainer.horizontalAlign = "center";
        skillContainer.width = width;
        skillContainer.paddingBottom = 4;

        var skillBar1 = new HBox();
        skillBar1.horizontalAlign = "center";
        skillBar1.horizontalSpacing = 4;
        for (i in 0...5) {
            var s = skillDefs[i];
            var btn = createSkillButton(s);
            uiSkillButtons.push(btn);
            skillBar1.addComponent(btn);
        }
        skillContainer.addComponent(skillBar1);

        var skillBar2 = new HBox();
        skillBar2.horizontalAlign = "center";
        skillBar2.horizontalSpacing = 4;
        for (i in 5...10) {
            var s = skillDefs[i];
            var btn = createSkillButton(s);
            uiSkillButtons.push(btn);
            skillBar2.addComponent(btn);
        }
        skillContainer.addComponent(skillBar2);

        Screen.instance.addComponent(skillContainer);

        // === 左侧阵法栏 ===
        var formationBar = new VBox();
        formationBar.verticalSpacing = 3;
        formationBar.paddingLeft = 8;
        formationBar.paddingTop = 100;
        formationBar.left = 4;
        formationBar.top = 100;

        var fmtTitle = new Label(); fmtTitle.text = "-- 阵法 --"; fmtTitle.styleString = SX_SUBTITLE;
        formationBar.addComponent(fmtTitle);

        for (f in formationDefs) {
            var btn = new Button();
            btn.text = f.key + " " + f.name;
            btn.width = 84; btn.height = 34;
            btn.styleString = SX_BTN;
            var fid = f.id;
            btn.onClick = function(_) { castFormation(fid); };
            uiFormationButtons.push(btn);
            formationBar.addComponent(btn);
        }
        Screen.instance.addComponent(formationBar);

        // === 时间控制按钮(左侧, 阵法栏下方) ===
        var speedTitle = new Label(); speedTitle.text = "-- 时间 --"; speedTitle.styleString = SX_SUBTITLE;
        speedTitle.left = 12;
        speedTitle.top = 170 + 20 + 6 * 37 + 8;  // 阵法栏paddingTop(100)+title(20)+6行按钮+间距+8
        Screen.instance.addComponent(speedTitle);

        var speedBar = new VBox();
        speedBar.verticalSpacing = 3;
        speedBar.left = 12;
        speedBar.top = 170 + 20 + 6 * 37 + 8 + 20;
        var speedConfigs = [
            {label: "暂停", scale: 0.0},
            {label: "1x", scale: 1.0},
            {label: "2x", scale: 2.0},
            {label: "4x", scale: 4.0}
        ];
        for (cfg in speedConfigs) {
            var btn = new Button();
            btn.text = cfg.label;
            btn.width = 84; btn.height = 30;
            btn.styleString = SX_BTN;
            var scale = cfg.scale;
            btn.onClick = function(_) { setTimeScale(scale); };
            uiSpeedButtons.push(btn);
            speedBar.addComponent(btn);
        }
        Screen.instance.addComponent(speedBar);

        // === 当前世界事件横幅(顶部中央, 醒目) ===
        uiActiveEvent = new Label();
        uiActiveEvent.text = "";
        uiActiveEvent.styleString = "font-size:16px;color:#ff8866;font-weight:bold;background-color:#1a0808ee;border:2px solid #c8442a;border-radius:4px;padding:4px;text-align:center;";
        uiActiveEvent.left = width / 2 - 180;
        uiActiveEvent.top = 40;
        uiActiveEvent.width = 360;
        uiActiveEvent.height = 24;
        Screen.instance.addComponent(uiActiveEvent);

        // === 物理状态/天气/昼夜 信息条 ===
        uiStatusInfo = new Label();
        uiStatusInfo.text = "";
        uiStatusInfo.styleString = "font-size:14px;color:#aaccff;background-color:#0a0a1aee;border:1px solid #336699;border-radius:4px;padding:4px 8px;";
        uiStatusInfo.left = 8;
        uiStatusInfo.top = height - 180;
        uiStatusInfo.width = 420;
        uiStatusInfo.height = 20;
        uiStatusInfo.visible = false;
        Screen.instance.addComponent(uiStatusInfo);

        // === NPC 详情浮窗(点击 NPC 弹出, 初始隐藏) ===
        npcDetailPanel = new VBox();
        npcDetailPanel.verticalSpacing = 4;
        npcDetailPanel.left = 80;
        npcDetailPanel.top = 80;
        npcDetailPanel.width = 320;
        npcDetailPanel.styleString = SX_PANEL;
        npcDetailPanel.hidden = true;

        var detailHeader = new HBox();
        detailHeader.horizontalSpacing = 8;
        var detailTitle = new Label();
        detailTitle.text = "修士详情";
        detailTitle.styleString = SX_TITLE;
        detailTitle.width = 240;
        detailHeader.addComponent(detailTitle);
        npcDetailCloseBtn = new Button();
        npcDetailCloseBtn.text = "×";
        npcDetailCloseBtn.width = 30; npcDetailCloseBtn.height = 24;
        npcDetailCloseBtn.styleString = SX_BTN_DANGER;
        npcDetailCloseBtn.onClick = function(_) { closeNpcDetail(); };
        detailHeader.addComponent(npcDetailCloseBtn);
        npcDetailPanel.addComponent(detailHeader);

        npcDetailLabel = new Label();
        npcDetailLabel.text = "";
        npcDetailLabel.styleString = SX_TEXT;
        npcDetailLabel.width = 300;
        npcDetailLabel.height = 360;
        npcDetailPanel.addComponent(npcDetailLabel);

        Screen.instance.addComponent(npcDetailPanel);

        // === 提示 ===
        uiInfo = new Label();
        uiInfo.text = "WASD/右键点击 移动 | 空格普攻 | 左键点NPC查看详情 | Q-P法术 | 1-5阵法\nF1暂停 | F2=1x | F3=2x | F4=4x 时间加速";
        uiInfo.styleString = SX_TEXT_DIM;
        uiInfo.left = 10;
        uiInfo.top = height - 50;
        uiInfo.width = 380;
        Screen.instance.addComponent(uiInfo);

        // 初始化按钮高亮
        updateSpeedButtonHighlight();

        // === 小地图画布(右下角, Heaps 原生 Graphics 不受镜头影响) ===
        var minimapTitle = new Label();
        minimapTitle.text = "▼ 天下堪舆图";
        minimapTitle.styleString = "font-size:14px;color:#d4a04c;font-weight:bold;background:transparent;border:none;text-align:right;";
        minimapTitle.left = width - 220;
        minimapTitle.top = height - 242;
        minimapTitle.width = 200;
        Screen.instance.addComponent(minimapTitle);

        minimapGraphics = new h2d.Graphics(this);
        minimapBorder = new h2d.Graphics(this);
    }

    function createSkillButton(s:{key:String, name:String, skill:String, cd:Float, mpCost:Int}):Button {
        var btn = new Button();
        btn.text = s.name;
        btn.width = 84; btn.height = 42;
        btn.styleString = SX_BTN;
        var skillId = s.skill;
        var mpCost = s.mpCost;
        var cdTime = s.cd;
        btn.onClick = function(_) { castSpell(skillId, mpCost, cdTime); };
        return btn;
    }

    // ============================================================
    //  法术目标选择系统
    //  按键/点击技能按钮 -> 进入瞄准模式 -> 左键选择释放位置 / Tab锁定最近敌人
    // ============================================================

    public function castSpell(skillId:String, mpCost:Int, cdTime:Float) {
        var cdKey = skillId;
        if (cooldowns.exists(cdKey) && cooldowns[cdKey] > 0) {
            flashInfo("技能冷却中...");
            return;
        }

        var cult = playerEntity.get(CultivationComp);
        if (cult.mp < mpCost) {
            flashInfo("灵力不足!");
            return;
        }

        // 进入瞄准模式
        pendingSpell = skillId;
        pendingSpellMpCost = mpCost;
        pendingSpellCd = cdTime;
        targetingTimer = targetingMaxTime;
        targetingIndicator.visible = true;
        flashInfo("选择释放位置 (左键确认 / Tab锁定最近敌人 / 右键取消)");
    }

    // 取消瞄准
    function cancelTargeting() {
        pendingSpell = null;
        targetingTimer = 0;
        targetingIndicator.visible = false;
    }

    // 更新瞄准指示器: 在鼠标位置画法术范围圈
    function updateTargetingIndicator() {
        if (pendingSpell == null) return;
        var spellType = getSpellType(pendingSpell);
        var spellRange = getSpellRange(pendingSpell);

        var pos = playerEntity.get(PositionComp);
        // self 类型法术: 指示器画在玩家位置
        var cx = (spellType == "self") ? pos.x : camMouseX;
        var cy = (spellType == "self") ? pos.y : camMouseY;

        // 法术颜色
        var color = switch (pendingSpell) {
            case "fireball": 0xff6600;
            case "thunder": 0x66aaff;
            case "ice": 0x88ddff;
            case "swordqi": 0xeeeeff;
            case "thunderstorm": 0xaa66ff;
            case "pocket": 0xaa44ff;
            case "lotus": 0xffdd00;
            case "bigdipper": 0xddddaa;
            case "clone": 0xaaaaaa;
            case "voidshift": 0x66ffcc;
            default: 0xffffff;
        };

        targetingIndicator.clear();
        targetingIndicator.x = cx;
        targetingIndicator.y = cy;

        // 外圈: 法术范围
        targetingIndicator.lineStyle(2, color, 0.8);
        drawCircleOn(targetingIndicator, 0, 0, spellRange);
        // 内圈填充(半透明)
        targetingIndicator.beginFill(color, 0.1);
        drawCircleOn(targetingIndicator, 0, 0, spellRange);
        targetingIndicator.endFill();

        // 中心十字准星
        targetingIndicator.lineStyle(2, color, 1.0);
        targetingIndicator.moveTo(-10, 0);
        targetingIndicator.lineTo(10, 0);
        targetingIndicator.moveTo(0, -10);
        targetingIndicator.lineTo(0, 10);

        // 倒计时弧线(指示剩余瞄准时间)
        var ratio = targetingTimer / targetingMaxTime;
        var arcSteps = 30;
        targetingIndicator.lineStyle(3, color, 0.5);
        targetingIndicator.moveTo(spellRange + 8, 0);
        for (i in 0...arcSteps + 1) {
            var a = (i / arcSteps) * Math.PI * 2 * ratio;
            var px = Math.cos(a) * (spellRange + 8);
            var py = Math.sin(a) * (spellRange + 8);
            targetingIndicator.lineTo(px, py);
        }
    }

    // 在 Graphics 上画圆(Heaps 的 drawCircle 不一定可用, 手动画)
    function drawCircleOn(g:h2d.Graphics, cx:Float, cy:Float, r:Float) {
        var steps = 32;
        g.moveTo(cx + r, cy);
        for (i in 1...steps + 1) {
            var a = (i / steps) * Math.PI * 2;
            g.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
        }
    }

    // 确认释放法术到指定坐标
    function executeSpellCast(targetX:Float, targetY:Float) {
        if (pendingSpell == null) return;

        var skillId = pendingSpell;
        var mpCost = pendingSpellMpCost;
        var cdTime = pendingSpellCd;

        // 再次检查冷却和灵力(瞄准期间可能状态变化)
        var cult = playerEntity.get(CultivationComp);
        if (cult.mp < mpCost) {
            flashInfo("灵力不足!");
            cancelTargeting();
            return;
        }
        if (cooldowns.exists(skillId) && cooldowns[skillId] > 0) {
            flashInfo("技能冷却中...");
            cancelTargeting();
            return;
        }

        cult.mp -= mpCost;
        cooldowns[skillId] = cdTime;

        var pos = playerEntity.get(PositionComp);
        var spellType = getSpellType(skillId);
        var spellRange = getSpellRange(skillId);

        // 确定法术释放的目标坐标
        var aimX:Float = targetX;
        var aimY:Float = targetY;
        if (spellType == "self") {
            // 以自身为中心的法术, 忽略鼠标位置
            aimX = pos.x;
            aimY = pos.y;
        }

        // 法术特效在渲染层执行
        switch (skillId) {
            case "fireball": SpellSystem.castFireball(pos.x, pos.y, aimX, aimY, fxLayer, this);
            case "thunder": SpellSystem.castThunder(pos.x, pos.y, aimX, aimY, fxLayer, this);
            case "ice": SpellSystem.castIce(pos.x, pos.y, aimX, aimY, fxLayer, this);
            case "swordqi": SpellSystem.castSwordQi(pos.x, pos.y, aimX, aimY, fxLayer, this);
            case "thunderstorm": SpellSystem.castThunderstorm(aimX, aimY, fxLayer, this);
            case "pocket": SpellSystem.castPocketDimension(pos.x, pos.y, aimX, aimY, fxLayer, this);
            case "lotus": SpellSystem.castLotusBloom(pos.x, pos.y, aimX, aimY, fxLayer, this);
            case "bigdipper": SpellSystem.castBigDipper(pos.x, pos.y, aimX, aimY, fxLayer, this);
            case "clone": SpellSystem.castShadowClone(pos.x, pos.y, aimX, aimY, fxLayer, this);
            case "voidshift": SpellSystem.castVoidShift(pos.x, pos.y, aimX, aimY, fxLayer, this);
        }

        // 对法术范围内的敌人造成伤害
        // - self 类型: 以玩家为中心
        // - aoe/projectile/blink 类型: 以目标点为中心
        var dmgCenterX = (spellType == "self") ? pos.x : aimX;
        var dmgCenterY = (spellType == "self") ? pos.y : aimY;

        var spellDmg = getSpellBaseDamage(skillId);
        for (e in engine.entities) {
            if (!e.alive || e.isPlayer) continue;
            var ePos = e.get(PositionComp);
            var eCult = e.get(CultivationComp);
            if (ePos == null || eCult == null) continue;
            var dx = ePos.x - dmgCenterX;
            var dy = ePos.y - dmgCenterY;
            if (dx * dx + dy * dy < spellRange * spellRange) {
                var mult = cult.getSpellMultiplier(skillId);
                var dmg = Math.round(spellDmg * mult);
                eCult.hp -= dmg;
                spawnDamageNumber(ePos.x, ePos.y - 20, dmg, 0xffdd44);

                // 击退(从释放中心向外)
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist < 1) dist = 1;
                var knockForce = 200;
                ePos.vx += (dx / dist) * knockForce;
                ePos.vy += (dy / dist) * knockForce;

                if (eCult.hp <= 0) {
                    e.alive = false;
                    killCount++;
                    spawnDeathEffect(ePos.x, ePos.y);
                    cult.exp += 20 + eCult.realmIndex * 15;

                    // 突破检查
                    if (cult.exp >= cult.expToNext) {
                        doPlayerBreakthrough();
                    }
                }
            }
        }

        // 退出瞄准模式
        cancelTargeting();
    }

    // 查找最近的敌人, 返回其位置
    function findNearestEnemy():{x:Float, y:Float} {
        var pos = playerEntity.get(PositionComp);
        if (pos == null) return null;

        var nearestDist = Math.POSITIVE_INFINITY;
        var nearestX:Float = 0;
        var nearestY:Float = 0;
        var found = false;

        for (e in engine.entities) {
            if (!e.alive || e.isPlayer) continue;
            var ePos = e.get(PositionComp);
            if (ePos == null) continue;
            var dx = ePos.x - pos.x;
            var dy = ePos.y - pos.y;
            var dist = dx * dx + dy * dy;
            if (dist < nearestDist) {
                nearestDist = dist;
                nearestX = ePos.x;
                nearestY = ePos.y;
                found = true;
            }
        }

        if (found) return {x: nearestX, y: nearestY};
        return null;
    }

    // ============================================================
    //  普攻: 空格键触发, 无灵力消耗, 短冷却
    //  朝面向方向发出一道剑气斩击, 对近距离敌人造成伤害
    // ============================================================
    public function normalAttack() {
        var cdKey = "normal";
        if (cooldowns.exists(cdKey) && cooldowns[cdKey] > 0) return;
        cooldowns[cdKey] = 0.4; // 0.4 秒冷却

        var pos = playerEntity.get(PositionComp);
        var cult = playerEntity.get(CultivationComp);
        if (pos == null || cult == null) return;

        // 朝鼠标方向攻击
        var dx = camMouseX - pos.x;
        var dy = camMouseY - pos.y;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 1) dist = 1;
        var dirX = dx / dist;
        var dirY = dy / dist;

        // 普攻特效: 短剑气斩
        var slashRange = 120;
        var slashX = pos.x + dirX * slashRange * 0.5;
        var slashY = pos.y + dirY * slashRange * 0.5;
        var slashAngle = Math.atan2(dirY, dirX);

        // 绘制剑气弧线
        var slash = new h2d.Graphics(fxLayer);
        slash.x = slashX;
        slash.y = slashY;
        slash.rotation = slashAngle;
        slash.alpha = 0.8;
        slash.lineStyle(3, 0xffffff, 0.9);
        slash.moveTo(-40, -15);
        slash.lineTo(40, 0);
        slash.lineTo(-40, 15);
        slash.lineTo(-30, 0);
        slash.endFill();
        slash.lineStyle(6, 0xaaddff, 0.3);
        slash.moveTo(-40, -15);
        slash.lineTo(40, 0);
        slash.lineTo(-40, 15);
        slash.endFill();

        haxe.Timer.delay(function() {
            if (slash.parent != null) slash.remove();
        }, 150);

        // 少量粒子
        for (i in 0...8) {
            var p = getParticle();
            p.x = slashX + randRange(-20, 20);
            p.y = slashY + randRange(-20, 20);
            p.vx = dirX * randRange(80, 200) + randRange(-40, 40);
            p.vy = dirY * randRange(80, 200) + randRange(-40, 40);
            p.life = randRange(0.15, 0.3);
            p.maxLife = p.life;
            p.size = randRange(2, 5);
            p.color = 0xffffff;
            p.type = Spark;
            p.glow = true;
            p.fade = true;
            p.drag = 0.9;
        }

        // 对前方扇形范围内的敌人造成伤害
        var baseDmg = Std.int(cult.attackPower * 0.8);
        var hitRange = slashRange;
        for (e in engine.entities) {
            if (!e.alive || e.isPlayer) continue;
            var ePos = e.get(PositionComp);
            var eCult = e.get(CultivationComp);
            if (ePos == null || eCult == null) continue;

            var ex = ePos.x - pos.x;
            var ey = ePos.y - pos.y;
            var eDist = Math.sqrt(ex * ex + ey * ey);
            if (eDist > hitRange) continue;

            // 检查角度: 前方 ±60 度
            var dot = (ex * dirX + ey * dirY) / (eDist + 0.01);
            if (dot < 0.5) continue; // cos(60°) ≈ 0.5

            var mult = cult.getSpellMultiplier("normal");
            var dmg = Math.round(baseDmg * mult);
            eCult.hp -= dmg;

            // 击退
            ePos.vx += dirX * 150;
            ePos.vy += dirY * 150;

            spawnDamageNumber(ePos.x, ePos.y - 20, dmg, 0xffffff);

            if (eCult.hp <= 0) {
                e.alive = false;
                killCount++;
                spawnDeathEffect(ePos.x, ePos.y);
                cult.exp += 10 + eCult.realmIndex * 8;
                if (cult.exp >= cult.expToNext) {
                    doPlayerBreakthrough();
                }
            }
        }
    }

    function getSpellBaseDamage(spellId:String):Int {
        return switch (spellId) {
            case "fireball": 60;
            case "thunder": 80;
            case "ice": 50;
            case "swordqi": 50;
            case "thunderstorm": 100;
            case "pocket": 40;
            case "lotus": 25;
            case "bigdipper": 50;
            case "clone": 60;
            case "voidshift": 70;
            default: 50;
        };
    }

    // 法术伤害范围(半径, 像素) - 用于目标选择指示器和伤害判定
    function getSpellRange(spellId:String):Float {
        return switch (spellId) {
            case "fireball": 80;     // 火球爆炸范围
            case "thunder": 60;      // 雷击范围
            case "ice": 70;          // 冰冻扩散范围
            case "swordqi": 200;     // 剑气发射范围(以玩家为中心)
            case "thunderstorm": 250;// 雷暴大范围
            case "pocket": 150;      // 袖里乾坤吸入范围
            case "lotus": 200;       // 莲花绽放范围
            case "bigdipper": 200;   // 北斗坠落范围
            case "clone": 100;       // 分影术范围
            case "voidshift": 80;    // 瞬移落点范围
            default: 100;
        };
    }

    // 法术类型: "projectile"=投射物(需要目标位置), "aoe"=范围伤害(以鼠标为中心), "self"=以自身为中心
    function getSpellType(spellId:String):String {
        return switch (spellId) {
            case "fireball": "projectile";  // 火球飞向目标点
            case "thunder": "aoe";          // 雷直接在目标点降下
            case "ice": "projectile";       // 冰晶飞向目标点
            case "swordqi": "self";         // 以自身为中心放射
            case "thunderstorm": "aoe";     // 以目标点为中心大范围雷暴
            case "pocket": "self";          // 以自身为中心吸入
            case "lotus": "self";           // 以自身为中心绽放
            case "bigdipper": "aoe";        // 以目标点为中心北斗坠落
            case "clone": "self";           // 以自身为中心分身
            case "voidshift": "blink";      // 瞬移到目标点
            default: "aoe";
        };
    }

    function doPlayerBreakthrough() {
        var cult = playerEntity.get(CultivationComp);
        while (cult.exp >= cult.expToNext && cult.realmIndex < WorldEngine.realmList.length - 1) {
            cult.realmIndex++;
            cult.realmName = WorldEngine.realmList[cult.realmIndex].name;
            cult.exp -= cult.expToNext;
            cult.expToNext = Std.int(cult.expToNext * 1.5);
            cult.maxHp = Std.int(cult.maxHp * 1.3 * cult.talent);
            cult.hp = cult.maxHp;
            cult.maxMp = Std.int(cult.maxMp * 1.3 * cult.talent);
            cult.mp = cult.maxMp;
            cult.attackPower = Std.int(cult.attackPower * 1.25 * cult.talent);
            cult.lifespan = WorldEngine.realmList[cult.realmIndex].lifespan;

            if (cult.spiritRootQuality < 4 && Math.random() < 0.15) {
                cult.spiritRootQuality++;
                var qNames = ["凡品", "良品", "上品", "极品", "天灵根"];
                cult.spiritRootQualityName = qNames[cult.spiritRootQuality];
            }

            spawnBreakthroughEffect();
            engine.emitEvent(new WorldEvent(playerEntity.id, -1, "Breakthrough",
                playerEntity.name + " 突破至 " + cult.realmName + "!"
            ));
        }
    }

    function spawnBreakthroughEffect() {
        breakthroughFlash = 1.0;
        var pos = playerEntity.get(PositionComp);
        SpellSystem.spawnRing(pos.x, pos.y, 0xFFD700, 200, 0.8, fxLayer, this);
        SpellSystem.spawnRing(pos.x, pos.y, 0xffffff, 150, 0.6, fxLayer, this);

        for (i in 0...50) {
            var p = getParticle();
            var angle = Math.random(Math.PI * 2);
            var speed = randRange(100, 300);
            p.x = pos.x; p.y = pos.y;
            p.vx = Math.cos(angle) * speed; p.vy = Math.sin(angle) * speed;
            p.life = randRange(0.5, 1.2); p.maxLife = p.life;
            p.size = randRange(4, 10);
            p.color = [0xFFD700, 0xffaa00, 0xffffff, 0xff6600][Std.int(Math.random(4))];
            p.type = Spark; p.glow = true; p.fade = true; p.gravity = 20; p.drag = 0.95;
        }

        for (i in 0...20) {
            var p = getParticle();
            p.x = pos.x + randRange(-15, 15); p.y = pos.y;
            p.vx = randRange(-5, 5); p.vy = randRange(-200, -100);
            p.life = randRange(0.6, 1.0); p.maxLife = p.life;
            p.size = randRange(3, 8); p.color = 0xFFD700;
            p.type = Glowing; p.glow = true; p.fade = true; p.drag = 0.98;
        }
    }

    public function castFormation(id:String) {
        if (activeFormation != null) { activeFormation.destroy(); activeFormation = null; }
        activeFormation = new Formation(id, formationLayer);
        var pos = playerEntity.get(PositionComp);
        activeFormation.x = pos.x;
        activeFormation.y = pos.y;
    }

    function flashInfo(msg:String) { uiInfo.text = msg; }

    // === 时间控制 ===
    public function setTimeScale(scale:Float) {
        timeScale = scale;
        paused = (scale <= 0);
        updateSpeedButtonHighlight();
        if (paused) {
            flashInfo("世界已暂停");
        } else {
            flashInfo("时间流速: " + scale + "x");
        }
    }

    function updateSpeedButtonHighlight() {
        for (i in 0...uiSpeedButtons.length) {
            var btn = uiSpeedButtons[i];
            var scales = [0.0, 1.0, 2.0, 4.0];
            if (scales[i] == timeScale) {
                btn.styleString = SX_BTN_HOT;
            } else {
                btn.styleString = SX_BTN;
            }
        }
    }

    // === 可折叠面板标题构造器 ===
    // 返回一个带 ▼/▶ 切换的按钮, 点击切换 contents 的显隐
    function makeCollapsibleTitle(titleText:String, contents:Array<Component>, width:Int = 260):Button {
        var btn = new Button();
        btn.text = "▼ " + titleText;
        btn.styleString = "font-size:13px;color:#d4a04c;font-weight:bold;background:transparent;border:none;text-align:left;padding:2px;";
        btn.width = width;
        btn.height = 22;
        btn.onClick = function(_) {
            var collapsed = btn.text.charAt(0) == "▶";
            btn.text = collapsed ? "▼ " + titleText : "▶ " + titleText;
            for (c in contents) c.hidden = collapsed ? false : true;
        };
        return btn;
    }

    // === 检测鼠标是否在 HaxeUI 组件上 ===
    // 用屏幕坐标范围判断, 避免 HaxeUI 内部 API 兼容问题
    function isMouseOverUI():Bool {
        var w = Window.getInstance();
        var mx = w.mouseX;
        var my = w.mouseY;
        var sw = width;
        var sh = height;

        // 顶部状态栏 (y < 135)
        if (my < 135) return true;
        // 右侧 Tab 面板 (x > sw - 285)
        if (mx > sw - 285) return true;
        // 底部技能栏 + 提示 (y > sh - 95)
        if (my > sh - 95) return true;
        // 左侧阵法栏 (x < 135, y 在中间区域)
        if (mx < 135 && my > 135 && my < sh - 95) return true;
        // NPC 详情浮窗 (如果可见)
        if (!npcDetailPanel.hidden) {
            if (mx >= npcDetailPanel.left && mx <= npcDetailPanel.left + npcDetailPanel.width &&
                my >= npcDetailPanel.top && my <= npcDetailPanel.top + npcDetailPanel.height) {
                return true;
            }
        }
        return false;
    }

    // === 右侧 Tab 切换 ===
    // 单 Label 方案: 只改 .text 和样式, 不增删组件
    function switchRightTab(tab:String) {
        #if js Browser.console.log("[TAB] switchRightTab called with:", tab, "| currentRightTab was:", currentRightTab); #end
        currentRightTab = tab;

        // 切换内容文本
        if (tab == "faction") {
            uiTabContent.text = factionTabText;
            tabFactionBtn.styleString = SX_BTN_HOT;
            tabWorldBtn.styleString = SX_BTN;
            tabChronicleBtn.styleString = SX_BTN;
        } else if (tab == "chronicle") {
            uiTabContent.text = chronicleTabText;
            tabChronicleBtn.styleString = SX_BTN_HOT;
            tabWorldBtn.styleString = SX_BTN;
            tabFactionBtn.styleString = SX_BTN;
        } else {
            uiTabContent.text = worldTabText;
            tabWorldBtn.styleString = SX_BTN_HOT;
            tabFactionBtn.styleString = SX_BTN;
            tabChronicleBtn.styleString = SX_BTN;
        }
    }

    // === NPC 详情浮窗 ===
    // 在世界坐标 (wx, wy) 附近查找 NPC, 半径 r 内最近者
    function findNpcAt(wx:Float, wy:Float, r:Float = 28):Entity {
        var nearest:Entity = null;
        var nearestDist = r * r;
        for (e in engine.entities) {
            if (!e.alive) continue;
            if (e.isPlayer) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;
            var dx = pos.x - wx;
            var dy = pos.y - wy;
            var d = dx * dx + dy * dy;
            if (d < nearestDist) {
                nearestDist = d;
                nearest = e;
            }
        }
        return nearest;
    }

    function showNpcDetail(e:Entity) {
        selectedNpcEntity = e;
        npcDetailPanel.hidden = false;
        updateNpcDetail();
    }

    function closeNpcDetail() {
        npcDetailPanel.hidden = true;
        selectedNpcEntity = null;
    }

    function updateNpcDetail() {
        if (selectedNpcEntity == null || !selectedNpcEntity.alive) {
            closeNpcDetail();
            return;
        }
        var e = selectedNpcEntity;
        var cult = e.get(CultivationComp);
        var pos = e.get(PositionComp);
        var fac = e.get(FactionComp);
        var karma = e.get(KarmaComp);
        var inv = e.get(InventoryComp);
        var social = e.get(SocialComp);
        var heritage = e.get(HeritageComp);
        var crafting = e.get(CraftingComp);
        var npcState = e.get(NPCStateComp);

        var text = "";
        text += "姓名: " + e.name + "\n";
        if (npcState != null) {
            var typeDesc = switch (npcState.npcType) {
                case "moxiu": "魔修";
                case "yaoshou": "妖兽";
                case "mojiang": "魔将";
                case "xiexian": "邪仙";
                case "cultivator": "正道修士";
                default: npcState.npcType;
            };
            text += "身份: " + typeDesc + "\n";
        }
        if (cult != null) {
            text += "境界: " + cult.realmName + " (修为 " + Std.int(cult.exp) + "/" + Std.int(cult.expToNext) + ")\n";
            text += "灵根: " + cult.spiritRootName + "·" + cult.spiritRootQualityName + "\n";
            text += "气血: " + Std.int(cult.hp) + "/" + Std.int(cult.maxHp) + "\n";
            text += "灵力: " + Std.int(cult.mp) + "/" + Std.int(cult.maxMp) + "\n";
            text += "攻力: " + Std.int(cult.attackPower) + "  战力: " + Std.int(cult.getCombatPower()) + "\n";
            text += "天赋: " + (Math.round(cult.talent * 100) / 100) + "  气运: " + (Math.round(cult.luck * 100) / 100) + "\n";
            text += "年龄: " + Std.int(cult.age) + "/" + Std.int(cult.lifespan) + "岁\n";
        }
        if (fac != null) {
            text += "势力: " + (fac.factionName != "" ? fac.factionName : "散修") + "\n";
        }
        if (heritage != null) {
            text += "血脉: " + heritage.bloodline + "(第" + heritage.generation + "代)\n";
            if (heritage.parentIds.length > 0) {
                text += "出身: 道侣所生\n";
            }
            if (heritage.childrenIds.length > 0) {
                text += "子嗣: " + heritage.childrenIds.length + "人\n";
            }
        }
        if (social != null) {
            var relParts:Array<String> = [];
            if (social.spouseId != -1) {
                var spouse = engine.getEntity(social.spouseId);
                if (spouse != null) relParts.push("道侣:" + spouse.name);
            }
            if (social.masterId != -1) {
                var master = engine.getEntity(social.masterId);
                if (master != null) relParts.push("师父:" + master.name);
            }
            if (social.disciples.length > 0) relParts.push("弟子:" + social.disciples.length + "人");
            if (social.allies.length > 0) relParts.push("盟友:" + social.allies.length + "人");
            if (social.enemies.length > 0) relParts.push("仇敌:" + social.enemies.length + "人");
            if (relParts.length > 0) text += "关系: " + relParts.join("  ") + "\n";
        }
        if (karma != null) {
            text += "业障: " + karma.sinValue + "  功德: " + karma.meritValue + "\n";
            if (karma.titles.length > 0) {
                text += "称号: " + karma.titles.join(", ") + "\n";
            }
        }
        if (inv != null) {
            text += "灵石: " + inv.spiritStones + "  灵草: " + inv.herbs + "  材料: " + inv.materials + "\n";
            if (inv.artifacts.length > 0) {
                text += "法器: " + inv.artifacts.join(", ") + "\n";
            }
            var pillNames:Array<String> = [];
            for (pName in inv.pills.keys()) pillNames.push(pName + "x" + inv.pills[pName]);
            if (pillNames.length > 0) text += "丹药: " + pillNames.join(", ") + "\n";
        }
        if (crafting != null) {
            if (crafting.alchemySkill > 0 || crafting.smithingSkill > 0) {
                text += "炼丹:" + Std.int(crafting.alchemySkill) + " 炼器:" + Std.int(crafting.smithingSkill) + "\n";
            }
        }
        if (pos != null) {
            text += "坐标: (" + Std.int(pos.x) + ", " + Std.int(pos.y) + ")\n";
        }
        npcDetailLabel.text = text;
    }

    // === 渲染世界元素: 灵草资源点 + 秘境 ===
    function renderWorldElements() {
        // --- 灵草资源点 ---
        // 同步图形对象数量
        while (herbNodeGraphics.length < engine.spiritHerbNodes.length) {
            var g = new h2d.Graphics(formationLayer);
            herbNodeGraphics.push(g);
        }
        while (herbNodeGraphics.length > engine.spiritHerbNodes.length) {
            var g = herbNodeGraphics.pop();
            if (g.parent != null) g.remove();
        }
        for (i in 0...engine.spiritHerbNodes.length) {
            var node = engine.spiritHerbNodes[i];
            var g = herbNodeGraphics[i];
            g.clear();
            if (!node.alive || node.herbs < 0.5) {
                g.visible = false;
                continue;
            }
            g.visible = true;
            g.x = node.x;
            g.y = node.y;
            // 灵草簇: 鲜艳绿色 + 脉动光晕
            var ratio = node.herbs / node.maxHerbs;
            var size = 6 + ratio * 8;
            var pulse = 1.0 + Math.sin(elapsed * 3 + i * 0.5) * 0.15;
            // 外层光晕(大范围柔光)
            g.beginFill(0x00ff44, 0.15);
            drawCircleOn(g, 0, 0, (size + 12) * pulse);
            g.endFill();
            // 中层光晕
            g.beginFill(0x22cc44, 0.3);
            drawCircleOn(g, 0, 0, (size + 5) * pulse);
            g.endFill();
            // 主体(鲜艳翠绿)
            g.beginFill(0x44ff66, 0.85);
            drawCircleOn(g, 0, 0, size);
            g.endFill();
            // 中心高亮(发光感)
            g.beginFill(0xccffcc, 1.0);
            drawCircleOn(g, 0, 0, size * 0.35);
            g.endFill();
        }

        // --- 秘境 ---
        while (secretRealmGraphics.length < engine.secretRealms.length) {
            var g = new h2d.Graphics(formationLayer);
            secretRealmGraphics.push(g);
        }
        while (secretRealmGraphics.length > engine.secretRealms.length) {
            var g = secretRealmGraphics.pop();
            if (g.parent != null) g.remove();
        }
        for (i in 0...engine.secretRealms.length) {
            var realm = engine.secretRealms[i];
            var g = secretRealmGraphics[i];
            g.clear();
            if (!realm.active) {
                g.visible = false;
                continue;
            }
            g.visible = true;
            g.x = realm.x;
            g.y = realm.y;
            // 秘境光环: 旋转的金色光圈
            var phase = elapsed * 2;
            var color = switch (realm.heritageType) {
                case "exp": 0xffaa44;
                case "artifact": 0x44aaff;
                case "root": 0xff44ff;
                default: 0xffaa44;
            };
            g.lineStyle(3, color, 0.8);
            drawCircleOn(g, 0, 0, realm.radius);
            g.lineStyle(1, color, 0.4);
            drawCircleOn(g, 0, 0, realm.radius + 10 + Math.sin(phase) * 5);
            // 中心符文
            g.beginFill(color, 0.3);
            drawCircleOn(g, 0, 0, realm.radius * 0.5);
            g.endFill();
            // 旋转的符文线
            for (k in 0...6) {
                var a = phase + k * Math.PI / 3;
                g.lineStyle(2, color, 0.6);
                g.moveTo(Math.cos(a) * realm.radius * 0.6, Math.sin(a) * realm.radius * 0.6);
                g.lineTo(Math.cos(a) * realm.radius * 0.9, Math.sin(a) * realm.radius * 0.9);
            }
        }

        // === 渲染小地图 ===
        renderMinimap();
    }

    // === 小地图渲染: 世界全貌缩略 ===
    function renderMinimap() {
        var g = minimapGraphics;
        if (g == null) return;
        g.clear();
        var mapSize = 200;
        var mapX = width - mapSize - 20;
        var mapY = height - mapSize - 20;
        g.x = mapX;
        g.y = mapY;

        var sx = mapSize / engine.worldWidth;
        var sy = mapSize / engine.worldHeight;

        // 背景 + 边框(卷轴风)
        g.beginFill(0x0a0a14, 0.88);
        g.drawRect(0, 0, mapSize, mapSize);
        g.endFill();
        g.lineStyle(2, 0x8b6914, 1);
        g.drawRect(0, 0, mapSize, mapSize);

        // 灵脉(金色光晕)
        for (v in engine.spiritVeins) {
            var vx = v.x * sx;
            var vy = v.y * sy;
            g.beginFill(0xd4a04c, 0.2);
            drawCircleOn(g, vx, vy, 8);
            g.endFill();
            g.beginFill(0xd4a04c, 0.9);
            drawCircleOn(g, vx, vy, 3);
            g.endFill();
        }

        // 灵草点(绿色)
        for (node in engine.spiritHerbNodes) {
            if (!node.alive || node.herbs < 1) continue;
            g.beginFill(0x44aa44, 0.7);
            g.drawRect(node.x * sx - 1, node.y * sy - 1, 2, 2);
            g.endFill();
        }

        // 秘境(金色闪烁)
        for (realm in engine.secretRealms) {
            if (!realm.active) continue;
            var phase = elapsed * 3;
            var rx = realm.x * sx;
            var ry = realm.y * sy;
            g.beginFill(0xffaa44, 0.4);
            drawCircleOn(g, rx, ry, 5 + Math.sin(phase) * 2);
            g.endFill();
            g.lineStyle(1, 0xffaa44, 0.8);
            drawCircleOn(g, rx, ry, 8);
        }

        // 妖潮/宗门大战区域(红色半透明)
        for (evt in engine.activeCataclysms) {
            if (evt.type == "BeastTide" || evt.type == "FactionWar") {
                var ex = evt.x * sx;
                var ey = evt.y * sy;
                g.beginFill(0xc8442a, 0.3);
                drawCircleOn(g, ex, ey, 14);
                g.endFill();
                g.lineStyle(1, 0xc8442a, 0.7);
                drawCircleOn(g, ex, ey, 14);
            }
        }

        // NPC (按类型颜色)
        for (e in engine.entities) {
            if (!e.alive) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;
            var px = pos.x * sx;
            var py = pos.y * sy;
            if (e.isPlayer) {
                // 玩家: 白色三角形(用多边形绘制)
                g.beginFill(0xffffff, 1);
                g.moveTo(px, py - 4);
                g.lineTo(px - 3, py + 3);
                g.lineTo(px + 3, py + 3);
                g.lineTo(px, py - 4);
                g.endFill();
            } else {
                var npcState = e.get(NPCStateComp);
                var color = 0x888888;
                if (npcState != null) {
                    color = switch (npcState.npcType) {
                        case "cultivator": 0x4a7ac8; // 正道蓝
                        case "moxiu": 0xc84444;       // 魔修红
                        case "yaoshou": 0x8a6a3a;     // 妖兽棕
                        case "mojiang": 0xc8442a;     // 魔将橙红
                        case "xiexian": 0xaa44aa;     // 邪仙紫
                        default: 0x888888;
                    };
                }
                g.beginFill(color, 0.9);
                drawCircleOn(g, px, py, 1.5);
                g.endFill();
            }
        }

        // 镜头视野矩形(白色虚框)
        var camLeft = camX * sx;
        var camTop = camY * sy;
        var camW = width * sx;
        var camH = height * sy;
        g.lineStyle(1, 0xffffff, 0.5);
        g.drawRect(camLeft, camTop, camW, camH);
    }

    public function spawnDamageNumber(x:Float, y:Float, dmg:Int, color:Int) {
        var p = getParticle();
        p.x = x; p.y = y;
        p.vx = randRange(-20, 20); p.vy = -60;
        p.life = 0.8; p.maxLife = 0.8;
        p.size = 16; p.color = color;
        p.type = DamageNumber; p.text = Std.string(dmg); p.glow = true;
    }

    public function spawnDeathEffect(x:Float, y:Float) {
        for (i in 0...20) {
            var p = getParticle();
            var angle = Math.random(Math.PI * 2);
            var speed = randRange(50, 200);
            p.x = x; p.y = y;
            p.vx = Math.cos(angle) * speed; p.vy = Math.sin(angle) * speed;
            p.life = randRange(0.5, 1.0); p.maxLife = p.life;
            p.size = randRange(3, 8); p.color = 0xff6600;
            p.type = DeathBurst; p.glow = true; p.fade = true; p.gravity = 100;
        }
    }

    public function getParticle():Particle {
        if (particlePool.length > 0) {
            var p = particlePool.pop();
            p.active = true; p.reset();
            particles.push(p);
            return p;
        }
        var p = new Particle(fxLayer);
        particles.push(p);
        return p;
    }

    public function recycleParticle(p:Particle) {
        p.active = false; p.visible = false;
        particles.remove(p);
        particlePool.push(p);
    }

    // ============================================================
    //  主循环: 驱动世界引擎 + 同步渲染
    // ============================================================
    override function sync(ctx:h2d.RenderContext) {
        var dt = ctx.elapsedTime;

        var win = Window.getInstance();

        // 玩家移动输入 -> 直接更新 PositionComp
        handleInput(dt);

        // === 镜头跟随玩家 ===
        var pos = playerEntity.get(PositionComp);
        if (pos != null) {
            // 镜头目标: 玩家居中
            var targetCamX = pos.x - viewW * 0.5;
            var targetCamY = pos.y - viewH * 0.5;

            // 镜头不超出世界边界
            targetCamX = Math.clamp(targetCamX, 0, engine.worldWidth - viewW);
            targetCamY = Math.clamp(targetCamY, 0, engine.worldHeight - viewH);

            // 平滑插值 (lerp factor 0.12)
            camX += (targetCamX - camX) * 0.12;
            camY += (targetCamY - camY) * 0.12;

            // 应用到 worldCamera
            worldCamera.x = -camX;
            worldCamera.y = -camY;
        }

        // 鼠标坐标转换为世界坐标
        camMouseX = win.mouseX + camX;
        camMouseY = win.mouseY + camY;

        // 背景动画
        bgTime += dt;
        updateBackground(dt);

        // === 驱动世界引擎(应用时间倍率) ===
        // 暂停时引擎不推进, 但玩家输入/镜头/UI 仍响应(观察者模式)
        elapsed += dt;
        if (!paused) {
            engine.update(dt * timeScale);
        }

        // === 同步渲染: 遍历世界实体, 更新对应的渲染对象 ===
        syncRender();

        // === 玩家采集灵草 ===
        if (!paused && playerGatherCd > 0) playerGatherCd -= dt;
        if (!paused && playerGatherCd <= 0) {
            var pPos = playerEntity.get(PositionComp);
            var pInv = playerEntity.get(InventoryComp);
            if (pPos != null && pInv != null) {
                for (node in engine.spiritHerbNodes) {
                    if (!node.alive || node.herbs < 1) continue;
                    var dx = node.x - pPos.x;
                    var dy = node.y - pPos.y;
                    if (dx * dx + dy * dy < 50 * 50) {
                        var gatherAmt = 1;
                        node.herbs -= gatherAmt;
                        pInv.herbs += gatherAmt;
                        if (Math.random() < 0.3) pInv.materials += 1;
                        playerGatherCd = 1.5; // 1.5秒采集冷却
                        flashInfo("采集灵草 +1 (合计: " + pInv.herbs + ")");
                        // 采集粒子效果
                        for (i in 0...6) {
                            var p = getParticle();
                            p.x = node.x + randRange(-10, 10);
                            p.y = node.y + randRange(-10, 10);
                            p.vx = randRange(-30, 30);
                            p.vy = randRange(-40, -10);
                            p.life = randRange(0.3, 0.6);
                            p.maxLife = p.life;
                            p.size = randRange(2, 4);
                            p.color = 0x44ff66;
                            p.type = Spark;
                            p.glow = true;
                            p.fade = true;
                            p.drag = 0.92;
                        }
                        break;
                    }
                }
            }
        }

        // === 渲染世界元素: 灵草资源点、秘境 ===
        renderWorldElements();

        // 粒子更新
        for (p in particles) {
            if (!p.active) continue;
            p.update(dt);
        }

        // 阵法
        if (activeFormation != null) {
            activeFormation.update(dt);
            var pos = playerEntity.get(PositionComp);
            activeFormation.x = pos.x;
            activeFormation.y = pos.y;
            // 阵法伤害
            for (e in engine.entities) {
                if (!e.alive || e.isPlayer) continue;
                var ePos = e.get(PositionComp);
                if (ePos == null) continue;
                var dx = ePos.x - activeFormation.x;
                var dy = ePos.y - activeFormation.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist < activeFormation.radius) {
                    var eCult = e.get(CultivationComp);
                    if (eCult != null) {
                        eCult.hp -= 5 * dt * 10;
                        if (eCult.hp <= 0) {
                            e.alive = false;
                            killCount++;
                            spawnDeathEffect(ePos.x, ePos.y);
                        }
                    }
                }
            }
        }

        // 冷却
        for (k in cooldowns.keys()) {
            if (cooldowns[k] > 0) {
                cooldowns[k] -= dt;
                if (cooldowns[k] < 0) cooldowns[k] = 0;
            }
        }

        // 法术瞄准模式: 更新指示器和超时
        if (pendingSpell != null) {
            targetingTimer -= dt;
            if (targetingTimer <= 0) {
                cancelTargeting();
                flashInfo("施法超时, 已取消");
            } else {
                updateTargetingIndicator();
            }
        }

        if (breakthroughFlash > 0) {
            breakthroughFlash -= dt * 2;
            if (breakthroughFlash < 0) breakthroughFlash = 0;
        }

        // 灵力恢复
        var cult = playerEntity.get(CultivationComp);
        cult.mp = Math.min(cult.maxMp, cult.mp + 15 * dt);

        updateUI(dt);
        updateSkillCooldowns();
        updateWeatherVisual(dt);
        updateDayNightVisual(dt);
        updateVeinAirflowVisual(dt);
        updateTerrainVisual(dt);
        updateReincarnationVisual(dt);
        updateDivineVisual(dt);
        updateKarmaChainVisual(dt);

        super.sync(ctx);
    }

    // --- 同步 ECS -> 渲染对象 ---
    function syncRender() {
        var aliveIds:Map<Int, Bool> = [];

        for (e in engine.entities) {
            if (!e.alive) {
                // 清理渲染对象
                if (renderMap.exists(e.id)) {
                    var c = renderMap[e.id];
                    c.alpha -= 0.05;
                    if (c.alpha <= 0) {
                        c.remove();
                        renderMap.remove(e.id);
                    }
                }
                continue;
            }

            aliveIds[e.id] = true;

            var pos = e.get(PositionComp);
            var cult = e.get(CultivationComp);
            if (pos == null || cult == null) continue;

            // 如果没有渲染对象, 创建一个
            if (!renderMap.exists(e.id)) {
                createRenderFor(e);
            }

            var c = renderMap[e.id];
            if (c == null) continue;

            // 同步位置(考虑飞行浮空偏移)
            c.x = pos.x;
            c.y = pos.y;

            // 同步 HP
            var ratio = Math.max(0, cult.hp / cult.maxHp);
            c.updateHpBar(ratio);

            // 同步物理状态到渲染对象
            var sp = e.get(SpiritPhysicsComp);
            if (sp != null) {
                c.physFrozen = sp.frozenTimer;
                c.physBurn = sp.burnTimer;
                c.physStun = sp.stunTimer;
                c.physSlow = sp.slowTimer;
                c.physSlowFactor = sp.slowFactor;
                c.physShieldActive = sp.shieldActive;
                c.physShieldStrength = sp.shieldStrength;
                c.physShieldMax = sp.shieldMaxStrength;
                c.physIsFlying = sp.isFlying;
                c.physPressure = sp.spiritPressure * (cult.hp / cult.maxHp);
                c.physResonanceStrength = sp.resonanceStrength;
                c.physResonanceBonus = sp.resonanceBonus;
                // 共振颜色匹配灵根
                c.physResonanceColor = cult.getRootColor();
                c.nightDarkness = dayNightAlpha;
            }

            // 更新动画
            c.updateAnimation(0.016);
        }

        // 玩家特殊同步
        if (playerEntity != null && playerEntity.alive) {
            var pos = playerEntity.get(PositionComp);
            var cult = playerEntity.get(CultivationComp);
            if (pos != null && cult != null && player != null) {
                player.x = pos.x;
                player.y = pos.y;
                player.syncFromComp(pos, cult);

                // 玩家也同步物理状态
                var sp = playerEntity.get(SpiritPhysicsComp);
                if (sp != null) {
                    player.physFrozen = sp.frozenTimer;
                    player.physBurn = sp.burnTimer;
                    player.physStun = sp.stunTimer;
                    player.physSlow = sp.slowTimer;
                    player.physSlowFactor = sp.slowFactor;
                    player.physShieldActive = sp.shieldActive;
                    player.physShieldStrength = sp.shieldStrength;
                    player.physShieldMax = sp.shieldMaxStrength;
                    player.physIsFlying = sp.isFlying;
                    player.nightDarkness = dayNightAlpha;
                    player.physPressure = sp.spiritPressure * (cult.hp / cult.maxHp);
                    player.physResonanceStrength = sp.resonanceStrength;
                    player.physResonanceBonus = sp.resonanceBonus;
                    player.physResonanceColor = cult.getRootColor();
                }
            }
        }
    }

    function handleInput(dt:Float) {
        var pos = playerEntity.get(PositionComp);
        if (pos == null) return;

        // 检测鼠标是否在 HaxeUI 组件上(按钮/面板等), 若是则跳过游戏鼠标操作
        var mouseOverUI = isMouseOverUI();

        // === 时间控制快捷键(总是响应, 即使暂停) ===
        if (Key.isPressed(Key.F1)) setTimeScale(paused ? 1.0 : 0.0);
        if (Key.isPressed(Key.F2)) setTimeScale(1.0);
        if (Key.isPressed(Key.F3)) setTimeScale(2.0);
        if (Key.isPressed(Key.F4)) setTimeScale(4.0);

        var speed = 350; // pixels per second

        // 玩家移动: 直接更新位置(实时响应, 不等 tick)
        pos.vx = 0;
        pos.vy = 0;
        var manualInput = false;
        if (Key.isDown(Key.W) || Key.isDown(Key.UP)) { pos.vy -= speed; manualInput = true; }
        if (Key.isDown(Key.S) || Key.isDown(Key.DOWN)) { pos.vy += speed; manualInput = true; }
        if (Key.isDown(Key.A) || Key.isDown(Key.LEFT)) { pos.vx -= speed; manualInput = true; }
        if (Key.isDown(Key.D) || Key.isDown(Key.RIGHT)) { pos.vx += speed; manualInput = true; }

        // 手动操作取消自动寻路
        if (manualInput) isAutoMoving = false;

        // 右键自动寻路(暂停时也响应, 方便观察者移动)
        if (isAutoMoving) {
            var dx = moveTargetX - pos.x;
            var dy = moveTargetY - pos.y;
            var dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < 10) {
                isAutoMoving = false;
            } else {
                pos.vx = (dx / dist) * speed;
                pos.vy = (dy / dist) * speed;
            }
        }

        pos.x += pos.vx * dt;
        pos.y += pos.vy * dt;
        // 玩家限制在世界边界内
        pos.x = Math.clamp(pos.x, 30, engine.worldWidth - 30);
        pos.y = Math.clamp(pos.y, 30, engine.worldHeight - 30);

        // 暂停时只允许移动 + 时间控制, 跳过施法/普攻
        if (paused) return;

        if (Key.isPressed(Key.Q)) castSpell("fireball", 30, 1.5);
        if (Key.isPressed(Key.F)) castSpell("thunder", 50, 2.0);
        if (Key.isPressed(Key.E)) castSpell("ice", 35, 1.8);
        if (Key.isPressed(Key.R)) castSpell("swordqi", 60, 3.0);
        if (Key.isPressed(Key.T)) castSpell("thunderstorm", 100, 5.0);
        if (Key.isPressed(Key.Y)) castSpell("pocket", 80, 6.0);
        if (Key.isPressed(Key.U)) castSpell("lotus", 70, 4.0);
        if (Key.isPressed(Key.I)) castSpell("bigdipper", 90, 5.0);
        if (Key.isPressed(Key.O)) castSpell("clone", 60, 4.5);
        if (Key.isPressed(Key.P)) castSpell("voidshift", 50, 3.0);

        if (Key.isPressed(Key.NUMPAD_1) || Key.isPressed(Key.NUMBER_1)) castFormation("bagua");
        if (Key.isPressed(Key.NUMPAD_2) || Key.isPressed(Key.NUMBER_2)) castFormation("wuxing");
        if (Key.isPressed(Key.NUMPAD_3) || Key.isPressed(Key.NUMBER_3)) castFormation("taiji");
        if (Key.isPressed(Key.NUMPAD_4) || Key.isPressed(Key.NUMBER_4)) castFormation("beidou");
        if (Key.isPressed(Key.NUMPAD_5) || Key.isPressed(Key.NUMBER_5)) castFormation("jiugong");

        if (Key.isPressed(Key.SPACE)) normalAttack();

        // === 法术目标选择 ===
        if (pendingSpell != null) {
            // 瞄准模式: 左键确认释放(不受 UI 区域限制, 玩家已明确要施法)
            if (Key.isPressed(Key.MOUSE_LEFT)) {
                executeSpellCast(camMouseX, camMouseY);
            }
            // Tab: 自动锁定最近敌人
            if (Key.isPressed(Key.TAB)) {
                var nearest = findNearestEnemy();
                if (nearest != null) {
                    executeSpellCast(nearest.x, nearest.y);
                } else {
                    flashInfo("附近无敌人, 使用鼠标选择位置");
                }
            }
            // 右键/Esc: 取消
            if (Key.isPressed(Key.ESCAPE) || Key.isPressed(Key.MOUSE_RIGHT)) {
                cancelTargeting();
                flashInfo("已取消施法");
            }
        } else {
            // 非瞄准模式: 左键点击 NPC = 查看详情, 左键空白 = 普攻, 右键 = 移动
            // 鼠标在 UI 上时跳过所有游戏鼠标操作
            if (!mouseOverUI && Key.isPressed(Key.MOUSE_LEFT)) {
                var clickedNpc = findNpcAt(camMouseX, camMouseY);
                if (clickedNpc != null) {
                    showNpcDetail(clickedNpc);
                } else {
                    normalAttack();
                }
            }
            if (!mouseOverUI && Key.isPressed(Key.MOUSE_RIGHT)) {
                moveTargetX = camMouseX;
                moveTargetY = camMouseY;
                isAutoMoving = true;
            }
        }
    }

    function updateUI(dt:Float) {
        var cult = playerEntity.get(CultivationComp);
        var pos = playerEntity.get(PositionComp);
        var karma = playerEntity.get(KarmaComp);
        var inv = playerEntity.get(InventoryComp);

        uiHpBar.pos = Math.max(0, cult.hp);
        uiMpBar.pos = Math.max(0, cult.mp);
        uiExpBar.pos = Math.max(0, cult.exp);
        uiExpBar.max = cult.expToNext;

        uiHpNum.text = Std.string(Math.max(0, Math.round(cult.hp))) + "/" + Std.string(cult.maxHp);
        uiMpNum.text = Std.string(Math.max(0, Math.round(cult.mp))) + "/" + Std.string(cult.maxMp);
        uiExpLabel.text = Std.string(Math.round(cult.exp)) + "/" + Std.string(cult.expToNext);
        uiKillLabel.text = "击杀: " + Std.string(killCount);
        uiRealmLabel.text = playerEntity.name + "  [" + cult.realmName + "]";
        uiRootLabel.text = cult.spiritRootName + "·" + cult.spiritRootQualityName;
        uiRootDetail.text = "天赋:" + cult.talent + "  气运:" + cult.luck + "  灵石:" + (inv != null ? inv.spiritStones : 0);

        // 世界信息
        var snap = engine.lastSnapshot;
        if (snap != null) {
            var speedTag = paused ? "已暂停" : (timeScale + "x");
            worldTabText = "第" + snap.worldYear + "年 第" + snap.worldDay + "日 [" + speedTag + "]\n" +
                "灵气浓度: " + Std.string(snap.globalSpiritDensity).substr(0, 4) + "\n" +
                "修仙者: " + snap.aliveCount + "/" + engine.maxEntities + "\n" +
                "宗门: " + snap.factionCount + "\n" +
                "飞升: " + engine.ascendedCount + "人\n" +
                "--- 天道日志 ---\n";
        }

        // 事件日志(最近5条)
        var logText = "";
        var recent = engine.eventLog.slice(-5);
        for (ev in recent) {
            logText += ev.desc + "\n";
        }
        worldTabText += logText;

        // === 势力面板 ===
        factionTabText = "--- 八大宗门 ---\n";
        for (f in engine.factions) {
            var status = f.alive ? "●" : "×";
            var align = f.alignment == "righteous" ? "正" : "魔";
            factionTabText += status + " [" + align + "] " + f.name + " " + f.memberCount + "人\n";
        }

        // === 编年史: 筛选重大事件 ===
        var chronicleTypes = ["Birth", "Ascension", "BeastTide", "SecretRealm", "FactionWar",
            "SpiritSurge", "HeritageTransfer", "TribulationSuccess", "TribulationDeath",
            "FactionFall", "Marry", "TakeDisciple", "LightningTribulation", "HeartDemonTribulation",
            "AscensionSurge", "SecretRealmClose", "FactionWarEnd", "SpiritSurgeEnd"];
        var chronicleEvents = engine.eventLog.filter(function(e) {
            return chronicleTypes.indexOf(e.type) >= 0;
        });
        chronicleTabText = "--- 天道编年史 ---\n";
        var recentChron = chronicleEvents.slice(-3);
        recentChron.reverse();
        for (ev in recentChron) {
            var desc = ev.desc;
            if (desc.length > 30) desc = desc.substr(0, 28) + "...";
            chronicleTabText += "[D" + ev.day + "] " + desc + "\n";
        }

        // 同步到当前显示的 Tab
        if (currentRightTab == "faction") {
            uiTabContent.text = factionTabText;
        } else if (currentRightTab == "chronicle") {
            uiTabContent.text = chronicleTabText;
        } else {
            uiTabContent.text = worldTabText;
        }

        // === 当前进行中的世界事件横幅 ===
        var eventText = "";
        for (evt in engine.activeCataclysms) {
            eventText += "【" + evt.desc + "】 ";
        }
        if (eventText == "") {
            uiActiveEvent.text = "";
            uiActiveEvent.visible = false;
        } else {
            uiActiveEvent.text = "⚠ " + eventText;
            uiActiveEvent.visible = true;
        }

        // === 实时更新 NPC 详情浮窗(如果打开) ===
        if (!npcDetailPanel.hidden) updateNpcDetail();

        // === 物理状态 / 天气 / 昼夜 信息条 ===
        var physInfo = "";

        // 玩家物理状态
        var physComp = playerEntity.get(SpiritPhysicsComp);
        if (physComp != null) {
            var statuses:Array<String> = [];
            if (physComp.frozenTimer > 0) statuses.push("❄冰冻");
            if (physComp.burnTimer > 0) statuses.push("🔥燃烧");
            if (physComp.stunTimer > 0) statuses.push("💫眩晕");
            if (physComp.slowTimer > 0) statuses.push("🐌减速");
            if (physComp.shieldActive) statuses.push("🛡护体灵光(" + Math.round(physComp.shieldStrength) + ")");
            if (physComp.isFlying) statuses.push("🦅御剑飞行");
            if (statuses.length > 0) physInfo += "状态: " + statuses.join(" ") + "  ";
        }

        // 天气
        var weatherSys2:WeatherSystem = null;
        for (s in engine.systems) {
            var ws2 = Std.downcast(s, WeatherSystem);
            if (ws2 != null) { weatherSys2 = ws2; break; }
        }
        if (weatherSys2 != null && weatherSys2.state.type != "clear") {
            var wNames:Map<String, String> = [
                "rain" => "🌧雨", "snow" => "❄雪", "thunder" => "⛈雷暴", "fog" => "🌫雾"
            ];
            physInfo += "天气: " + (wNames.exists(weatherSys2.state.type) ? wNames[weatherSys2.state.type] : weatherSys2.state.type) + "  ";
        }

        // 昼夜
        var dayNightSys2:DayNightSystem = null;
        for (s in engine.systems) {
            var dns2 = Std.downcast(s, DayNightSystem);
            if (dns2 != null) { dayNightSys2 = dns2; break; }
        }
        if (dayNightSys2 != null) {
            var phaseNames:Map<String, String> = [
                "dawn" => "🌅黎明", "day" => "☀白昼", "dusk" => "🌇黄昏", "night" => "🌙夜晚"
            ];
            physInfo += "时辰: " + (phaseNames.exists(dayNightSys2.state.dayPhase) ? phaseNames[dayNightSys2.state.dayPhase] : dayNightSys2.state.dayPhase);
        }

        playerPhysStatus = physInfo;
        if (uiStatusInfo != null) {
            uiStatusInfo.text = physInfo;
            uiStatusInfo.visible = physInfo.length > 0;
        }
    }

    function updateSkillCooldowns() {
        var skillKeys = ["fireball", "thunder", "ice", "swordqi", "thunderstorm", "pocket", "lotus", "bigdipper", "clone", "voidshift"];
        for (i in 0...uiSkillButtons.length) {
            var btn = uiSkillButtons[i];
            var key = skillKeys[i];
            var cd = cooldowns.exists(key) ? cooldowns[key] : 0;
            if (cd > 0) { btn.alpha = 0.5; btn.disabled = true; }
            else { btn.alpha = 1.0; btn.disabled = false; }
        }
    }

    // ============================================================
    //  天气视觉层 — 全屏雨/雪/雷暴/雾效果
    // ============================================================
    function updateWeatherVisual(dt:Float):Void {
        // 获取天气系统
        var weatherSys:WeatherSystem = null;
        for (s in engine.systems) {
            var ws = Std.downcast(s, WeatherSystem);
            if (ws != null) { weatherSys = ws; break; }
        }

        weatherOverlay.clear();

        if (weatherSys == null) return;

        var weather = weatherSys.state.type;
        var screenW = width;
        var screenH = height;

        switch (weather) {
            case "rain":
                // 雨天: 生成雨滴粒子
                if (weatherParticles.length < 120) {
                    for (i in 0...4) {
                        weatherParticles.push({
                            x: Math.random() * screenW,
                            y: -10,
                            vx: -30 + Math.random() * 20,
                            vy: 400 + Math.random() * 200,
                            type: "rain",
                            life: 2
                        });
                    }
                }
                // 全屏微蓝
                weatherOverlay.beginFill(0x223366, 0.08);
                weatherOverlay.drawRect(0, 0, screenW, screenH);
                weatherOverlay.endFill();

            case "snow":
                // 雪天: 生成雪花粒子
                if (weatherParticles.length < 80) {
                    for (i in 0...2) {
                        weatherParticles.push({
                            x: Math.random() * screenW,
                            y: -10,
                            vx: -15 + Math.random() * 30,
                            vy: 50 + Math.random() * 60,
                            type: "snow",
                            life: 5
                        });
                    }
                }
                // 全屏微白
                weatherOverlay.beginFill(0xddddff, 0.06);
                weatherOverlay.drawRect(0, 0, screenW, screenH);
                weatherOverlay.endFill();

            case "thunder":
                // 雷暴: 雨滴 + 随机闪光
                if (weatherParticles.length < 150) {
                    for (i in 0...5) {
                        weatherParticles.push({
                            x: Math.random() * screenW,
                            y: -10,
                            vx: -40 + Math.random() * 20,
                            vy: 500 + Math.random() * 200,
                            type: "rain",
                            life: 2
                        });
                    }
                }
                // 闪光效果
                weatherFlash -= dt;
                if (weatherFlash <= 0 && Math.random() < 0.02) {
                    weatherFlash = 0.15;
                }
                if (weatherFlash > 0) {
                    weatherOverlay.beginFill(0xffffff, weatherFlash * 2);
                    weatherOverlay.drawRect(0, 0, screenW, screenH);
                    weatherOverlay.endFill();
                }
                // 暗紫色底色
                weatherOverlay.beginFill(0x332244, 0.12);
                weatherOverlay.drawRect(0, 0, screenW, screenH);
                weatherOverlay.endFill();

            case "fog":
                // 雾天: 飘动雾气
                if (weatherParticles.length < 40) {
                    weatherParticles.push({
                        x: Math.random() * screenW,
                        y: Math.random() * screenH,
                        vx: 10 + Math.random() * 20,
                        vy: -2 + Math.random() * 4,
                        type: "fog",
                        life: 8
                    });
                }
                // 全屏灰白
                weatherOverlay.beginFill(0xaaaaaa, 0.12);
                weatherOverlay.drawRect(0, 0, screenW, screenH);
                weatherOverlay.endFill();

            case "clear":
                // 晴天: 无覆盖
        }

        // 更新和绘制天气粒子
        var i = weatherParticles.length;
        while (i-- > 0) {
            var p = weatherParticles[i];
            p.x += p.vx * dt;
            p.y += p.vy * dt;
            p.life -= dt;

            if (p.y > screenH + 10 || p.x < -20 || p.x > screenW + 20 || p.life <= 0) {
                weatherParticles.splice(i, 1);
                continue;
            }

            switch (p.type) {
                case "rain":
                    weatherOverlay.lineStyle(1.5, 0x88aacc, 0.5);
                    weatherOverlay.moveTo(p.x, p.y);
                    weatherOverlay.lineTo(p.x - p.vx * 0.02, p.y - p.vy * 0.02);
                case "snow":
                    weatherOverlay.beginFill(0xffffff, 0.7);
                    weatherOverlay.drawCircle(p.x, p.y, 2 + Math.sin(p.life * 5) * 0.5);
                    weatherOverlay.endFill();
                case "fog":
                    weatherOverlay.beginFill(0xcccccc, 0.06);
                    weatherOverlay.drawCircle(p.x, p.y, 30 + Math.sin(p.life * 2) * 10);
                    weatherOverlay.endFill();
            }
        }
    }

    // ============================================================
    //  昼夜光照层 — 夜晚暗化 + 黎明黄昏渐变
    // ============================================================
    function updateDayNightVisual(dt:Float):Void {
        // 获取昼夜系统
        var dayNightSys:DayNightSystem = null;
        for (s in engine.systems) {
            var dns = Std.downcast(s, DayNightSystem);
            if (dns != null) { dayNightSys = dns; break; }
        }

        if (dayNightSys == null || dayNightOverlay == null) return;

        var targetAlpha = dayNightSys.state.darkness;
        // 平滑过渡
        dayNightAlpha += (targetAlpha - dayNightAlpha) * dt * 2;
        dayNightOverlay.alpha = dayNightAlpha;

        // 根据阶段调整颜色
        var color = switch (dayNightSys.state.dayPhase) {
            case "dawn":  0x994433;   // 黎明: 微红
            case "day":   0x000033;   // 白天: 几乎无
            case "dusk":  0x443366;   // 黄昏: 微紫
            case "night": 0x001144;   // 夜晚: 深蓝(亮度增加)
            default:      0x000033;
        };
        // 重新创建颜色 tile
        if (dayNightAlpha > 0.005) {
            dayNightOverlay.tile = h2d.Tile.fromColor(color, 1, 1);
        }
    }

    // ============================================================
    //  灵脉气流粒子可视化
    // ============================================================
    function updateVeinAirflowVisual(dt:Float):Void {
        // 在每个灵脉位置偶尔生成上升气流粒子
        for (vein in engine.spiritVeins) {
            if (vein.currentDensity < 0.5) continue;
            if (Math.random() < vein.currentDensity * dt * 2) {
                var px = vein.x + (Math.random() - 0.5) * 100;
                var py = vein.y + (Math.random() - 0.5) * 100;
                // 只在镜头范围内生成
                if (px < camX - 50 || px > camX + viewW + 50) continue;
                if (py < camY - 50 || py > camY + viewH + 50) continue;

                var p = getParticle();
                if (p == null) continue;
                p.x = px;
                p.y = py;
                p.vx = (Math.random() - 0.5) * 10;
                p.vy = -20 - Math.random() * 30;
                p.life = 2;
                p.maxLife = 2;
                p.size = 2 + Math.random() * 2;
                p.color = 0x88ffaa;
                p.alpha = 0.4;
                p.gravity = 0;
            }
        }
    }

    // ============================================================
    //  地形系统可视化 — 在背景层渲染地形类型颜色
    // ============================================================
    function updateTerrainVisual(dt:Float):Void {
        if (terrainLayer == null) return;

        // 获取地形系统
        var terrainSys:TerrainSystem = null;
        for (s in engine.systems) {
            var ts = Std.downcast(s, TerrainSystem);
            if (ts != null) { terrainSys = ts; break; }
        }
        if (terrainSys == null) return;

        // 懒初始化: 只渲染一次(地形不频繁变化)
        if (terrainInitialized) {
            // 每日刷新一次(地形微调)
            if (engine.tickCount % engine.ticksPerDay != 0) return;
        }
        terrainInitialized = true;

        terrainLayer.clear();

        // 只渲染镜头可见区域的地形
        var camLeft = camX;
        var camTop = camY;
        var camRight = camX + viewW;
        var camBottom = camY + viewH;

        var startCol = Std.int(Math.max(0, camLeft / terrainSys.gridSize));
        var endCol = Std.int(Math.min(terrainSys.gridCols - 1, camRight / terrainSys.gridSize));
        var startRow = Std.int(Math.max(0, camTop / terrainSys.gridSize));
        var endRow = Std.int(Math.min(terrainSys.gridRows - 1, camBottom / terrainSys.gridSize));

        for (gy in startRow...endRow + 1) {
            for (gx in startCol...endCol + 1) {
                if (gy < 0 || gy >= terrainSys.gridRows || gx < 0 || gx >= terrainSys.gridCols) continue;
                var cell = terrainSys.grid[gy][gx];
                var px = gx * terrainSys.gridSize;
                var py = gy * terrainSys.gridSize;
                var sz = terrainSys.gridSize;

                // 地形颜色 + 透明度
                var col = switch (cell.type) {
                    case "mountain": 0x4a3a2a;
                    case "water": 0x1a3a5a;
                    case "forest": 0x1a3a1a;
                    case "desert": 0x5a4a2a;
                    default: 0x2a2a2a;
                };
                terrainLayer.beginFill(col, 0.25);
                terrainLayer.drawRect(px, py, sz, sz);
                terrainLayer.endFill();

                // 山脉: 画三角形
                if (cell.type == "mountain") {
                    terrainLayer.lineStyle(1, 0x6a5a3a, 0.3);
                    var cx = px + sz * 0.5;
                    var cy = py + sz * 0.5;
                    terrainLayer.moveTo(cx, cy - sz * 0.3);
                    terrainLayer.lineTo(cx - sz * 0.25, cy + sz * 0.2);
                    terrainLayer.lineTo(cx + sz * 0.25, cy + sz * 0.2);
                    terrainLayer.lineTo(cx, cy - sz * 0.3);
                }

                // 水域: 波纹线
                if (cell.type == "water") {
                    terrainLayer.lineStyle(1, 0x3a6a9a, 0.2);
                    var cy = py + sz * 0.5;
                    terrainLayer.moveTo(px + 10, cy);
                    terrainLayer.lineTo(px + 30, cy - 4);
                    terrainLayer.lineTo(px + 50, cy);
                    terrainLayer.lineTo(px + 70, cy - 4);
                }

                // 森林: 小圆点表示树木
                if (cell.type == "forest") {
                    terrainLayer.beginFill(0x2a5a2a, 0.3);
                    for (i in 0...3) {
                        var tx = px + 50 + i * 100;
                        var ty = py + 50 + (i % 2) * 80;
                        terrainLayer.drawCircle(tx, ty, 8);
                    }
                    terrainLayer.endFill();
                }

                // 沙漠: 横线表示沙丘
                if (cell.type == "desert") {
                    terrainLayer.lineStyle(1, 0x8a7a4a, 0.2);
                    terrainLayer.moveTo(px + 20, py + sz * 0.4);
                    terrainLayer.lineTo(px + sz - 20, py + sz * 0.4);
                    terrainLayer.moveTo(px + 30, py + sz * 0.7);
                    terrainLayer.lineTo(px + sz - 30, py + sz * 0.7);
                }
            }
        }
    }

    // ============================================================
    //  轮回系统可视化 — 残魂粒子 + 转世光柱
    // ============================================================
    function updateReincarnationVisual(dt:Float):Void {
        if (reincarnationFxLayer == null) return;
        reincarnationFxLayer.clear();

        // 扫描事件日志中的轮回相关事件(最近20条)
        var recentEvents = engine.eventLog.slice(-20);
        var soulPendingEvents:Array<WorldEvent> = [];
        var reincarnationEvents:Array<WorldEvent> = [];

        for (evt in recentEvents) {
            if (evt.type == "SoulPending") soulPendingEvents.push(evt);
            if (evt.type == "Reincarnation") reincarnationEvents.push(evt);
        }

        // 转世光柱: 新转世的实体位置画金色光柱(渐隐)
        for (evt in reincarnationEvents) {
            var e = engine.getEntity(evt.sourceId);
            if (e == null || !e.alive) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;

            // 只在镜头范围内渲染
            if (pos.x < camX - 100 || pos.x > camX + viewW + 100) continue;
            if (pos.y < camY - 100 || pos.y > camY + viewH + 100) continue;

            // 金色光柱
            reincarnationFxLayer.lineStyle(2, 0xffdd44, 0.5);
            reincarnationFxLayer.moveTo(pos.x, pos.y - 80);
            reincarnationFxLayer.lineTo(pos.x, pos.y + 10);

            // 光环
            reincarnationFxLayer.beginFill(0xffdd44, 0.08);
            reincarnationFxLayer.drawCircle(pos.x, pos.y, 40);
            reincarnationFxLayer.endFill();

            // "转世" 文字标记
            reincarnationFxLayer.beginFill(0xffdd44, 0.15);
            reincarnationFxLayer.drawCircle(pos.x, pos.y - 50, 6);
            reincarnationFxLayer.endFill();
        }

        // 残魂: 为有前世记忆的实体画灵魂标记
        for (e in engine.entities) {
            if (!e.alive) continue;
            var reinc = e.get(ReincarnationComp);
            if (reinc == null || !reinc.hasPastLife) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;

            // 只在镜头范围内渲染
            if (pos.x < camX - 50 || pos.x > camX + viewW + 50) continue;
            if (pos.y < camY - 50 || pos.y > camY + viewH + 50) continue;

            // 前世记忆标记: 头顶淡紫色灵魂图标
            var alpha = 0.3 + Math.sin(elapsed * 3 + e.id) * 0.1;
            reincarnationFxLayer.beginFill(0xaa88ff, alpha);
            reincarnationFxLayer.drawCircle(pos.x, pos.y - 35, 4);
            reincarnationFxLayer.endFill();

            // 多世轮回: 转世次数越多光环越大
            if (reinc.reincarnationCount > 1) {
                reincarnationFxLayer.lineStyle(1, 0xaa88ff, 0.15);
                reincarnationFxLayer.drawCircle(pos.x, pos.y, 20 + reinc.reincarnationCount * 3);
            }
        }
    }

    // ============================================================
    //  天道意志可视化 — 天道干预金光 + 天罚雷击 + 天道之眼 + 命运光环
    // ============================================================
    function updateDivineVisual(dt:Float):Void {
        if (divineFxLayer == null) return;
        divineFxLayer.clear();

        // 闪光衰减
        if (divineFlash > 0) divineFlash -= dt * 2;
        if (tribulationFlash > 0) tribulationFlash -= dt * 3;

        // 扫描天道事件
        var recentEvents = engine.eventLog.slice(-15);
        for (evt in recentEvents) {
            switch (evt.type) {
                case "HeavenlyIntervention", "SpiritRain", "SpiritBeastGuardian":
                    // 天道干预: 全屏金光闪烁
                    divineFlash = 1.0;
                case "HeavenlyTribulation":
                    // 天罚: 雷击效果
                    tribulationFlash = 1.0;
                    var target = engine.getEntity(evt.sourceId);
                    if (target != null && target.alive) {
                        var pos = target.get(PositionComp);
                        if (pos != null) {
                            // 画天罚雷柱
                            divineFxLayer.lineStyle(3, 0xffff44, 0.6);
                            divineFxLayer.moveTo(pos.x + (Math.random() * 20 - 10), pos.y - 120);
                            divineFxLayer.lineTo(pos.x, pos.y);
                            divineFxLayer.lineStyle(1, 0xffffff, 0.8);
                            divineFxLayer.moveTo(pos.x, pos.y - 100);
                            divineFxLayer.lineTo(pos.x, pos.y);
                            // 冲击波
                            divineFxLayer.beginFill(0xffff44, 0.1);
                            divineFxLayer.drawCircle(pos.x, pos.y, 30);
                            divineFxLayer.endFill();
                        }
                    }
                case "HeavenlyEye":
                    // 天道之眼: 锁定目标画眼睛图标
                    var target = engine.getEntity(evt.sourceId);
                    if (target != null && target.alive) {
                        var pos = target.get(PositionComp);
                        if (pos != null) {
                            var eyePulse = 0.3 + Math.sin(elapsed * 5) * 0.2;
                            // 眼睛轮廓
                            divineFxLayer.lineStyle(2, 0xff4444, eyePulse);
                            divineFxLayer.moveTo(pos.x - 15, pos.y - 45);
                            divineFxLayer.lineTo(pos.x, pos.y - 50);
                            divineFxLayer.lineTo(pos.x + 15, pos.y - 45);
                            divineFxLayer.lineTo(pos.x, pos.y - 40);
                            divineFxLayer.lineTo(pos.x - 15, pos.y - 45);
                            // 瞳孔
                            divineFxLayer.beginFill(0xff0000, eyePulse);
                            divineFxLayer.drawCircle(pos.x, pos.y - 45, 3);
                            divineFxLayer.endFill();
                        }
                    }
                case "DestinyChosen":
                    // 天命之人: 金色光环
                    var target = engine.getEntity(evt.sourceId);
                    if (target != null && target.alive) {
                        var pos = target.get(PositionComp);
                        if (pos != null) {
                            var pulse = 0.2 + Math.sin(elapsed * 2) * 0.1;
                            divineFxLayer.lineStyle(2, 0xffdd00, pulse);
                            divineFxLayer.drawCircle(pos.x, pos.y, 25);
                            divineFxLayer.lineStyle(1, 0xffdd00, pulse * 0.5);
                            divineFxLayer.drawCircle(pos.x, pos.y, 35);
                        }
                    }
                case "DestinyForsaken":
                    // 天弃之子: 灰暗光环
                    var target = engine.getEntity(evt.sourceId);
                    if (target != null && target.alive) {
                        var pos = target.get(PositionComp);
                        if (pos != null) {
                            divineFxLayer.lineStyle(1, 0x666666, 0.3);
                            divineFxLayer.drawCircle(pos.x, pos.y, 20);
                        }
                    }
            }
        }

        // 天道干预全屏金光
        if (divineFlash > 0) {
            divineFxLayer.beginFill(0xffdd44, divineFlash * 0.06);
            divineFxLayer.drawRect(camX, camY, viewW, viewH);
            divineFxLayer.endFill();
        }

        // 天罚闪光
        if (tribulationFlash > 0) {
            divineFxLayer.beginFill(0xffffff, tribulationFlash * 0.08);
            divineFxLayer.drawRect(camX, camY, viewW, viewH);
            divineFxLayer.endFill();
        }
    }

    // ============================================================
    //  因果链可视化 — 追杀红线 + 悬赏标记
    // ============================================================
    function updateKarmaChainVisual(dt:Float):Void {
        if (karmaFxLayer == null) return;
        karmaFxLayer.clear();

        // 获取因果链系统
        var karmaChainSys:KarmaChainSystem = null;
        for (s in engine.systems) {
            var kcs = Std.downcast(s, KarmaChainSystem);
            if (kcs != null) { karmaChainSys = kcs; break; }
        }

        // 遍历所有正在追杀的实体, 画追杀红线
        for (e in engine.entities) {
            if (!e.alive) continue;
            var chainComp = e.get(KarmaChainComp);
            if (chainComp == null || !chainComp.isPursuing) continue;

            var myPos = e.get(PositionComp);
            if (myPos == null) continue;

            var target = engine.getEntity(chainComp.pursuitTargetId);
            if (target == null || !target.alive) continue;
            var targetPos = target.get(PositionComp);
            if (targetPos == null) continue;

            // 只在镜头范围内渲染
            var midX = (myPos.x + targetPos.x) * 0.5;
            var midY = (myPos.y + targetPos.y) * 0.5;
            if (midX < camX - 200 || midX > camX + viewW + 200) continue;
            if (midY < camY - 200 || midY > camY + viewH + 200) continue;

            // 追杀红线(虚线效果用多段)
            var dx = targetPos.x - myPos.x;
            var dy = targetPos.y - myPos.y;
            var dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < 1) continue;

            var segments = Std.int(dist / 15);
            var pulse = 0.3 + Math.sin(elapsed * 8 + e.id) * 0.2;

            for (i in 0...segments) {
                if (i % 2 == 0) continue; // 虚线
                var t1 = i / segments;
                var t2 = (i + 1) / segments;
                karmaFxLayer.lineStyle(1, 0xff3333, pulse);
                karmaFxLayer.moveTo(myPos.x + dx * t1, myPos.y + dy * t1);
                karmaFxLayer.lineTo(myPos.x + dx * t2, myPos.y + dy * t2);
            }

            // 目标头顶悬赏标记(红色感叹号)
            karmaFxLayer.beginFill(0xff3333, pulse);
            karmaFxLayer.drawRect(targetPos.x - 2, targetPos.y - 45, 4, 10);
            karmaFxLayer.drawCircle(targetPos.x, targetPos.y - 30, 3);
            karmaFxLayer.endFill();
        }

        // 因果链总计数(如果玩家有因果链)
        var playerChain = playerEntity.get(KarmaChainComp);
        if (playerChain != null && playerChain.killCount > 0) {
            // 玩家头顶画因果标记(紫色因果丝线)
            var pos = playerEntity.get(PositionComp);
            if (pos != null) {
                for (i in 0...Std.int(Math.min(playerChain.killCount, 5))) {
                    var angle = elapsed * 2 + i * 1.2;
                    var r = 30;
                    karmaFxLayer.lineStyle(1, 0xaa44ff, 0.2);
                    karmaFxLayer.moveTo(pos.x, pos.y - 20);
                    karmaFxLayer.lineTo(pos.x + Math.cos(angle) * r, pos.y - 20 + Math.sin(angle) * r);
                }
            }
        }
    }

    // ============================================================
    //  兼容层: 供 SpellSystem / Formation 调用
    //  将旧的 Cultivator-based API 映射到 ECS 实体
    // ============================================================

    // 返回所有存活的非玩家渲染对象(兼容旧 API)
    public var enemies(get, null):Array<Cultivator>;
    function get_enemies():Array<Cultivator> {
        var result:Array<Cultivator> = [];
        for (e in engine.entities) {
            if (!e.alive || e.isPlayer) continue;
            var c = renderMap.get(e.id);
            if (c != null) result.push(c);
        }
        return result;
    }

    // 法术伤害(兼容旧 API): 在 Cultivator 上查找对应的 Entity 并应用伤害
    public function dealSpellDamage(target:Cultivator, baseDmg:Int, spellId:String, knockbackX:Float, knockbackY:Float):Void {
        // 通过 renderMap 反查 Entity
        var targetEntity:Entity = null;
        for (id => c in renderMap) {
            if (c == target) {
                targetEntity = engine.getEntity(id);
                break;
            }
        }
        if (targetEntity == null || !targetEntity.alive) return;

        var cult = targetEntity.get(CultivationComp);
        var pos = targetEntity.get(PositionComp);
        if (cult == null) return;

        // 应用灵根加成
        var playerCult = playerEntity.get(CultivationComp);
        var mult = playerCult != null ? playerCult.getSpellMultiplier(spellId) : 1.0;
        var dmg = Math.round(baseDmg * mult);
        cult.hp -= dmg;

        // 击退
        if (pos != null) {
            pos.vx += knockbackX;
            pos.vy += knockbackY;
        }

        // 伤害数字
        if (pos != null) spawnDamageNumber(pos.x, pos.y - 20, dmg, 0xffdd44);

        // 死亡处理
        if (cult.hp <= 0) {
            targetEntity.alive = false;
            killCount++;
            if (pos != null) spawnDeathEffect(pos.x, pos.y);

            // 玩家获得经验
            if (playerCult != null) {
                playerCult.exp += 20 + cult.realmIndex * 15;
                if (playerCult.exp >= playerCult.expToNext) {
                    doPlayerBreakthrough();
                }
            }
        }
    }

    // 阵法伤害(兼容旧 API)
    public function dealDamage(target:Cultivator, dmg:Int, knockbackX:Float, knockbackY:Float):Void {
        dealSpellDamage(target, dmg, "formation", knockbackX, knockbackY);
    }
}
