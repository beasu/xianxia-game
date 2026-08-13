import h2d.Object;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Graphics;
import h2d.Text;
import h2d.filter.Glow;
import hxd.Math;
import ecs.Components.PositionComp;
import ecs.Components.CultivationComp;
import ecs.Entity.Entity;

/**
    Cultivator - 修仙者(玩家/敌人)
    包含: 角色渲染、血条、状态、移动、境界系统、灵根系统
**/
class Cultivator extends Object {
    public var charName:String;
    public var realm:String;
    public var realmIndex:Int = 0;
    public var isPlayer:Bool = false;
    public var dead:Bool = false;
    public var enemyType:String = "moxiu"; // moxiu, yaoshou, mojiang, xiexian

    public var hp:Float;
    public var maxHp:Float;
    public var mp:Float;
    public var maxMp:Float;
    public var attackPower:Int;
    public var exp:Float = 0;
    public var expToNext:Float = 100;

    // ========== 灵根系统 ==========
    // 灵根类型: 金木水火土五行 + 变异灵根(雷/冰/暗)
    public var spiritRoot:String = "fire";  // fire/water/wood/metal/earth/thunder/ice/dark
    public var spiritRootName:String = "火灵根";
    public var spiritRootQuality:Int = 0;   // 0=凡品 1=良品 2=上品 3=极品 4=天灵根
    public var spiritRootQualityName:String = "凡品";

    // 灵根定义表
    public static var spiritRootDefs = [
        {id: "fire",    name: "火灵根",   color: 0xff4400, element: "火",
         dmgBonus: ["fireball" => 1.5, "thunderstorm" => 1.3, "lotus" => 1.2],
         desc: "火系法术伤害+50%"},
        {id: "water",   name: "水灵根",   color: 0x0066ff, element: "水",
         dmgBonus: ["ice" => 1.5, "lotus" => 1.3],
         desc: "冰系法术伤害+50%"},
        {id: "wood",    name: "木灵根",   color: 0x22aa44, element: "木",
         dmgBonus: ["lotus" => 1.6, "clone" => 1.3],
         desc: "治疗/分身强化+60%"},
        {id: "metal",   name: "金灵根",   color: 0xddaa00, element: "金",
         dmgBonus: ["swordqi" => 1.6, "thunder" => 1.2],
         desc: "剑系法术伤害+60%"},
        {id: "earth",   name: "土灵根",   color: 0x886644, element: "土",
         dmgBonus: ["pocket" => 1.5, "voidshift" => 1.3],
         desc: "空间法术伤害+50%"},
        {id: "thunder", name: "雷灵根",   color: 0xcc88ff, element: "雷",
         dmgBonus: ["thunder" => 1.6, "thunderstorm" => 1.4, "bigdipper" => 1.2],
         desc: "雷系法术伤害+60%"},
        {id: "ice",     name: "冰灵根",   color: 0x88ddff, element: "冰",
         dmgBonus: ["ice" => 1.6, "thunderstorm" => 1.2],
         desc: "冰系法术伤害+60%"},
        {id: "dark",    name: "暗灵根",   color: 0x8800ff, element: "暗",
         dmgBonus: ["pocket" => 1.4, "voidshift" => 1.4, "clone" => 1.3],
         desc: "空间/暗系法术+40%"}
    ];

    // 灵根品质定义
    public static var qualityDefs = [
        {name: "凡品",   expMult: 1.0,  statMult: 1.0,  color: 0x888888},
        {name: "良品",   expMult: 1.3,  statMult: 1.15, color: 0x66ccff},
        {name: "上品",   expMult: 1.6,  statMult: 1.3,  color: 0xaa44ff},
        {name: "极品",   expMult: 2.0,  statMult: 1.5,  color: 0xffaa00},
        {name: "天灵根", expMult: 3.0,  statMult: 2.0,  color: 0xff3333}
    ];

    // 获取灵根颜色
    public function getRootColor():Int {
        for (d in spiritRootDefs) {
            if (d.id == spiritRoot) return d.color;
        }
        return 0xff4400;
    }

    // 获取法术伤害倍率(基于灵根)
    public function getSpellMultiplier(spellId:String):Float {
        for (d in spiritRootDefs) {
            if (d.id == spiritRoot) {
                if (d.dmgBonus.exists(spellId)) {
                    var base = d.dmgBonus[spellId];
                    // 品质额外加成
                    var qMult = 1.0 + spiritRootQuality * 0.1;
                    return base * qMult;
                }
                break;
            }
        }
        return 1.0;
    }

    // 获取经验倍率(基于灵根品质)
    public function getExpMult():Float {
        return qualityDefs[spiritRootQuality].expMult;
    }

    // 获取灵根全称
    public function getRootFullName():String {
        return spiritRootName + "·" + spiritRootQualityName;
    }

    // 随机分配灵根(用于敌人或玩家初始)
    public function randomSpiritRoot() {
        var roll = Math.random(100);
        if (roll < 30) spiritRoot = "fire";
        else if (roll < 50) spiritRoot = "water";
        else if (roll < 65) spiritRoot = "wood";
        else if (roll < 78) spiritRoot = "metal";
        else if (roll < 88) spiritRoot = "earth";
        else if (roll < 94) spiritRoot = "thunder";
        else if (roll < 98) spiritRoot = "ice";
        else spiritRoot = "dark";

        updateSpiritRootName();

        // 品质随机(敌人用)
        var qRoll = Math.random(100);
        if (qRoll < 50) spiritRootQuality = 0;
        else if (qRoll < 78) spiritRootQuality = 1;
        else if (qRoll < 92) spiritRootQuality = 2;
        else if (qRoll < 98) spiritRootQuality = 3;
        else spiritRootQuality = 4;
        spiritRootQualityName = qualityDefs[spiritRootQuality].name;
    }

    function updateSpiritRootName() {
        for (d in spiritRootDefs) {
            if (d.id == spiritRoot) {
                spiritRootName = d.name;
                return;
            }
        }
        spiritRootName = "火灵根";
    }

    public var vx:Float = 0;
    public var vy:Float = 0;

    public var attackTimer:Float = 1.0;
    public var hitFlash:Float = 0;

