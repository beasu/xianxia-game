import h2d.Scene;
import h2d.Object;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Text;
import h2d.filter.Glow;
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
import haxe.ui.Toolkit;

/**
    GameScene - 修仙游戏主场景
    包含: 角色、敌人、法术特效、阵法、UI、境界系统
**/
class GameScene extends Scene {
    public static var inst:GameScene;

    // --- 角色系统 ---
    public var player:Cultivator;
    public var enemies:Array<Cultivator> = [];

    // --- 特效层 ---
    public var fxLayer:Object;
    public var formationLayer:Object;
    public var bgLayer:Object;
    public var entityLayer:Object;
    public var uiLayer:Object;

    // --- 阵法系统 ---
    public var activeFormation:Formation;

    // --- 粒子池 ---
    public var particles:Array<Particle> = [];
    public var particlePool:Array<Particle> = [];

    // --- 输入 ---
    public var camMouseX:Float = 0;
    public var camMouseY:Float = 0;

    // --- 时间 ---
    public var elapsed:Float = 0;
    public var spawnTimer:Float = 0;
    public var killCount:Int = 0;
    public var breakthroughFlash:Float = 0;

    // --- HaxeUI 界面 ---
    var uiHpBar:HorizontalProgress;
    var uiMpBar:HorizontalProgress;
    var uiExpBar:HorizontalProgress;
    var uiInfo:Label;
    var uiHpNum:Label;
    var uiMpNum:Label;
    var uiKillLabel:Label;
    var uiRealmLabel:Label;
    var uiExpLabel:Label;
    var uiSkillButtons:Array<Button> = [];
    var uiFormationButtons:Array<Button> = [];

    // --- 技能冷却 ---
    public var cooldowns:Map<String, Float> = [];

    // --- 技能定义 ---
    static var skillDefs = [
        {key: "Q", name: "Q\n三昧真火", skill: "fireball", cd: 1.5, mpCost: 30},
        {key: "W", name: "W\n九天玄雷", skill: "thunder", cd: 2.0, mpCost: 50},
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
        initBackground();
        initPlayer();
        initHaxeUI();

        for (i in 0...3) {
            spawnEnemy();
        }

        castFormation("bagua");
    }

    function initLayers() {
        bgLayer = new Object(this);
        formationLayer = new Object(this);
        entityLayer = new Object(this);
        fxLayer = new Object(this);
        uiLayer = new Object(this);
    }

    function initBackground() {
        // 渐变背景
        for (i in 0...20) {
            var t = i / 20.0;
            var r = Std.int(0x0a + (0x1a - 0x0a) * t);
            var g = Std.int(0x0a + (0x1a - 0x0a) * t);
            var b = Std.int(0x1a + (0x3a - 0x1a) * t);
            var color = (r << 16) | (g << 8) | b;
            var tile = Tile.fromColor(color, 1, 1);
            var bmp = new Bitmap(tile, bgLayer);
            bmp.scaleX = width;
            bmp.scaleY = height / 20;
            bmp.y = i * (height / 20);
        }

        // 星星
        for (i in 0...40) {
            var star = new Bitmap(Tile.fromColor(0xffffff, 2, 2), bgLayer);
            star.x = Math.random(width);
            star.y = Math.random(height);
            star.alpha = randRange(0.3, 0.8);
        }

        drawInkMountains();
    }

