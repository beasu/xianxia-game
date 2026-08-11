import h2d.Scene;
import h2d.Object;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Text;
import hxd.Key;
import hxd.Math;
import hxd.Window;

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

import ecs.Entity.Entity;
import ecs.Entity.ISystem;
import ecs.Components;
import ecs.WorldEngine;
import ecs.Systems;
import ecs.WorldEcologySystem;
import ecs.KarmaAndTribulationSystem;
import ecs.NPCSocialSystem;

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
    var uiWorldInfo:Label;           // 世界信息
    var uiEventLog:Label;            // 事件日志

    // --- 技能冷却 ---
    public var cooldowns:Map<String, Float> = [];

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

        // UI 层直接挂在 Scene 下, 不受镜头移动影响
        uiLayer = new Object(this);
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
        engine.addSystem(new IntentResolutionSystem());
        engine.addSystem(new NPCSocialSystem());
        engine.addSystem(new WorldEcologySystem());
        engine.addSystem(new EcologySystem());
        engine.addSystem(new KarmaAndTribulationSystem());
        engine.addSystem(new HistorySystem());

        // 初始化灵脉
        engine.initSpiritVeins();

        // 初始化势力
        engine.initFactions();

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

        playerEntity.add(pos).add(cult).add(intent).add(karma).add(inv).add(fac).add(npc).add(social);
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
        topBar.width = width;
        topBar.paddingTop = 8;
        topBar.paddingLeft = 12;
        topBar.verticalSpacing = 3;

        var nameRow = new HBox();
        nameRow.horizontalSpacing = 8;
        uiRealmLabel = new Label();
        var cult = playerEntity.get(CultivationComp);
        uiRealmLabel.text = playerEntity.name + "  [" + cult.realmName + "]";
        uiRealmLabel.styleString = "font-size:18px;color:#FFD700;font-weight:bold;";
        uiRealmLabel.width = 200;
        nameRow.addComponent(uiRealmLabel);

        uiRootLabel = new Label();
        uiRootLabel.text = cult.spiritRootName + "·" + cult.spiritRootQualityName;
        uiRootLabel.styleString = "font-size:15px;color:#" + StringTools.hex(cult.getRootColor() & 0xffffff, 6) + ";font-weight:bold;";
        uiRootLabel.width = 130;
        nameRow.addComponent(uiRootLabel);

        uiKillLabel = new Label();
        uiKillLabel.text = "击杀: 0";
        uiKillLabel.styleString = "font-size:14px;color:#aaaaff;";
        uiKillLabel.width = 100;
        nameRow.addComponent(uiKillLabel);
        topBar.addComponent(nameRow);

        // 灵根详情
        var rootDescRow = new HBox();
        rootDescRow.horizontalSpacing = 6;
        uiRootDetail = new Label();
        uiRootDetail.text = "天赋:" + cult.talent + "  气运:" + cult.luck;
        uiRootDetail.styleString = "font-size:12px;color:#aaaaff;";
        uiRootDetail.width = 400;
        rootDescRow.addComponent(uiRootDetail);
        topBar.addComponent(rootDescRow);

        // HP/MP/EXP bars
        var hpRow = new HBox();
        hpRow.horizontalSpacing = 6;
        var hpText = new Label(); hpText.text = "气血"; hpText.styleString = "font-size:13px;color:#ff6666;width:35px;";
        hpRow.addComponent(hpText);
        uiHpBar = new HorizontalProgress(); uiHpBar.width = 220; uiHpBar.height = 16; uiHpBar.min = 0; uiHpBar.max = cult.maxHp; uiHpBar.pos = cult.hp;
        uiHpBar.styleString = "background-color:#330000;border-color:#660000;";
        hpRow.addComponent(uiHpBar);
        uiHpNum = new Label(); uiHpNum.text = Std.string(cult.hp) + "/" + Std.string(cult.maxHp); uiHpNum.styleString = "font-size:12px;color:#ffaaaa;"; uiHpNum.width = 100;
        hpRow.addComponent(uiHpNum);
        topBar.addComponent(hpRow);

        var mpRow = new HBox();
        mpRow.horizontalSpacing = 6;
        var mpText = new Label(); mpText.text = "灵力"; mpText.styleString = "font-size:13px;color:#66aaff;width:35px;";
        mpRow.addComponent(mpText);
        uiMpBar = new HorizontalProgress(); uiMpBar.width = 220; uiMpBar.height = 16; uiMpBar.min = 0; uiMpBar.max = cult.maxMp; uiMpBar.pos = cult.mp;
        uiMpBar.styleString = "background-color:#000033;border-color:#000066;";
        mpRow.addComponent(uiMpBar);
        uiMpNum = new Label(); uiMpNum.text = Std.string(cult.mp) + "/" + Std.string(cult.maxMp); uiMpNum.styleString = "font-size:12px;color:#aaccff;"; uiMpNum.width = 100;
        mpRow.addComponent(uiMpNum);
        topBar.addComponent(mpRow);

        var expRow = new HBox();
        expRow.horizontalSpacing = 6;
        var expText = new Label(); expText.text = "修为"; expText.styleString = "font-size:13px;color:#88ff88;width:35px;";
        expRow.addComponent(expText);
        uiExpBar = new HorizontalProgress(); uiExpBar.width = 220; uiExpBar.height = 12; uiExpBar.min = 0; uiExpBar.max = cult.expToNext; uiExpBar.pos = cult.exp;
        uiExpBar.styleString = "background-color:#003300;border-color:#006600;";
        expRow.addComponent(uiExpBar);
        uiExpLabel = new Label(); uiExpLabel.text = "0/100"; uiExpLabel.styleString = "font-size:12px;color:#88ff88;"; uiExpLabel.width = 100;
        expRow.addComponent(uiExpLabel);
        topBar.addComponent(expRow);

        Screen.instance.addComponent(topBar);

        // === 世界信息面板(右上) ===
        var worldPanel = new VBox();
        worldPanel.verticalSpacing = 2;
        worldPanel.paddingRight = 8;
        worldPanel.paddingTop = 8;
        worldPanel.left = width - 280;
        worldPanel.top = 0;
        worldPanel.width = 270;

        var worldTitle = new Label();
        worldTitle.text = "--- 天道纪元 ---";
        worldTitle.styleString = "font-size:14px;color:#ffaa00;font-weight:bold;";
        worldPanel.addComponent(worldTitle);

        uiWorldInfo = new Label();
        uiWorldInfo.text = "第1年 第1日\n灵气浓度: 1.0\n修仙者: 6\n宗门: 8";
        uiWorldInfo.styleString = "font-size:12px;color:#ccccaa;";
        uiWorldInfo.width = 260;
        worldPanel.addComponent(uiWorldInfo);

        var logTitle = new Label();
        logTitle.text = "--- 天道日志 ---";
        logTitle.styleString = "font-size:13px;color:#ffaa00;";
        worldPanel.addComponent(logTitle);

        uiEventLog = new Label();
        uiEventLog.text = "";
        uiEventLog.styleString = "font-size:11px;color:#999999;";
        uiEventLog.width = 260;
        worldPanel.addComponent(uiEventLog);

        Screen.instance.addComponent(worldPanel);

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

        var fmtTitle = new Label(); fmtTitle.text = "-- 阵法 --"; fmtTitle.styleString = "font-size:13px;color:#ffaa00;";
        formationBar.addComponent(fmtTitle);

        for (f in formationDefs) {
            var btn = new Button();
            btn.text = f.key + " " + f.name;
            btn.width = 72; btn.height = 30;
            btn.styleString = "font-size:11px;background-color:#2a1a0a;border-color:#aa6600;color:#ffcc88;";
            var fid = f.id;
            btn.onClick = function(_) { castFormation(fid); };
            uiFormationButtons.push(btn);
            formationBar.addComponent(btn);
        }
        Screen.instance.addComponent(formationBar);

        // === 提示 ===
        uiInfo = new Label();
        uiInfo.text = "WASD移动 | Q-P法术 | 1-5阵法\n世界自运转中...";
        uiInfo.styleString = "font-size:12px;color:#888888;";
        uiInfo.left = width - 210;
        uiInfo.top = height - 80;
        uiInfo.width = 200;
        Screen.instance.addComponent(uiInfo);
    }

    function createSkillButton(s:{key:String, name:String, skill:String, cd:Float, mpCost:Int}):Button {
        var btn = new Button();
        btn.text = s.name;
        btn.width = 72; btn.height = 42;
        btn.styleString = "font-size:11px;background-color:#1a1a3a;border-color:#4a4aaa;color:#ddddff;";
        var skillId = s.skill;
        var mpCost = s.mpCost;
        var cdTime = s.cd;
        btn.onClick = function(_) { castSpell(skillId, mpCost, cdTime); };
        return btn;
    }

    // ============================================================
    //  玩家法术: 通过 PlayerCommand 提交给世界引擎
    // ============================================================
    public function castSpell(skillId:String, mpCost:Int, cdTime:Float) {
        var cdKey = skillId;
        if (cooldowns.exists(cdKey) && cooldowns[cdKey] > 0) return;

        var cult = playerEntity.get(CultivationComp);
        if (cult.mp < mpCost) { flashInfo("灵力不足!"); return; }

        cult.mp -= mpCost;
        cooldowns[cdKey] = cdTime;

        var pos = playerEntity.get(PositionComp);
        var mx = camMouseX;
        var my = camMouseY;

        // 法术特效仍然在渲染层执行
        switch (skillId) {
            case "fireball": SpellSystem.castFireball(pos.x, pos.y, mx, my, fxLayer, this);
            case "thunder": SpellSystem.castThunder(pos.x, pos.y, mx, my, fxLayer, this);
            case "ice": SpellSystem.castIce(pos.x, pos.y, mx, my, fxLayer, this);
            case "swordqi": SpellSystem.castSwordQi(pos.x, pos.y, mx, my, fxLayer, this);
            case "thunderstorm": SpellSystem.castThunderstorm(mx, my, fxLayer, this);
            case "pocket": SpellSystem.castPocketDimension(pos.x, pos.y, mx, my, fxLayer, this);
            case "lotus": SpellSystem.castLotusBloom(pos.x, pos.y, mx, my, fxLayer, this);
            case "bigdipper": SpellSystem.castBigDipper(pos.x, pos.y, mx, my, fxLayer, this);
            case "clone": SpellSystem.castShadowClone(pos.x, pos.y, mx, my, fxLayer, this);
            case "voidshift": SpellSystem.castVoidShift(pos.x, pos.y, mx, my, fxLayer, this);
        }

        // 查找法术范围内的敌人实体, 对其造成伤害
        var spellDmg = getSpellBaseDamage(skillId);
        for (e in engine.entities) {
            if (!e.alive || e.isPlayer) continue;
            var ePos = e.get(PositionComp);
            var eCult = e.get(CultivationComp);
            if (ePos == null || eCult == null) continue;
            var dx = ePos.x - mx;
            var dy = ePos.y - my;
            if (dx * dx + dy * dy < 100 * 100) {
                var mult = cult.getSpellMultiplier(skillId);
                var dmg = Math.round(spellDmg * mult);
                eCult.hp -= dmg;
                spawnDamageNumber(ePos.x, ePos.y - 20, dmg, 0xffdd44);

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

        // === 驱动世界引擎 ===
        engine.update(dt);

        // === 同步渲染: 遍历世界实体, 更新对应的渲染对象 ===
        syncRender();

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

        if (breakthroughFlash > 0) {
            breakthroughFlash -= dt * 2;
            if (breakthroughFlash < 0) breakthroughFlash = 0;
        }

        // 灵力恢复
        var cult = playerEntity.get(CultivationComp);
        cult.mp = Math.min(cult.maxMp, cult.mp + 15 * dt);

        updateUI(dt);
        updateSkillCooldowns();

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

            // 同步位置
            c.x = pos.x;
            c.y = pos.y;

            // 同步 HP
            var ratio = Math.max(0, cult.hp / cult.maxHp);
            c.updateHpBar(ratio);

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
            }
        }
    }

    function handleInput(dt:Float) {
        var pos = playerEntity.get(PositionComp);
        if (pos == null) return;
        var speed = 350; // pixels per second

        // 玩家移动: 直接更新位置(实时响应, 不等 tick)
        pos.vx = 0;
        pos.vy = 0;
        if (Key.isDown(Key.W) || Key.isDown(Key.UP)) pos.vy -= speed;
        if (Key.isDown(Key.S) || Key.isDown(Key.DOWN)) pos.vy += speed;
        if (Key.isDown(Key.A) || Key.isDown(Key.LEFT)) pos.vx -= speed;
        if (Key.isDown(Key.D) || Key.isDown(Key.RIGHT)) pos.vx += speed;
        pos.x += pos.vx * dt;
        pos.y += pos.vy * dt;
        // 玩家限制在世界边界内
        pos.x = Math.clamp(pos.x, 30, engine.worldWidth - 30);
        pos.y = Math.clamp(pos.y, 30, engine.worldHeight - 30);

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
        if (Key.isPressed(Key.MOUSE_LEFT)) castSpell("thunder", 50, 2.0);
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
            uiWorldInfo.text = "第" + snap.worldYear + "年 第" + snap.worldDay + "日\n" +
                "灵气浓度: " + Std.string(snap.globalSpiritDensity).substr(0, 4) + "\n" +
                "修仙者: " + snap.aliveCount + "\n" +
                "宗门: " + snap.factionCount;
        }

        // 事件日志(最近5条)
        var logText = "";
        var recent = engine.eventLog.slice(-5);
        for (ev in recent) {
            logText += ev.desc + "\n";
        }
        uiEventLog.text = logText;
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