    public var body:Graphics;
    var aura:Graphics;
    var robe:Graphics;      // 飘动外袍层
    var hair:Graphics;      // 飘动长发层
    var hpBarBg:Bitmap;
    var hpBarFill:Bitmap;
    public var nameText:Text;

    // === 物理状态视觉层 ===
    public var statusLayer:Graphics;      // 状态效果层(冰冻/燃烧/眩晕)
    public var shieldLayer:Graphics;      // 护体灵光层
    public var pressureLayer:Graphics;    // 灵压可视化层
    public var resonanceLayer:Graphics;   // 元素共振光环层
    public var flightLayer:Graphics;      // 御剑飞行光环层
    public var nightGlowLayer:Graphics;   // 夜间灵力辉光层

    // 物理状态值(由 GameScene.syncRender 每帧同步)
    public var physFrozen:Float = 0;
    public var physBurn:Float = 0;
    public var physStun:Float = 0;
    public var physSlow:Float = 0;
    public var physSlowFactor:Float = 1.0;
    public var physShieldActive:Bool = false;
    public var physShieldStrength:Float = 0;
    public var physShieldMax:Float = 0;
    public var physIsFlying:Bool = false;
    public var physPressure:Float = 0;
    public var physResonanceStrength:Float = 0;
    public var physResonanceBonus:Float = 1.0;
    public var physResonanceColor:Int = 0xffffff;
    public var nightDarkness:Float = 0;       // 当前夜晚暗度(由GameScene同步)

    var animTime:Float = 0;
    var facingRight:Bool = true;

    // 整体缩放 - 让角色大小适中
    var charScale:Float = 1.2;

    // 境界列表
    public static var realmList = [
        {name: "练气期", color: 0x66aa66},
        {name: "筑基期", color: 0x66aaff},
        {name: "金丹期", color: 0xffaa00},
        {name: "元婴期", color: 0xff66ff},
        {name: "化神期", color: 0xff3333}
    ];

    public function new(parent:Object) {
        super(parent);
        initVisual();
    }

    function initVisual() {
        aura = new Graphics(this);
        robe = new Graphics(this);   // 外袍层(在身体下方)
        hair = new Graphics(this);   // 头发层(在身体上方)
        body = new Graphics(this);

        // 物理状态视觉层(在身体上方)
        pressureLayer = new Graphics(this);
        resonanceLayer = new Graphics(this);
        shieldLayer = new Graphics(this);
        flightLayer = new Graphics(this);
        statusLayer = new Graphics(this);
        nightGlowLayer = new Graphics(this);

        var bgTile = Tile.fromColor(0x000000, 80, 6);
        hpBarBg = new Bitmap(bgTile, this);
        hpBarBg.x = -40;
        hpBarBg.y = -70;
        hpBarBg.alpha = 0.7;
        hpBarBg.scaleX = charScale;

        var fillTile = Tile.fromColor(0xff3333, 80, 6);
        hpBarFill = new Bitmap(fillTile, this);
        hpBarFill.x = -40;
        hpBarFill.y = -70;
        hpBarFill.scaleX = charScale;

        nameText = new Text(Main.cjkFont, this);
        nameText.text = charName != null ? charName : "";
        nameText.x = -50;
        nameText.y = -85;
        nameText.textColor = isPlayer ? 0xFFD700 : 0xff6666;
        nameText.scaleX = charScale * 0.8;
        nameText.scaleY = charScale * 0.8;
        nameText.visible = !isPlayer;

        redraw();
    }

    function drawPolyShape(g:Graphics, points:Array<Float>) {
        if (points.length < 6) return;
        g.moveTo(points[0], points[1]);
        var i = 2;
        while (i < points.length) {
            g.lineTo(points[i], points[i + 1]);
            i += 2;
        }
        g.lineTo(points[0], points[1]);
    }

    public function redraw() {
        body.clear();
        aura.clear();
        if (robe != null) robe.clear();
        if (hair != null) hair.clear();

        if (isPlayer) {
            drawPlayer();
        } else {
            switch (enemyType) {
                case "yaoshou": drawYaoshou();
                case "mojiang": drawMojiang();
                case "xiexian": drawXiexian();
                default: drawMoxiu();
            }
        }
    }

    // 辅助: 多层半透明圆叠加(模拟光晕渐变)
    function drawGlowCircle(g:Graphics, x:Float, y:Float, radius:Float, color:Int, layers:Int = 4) {
        var r = (color >> 16) & 0xff;
        var gn = (color >> 8) & 0xff;
        var b = color & 0xff;
        for (i in 0...layers) {
            var t = i / layers;
            var alpha = (1.0 - t) * 0.25;
            var rr = radius * (1.0 + t * 0.5);
            g.beginFill(color, alpha);
            g.drawCircle(x, y, rr);
            g.endFill();
        }
    }

    // 辅助: 绘制飘逸衣袍(多段曲线模拟丝绸质感)
    function drawFlowingRobe(g:Graphics, cx:Float, cy:Float, width:Float, length:Float, baseColor:Int, accentColor:Int, wave:Float) {
        var halfW = width * 0.5;
        var waveAmt = halfW * 0.3 * wave;

        // 外层(深色阴影)
        g.beginFill(baseColor, 0.8);
        g.moveTo(cx - halfW - waveAmt, cy);
        // 右下飘
        g.lineTo(cx - halfW * 0.7 + waveAmt, cy + length);
        g.lineTo(cx + halfW * 0.7 - waveAmt, cy + length);
        g.lineTo(cx + halfW + waveAmt, cy);
        g.lineTo(cx + halfW * 0.5, cy - 2);
        g.lineTo(cx - halfW * 0.5, cy - 2);
        g.lineTo(cx - halfW - waveAmt, cy);
        g.endFill();

        // 中层(亮色丝绸)
        g.beginFill(accentColor, 0.4);
        g.moveTo(cx - halfW * 0.7 + waveAmt * 0.5, cy);
        g.lineTo(cx - halfW * 0.5 + waveAmt, cy + length * 0.9);
        g.lineTo(cx + halfW * 0.5 - waveAmt, cy + length * 0.9);
        g.lineTo(cx + halfW * 0.7 - waveAmt * 0.5, cy);
        g.endFill();

        // 衣褶高光线
        g.lineStyle(1, accentColor, 0.3);
        g.moveTo(cx - halfW * 0.3, cy + 2);
        g.lineTo(cx - halfW * 0.2 + waveAmt * 0.5, cy + length * 0.8);
        g.moveTo(cx, cy + 2);
        g.lineTo(cx + waveAmt * 0.3, cy + length * 0.8);
        g.moveTo(cx + halfW * 0.3, cy + 2);
        g.lineTo(cx + halfW * 0.2 - waveAmt * 0.5, cy + length * 0.8);
        g.lineStyle();
    }