    function drawInkMountains() {
        var g = new h2d.Graphics(bgLayer);
        g.alpha = 0.3;
        g.beginFill(0x2a2a4a);
        var baseY = height * 0.65;
        g.moveTo(0, baseY + 30);
        g.lineTo(width * 0.15, baseY - 20);
        g.lineTo(width * 0.3, baseY + 10);
        g.lineTo(width * 0.5, baseY - 40);
        g.lineTo(width * 0.7, baseY + 5);
        g.lineTo(width * 0.85, baseY - 25);
        g.lineTo(width * 1.0, baseY + 20);
        g.lineTo(width * 1.0, height * 1.0);
        g.lineTo(0, height * 1.0);
        g.lineTo(0, baseY + 30);
        g.endFill();

        var g2 = new h2d.Graphics(bgLayer);
        g2.alpha = 0.5;
        g2.beginFill(0x1a1a3a);
        baseY = height * 0.8;
        g2.moveTo(0, baseY + 40);
        g2.lineTo(width * 0.1, baseY - 10);
        g2.lineTo(width * 0.25, baseY + 20);
        g2.lineTo(width * 0.4, baseY - 30);
        g2.lineTo(width * 0.55, baseY + 15);
        g2.lineTo(width * 0.75, baseY - 20);
        g2.lineTo(width * 0.9, baseY + 25);
        g2.lineTo(width * 1.0, baseY);
        g2.lineTo(width * 1.0, height * 1.0);
        g2.lineTo(0, height * 1.0);
        g2.lineTo(0, baseY + 40);
        g2.endFill();
    }

    function initPlayer() {
        player = new Cultivator(entityLayer);
        player.x = width * 0.5;
        player.y = height * 0.7;
        player.charName = "青云道长";
        player.isPlayer = true;
        player.maxHp = 1000;
        player.hp = 1000;
        player.maxMp = 500;
        player.mp = 500;
        player.realm = Cultivator.realmList[0].name;
        player.realmIndex = 0;
        player.attackPower = 80;
        player.exp = 0;
        player.expToNext = 100;
        player.redraw();
        player.nameText.visible = false;
    }

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
        uiRealmLabel.text = player.charName + "  [" + player.realm + "]";
        uiRealmLabel.styleString = "font-size:18px;color:#FFD700;font-weight:bold;";
        uiRealmLabel.width = 280;
        nameRow.addComponent(uiRealmLabel);

        uiKillLabel = new Label();
        uiKillLabel.text = "击杀: 0";
        uiKillLabel.styleString = "font-size:14px;color:#aaaaff;";
        uiKillLabel.width = 100;
        nameRow.addComponent(uiKillLabel);
        topBar.addComponent(nameRow);

        // HP条
        var hpRow = new HBox();
        hpRow.horizontalSpacing = 6;
        var hpText = new Label();
        hpText.text = "气血";
        hpText.styleString = "font-size:13px;color:#ff6666;width:35px;";
        hpRow.addComponent(hpText);
        uiHpBar = new HorizontalProgress();
        uiHpBar.width = 220;
        uiHpBar.height = 16;
        uiHpBar.min = 0;
        uiHpBar.max = player.maxHp;
        uiHpBar.pos = player.hp;
        uiHpBar.styleString = "background-color:#330000;border-color:#660000;";
        hpRow.addComponent(uiHpBar);
        uiHpNum = new Label();
        uiHpNum.text = Std.string(player.hp) + "/" + Std.string(player.maxHp);
        uiHpNum.styleString = "font-size:12px;color:#ffaaaa;";
        uiHpNum.width = 100;
        hpRow.addComponent(uiHpNum);
        topBar.addComponent(hpRow);

        // MP条
        var mpRow = new HBox();
        mpRow.horizontalSpacing = 6;
        var mpText = new Label();
        mpText.text = "灵力";
        mpText.styleString = "font-size:13px;color:#66aaff;width:35px;";
        mpRow.addComponent(mpText);
        uiMpBar = new HorizontalProgress();
        uiMpBar.width = 220;
        uiMpBar.height = 16;
        uiMpBar.min = 0;
        uiMpBar.max = player.maxMp;
        uiMpBar.pos = player.mp;
        uiMpBar.styleString = "background-color:#000033;border-color:#000066;";
        mpRow.addComponent(uiMpBar);
        uiMpNum = new Label();
        uiMpNum.text = Std.string(player.mp) + "/" + Std.string(player.maxMp);
        uiMpNum.styleString = "font-size:12px;color:#aaccff;";
        uiMpNum.width = 100;
        mpRow.addComponent(uiMpNum);
        topBar.addComponent(mpRow);

