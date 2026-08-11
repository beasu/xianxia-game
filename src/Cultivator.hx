import h2d.Object;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Graphics;
import h2d.Text;
import h2d.filter.Glow;
import hxd.Math;

/**
    Cultivator - 修仙者(玩家/敌人)
    包含: 角色渲染、血条、状态、移动、境界系统
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

    public var vx:Float = 0;
    public var vy:Float = 0;

    public var attackTimer:Float = 1.0;
    public var hitFlash:Float = 0;

    public var body:Graphics;
    var aura:Graphics;
    var hpBarBg:Bitmap;
    var hpBarFill:Bitmap;
    public var nameText:Text;

    var animTime:Float = 0;
    var facingRight:Bool = true;

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
        body = new Graphics(this);

        var bgTile = Tile.fromColor(0x000000, 40, 5);
        hpBarBg = new Bitmap(bgTile, this);
        hpBarBg.x = -20;
        hpBarBg.y = -35;
        hpBarBg.alpha = 0.7;

        var fillTile = Tile.fromColor(0xff3333, 40, 5);
        hpBarFill = new Bitmap(fillTile, this);
        hpBarFill.x = -20;
        hpBarFill.y = -35;

        nameText = new Text(Main.cjkFont, this);
        nameText.text = charName != null ? charName : "";
        nameText.x = -30;
        nameText.y = -50;
        nameText.textColor = isPlayer ? 0xFFD700 : 0xff6666;
        nameText.scaleX = 1.0;
        nameText.scaleY = 1.0;
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

    // ========== 玩家: 道袍修仙者 ==========
    function drawPlayer() {
        var realmColor = realmList[realmIndex].color;

        // 灵气光环
        aura.beginFill(realmColor, 0.08);
        aura.drawCircle(0, 0, 28);
        aura.endFill();
        aura.beginFill(realmColor, 0.04);
        aura.drawCircle(0, 0, 35);
        aura.endFill();

        // 袍子
        body.beginFill(0x2a3a6a);
        drawPolyShape(body, [-12, 8, -8, 20, 8, 20, 12, 8, 10, -5, -10, -5]);
        body.endFill();

        // 腰带
        body.beginFill(realmColor);
        body.drawRect(-10, 5, 20, 3);
        body.endFill();

        // 上半身
        body.beginFill(0xe0e0ff);
        drawPolyShape(body, [-8, -5, -6, 8, 6, 8, 8, -5, 6, -12, -6, -12]);
        body.endFill();

        // 头
        body.beginFill(0xffe0c0);
        body.drawCircle(0, -16, 8);
        body.endFill();

        // 发髻
        body.beginFill(0x1a1a2a);
        body.drawCircle(0, -22, 6);
        body.endFill();
        // 发簪
        body.beginFill(realmColor);
        body.drawRect(-1, -24, 2, 4);
        body.endFill();

        // 眼睛
        body.beginFill(0x000000);
        body.drawCircle(-3, -16, 1);
        body.drawCircle(3, -16, 1);
        body.endFill();

        // 法印发光球 (颜色随境界变化)
        body.beginFill(realmColor, 0.6);
        body.drawCircle(14, 0, 5);
        body.endFill();
        body.beginFill(realmColor, 0.3);
        body.drawCircle(14, 0, 8);
        body.endFill();

        // 化神期额外特效: 背后灵纹
        if (realmIndex >= 3) {
            body.beginFill(realmColor, 0.2);
            for (i in 0...6) {
                var a = (i / 6) * Math.PI * 2;
                body.drawCircle(Math.cos(a) * 20, Math.sin(a) * 20, 3);
            }
            body.endFill();
        }
    }

    // ========== 魔修 (基础敌人) ==========
    function drawMoxiu() {
        aura.beginFill(0x660066, 0.1);
        aura.drawCircle(0, 0, 22);
        aura.endFill();

        body.beginFill(0x3a0a0a);
        drawPolyShape(body, [-10, 6, -7, 18, 7, 18, 10, 6, 8, -4, -8, -4]);
        body.endFill();

        body.beginFill(0x4a2020);
        drawPolyShape(body, [-6, -4, -5, 6, 5, 6, 6, -4, 5, -10, -5, -10]);
        body.endFill();

        // 头
        body.beginFill(0xc0a0a0);
        body.drawCircle(0, -14, 7);
        body.endFill();

        // 兜帽
        body.beginFill(0x2a0a0a);
        drawPolyShape(body, [-8, -10, -10, -18, -6, -22, 0, -24, 6, -22, 10, -18, 8, -10]);
        body.endFill();

        // 红眼
        body.beginFill(0xff0000);
        body.drawCircle(-3, -14, 1.5);
        body.drawCircle(3, -14, 1.5);
        body.endFill();

        // 魔气
        body.beginFill(0x880088, 0.3);
        body.drawCircle(-12, 0, 4);
        body.drawCircle(12, 0, 4);
        body.endFill();
    }

    // ========== 妖兽 (四足野兽型) ==========
    function drawYaoshou() {
        aura.beginFill(0x664400, 0.12);
        aura.drawCircle(0, 0, 25);
        aura.endFill();

        // 兽身
        body.beginFill(0x4a3320);
        drawPolyShape(body, [-16, 4, -14, 14, 14, 14, 16, 4, 12, -4, -12, -4]);
        body.endFill();

        // 兽毛纹理
        body.beginFill(0x5a4030, 0.5);
        body.drawRect(-10, 0, 20, 2);
        body.drawRect(-8, 4, 16, 2);
        body.endFill();

        // 兽腿
        body.beginFill(0x3a2810);
        body.drawRect(-12, 12, 4, 6);
        body.drawRect(8, 12, 4, 6);
        body.endFill();

        // 兽头
        body.beginFill(0x5a4030);
        body.drawCircle(0, -12, 9);
        body.endFill();

        // 兽耳
        body.beginFill(0x4a3320);
        drawPolyShape(body, [-8, -18, -10, -24, -5, -20]);
        body.endFill();
        body.beginFill(0x4a3320);
        drawPolyShape(body, [8, -18, 10, -24, 5, -20]);
        body.endFill();

        // 獠牙
        body.beginFill(0xffffff, 0.9);
        drawPolyShape(body, [-3, -8, -2, -4, -1, -8]);
        body.endFill();
        body.beginFill(0xffffff, 0.9);
        drawPolyShape(body, [3, -8, 2, -4, 1, -8]);
        body.endFill();

        // 兽眼 (金色)
        body.beginFill(0xffaa00);
        body.drawCircle(-4, -12, 2);
        body.drawCircle(4, -12, 2);
        body.endFill();
        body.beginFill(0x000000);
        body.drawCircle(-4, -12, 1);
        body.drawCircle(4, -12, 1);
        body.endFill();

        // 额头兽纹
        body.beginFill(0x884400, 0.6);
        body.drawRect(-1, -20, 2, 4);
        body.endFill();
    }

    // ========== 魔将 (大型重甲型) ==========
    function drawMojiang() {
        aura.beginFill(0x880000, 0.15);
        aura.drawCircle(0, 0, 30);
        aura.endFill();

        // 重甲身体
        body.beginFill(0x3a0a0a);
        drawPolyShape(body, [-14, 8, -10, 22, 10, 22, 14, 8, 12, -6, -12, -6]);
        body.endFill();

        // 甲胄
        body.beginFill(0x5a1a1a);
        drawPolyShape(body, [-10, -6, -8, 8, 8, 8, 10, -6, 8, -14, -8, -14]);
        body.endFill();

        // 肩甲
        body.beginFill(0x6a2a2a);
        body.drawCircle(-12, -4, 6);
        body.drawCircle(12, -4, 6);
        body.endFill();

        // 胸甲纹路
        body.beginFill(0x880000, 0.6);
        body.drawRect(-6, -2, 12, 2);
        body.drawRect(-4, 2, 8, 2);
        body.endFill();

        // 头盔
        body.beginFill(0x4a1a1a);
        drawPolyShape(body, [-8, -12, -9, -22, 0, -26, 9, -22, 8, -12]);
        body.endFill();

        // 面甲缝
        body.beginFill(0x000000, 0.8);
        body.drawRect(-5, -18, 10, 2);
        body.endFill();

        // 眼缝红光
        body.beginFill(0xff0000, 0.9);
        body.drawCircle(-3, -17, 1.5);
        body.drawCircle(3, -17, 1.5);
        body.endFill();

        // 头盔角
        body.beginFill(0x2a0a0a);
        drawPolyShape(body, [-8, -22, -12, -30, -6, -24]);
        body.endFill();
        body.beginFill(0x2a0a0a);
        drawPolyShape(body, [8, -22, 12, -30, 6, -24]);
        body.endFill();

        // 魔气
        body.beginFill(0xaa0000, 0.3);
        body.drawCircle(-14, 0, 5);
        body.drawCircle(14, 0, 5);
        body.endFill();
    }

    // ========== 邪仙 (飘浮法袍型) ==========
    function drawXiexian() {
        aura.beginFill(0x006644, 0.12);
        aura.drawCircle(0, 0, 28);
        aura.endFill();

        // 飘逸法袍
        body.beginFill(0x0a3322);
        drawPolyShape(body, [-14, 6, -10, 20, -6, 24, 0, 22, 6, 24, 10, 20, 14, 6, 10, -4, -10, -4]);
        body.endFill();

        // 法袍纹路
        body.beginFill(0x1a5544, 0.5);
        body.drawRect(-8, 0, 16, 2);
        body.drawRect(-6, 6, 12, 2);
        body.endFill();

        // 上半身
        body.beginFill(0x2a6655);
        drawPolyShape(body, [-8, -4, -6, 8, 6, 8, 8, -4, 6, -12, -6, -12]);
        body.endFill();

        // 头
        body.beginFill(0xc0e0d0);
        body.drawCircle(0, -16, 7);
        body.endFill();

        // 长发 (邪仙特征)
        body.beginFill(0x0a3322);
        drawPolyShape(body, [-6, -18, -10, -10, -8, 0, -4, -16]);
        body.endFill();
        body.beginFill(0x0a3322);
        drawPolyShape(body, [6, -18, 10, -10, 8, 0, 4, -16]);
        body.endFill();

        // 邪眼 (绿色)
        body.beginFill(0x00ff66);
        body.drawCircle(-3, -16, 1.5);
        body.drawCircle(3, -16, 1.5);
        body.endFill();

        // 邪气珠
        body.beginFill(0x00aa44, 0.5);
        body.drawCircle(14, 0, 6);
        body.endFill();
        body.beginFill(0x00ff66, 0.7);
        body.drawCircle(14, 0, 3);
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
            var pulse = 1.0 + Math.sin(animTime * 3) * 0.1;
            aura.scaleX = pulse;
            aura.scaleY = pulse;
        }

        if (hitFlash > 0) {
            hitFlash -= dt;
            body.alpha = 0.5 + Math.sin(hitFlash * 60) * 0.5;
        } else {
            body.alpha = 1.0;
        }

        var ratio = Math.max(0, hp / maxHp);
        hpBarFill.scaleX = ratio;
        hpBarFill.x = -20;

        if (isPlayer) {
            var sc = GameScene.inst;
            x = Math.clamp(x, 20, sc.width - 20);
            y = Math.clamp(y, 40, sc.height - 60);
        }

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

            // 突破增益
            maxHp = Std.int(maxHp * 1.3);
            hp = maxHp;
            maxMp = Std.int(maxMp * 1.3);
            mp = maxMp;
            attackPower = Std.int(attackPower * 1.25);

            redraw();
            return true;
        }
        return false;
    }

    public function gainExp(amount:Float) {
        exp += amount;
    }
}