    // ========== 玩家: 仙人道袍 ==========
    function drawPlayer() {
        var realmColor = realmList[realmIndex].color;
        var rootColor = getRootColor();
        var s = charScale;  // 缩放系数

        // ===== 灵根光环(多层渐变模拟光晕) =====
        var auraSize = 50 + spiritRootQuality * 8;
        drawGlowCircle(aura, 0, 0, auraSize, rootColor, 6);
        drawGlowCircle(aura, 0, 0, auraSize * 0.5, rootColor, 3);

        // 天灵根: 额外外层光环
        if (spiritRootQuality >= 4) {
            drawGlowCircle(aura, 0, 0, auraSize * 1.5, rootColor, 4);
        }

        // 境界>=金丹: 灵力流转环
        if (realmIndex >= 2) {
            aura.lineStyle(1, realmColor, 0.15);
            for (i in 0...3) {
                var r = 55 + i * 8;
                aura.drawCircle(0, 0, r);
            }
            aura.lineStyle();
        }

        // ===== 飘动外袍(丝绸质感) =====
        var wave = Math.sin(animTime * 2);
        // 深色外层
        drawFlowingRobe(robe, 0, -5 * s, 24 * s, 30 * s, 0x1a2a5a, 0x3a5aaa, wave);
        // 内衬亮色
        drawFlowingRobe(robe, 0, -3 * s, 16 * s, 24 * s, 0x2a4a8a, 0x6a8add, wave * 0.7);

        // 腰带(灵根色+金边)
        body.beginFill(rootColor, 0.9);
        body.drawRect(-10 * s, 3 * s, 20 * s, 4 * s);
        body.endFill();
        body.beginFill(0xffd700, 0.5);
        body.drawRect(-10 * s, 6 * s, 20 * s, 1 * s);
        body.endFill();
        // 腰间玉佩
        body.beginFill(0x66ddaa, 0.8);
        body.drawCircle(8 * s, 10 * s, 3 * s);
        body.endFill();
        body.beginFill(0x88ffcc, 0.5);
        body.drawCircle(8 * s, 10 * s, 2 * s);
        body.endFill();

        // ===== 内衣/上半身 =====
        body.beginFill(0xe8e8ff, 0.9);
        drawPolyShape(body, [-7 * s, -8 * s, -5 * s, 4 * s, 5 * s, 4 * s, 7 * s, -8 * s, 5 * s, -16 * s, -5 * s, -16 * s]);
        body.endFill();
        // 领口V字
        body.beginFill(0x2a4a8a, 0.8);
        drawPolyShape(body, [-4 * s, -16 * s, 0, -8 * s, 4 * s, -16 * s, 2 * s, -14 * s, -2 * s, -14 * s]);
        body.endFill();

        // 胸口灵根印记(多层光晕)
        drawGlowCircle(body, 0, -2 * s, 5 * s, rootColor, 3);
        body.beginFill(0xffffff, 0.8);
        body.drawCircle(0, -2 * s, 1.5 * s);
        body.endFill();

        // ===== 手臂(道袍袖口飘逸) =====
        var armWave = Math.sin(animTime * 2 + 1) * 3;
        body.beginFill(0x2a4a8a, 0.85);
        drawPolyShape(body, [
            -7 * s, -10 * s, -14 * s, -6 * s + armWave, -16 * s, 2 * s + armWave, -12 * s, 4 * s, -7 * s, 0 * s
        ]);
        body.endFill();
        body.beginFill(0x2a4a8a, 0.85);
        drawPolyShape(body, [
            7 * s, -10 * s, 14 * s, -6 * s - armWave, 16 * s, 2 * s - armWave, 12 * s, 4 * s, 7 * s, 0 * s
        ]);
        body.endFill();
        // 袖口金边
        body.beginFill(0xffd700, 0.4);
        body.drawCircle(-13 * s, 2 * s + armWave, 3 * s);
        body.drawCircle(13 * s, 2 * s - armWave, 3 * s);
        body.endFill();

        // ===== 头部(肤色渐变) =====
        drawGlowCircle(body, 0, -22 * s, 10 * s, 0xffe0c0, 3);
        body.beginFill(0xffe0c0, 0.9);
        body.drawCircle(0, -22 * s, 8 * s);
        body.endFill();
        // 面部阴影
        body.beginFill(0xddc0a0, 0.3);
        body.drawCircle(2 * s, -20 * s, 5 * s);
        body.endFill();

        // ===== 长发(飘逸, 多层) =====
        var hairWave = Math.sin(animTime * 1.5) * 4;
        // 后方长发(最深层)
        hair.beginFill(0x0a0a1a, 0.9);
        hair.moveTo(-6 * s, -28 * s);
        hair.lineTo(-12 * s + hairWave, -30 * s);
        hair.lineTo(-14 * s + hairWave, -10 * s);
        hair.lineTo(-10 * s, 0 * s);
        hair.lineTo(-4 * s, -16 * s);
        hair.endFill();
        hair.beginFill(0x0a0a1a, 0.9);
        hair.moveTo(6 * s, -28 * s);
        hair.lineTo(12 * s - hairWave, -30 * s);
        hair.lineTo(14 * s - hairWave, -10 * s);
        hair.lineTo(10 * s, 0 * s);
        hair.lineTo(4 * s, -16 * s);
        hair.endFill();
        // 头顶发髻
        hair.beginFill(0x0a0a1a, 0.95);
        hair.drawCircle(0, -30 * s, 8 * s);
        hair.endFill();
        // 发饰金环
        hair.beginFill(0xffd700, 0.6);
        hair.drawCircle(0, -30 * s, 9 * s);
        hair.endFill();
        hair.beginFill(0x0a0a1a, 0.95);
        hair.drawCircle(0, -30 * s, 7 * s);
        hair.endFill();
        // 发簪(灵根色)
        hair.beginFill(rootColor, 0.9);
        hair.drawRect(-1 * s, -34 * s, 2 * s, 6 * s);
        hair.endFill();
        drawGlowCircle(hair, 0, -34 * s, 3 * s, rootColor, 2);

        // ===== 面部细节 =====
        // 眉毛
        body.lineStyle(1.5, 0x222222, 0.8);
        body.moveTo(-5 * s, -24 * s);
        body.lineTo(-2 * s, -25 * s);
        body.moveTo(5 * s, -24 * s);
        body.lineTo(2 * s, -25 * s);
        body.lineStyle();
        // 眼睛
        body.beginFill(0x000000, 0.9);
        body.drawCircle(-3.5 * s, -22 * s, 1.2 * s);
        body.drawCircle(3.5 * s, -22 * s, 1.2 * s);
        body.endFill();
        // 眼中灵光(灵根色)
        body.beginFill(rootColor, 0.7);
        body.drawCircle(-3.5 * s, -22 * s, 0.5 * s);
        body.drawCircle(3.5 * s, -22 * s, 0.5 * s);
        body.endFill();
        // 嘴
        body.lineStyle(1, 0x884444, 0.6);
        body.moveTo(-2 * s, -18 * s);
        body.lineTo(2 * s, -18 * s);
        body.lineStyle();

        // ===== 法印发光球(灵根色) =====
        var orbSize = (5 + spiritRootQuality * 1.5) * s;
        drawGlowCircle(body, 16 * s, 0, orbSize, rootColor, 4);
        body.beginFill(0xffffff, 0.6);
        body.drawCircle(16 * s, 0, orbSize * 0.4);
        body.endFill();

        // ===== 品质特效 =====
        // 上品以上: 灵根纹路环绕
        if (spiritRootQuality >= 2) {
            aura.beginFill(rootColor, 0.2);
            for (i in 0...12) {
                var a = (i / 12) * Math.PI * 2 + animTime * 0.5;
                var r = 40 * s;
                aura.drawCircle(Math.cos(a) * r, Math.sin(a) * r, 2 * s);
            }
            aura.endFill();
        }

        // 天灵根: 五行符文环
        if (spiritRootQuality >= 4) {
            aura.beginFill(rootColor, 0.15);
            for (i in 0...5) {
                var a = (i / 5) * Math.PI * 2 - Math.PI / 2 + animTime * 0.3;
                var r = 55 * s;
                aura.drawCircle(Math.cos(a) * r, Math.sin(a) * r, 4 * s);
            }
            aura.endFill();
        }

        // 化神期: 背后灵纹法阵
        if (realmIndex >= 3) {
            aura.lineStyle(1, realmColor, 0.2);
            for (i in 0...8) {
                var a = (i / 8) * Math.PI * 2 + animTime * 0.2;
                aura.moveTo(0, 0);
                aura.lineTo(Math.cos(a) * 35 * s, Math.sin(a) * 35 * s);
            }
            aura.lineStyle();
            aura.drawCircle(0, 0, 35 * s);
        }
    }