        // 经验条
        var expRow = new HBox();
        expRow.horizontalSpacing = 6;
        var expText = new Label();
        expText.text = "修为";
        expText.styleString = "font-size:13px;color:#88ff88;width:35px;";
        expRow.addComponent(expText);
        uiExpBar = new HorizontalProgress();
        uiExpBar.width = 220;
        uiExpBar.height = 12;
        uiExpBar.min = 0;
        uiExpBar.max = player.expToNext;
        uiExpBar.pos = player.exp;
        uiExpBar.styleString = "background-color:#003300;border-color:#006600;";
        expRow.addComponent(uiExpBar);
        uiExpLabel = new Label();
        uiExpLabel.text = Std.string(Math.round(player.exp)) + "/" + Std.string(player.expToNext);
        uiExpLabel.styleString = "font-size:12px;color:#88ff88;";
        uiExpLabel.width = 100;
        expRow.addComponent(uiExpLabel);
        topBar.addComponent(expRow);

        Screen.instance.addComponent(topBar);

        // === 底部技能栏 (两行) ===
        var skillContainer = new VBox();
        skillContainer.horizontalAlign = "center";
        skillContainer.width = width;
        skillContainer.paddingBottom = 4;

        // 第一行: Q-T (原5技能)
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

        // 第二行: Y-P (新5技能)
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

        var fmtTitle = new Label();
        fmtTitle.text = "-- 阵法 --";
        fmtTitle.styleString = "font-size:13px;color:#ffaa00;";
        formationBar.addComponent(fmtTitle);

        for (f in formationDefs) {
            var btn = new Button();
            btn.text = f.key + " " + f.name;
            btn.width = 72;
            btn.height = 30;
            btn.styleString = "font-size:11px;background-color:#2a1a0a;border-color:#aa6600;color:#ffcc88;";
            var fid = f.id;
            btn.onClick = function(_) {
                castFormation(fid);
            };
            uiFormationButtons.push(btn);
            formationBar.addComponent(btn);
        }

        Screen.instance.addComponent(formationBar);