    // ========== 魔修 (基础敌人) ==========
    function drawMoxiu() {
        var s = charScale * 0.85;
        drawGlowCircle(aura, 0, 0, 40, 0x660066, 4);

        // 飘动魔袍
        var wave = Math.sin(animTime * 1.5) * 0.5;
        drawFlowingRobe(robe, 0, -3 * s, 20 * s, 28 * s, 0x2a0a1a, 0x4a1a2a, wave);

        // 上半身
        body.beginFill(0x4a2020, 0.9);
        drawPolyShape(body, [-7 * s, -6 * s, -5 * s, 6 * s, 5 * s, 6 * s, 7 * s, -6 * s, 5 * s, -14 * s, -5 * s, -14 * s]);
        body.endFill();

        // 头(苍白)
        drawGlowCircle(body, 0, -20 * s, 10 * s, 0xc0a0a0, 3);
        body.beginFill(0xc0a0a0, 0.9);
        body.drawCircle(0, -20 * s, 7 * s);
        body.endFill();

        // 兜帽(深色多层)
        body.beginFill(0x1a0505, 0.95);
        drawPolyShape(body, [-9 * s, -10 * s, -11 * s, -22 * s, -7 * s, -28 * s, 0, -30 * s, 7 * s, -28 * s, 11 * s, -22 * s, 9 * s, -10 * s]);
        body.endFill();
        body.beginFill(0x3a0a0a, 0.5);
        drawPolyShape(body, [-7 * s, -14 * s, -8 * s, -24 * s, 0, -28 * s, 8 * s, -24 * s, 7 * s, -14 * s]);
        body.endFill();

        // 红眼(发光)
        drawGlowCircle(body, -3.5 * s, -20 * s, 3 * s, 0xff0000, 3);
        drawGlowCircle(body, 3.5 * s, -20 * s, 3 * s, 0xff0000, 3);
        body.beginFill(0xff0000, 1);
        body.drawCircle(-3.5 * s, -20 * s, 1.5 * s);
        body.drawCircle(3.5 * s, -20 * s, 1.5 * s);
        body.endFill();

        // 魔气(环绕粒子)
        body.beginFill(0x880088, 0.3);
        body.drawCircle(-16 * s, 0, 5 * s);
        body.drawCircle(16 * s, 0, 5 * s);
        body.endFill();
    }

    // ========== 妖兽 (四足野兽型) ==========
    function drawYaoshou() {
        var s = charScale * 1.0;
        drawGlowCircle(aura, 0, 0, 45, 0x664400, 4);

        // 兽身(多层毛发质感)
        body.beginFill(0x3a2810, 0.9);
        drawPolyShape(body, [-18 * s, 6 * s, -16 * s, 18 * s, 16 * s, 18 * s, 18 * s, 6 * s, 14 * s, -4 * s, -14 * s, -4 * s]);
        body.endFill();
        body.beginFill(0x5a4030, 0.4);
        drawPolyShape(body, [-14 * s, 2 * s, -12 * s, 16 * s, 12 * s, 16 * s, 14 * s, 2 * s, 10 * s, -2 * s, -10 * s, -2 * s]);
        body.endFill();

        // 毛纹
        body.beginFill(0x6a5040, 0.3);
        for (i in 0...4) {
            body.drawRect(-12 * s + i * 6 * s, 0, 3 * s, 2 * s);
            body.drawRect(-10 * s + i * 6 * s, 6 * s, 3 * s, 2 * s);
        }
        body.endFill();

        // 兽腿
        body.beginFill(0x2a1808, 0.95);
        body.drawRect(-14 * s, 16 * s, 5 * s, 8 * s);
        body.drawRect(9 * s, 16 * s, 5 * s, 8 * s);
        body.drawRect(-10 * s, 16 * s, 4 * s, 6 * s);
        body.drawRect(6 * s, 16 * s, 4 * s, 6 * s);
        body.endFill();
        // 爪子
        body.beginFill(0x1a0a00, 1);
        body.drawCircle(-11 * s, 24 * s, 2.5 * s);
        body.drawCircle(11 * s, 24 * s, 2.5 * s);
        body.endFill();

        // 兽头(渐变)
        drawGlowCircle(body, 0, -14 * s, 14 * s, 0x5a4030, 3);
        body.beginFill(0x5a4030, 0.95);
        body.drawCircle(0, -14 * s, 10 * s);
        body.endFill();

        // 兽耳(尖耳)
        body.beginFill(0x4a3320, 0.9);
        drawPolyShape(body, [-9 * s, -22 * s, -12 * s, -30 * s, -5 * s, -24 * s]);
        body.endFill();
        body.beginFill(0x4a3320, 0.9);
        drawPolyShape(body, [9 * s, -22 * s, 12 * s, -30 * s, 5 * s, -24 * s]);
        body.endFill();
        // 耳内
        body.beginFill(0x884400, 0.4);
        drawPolyShape(body, [-9 * s, -22 * s, -10 * s, -27 * s, -6 * s, -23 * s]);
        body.endFill();
        body.beginFill(0x884400, 0.4);
        drawPolyShape(body, [9 * s, -22 * s, 10 * s, -27 * s, 6 * s, -23 * s]);
        body.endFill();

        // 獠牙(发光)
        body.beginFill(0xffffff, 0.95);
        drawPolyShape(body, [-4 * s, -8 * s, -2 * s, -2 * s, -1 * s, -8 * s]);
        body.endFill();
        body.beginFill(0xffffff, 0.95);
        drawPolyShape(body, [4 * s, -8 * s, 2 * s, -2 * s, 1 * s, -8 * s]);
        body.endFill();

        // 兽眼(金色发光)
        drawGlowCircle(body, -5 * s, -14 * s, 4 * s, 0xffaa00, 3);
        drawGlowCircle(body, 5 * s, -14 * s, 4 * s, 0xffaa00, 3);
        body.beginFill(0xffaa00, 1);
        body.drawCircle(-5 * s, -14 * s, 2.5 * s);
        body.drawCircle(5 * s, -14 * s, 2.5 * s);
        body.endFill();
        body.beginFill(0x000000, 0.9);
        body.drawCircle(-5 * s, -14 * s, 1 * s);
        body.drawCircle(5 * s, -14 * s, 1 * s);
        body.endFill();

        // 额头兽纹(发光)
        body.beginFill(0x884400, 0.7);
        body.drawRect(-1 * s, -24 * s, 2 * s, 6 * s);
        body.endFill();
        drawGlowCircle(body, 0, -24 * s, 3 * s, 0xff6600, 2);
    }

    // ========== 魔将 (大型重甲型) ==========
    function drawMojiang() {
        var s = charScale * 1.1;
        drawGlowCircle(aura, 0, 0, 50, 0x880000, 5);

        // 重甲身体(多层金属质感)
        body.beginFill(0x2a0505, 0.95);
        drawPolyShape(body, [-16 * s, 10 * s, -12 * s, 26 * s, 12 * s, 26 * s, 16 * s, 10 * s, 13 * s, -6 * s, -13 * s, -6 * s]);
        body.endFill();
        body.beginFill(0x4a1010, 0.6);
        drawPolyShape(body, [-13 * s, 8 * s, -10 * s, 24 * s, 10 * s, 24 * s, 13 * s, 8 * s, 10 * s, -4 * s, -10 * s, -4 * s]);
        body.endFill();

        // 胸甲(金属反光)
        body.beginFill(0x6a2020, 0.7);
        drawPolyShape(body, [-10 * s, -6 * s, -8 * s, 8 * s, 8 * s, 8 * s, 10 * s, -6 * s, 8 * s, -14 * s, -8 * s, -14 * s]);
        body.endFill();
        body.beginFill(0x8a3030, 0.3);
        drawPolyShape(body, [-8 * s, -8 * s, -6 * s, 6 * s, 6 * s, 6 * s, 8 * s, -8 * s, 6 * s, -12 * s, -6 * s, -12 * s]);
        body.endFill();

        // 肩甲(球形+金属光泽)
        drawGlowCircle(body, -14 * s, -4 * s, 8 * s, 0x6a2a2a, 3);
        body.beginFill(0x6a2a2a, 0.9);
        body.drawCircle(-14 * s, -4 * s, 7 * s);
        body.endFill();
        body.beginFill(0xaa4444, 0.4);
        body.drawCircle(-15 * s, -5 * s, 4 * s);
        body.endFill();

        drawGlowCircle(body, 14 * s, -4 * s, 8 * s, 0x6a2a2a, 3);
        body.beginFill(0x6a2a2a, 0.9);
        body.drawCircle(14 * s, -4 * s, 7 * s);
        body.endFill();
        body.beginFill(0xaa4444, 0.4);
        body.drawCircle(13 * s, -5 * s, 4 * s);
        body.endFill();

        // 胸甲符文
        body.beginFill(0xff0000, 0.6);
        body.drawRect(-8 * s, 0, 16 * s, 2 * s);
        body.drawRect(-6 * s, 4 * s, 12 * s, 2 * s);
        body.endFill();
        drawGlowCircle(body, 0, 2 * s, 4 * s, 0xff0000, 2);

        // 头盔(多层金属)
        body.beginFill(0x3a0a0a, 0.95);
        drawPolyShape(body, [-10 * s, -14 * s, -11 * s, -26 * s, 0, -32 * s, 11 * s, -26 * s, 10 * s, -14 * s]);
        body.endFill();
        body.beginFill(0x5a1a1a, 0.5);
        drawPolyShape(body, [-8 * s, -16 * s, -9 * s, -26 * s, 0, -30 * s, 9 * s, -26 * s, 8 * s, -16 * s]);
        body.endFill();

        // 面甲缝
        body.beginFill(0x000000, 0.9);
        body.drawRect(-7 * s, -22 * s, 14 * s, 3 * s);
        body.endFill();

        // 眼缝红光(强发光)
        drawGlowCircle(body, -4 * s, -21 * s, 4 * s, 0xff0000, 4);
        drawGlowCircle(body, 4 * s, -21 * s, 4 * s, 0xff0000, 4);
        body.beginFill(0xff0000, 1);
        body.drawCircle(-4 * s, -21 * s, 2 * s);
        body.drawCircle(4 * s, -21 * s, 2 * s);
        body.endFill();

        // 头盔角(弯曲尖角)
        body.beginFill(0x1a0505, 0.95);
        drawPolyShape(body, [-10 * s, -26 * s, -16 * s, -38 * s, -12 * s, -40 * s, -6 * s, -28 * s]);
        body.endFill();
        body.beginFill(0x1a0505, 0.95);
        drawPolyShape(body, [10 * s, -26 * s, 16 * s, -38 * s, 12 * s, -40 * s, 6 * s, -28 * s]);
        body.endFill();

        // 魔气(浓烈)
        drawGlowCircle(body, -18 * s, 0, 7 * s, 0xaa0000, 3);
        drawGlowCircle(body, 18 * s, 0, 7 * s, 0xaa0000, 3);
    }