        // === 右侧提示 ===
        uiInfo = new Label();
        uiInfo.text = "WASD移动 | 鼠标瞄准\nQ-P 释放法术\n1-5 切换阵法\n点击敌人或法术栏施法";
        uiInfo.styleString = "font-size:12px;color:#888888;";
        uiInfo.left = width - 210;
        uiInfo.top = height - 180;
        uiInfo.width = 200;
        Screen.instance.addComponent(uiInfo);
    }

    function createSkillButton(s:{key:String, name:String, skill:String, cd:Float, mpCost:Int}):Button {
        var btn = new Button();
        btn.text = s.name;
        btn.width = 72;
        btn.height = 42;
        btn.styleString = "font-size:11px;background-color:#1a1a3a;border-color:#4a4aaa;color:#ddddff;";
        var skillId = s.skill;
        var mpCost = s.mpCost;
        var cdTime = s.cd;
        btn.onClick = function(_) {
            castSpell(skillId, mpCost, cdTime);
        };
        return btn;
    }

    public function castSpell(skillId:String, mpCost:Int, cdTime:Float) {
        var cdKey = skillId;
        if (cooldowns.exists(cdKey) && cooldowns[cdKey] > 0) {
            return;
        }
        if (player.mp < mpCost) {
            flashInfo("灵力不足!");
            return;
        }

        player.mp -= mpCost;
        cooldowns[cdKey] = cdTime;

        var mx = camMouseX;
        var my = camMouseY;

        switch (skillId) {
            case "fireball":
                SpellSystem.castFireball(player.x, player.y, mx, my, fxLayer, this);
            case "thunder":
                SpellSystem.castThunder(player.x, player.y, mx, my, fxLayer, this);
            case "ice":
                SpellSystem.castIce(player.x, player.y, mx, my, fxLayer, this);
            case "swordqi":
                SpellSystem.castSwordQi(player.x, player.y, mx, my, fxLayer, this);
            case "thunderstorm":
                SpellSystem.castThunderstorm(mx, my, fxLayer, this);
            case "pocket":
                SpellSystem.castPocketDimension(player.x, player.y, mx, my, fxLayer, this);
            case "lotus":
                SpellSystem.castLotusBloom(player.x, player.y, mx, my, fxLayer, this);
            case "bigdipper":
                SpellSystem.castBigDipper(player.x, player.y, mx, my, fxLayer, this);
            case "clone":
                SpellSystem.castShadowClone(player.x, player.y, mx, my, fxLayer, this);
            case "voidshift":
                SpellSystem.castVoidShift(player.x, player.y, mx, my, fxLayer, this);
        }
    }

    public function castFormation(id:String) {
        if (activeFormation != null) {
            activeFormation.destroy();
            activeFormation = null;
        }
        activeFormation = new Formation(id, formationLayer);
        activeFormation.x = player.x;
        activeFormation.y = player.y;
    }

    function flashInfo(msg:String) {
        uiInfo.text = msg;
    }

    public function spawnEnemy() {
        var e = new Cultivator(entityLayer);
        e.isPlayer = false;

        // 根据击杀数决定敌人类型
        var typeRoll = Math.random();
        if (killCount < 5) {
            e.enemyType = "moxiu";
        } else if (killCount < 15) {
            if (typeRoll < 0.6) e.enemyType = "moxiu";
            else e.enemyType = "yaoshou";
        } else if (killCount < 30) {
            if (typeRoll < 0.4) e.enemyType = "moxiu";
            else if (typeRoll < 0.7) e.enemyType = "yaoshou";
            else e.enemyType = "mojiang";
        } else {
            if (typeRoll < 0.25) e.enemyType = "moxiu";
            else if (typeRoll < 0.5) e.enemyType = "yaoshou";
            else if (typeRoll < 0.8) e.enemyType = "mojiang";
            else e.enemyType = "xiexian";
        }

        // 根据敌人类型设置属性
        switch (e.enemyType) {
            case "yaoshou":
                e.maxHp = 300 + killCount * 12;
                e.attackPower = 25 + killCount * 2;
                e.charName = "妖兽";
            case "mojiang":
                e.maxHp = 500 + killCount * 15;
                e.attackPower = 35 + killCount * 3;
                e.charName = "魔将";
            case "xiexian":
                e.maxHp = 400 + killCount * 10;
                e.attackPower = 30 + killCount * 2;
                e.charName = "邪仙";
            default:
                e.maxHp = 200 + killCount * 10;
                e.attackPower = 15 + killCount * 2;
                e.charName = "魔修";
        }

        e.hp = e.maxHp;
        e.realm = "练气" + (Std.int(randRange(1, 7))) + "层";
        e.redraw();

        var side = Std.int(Math.random(4));
        switch (side) {
            case 0: e.x = Math.random(width); e.y = -30;
            case 1: e.x = width + 30; e.y = Math.random(height);
            case 2: e.x = Math.random(width); e.y = height + 30;
            case 3: e.x = -30; e.y = Math.random(height);
        }
        enemies.push(e);
    }

    public function dealDamage(target:Cultivator, dmg:Int, knockbackX:Float = 0, knockbackY:Float = 0) {
        target.hp -= dmg;
        if (knockbackX != 0 || knockbackY != 0) {
            target.vx += knockbackX;
            target.vy += knockbackY;
        }

        spawnDamageNumber(target.x, target.y - 20, dmg, target.isPlayer ? 0xff4444 : 0xffdd44);
        target.hitFlash = 0.15;

        if (target.hp <= 0) {
            target.dead = true;
            if (!target.isPlayer) {
                killCount++;
                spawnDeathEffect(target.x, target.y);

                // 获得经验
                var expGain = 15.0 + killCount * 0.5;
                player.gainExp(expGain);

                // 尝试突破
                if (player.tryBreakthrough()) {
                    spawnBreakthroughEffect();
                }
            }
        }
    }

    function spawnBreakthroughEffect() {
        breakthroughFlash = 1.0;

        // 突破光柱
        SpellSystem.spawnRing(player.x, player.y, 0xFFD700, 200, 0.8, fxLayer, this);
        SpellSystem.spawnRing(player.x, player.y, 0xffffff, 150, 0.6, fxLayer, this);

        for (i in 0...50) {
            var p = getParticle();
            var angle = Math.random(Math.PI * 2);
            var speed = randRange(100, 300);
            p.x = player.x;
            p.y = player.y;
            p.vx = Math.cos(angle) * speed;
            p.vy = Math.sin(angle) * speed;
            p.life = randRange(0.5, 1.2);
            p.maxLife = p.life;
            p.size = randRange(4, 10);
            p.color = [0xFFD700, 0xffaa00, 0xffffff, 0xff6600][Std.int(Math.random(4))];
            p.type = Spark;
            p.glow = true;
            p.fade = true;
            p.gravity = 20;
            p.drag = 0.95;
        }

        // 上行光柱
        for (i in 0...20) {
            var p = getParticle();
            p.x = player.x + randRange(-15, 15);
            p.y = player.y;
            p.vx = randRange(-5, 5);
            p.vy = randRange(-200, -100);
            p.life = randRange(0.6, 1.0);
            p.maxLife = p.life;
            p.size = randRange(3, 8);
            p.color = 0xFFD700;
            p.type = Glowing;
            p.glow = true;
            p.fade = true;
            p.drag = 0.98;
        }

        // 更新UI
        uiRealmLabel.text = player.charName + "  [" + player.realm + "]";
        uiHpBar.max = player.maxHp;
        uiMpBar.max = player.maxMp;
        flashInfo("境界突破! -> " + player.realm);
    }

    function spawnDamageNumber(x:Float, y:Float, dmg:Int, color:Int) {
        var p = getParticle();
        p.x = x;
        p.y = y;
        p.vx = randRange(-20, 20);
        p.vy = -60;
        p.life = 0.8;
        p.maxLife = 0.8;
        p.size = 16;
        p.color = color;
        p.type = DamageNumber;
        p.text = Std.string(dmg);
        p.glow = true;
    }

    function spawnDeathEffect(x:Float, y:Float) {
        for (i in 0...20) {
            var p = getParticle();
            var angle = Math.random(Math.PI * 2);
            var speed = randRange(50, 200);
            p.x = x;
            p.y = y;
            p.vx = Math.cos(angle) * speed;
            p.vy = Math.sin(angle) * speed;
            p.life = randRange(0.5, 1.0);
            p.maxLife = p.life;
            p.size = randRange(3, 8);
            p.color = 0xff6600;
            p.type = DeathBurst;
            p.glow = true;
            p.fade = true;
            p.gravity = 100;
        }
    }

    public function getParticle():Particle {
        if (particlePool.length > 0) {
            var p = particlePool.pop();
            p.active = true;
            p.reset();
            particles.push(p);
            return p;
        }
        var p = new Particle(fxLayer);
        particles.push(p);
        return p;
    }

    public function recycleParticle(p:Particle) {
        p.active = false;
        p.visible = false;
        particles.remove(p);
        particlePool.push(p);
    }

    override function sync(ctx:h2d.RenderContext) {
        var dt = ctx.elapsedTime;

        var win = Window.getInstance();
        camMouseX = win.mouseX;
        camMouseY = win.mouseY;

        handleInput(dt);
        player.update(dt);

        for (e in enemies) {
            if (e.dead) continue;
            var dx = player.x - e.x;
            var dy = player.y - e.y;
            var dist = Math.sqrt(dx * dx + dy * dy);

            // 不同敌人类型有不同行为
            var moveSpeed = 60.0;
            switch (e.enemyType) {
                case "yaoshou": moveSpeed = 90; // 妖兽更快
                case "mojiang": moveSpeed = 40; // 魔将更慢
                case "xiexian": moveSpeed = 50; // 邪仙中等
                default: moveSpeed = 60;
            }

            if (dist > 30) {
                e.vx += (dx / dist) * moveSpeed * dt;
                e.vy += (dy / dist) * moveSpeed * dt;
            } else {
                e.attackTimer -= dt;
                if (e.attackTimer <= 0) {
                    dealDamage(player, e.attackPower);
                    e.attackTimer = 1.0;
                }
            }
            e.update(dt);
        }

        var i = enemies.length;
        while (i-- > 0) {
            if (enemies[i].dead && enemies[i].alpha <= 0) {
                enemies[i].remove();
                enemies.remove(enemies[i]);
            }
        }

        spawnTimer -= dt;
        if (spawnTimer <= 0 && enemies.length < 8) {
            spawnEnemy();
            spawnTimer = 3.0 - Math.min(killCount * 0.05, 2.0);
        }

        for (p in particles) {
            if (!p.active) continue;
            p.update(dt);
        }

        if (activeFormation != null) {
            activeFormation.update(dt);
            activeFormation.x = player.x;
            activeFormation.y = player.y;

            for (e in enemies) {
                if (e.dead) continue;
                var dx = e.x - activeFormation.x;
                var dy = e.y - activeFormation.y;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist < activeFormation.radius) {
                    activeFormation.applyEffect(e, dt);
                }
            }
        }

        for (k in cooldowns.keys()) {
            if (cooldowns[k] > 0) {
                cooldowns[k] -= dt;
                if (cooldowns[k] < 0) cooldowns[k] = 0;
            }
        }

        // 突破闪光
        if (breakthroughFlash > 0) {
            breakthroughFlash -= dt * 2;
            if (breakthroughFlash < 0) breakthroughFlash = 0;
        }

        updateUI(dt);
        updateSkillCooldowns();

        super.sync(ctx);
    }

    function handleInput(dt:Float) {
        var speed = 200 * dt;

        if (Key.isDown(Key.W) || Key.isDown(Key.UP)) player.vy -= speed * 10;
        if (Key.isDown(Key.S) || Key.isDown(Key.DOWN)) player.vy += speed * 10;
        if (Key.isDown(Key.A) || Key.isDown(Key.LEFT)) player.vx -= speed * 10;
        if (Key.isDown(Key.D) || Key.isDown(Key.RIGHT)) player.vx += speed * 10;

        if (Key.isPressed(Key.Q)) castSpell("fireball", 30, 1.5);
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

        if (Key.isPressed(Key.MOUSE_LEFT)) {
            castSpell("thunder", 50, 2.0);
        }
    }

    function updateUI(dt:Float) {
        uiHpBar.pos = Math.max(0, player.hp);
        uiMpBar.pos = Math.max(0, player.mp);
        uiExpBar.pos = Math.max(0, player.exp);
        uiExpBar.max = player.expToNext;

        uiHpNum.text = Std.string(Math.max(0, Math.round(player.hp))) + "/" + Std.string(player.maxHp);
        uiMpNum.text = Std.string(Math.max(0, Math.round(player.mp))) + "/" + Std.string(player.maxMp);
        uiExpLabel.text = Std.string(Math.round(player.exp)) + "/" + Std.string(player.expToNext);
        uiKillLabel.text = "击杀: " + Std.string(killCount);
        uiRealmLabel.text = player.charName + "  [" + player.realm + "]";

        player.mp = Math.min(player.maxMp, player.mp + 15 * dt);
    }

    function updateSkillCooldowns() {
        var skillKeys = ["fireball", "thunder", "ice", "swordqi", "thunderstorm", "pocket", "lotus", "bigdipper", "clone", "voidshift"];
        for (i in 0...uiSkillButtons.length) {
            var btn = uiSkillButtons[i];
            var key = skillKeys[i];
            var cd = cooldowns.exists(key) ? cooldowns[key] : 0;
            if (cd > 0) {
                btn.alpha = 0.5;
                btn.disabled = true;
            } else {
                btn.alpha = 1.0;
                btn.disabled = false;
            }
        }
    }
}