    // ========== 邪仙 (飘浮法袍型) ==========
    function drawXiexian() {
        var s = charScale * 1.0;
        drawGlowCircle(aura, 0, 0, 48, 0x006644, 4);

        // 飘逸法袍(多层)
        var wave = Math.sin(animTime * 1.8) * 0.6;
        drawFlowingRobe(robe, 0, -3 * s, 24 * s, 34 * s, 0x0a3322, 0x1a6644, wave);
        drawFlowingRobe(robe, 0, -1 * s, 16 * s, 26 * s, 0x1a5544, 0x2a8866, wave * 0.7);

        // 法袍下摆波浪边
        body.beginFill(0x1a5544, 0.5);
        for (i in 0...5) {
            var x = -10 * s + i * 5 * s;
            body.drawCircle(x, 28 * s, 3 * s);
        }
        body.endFill();

        // 上半身
        body.beginFill(0x2a6655, 0.9);
        drawPolyShape(body, [-8 * s, -6 * s, -6 * s, 6 * s, 6 * s, 6 * s, 8 * s, -6 * s, 6 * s, -14 * s, -6 * s, -14 * s]);
        body.endFill();

        // 头(苍白发绿)
        drawGlowCircle(body, 0, -22 * s, 10 * s, 0xc0e0d0, 3);
        body.beginFill(0xc0e0d0, 0.9);
        body.drawCircle(0, -22 * s, 8 * s);
        body.endFill();

        // 长发(飘逸, 深绿色)
        var hairWave = Math.sin(animTime * 1.2) * 5;
        hair.beginFill(0x0a3322, 0.9);
        hair.moveTo(-7 * s, -28 * s);
        hair.lineTo(-14 * s + hairWave, -32 * s);
        hair.lineTo(-16 * s + hairWave, -8 * s);
        hair.lineTo(-12 * s, 4 * s);
        hair.lineTo(-5 * s, -16 * s);
        hair.endFill();
        hair.beginFill(0x0a3322, 0.9);
        hair.moveTo(7 * s, -28 * s);
        hair.lineTo(14 * s - hairWave, -32 * s);
        hair.lineTo(16 * s - hairWave, -8 * s);
        hair.lineTo(12 * s, 4 * s);
        hair.lineTo(5 * s, -16 * s);
        hair.endFill();
        // 头顶
        hair.beginFill(0x0a3322, 0.95);
        hair.drawCircle(0, -30 * s, 8 * s);
        hair.endFill();

        // 邪眼(绿色强发光)
        drawGlowCircle(body, -3.5 * s, -22 * s, 4 * s, 0x00ff66, 4);
        drawGlowCircle(body, 3.5 * s, -22 * s, 4 * s, 0x00ff66, 4);
        body.beginFill(0x00ff66, 1);
        body.drawCircle(-3.5 * s, -22 * s, 1.5 * s);
        body.drawCircle(3.5 * s, -22 * s, 1.5 * s);
        body.endFill();

        // 邪气珠(多层光晕)
        drawGlowCircle(body, 18 * s, 0, 8 * s, 0x00aa44, 4);
        body.beginFill(0x00ff66, 0.8);
        body.drawCircle(18 * s, 0, 4 * s);
        body.endFill();
        body.beginFill(0xffffff, 0.5);
        body.drawCircle(18 * s, 0, 2 * s);
        body.endFill();
    }

    public function update(dt:Float) {
        animTime += dt;

        x += vx * dt;
        y += vy * dt;

        vx *= 0.85;
        vy *= 0.85;

        if (Math.abs(vx) > 5) {
            facingRight = vx > 0;
            scaleX = facingRight ? 1 : -1;
        }

        if (aura != null) {
            var pulse = 1.0 + Math.sin(animTime * 3) * 0.08;
            aura.scaleX = pulse;
            aura.scaleY = pulse;
        }

        // 外袍轻微飘动
        if (robe != null) {
            robe.scaleX = 1.0 + Math.sin(animTime * 2) * 0.03;
        }

        if (hitFlash > 0) {
            hitFlash -= dt;
            body.alpha = 0.5 + Math.sin(hitFlash * 60) * 0.5;
            if (robe != null) robe.alpha = body.alpha;
            if (hair != null) hair.alpha = body.alpha;
        } else {
            body.alpha = 1.0;
            if (robe != null) robe.alpha = 1.0;
            if (hair != null) hair.alpha = 1.0;
        }

        var ratio = Math.max(0, hp / maxHp);
        hpBarFill.scaleX = ratio * charScale;
        hpBarFill.x = -40;

        // 玩家位置由 PositionComp + handleInput 控制, 不在此处 clamp

        if (dead) {
            alpha -= dt * 2;
            if (alpha < 0) alpha = 0;
        }
    }

    // ========== 境界突破 ==========
    public function tryBreakthrough():Bool {
        if (exp >= expToNext && realmIndex < realmList.length - 1) {
            realmIndex++;
            realm = realmList[realmIndex].name;
            exp -= expToNext;
            expToNext = Std.int(expToNext * 1.5);

            // 突破增益(受灵根品质影响)
            var statMult = qualityDefs[spiritRootQuality].statMult;
            maxHp = Std.int(maxHp * 1.3 * statMult);
            hp = maxHp;
            maxMp = Std.int(maxMp * 1.3 * statMult);
            mp = maxMp;
            attackPower = Std.int(attackPower * 1.25 * statMult);

            // 突破时有概率提升灵根品质
            if (spiritRootQuality < 4 && Math.random() < 0.15) {
                spiritRootQuality++;
                spiritRootQualityName = qualityDefs[spiritRootQuality].name;
            }

            redraw();
            return true;
        }
        return false;
    }

    public function gainExp(amount:Float) {
        // 灵根品质影响经验获取
        exp += amount * getExpMult();
    }

    // ========== ECS 集成方法 ==========
    // 从 ECS 组件同步数据到渲染对象
    public function syncFromComp(pos:PositionComp, cult:CultivationComp):Void {
        // 更新境界显示
        if (realmIndex != cult.realmIndex) {
            realmIndex = cult.realmIndex;
            if (realmIndex < realmList.length) {
                realm = realmList[realmIndex].name;
            }
            redraw();
        }

        // 同步灵根
        if (spiritRoot != cult.spiritRoot || spiritRootQuality != cult.spiritRootQuality) {
            spiritRoot = cult.spiritRoot;
            spiritRootName = cult.spiritRootName;
            spiritRootQuality = cult.spiritRootQuality;
            spiritRootQualityName = cult.spiritRootQualityName;
            redraw();
        }

        // 同步数值
        hp = cult.hp;
        maxHp = cult.maxHp;
        mp = cult.mp;
        maxMp = cult.maxMp;
        exp = cult.exp;
        expToNext = cult.expToNext;
        attackPower = cult.attackPower;
    }

    // 更新血条(由 GameScene 每帧调用)
    public function updateHpBar(ratio:Float):Void {
        if (hpBarFill != null) {
            hpBarFill.scaleX = ratio * charScale;
            hpBarFill.x = -40;
        }
    }

    // 更新动画(由 GameScene 每帧调用, 只更新动画不更新位置)
    public function updateAnimation(dt:Float):Void {
        animTime += dt;

        // 光环脉动
        if (aura != null) {
            var pulse = 1.0 + Math.sin(animTime * 3) * 0.08;
            aura.scaleX = pulse;
            aura.scaleY = pulse;
        }

        // 外袍飘动
        if (robe != null) {
            robe.scaleX = 1.0 + Math.sin(animTime * 2) * 0.03;
        }

        // 物理状态视觉更新
        updatePhysicsVisual(dt);
    }

    // === 物理状态视觉渲染 ===
    function updatePhysicsVisual(dt:Float):Void {
        // 清除所有状态层
        if (statusLayer != null) statusLayer.clear();
        if (shieldLayer != null) shieldLayer.clear();
        if (pressureLayer != null) pressureLayer.clear();
        if (resonanceLayer != null) resonanceLayer.clear();
        if (flightLayer != null) flightLayer.clear();
        if (nightGlowLayer != null) nightGlowLayer.clear();

        // --- 冰冻效果: 蓝色冰晶覆盖 ---
        if (physFrozen > 0) {
            var iceAlpha = Math.min(0.6, physFrozen * 0.3);
            // 冰晶外壳
            statusLayer.beginFill(0x88ccff, iceAlpha);
            statusLayer.drawCircle(0, -10, 28);
            statusLayer.endFill();
            // 冰晶尖刺(6个方向)
            for (i in 0...6) {
                var angle = (i / 6) * Math.PI * 2 + animTime * 0.5;
                var cx = Math.cos(angle) * 25;
                var cy = Math.sin(angle) * 25 - 10;
                var spikeLen = 8 + Math.sin(animTime * 4 + i) * 3;
                statusLayer.lineStyle(2, 0xaaeeff, iceAlpha + 0.2);
                statusLayer.moveTo(cx, cy);
                statusLayer.lineTo(cx + Math.cos(angle) * spikeLen, cy + Math.sin(angle) * spikeLen);
            }
            // 冰冻时整体偏蓝
            statusLayer.beginFill(0x4488ff, 0.15);
            statusLayer.drawCircle(0, -10, 30);
            statusLayer.endFill();
        }

        // --- 燃烧效果: 火焰粒子 ---
        if (physBurn > 0) {
            var fireAlpha = Math.min(0.7, physBurn * 0.35);
            // 火焰光晕
            for (i in 0...5) {
                var phase = animTime * 3 + i * 1.2;
                var fx = Math.sin(phase) * 15;
                var fy = -15 + Math.cos(phase * 0.7) * 10 - i * 3;
                var fr = 6 + Math.sin(phase * 2) * 3;
                statusLayer.beginFill(0xff4400, fireAlpha * (1 - i * 0.15));
                statusLayer.drawCircle(fx, fy, fr);
                statusLayer.endFill();
                statusLayer.beginFill(0xffaa00, fireAlpha * 0.5 * (1 - i * 0.15));
                statusLayer.drawCircle(fx, fy - 2, fr * 0.6);
                statusLayer.endFill();
            }
        }

        // --- 眩晕效果: 头顶星星 ---
        if (physStun > 0) {
            var starAlpha = Math.min(0.8, physStun * 0.4);
            for (i in 0...3) {
                var angle = animTime * 2 + i * (Math.PI * 2 / 3);
                var sx = Math.cos(angle) * 12;
                var sy = -60 + Math.sin(angle) * 5;
                // 绘制小星星(十字光)
                statusLayer.lineStyle(2, 0xffee44, starAlpha);
                statusLayer.moveTo(sx - 4, sy);
                statusLayer.lineTo(sx + 4, sy);
                statusLayer.moveTo(sx, sy - 4);
                statusLayer.lineTo(sx, sy + 4);
                statusLayer.beginFill(0xffee44, starAlpha * 0.5);
                statusLayer.drawCircle(sx, sy, 2);
                statusLayer.endFill();
            }
        }

        // --- 减速效果: 脚下减速光环 ---
        if (physSlow > 0 && physSlowFactor < 1.0) {
            var slowAlpha = (1.0 - physSlowFactor) * 0.4;
            statusLayer.beginFill(0x8866ff, slowAlpha);
            statusLayer.drawCircle(0, 10, 22);
            statusLayer.endFill();
            // 减速波纹
            for (i in 0...2) {
                var r = 18 + ((animTime * 20 + i * 15) % 20);
                var a = slowAlpha * (1 - (r - 18) / 20);
                statusLayer.lineStyle(1.5, 0xaa88ff, a);
                statusLayer.drawCircle(0, 10, r);
            }
        }

        // --- 护体灵光: 旋转护盾环 ---
        if (physShieldActive && physShieldStrength > 0) {
            var shieldRatio = physShieldMax > 0 ? physShieldStrength / physShieldMax : 1;
            var shieldAlpha = 0.3 + shieldRatio * 0.4;
            // 内层护盾
            shieldLayer.beginFill(0x44aaff, shieldAlpha * 0.15);
            shieldLayer.drawCircle(0, -10, 32);
            shieldLayer.endFill();
            // 旋转护盾环(六边形)
            var rot = animTime * 1.5;
            shieldLayer.lineStyle(2, 0x66ddff, shieldAlpha);
            for (i in 0...6) {
                var a1 = rot + i * Math.PI / 3;
                var a2 = rot + (i + 1) * Math.PI / 3;
                var r = 30;
                shieldLayer.moveTo(Math.cos(a1) * r, Math.sin(a1) * r - 10);
                shieldLayer.lineTo(Math.cos(a2) * r, Math.sin(a2) * r - 10);
            }
            // 护盾碎片(强度低时出现裂纹)
            if (shieldRatio < 0.5) {
                shieldLayer.lineStyle(1, 0xff4444, 0.5);
                shieldLayer.moveTo(-15, -20);
                shieldLayer.lineTo(10, 5);
                shieldLayer.moveTo(12, -25);
                shieldLayer.lineTo(-8, 0);
            }
        }

        // --- 灵压可视化: 脚下扩散波纹 ---
        if (physPressure > 10) {
            var pressureAlpha = Math.min(0.4, physPressure / 200);
            for (i in 0...3) {
                var r = 25 + ((animTime * 15 + i * 20) % 40);
                var a = pressureAlpha * (1 - (r - 25) / 40);
                pressureLayer.lineStyle(2, 0xffaa00, a);
                pressureLayer.drawCircle(0, 10, r);
            }
            // 灵压核心光晕
            pressureLayer.beginFill(0xff8800, pressureAlpha * 0.3);
            pressureLayer.drawCircle(0, -10, 28);
            pressureLayer.endFill();
        }

        // --- 元素共振光环 ---
        if (physResonanceStrength > 0 && physResonanceBonus > 1.0) {
            var resAlpha = Math.min(0.5, (physResonanceBonus - 1.0) * 3);
            var pulse = 1.0 + Math.sin(animTime * 4) * 0.1;
            // 共振光环
            resonanceLayer.beginFill(physResonanceColor, resAlpha * 0.2);
            resonanceLayer.drawCircle(0, -10, 35 * pulse);
            resonanceLayer.endFill();
            // 共振粒子(4个旋转光点)
            for (i in 0...4) {
                var angle = animTime * 2 + i * (Math.PI / 2);
                var px = Math.cos(angle) * 30 * pulse;
                var py = Math.sin(angle) * 30 * pulse - 10;
                resonanceLayer.beginFill(physResonanceColor, resAlpha);
                resonanceLayer.drawCircle(px, py, 3);
                resonanceLayer.endFill();
            }
        } else if (physResonanceStrength < 0) {
            // 元素压制: 暗色压制光环
            var supAlpha = Math.min(0.4, (1.0 - physResonanceBonus) * 3);
            resonanceLayer.beginFill(0x666666, supAlpha * 0.3);
            resonanceLayer.drawCircle(0, -10, 30);
            resonanceLayer.endFill();
        }

        // 夜间辉光: 夜晚时角色自动发光，照亮自身和周围
        if (nightDarkness > 0.05) {
            // 暗度越大，辉光越强(暗度0.25→辉光强度0.5)
            var glowStrength = (nightDarkness - 0.05) / 0.2; // 0~1
            var glowAlpha = glowStrength * 0.5;
            var glowColor = realmList[realmIndex].color;

            // 角色主体发光: 填充式光晕照亮角色轮廓
            nightGlowLayer.beginFill(glowColor, glowAlpha * 0.25);
            nightGlowLayer.drawCircle(0, -10, 30 * charScale);
            nightGlowLayer.endFill();

            // 内层核心亮斑
            nightGlowLayer.beginFill(glowColor, glowAlpha * 0.6);
            nightGlowLayer.drawCircle(0, -10, 12 * charScale);
            nightGlowLayer.endFill();

            // 头顶灵力光晕(身份标识)
            nightGlowLayer.beginFill(0xffffee, glowAlpha * 0.4);
            nightGlowLayer.drawCircle(0, -38 * charScale, 4);
            nightGlowLayer.endFill();

            // 周围地光(照亮脚下，范围大于角色)
            var groundGlowR = 20 + realmIndex * 5;
            nightGlowLayer.beginFill(glowColor, glowAlpha * 0.08);
            nightGlowLayer.drawEllipse(0, 10, groundGlowR * charScale, groundGlowR * 0.3 * charScale);
            nightGlowLayer.endFill();

            // 境界越高光越强: 金丹期以上增加外环脉动
            if (realmIndex >= 2) {
                var pulseR = (40 + realmIndex * 8) * charScale;
                var pulseA = glowAlpha * (0.1 + Math.sin(animTime * 3) * 0.05);
                nightGlowLayer.lineStyle(2, glowColor, pulseA);
                nightGlowLayer.drawCircle(0, -10, pulseR);
                nightGlowLayer.lineStyle();
            }
        }
    }

    // yOffset 属性(用于飞行时微微浮空)
    public var yOffset:Float = 0;
}
