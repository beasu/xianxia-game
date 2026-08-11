import h2d.Object;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Graphics;
import h2d.filter.Glow;
import hxd.Math;

/**
    SpellSystem - 法术特效系统
    实现动漫级华丽法术:
    - 三昧真火 (火球术): 火球飞行+拖尾+爆裂
    - 九天玄雷 (雷术): 闪电链+雷云
    - 玄冰诀 (冰术): 冰晶弹+冰冻扩散
    - 万剑归宗 (剑气): 多剑齐射+剑气斩
    - 天雷破 (大招): 全屏雷暴
    - 袖里乾坤 (空间术): 空间扭曲+吸入+引爆
    - 莲花绽放 (佛门术): 金莲绽放+净化波
    - 天罡北斗阵 (星辰术): 北斗七星坠落
    - 分影术 (幻术): 分身齐射
    - 乾坤大挪移 (位移术): 瞬移+冲击波
**/
class SpellSystem {

    static inline function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }

    static function drawPolyShape(g:Graphics, points:Array<Float>) {
        if (points.length < 6) return;
        g.moveTo(points[0], points[1]);
        var i = 2;
        while (i < points.length) {
            g.lineTo(points[i], points[i + 1]);
            i += 2;
        }
        g.lineTo(points[0], points[1]);
    }

    // ========== 三昧真火 ==========
    public static function castFireball(fromX:Float, fromY:Float, toX:Float, toY:Float, layer:Object, scene:GameScene) {
        spawnCastEffect(fromX, fromY, 0xff6600, layer, scene);
        var fireball = new FireballProjectile(layer, fromX, fromY, toX, toY, scene);
    }

    // ========== 九天玄雷 ==========
    public static function castThunder(fromX:Float, fromY:Float, toX:Float, toY:Float, layer:Object, scene:GameScene) {
        spawnCastEffect(fromX, fromY, 0x66aaff, layer, scene);
        spawnLightning(toX, toY, layer, scene);
    }

    // ========== 玄冰诀 ==========
    public static function castIce(fromX:Float, fromY:Float, toX:Float, toY:Float, layer:Object, scene:GameScene) {
        spawnCastEffect(fromX, fromY, 0x88ddff, layer, scene);
        var ice = new IceProjectile(layer, fromX, fromY, toX, toY, scene);
    }

    // ========== 万剑归宗 ==========
    public static function castSwordQi(fromX:Float, fromY:Float, toX:Float, toY:Float, layer:Object, scene:GameScene) {
        spawnCastEffect(fromX, fromY, 0xeeeeff, layer, scene);

        var count = 12;
        for (i in 0...count) {
            var angle = (i / count) * Math.PI * 2;
            var dist = 60;
            var sx = fromX + Math.cos(angle) * dist;
            var sy = fromY + Math.sin(angle) * dist;

            haxe.Timer.delay(function() {
                if (scene != null) {
                    var tx = sx + Math.cos(angle) * 500;
                    var ty = sy + Math.sin(angle) * 500;
                    spawnSwordBlade(sx, sy, tx, ty, angle, layer, scene);
                }
            }, Std.int(i * 30));
        }

        spawnRing(fromX, fromY, 0xeeeeff, 80, 0.4, layer, scene);
    }

    // ========== 天雷破 (大招) ==========
    public static function castThunderstorm(cx:Float, cy:Float, layer:Object, scene:GameScene) {
        spawnScreenFlash(0x330055, 0.4, 0.5, layer, scene);

        for (i in 0...8) {
            haxe.Timer.delay(function() {
                if (scene != null) {
                    var lx = cx + randRange(-200, 200);
                    var ly = cy + randRange(-150, 150);
                    spawnLightning(lx, ly, layer, scene);
                }
            }, Std.int(i * 80));
        }

        haxe.Timer.delay(function() {
            if (scene != null) {
                spawnExplosion(cx, cy, 0xaa66ff, 150, layer, scene);
                spawnRing(cx, cy, 0xffffff, 200, 0.6, layer, scene);
            }
        }, 600);
    }

    // ========== 袖里乾坤 (空间术) ==========
    public static function castPocketDimension(fromX:Float, fromY:Float, toX:Float, toY:Float, layer:Object, scene:GameScene) {
        spawnCastEffect(fromX, fromY, 0xaa44ff, layer, scene);

        // 空间扭曲漩涡 - 持续吸入敌人
        var vortex = new SpaceVortex(layer, fromX, fromY, scene);
    }

    // ========== 莲花绽放 (佛门术) ==========
    public static function castLotusBloom(fromX:Float, fromY:Float, toX:Float, toY:Float, layer:Object, scene:GameScene) {
        spawnCastEffect(fromX, fromY, 0xffdd00, layer, scene);

        // 金莲绽放 - 范围净化+治疗+伤害亡灵类
        var lotus = new LotusBloomEffect(layer, toX, toY, scene);
    }

    // ========== 天罡北斗阵 (星辰术) ==========
    public static function castBigDipper(fromX:Float, fromY:Float, toX:Float, toY:Float, layer:Object, scene:GameScene) {
        spawnCastEffect(fromX, fromY, 0xaaaaff, layer, scene);

        // 北斗七星依次坠落
        var cx = toX;
        var cy = toY;
        var starPositions = [
            {dx: -90, dy: -60}, {dx: -50, dy: -30}, {dx: -10, dy: 0},
            {dx: 20, dy: 20}, {dx: 50, dy: 40}, {dx: 80, dy: 20}, {dx: 110, dy: -10}
        ];

        for (i in 0...starPositions.length) {
            haxe.Timer.delay(function() {
                if (scene != null) {
                    var sx = cx + starPositions[i].dx;
                    var sy = cy + starPositions[i].dy;
                    spawnStarFall(sx, sy, layer, scene);
                }
            }, Std.int(i * 150));
        }
    }

    // ========== 分影术 (幻术) ==========
    public static function castShadowClone(fromX:Float, fromY:Float, toX:Float, toY:Float, layer:Object, scene:GameScene) {
        spawnCastEffect(fromX, fromY, 0x44ffaa, layer, scene);

        // 创建3个分身，向不同方向发射法术
        var angles = [0.0, Math.PI * 2 / 3, Math.PI * 4 / 3];
        for (i in 0...3) {
            var angle = angles[i];
            haxe.Timer.delay(function() {
                if (scene != null) {
                    var cloneX = fromX + Math.cos(angle) * 40;
                    var cloneY = fromY + Math.sin(angle) * 40;

                    // 分身残影
                    for (j in 0...8) {
                        var p = scene.getParticle();
                        p.x = fromX + Math.cos(angle) * j * 5;
                        p.y = fromY + Math.sin(angle) * j * 5;
                        p.vx = 0;
                        p.vy = 0;
                        p.life = 0.3 + j * 0.05;
                        p.maxLife = p.life;
                        p.size = 6;
                        p.color = 0x44ffaa;
                        p.type = Glowing;
                        p.glow = true;
                        p.fade = true;
                        p.drag = 1.0;
                    }

                    // 分身发射火球
                    var tx = cloneX + Math.cos(angle) * 300;
                    var ty = cloneY + Math.sin(angle) * 300;
                    var fireball = new FireballProjectile(layer, cloneX, cloneY, tx, ty, scene);
                }
            }, Std.int(i * 100));
        }

        spawnRing(fromX, fromY, 0x44ffaa, 60, 0.3, layer, scene);
    }

    // ========== 乾坤大挪移 (位移术) ==========
    public static function castVoidShift(fromX:Float, fromY:Float, toX:Float, toY:Float, layer:Object, scene:GameScene) {
        spawnCastEffect(fromX, fromY, 0xff44aa, layer, scene);

        // 瞬移玩家到目标位置 + 冲击波
        var player = scene.player;

        // 起点残影
        for (i in 0...15) {
            var p = scene.getParticle();
            var angle = Math.random(Math.PI * 2);
            p.x = fromX;
            p.y = fromY;
            p.vx = Math.cos(angle) * randRange(50, 150);
            p.vy = Math.sin(angle) * randRange(50, 150);
            p.life = 0.4;
            p.maxLife = 0.4;
            p.size = randRange(3, 6);
            p.color = 0xff44aa;
            p.type = Glowing;
            p.glow = true;
            p.fade = true;
            p.drag = 0.92;
        }

        // 瞬移
        var clampedX = Math.clamp(toX, 20, scene.width - 20);
        var clampedY = Math.clamp(toY, 40, scene.height - 60);
        player.x = clampedX;
        player.y = clampedY;

        // 终点冲击波
        spawnExplosion(clampedX, clampedY, 0xff44aa, 100, layer, scene);
        spawnRing(clampedX, clampedY, 0xffffff, 120, 0.4, layer, scene);
        spawnRing(clampedX, clampedY, 0xff44aa, 80, 0.3, layer, scene);

        // 对周围敌人造成伤害+击退
        for (e in scene.enemies) {
            if (e.dead) continue;
            var dx = e.x - clampedX;
            var dy = e.y - clampedY;
            var distSq = dx * dx + dy * dy;
            if (distSq < 100 * 100) {
                scene.dealDamage(e, 70, dx * 3, dy * 3);
            }
        }
    }

    // ========== 通用特效 ==========

    static function spawnCastEffect(x:Float, y:Float, color:Int, layer:Object, scene:GameScene) {
        spawnRing(x, y, color, 50, 0.3, layer, scene);

        for (i in 0...12) {
            var p = scene.getParticle();
            var angle = Math.random(Math.PI * 2);
            var dist = randRange(20, 40);
            p.x = x + Math.cos(angle) * dist;
            p.y = y + Math.sin(angle) * dist;
            p.vx = -Math.cos(angle) * 80;
            p.vy = -Math.sin(angle) * 80;
            p.life = 0.4;
            p.maxLife = 0.4;
            p.size = randRange(2, 5);
            p.color = color;
            p.type = Glowing;
            p.glow = true;
            p.fade = true;
            p.drag = 0.92;
        }
    }

    public static function spawnRing(x:Float, y:Float, color:Int, maxRadius:Float, duration:Float, layer:Object, scene:GameScene) {
        var p = scene.getParticle();
        p.x = x;
        p.y = y;
        p.life = duration;
        p.maxLife = duration;
        p.color = color;
        p.type = Ring;
        p.ringExpand = maxRadius;
        p.ringMaxRadius = 0;
        p.glow = true;
        p.fade = true;
        p.drag = 0;
    }

    static function spawnLightning(x:Float, y:Float, layer:Object, scene:GameScene) {
        spawnCloud(x, y - 120, 0x3344aa, layer, scene);

        var segments = 8;
        var startX = x + randRange(-20, 20);
        var startY = y - 120;
        var points:Array<{x:Float, y:Float}> = [];
        for (i in 0...segments + 1) {
            var t = i / segments;
            var py = startY + (y - startY) * t;
            var px = x + (if (i == 0 || i == segments) 0.0 else randRange(-25, 25));
            points.push({x: px, y: py});
        }

        var lightning = new Graphics(layer);

        lightning.lineStyle(8, 0x3344aa, 0.3);
        drawZigzag(lightning, points);

        lightning.lineStyle(5, 0x66aaff, 0.6);
        drawZigzag(lightning, points);

        lightning.lineStyle(2, 0xffffff, 1);
        drawZigzag(lightning, points);

        haxe.Timer.delay(function() {
            if (lightning.parent != null) {
                lightning.remove();
            }
        }, 200);

        spawnExplosion(x, y, 0x66aaff, 60, layer, scene);

        for (e in scene.enemies) {
            if (e.dead) continue;
            var dx = e.x - x;
            var dy = e.y - y;
            if (dx * dx + dy * dy < 60 * 60) {
                scene.dealDamage(e, 80, dx * 2, dy * 2);
            }
        }
    }

    static function drawZigzag(g:Graphics, points:Array<{x:Float, y:Float}>) {
        if (points.length < 2) return;
        g.moveTo(points[0].x, points[0].y);
        for (i in 1...points.length) {
            g.lineTo(points[i].x, points[i].y);
        }
    }

    static function spawnCloud(x:Float, y:Float, color:Int, layer:Object, scene:GameScene) {
        for (i in 0...15) {
            var p = scene.getParticle();
            var angle = Math.random(Math.PI * 2);
            var dist = randRange(10, 30);
            p.x = x + Math.cos(angle) * dist;
            p.y = y + Math.sin(angle) * dist * 0.6;
            p.vx = randRange(-10, 10);
            p.vy = randRange(-5, 5);
            p.life = 0.6;
            p.maxLife = 0.6;
            p.size = randRange(8, 15);
            p.color = color;
            p.type = Normal;
            p.fade = true;
            p.drag = 0.95;
        }
    }

    static function spawnExplosion(x:Float, y:Float, color:Int, radius:Float, layer:Object, scene:GameScene) {
        spawnRing(x, y, 0xffffff, radius * 0.5, 0.2, layer, scene);
        spawnRing(x, y, color, radius, 0.4, layer, scene);

        var count = Std.int(radius / 3);
        for (i in 0...count) {
            var p = scene.getParticle();
            var angle = Math.random(Math.PI * 2);
            var speed = randRange(80, 250);
            p.x = x;
            p.y = y;
            p.vx = Math.cos(angle) * speed;
            p.vy = Math.sin(angle) * speed;
            p.life = randRange(0.3, 0.8);
            p.maxLife = p.life;
            p.size = randRange(3, 8);
            p.color = i % 3 == 0 ? 0xffffff : color;
            p.type = Spark;
            p.glow = true;
            p.fade = true;
            p.gravity = 50;
            p.drag = 0.94;
        }
    }

    static function spawnSwordBlade(fromX:Float, fromY:Float, toX:Float, toY:Float, angle:Float, layer:Object, scene:GameScene) {
        var sword = new SwordProjectile(layer, fromX, fromY, toX, toY, angle, scene);
    }

    public static function spawnScreenFlash(color:Int, intensity:Float, duration:Float, layer:Object, scene:GameScene) {
        var flash = new Bitmap(Tile.fromColor(color, 1, 1), layer);
        flash.scaleX = scene.width;
        flash.scaleY = scene.height;
        flash.alpha = intensity;

        haxe.Timer.delay(function() {
            if (flash.parent != null) {
                flash.remove();
            }
        }, Std.int(duration * 1000));
    }

    // ========== 星辰坠落特效 ==========
    static function spawnStarFall(x:Float, y:Float, layer:Object, scene:GameScene) {
        // 星辰从上方坠落
        var star = new Graphics(layer);

        // 外光晕
        star.beginFill(0x4444aa, 0.2);
        star.drawCircle(0, 0, 20);
        star.endFill();
        star.beginFill(0x6666ff, 0.4);
        star.drawCircle(0, 0, 12);
        star.endFill();
        star.beginFill(0xaabbff, 0.7);
        star.drawCircle(0, 0, 7);
        star.endFill();
        star.beginFill(0xffffff, 1);
        star.drawCircle(0, 0, 3);
        star.endFill();

        // 五角星形
        star.beginFill(0xffffff, 0.8);
        var r1 = 10.0;
        var r2 = 4.0;
        for (i in 0...5) {
            var a1 = (i / 5) * Math.PI * 2 - Math.PI / 2;
            var a2 = ((i + 0.5) / 5) * Math.PI * 2 - Math.PI / 2;
            if (i == 0) {
                star.moveTo(Math.cos(a1) * r1, Math.sin(a1) * r1);
            }
            star.lineTo(Math.cos(a2) * r2, Math.sin(a2) * r2);
            var a3 = ((i + 1) / 5) * Math.PI * 2 - Math.PI / 2;
            star.lineTo(Math.cos(a3) * r1, Math.sin(a3) * r1);
        }
        star.endFill();

        star.x = x;
        star.y = y - 300;

        // 拖尾
        for (i in 0...10) {
            var p = scene.getParticle();
            p.x = x + randRange(-3, 3);
            p.y = y - 300 + i * 20;
            p.vx = randRange(-5, 5);
            p.vy = randRange(20, 40);
            p.life = 0.5 + i * 0.05;
            p.maxLife = p.life;
            p.size = randRange(2, 5);
            p.color = 0xaabbff;
            p.type = Glowing;
            p.glow = true;
            p.fade = true;
            p.drag = 0.98;
        }

        // 下落动画
        var startY = y - 300;
        var fallTime = 0.4;
        var elapsed = 0.0;
        var arrived = false;

        var fallFunc = null;
        fallFunc = function() {
            elapsed += 0.016;
            var t = elapsed / fallTime;
            if (t >= 1.0) {
                if (!arrived) {
                    arrived = true;
                    // 爆炸
                    spawnExplosion(x, y, 0xaabbff, 80, layer, scene);
                    spawnRing(x, y, 0xffffff, 60, 0.3, layer, scene);

                    for (e in scene.enemies) {
                        if (e.dead) continue;
                        var dx = e.x - x;
                        var dy = e.y - y;
                        if (dx * dx + dy * dy < 70 * 70) {
                            scene.dealDamage(e, 50, dx * 1.5, dy * 1.5);
                        }
                    }

                    if (star.parent != null) star.remove();
                }
                return;
            }
            star.y = startY + (y - startY) * t;
            star.rotation = t * Math.PI * 2;
            star.alpha = 1.0 - t * 0.2;

            haxe.Timer.delay(fallFunc, 16);
        };
        haxe.Timer.delay(fallFunc, 16);
    }
}

// ========== 火球投射物 ==========
class FireballProjectile extends Object {
    var scene:GameScene;
    var targetX:Float;
    var targetY:Float;
    var angle:Float;
    var speed:Float = 400;
    var alive:Bool = true;
    var trailTimer:Float = 0;
    var core:Graphics;
    var age:Float = 0;

    static inline function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }

    public function new(parent:Object, x:Float, y:Float, tx:Float, ty:Float, s:GameScene) {
        super(parent);
        this.x = x;
        this.y = y;
        this.targetX = tx;
        this.targetY = ty;
        this.scene = s;
        this.angle = Math.atan2(ty - y, tx - x);

        core = new Graphics(this);
        redraw();
        rotation = angle;
    }

    function redraw() {
        core.clear();
        core.beginFill(0xff3300, 0.3);
        core.drawCircle(0, 0, 16);
        core.endFill();
        core.beginFill(0xff6600, 0.6);
        core.drawCircle(0, 0, 10);
        core.endFill();
        core.beginFill(0xffaa00, 0.8);
        core.drawCircle(0, 0, 6);
        core.endFill();
        core.beginFill(0xffffaa, 1);
        core.drawCircle(0, 0, 3);
        core.endFill();
    }

    function update(dt:Float) {
        if (!alive) return;
        age += dt;

        x += Math.cos(angle) * speed * dt;
        y += Math.sin(angle) * speed * dt;

        trailTimer += dt;
        if (trailTimer > 0.015) {
            trailTimer = 0;
            for (i in 0...3) {
                var p = scene.getParticle();
                p.x = x + randRange(-5, 5);
                p.y = y + randRange(-5, 5);
                p.vx = -Math.cos(angle) * 50 + randRange(-30, 30);
                p.vy = -Math.sin(angle) * 50 + randRange(-30, 30);
                p.life = randRange(0.2, 0.5);
                p.maxLife = p.life;
                p.size = randRange(4, 8);
                p.color = Math.random() > 0.5 ? 0xff6600 : 0xffaa00;
                p.type = Glowing;
                p.glow = true;
                p.fade = true;
                p.drag = 0.92;
            }
        }

        var pulse = 1.0 + Math.sin(age * 20) * 0.15;
        core.scaleX = pulse;
        core.scaleY = pulse;

        for (e in scene.enemies) {
            if (e.dead) continue;
            var dx = e.x - x;
            var dy = e.y - y;
            if (dx * dx + dy * dy < 20 * 20) {
                explode();
                return;
            }
        }

        if (x < -50 || x > scene.width + 50 || y < -50 || y > scene.height + 50) {
            alive = false;
            remove();
        }
    }

    function explode() {
        alive = false;

        for (i in 0...30) {
            var p = scene.getParticle();
            var a = Math.random(Math.PI * 2);
            var s = randRange(80, 250);
            p.x = x;
            p.y = y;
            p.vx = Math.cos(a) * s;
            p.vy = Math.sin(a) * s;
            p.life = randRange(0.4, 0.9);
            p.maxLife = p.life;
            p.size = randRange(4, 10);
            var colors = [0xff3300, 0xff6600, 0xffaa00, 0xffffaa];
            p.color = colors[Std.int(Math.random(4))];
            p.type = Spark;
            p.glow = true;
            p.fade = true;
            p.gravity = 30;
            p.drag = 0.93;
        }

        SpellSystem.spawnRing(x, y, 0xff6600, 80, 0.3, scene.fxLayer, scene);
        SpellSystem.spawnRing(x, y, 0xffffff, 40, 0.2, scene.fxLayer, scene);

        for (e in scene.enemies) {
            if (e.dead) continue;
            var dx = e.x - x;
            var dy = e.y - y;
            if (dx * dx + dy * dy < 80 * 80) {
                scene.dealDamage(e, 60, dx * 1.5, dy * 1.5);
            }
        }

        remove();
    }

    override function sync(ctx:h2d.RenderContext) {
        super.sync(ctx);
        if (alive) update(ctx.elapsedTime);
    }
}

// ========== 冰晶投射物 ==========
class IceProjectile extends Object {
    var scene:GameScene;
    var targetX:Float;
    var targetY:Float;
    var angle:Float;
    var speed:Float = 350;
    var alive:Bool = true;
    var trailTimer:Float = 0;
    var core:Graphics;
    var age:Float = 0;

    static inline function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
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

    public function new(parent:Object, x:Float, y:Float, tx:Float, ty:Float, s:GameScene) {
        super(parent);
        this.x = x;
        this.y = y;
        this.targetX = tx;
        this.targetY = ty;
        this.scene = s;
        this.angle = Math.atan2(ty - y, tx - x);

        core = new Graphics(this);
        redraw();
        rotation = angle;
    }

    function redraw() {
        core.clear();
        core.beginFill(0x88ddff, 0.2);
        core.drawCircle(0, 0, 14);
        core.endFill();
        core.beginFill(0xaaddff, 0.7);
        drawPolyShape(core, [0, -10, 7, 0, 0, 10, -7, 0]);
        core.endFill();
        core.beginFill(0xddffff, 0.9);
        drawPolyShape(core, [0, -5, 3, 0, 0, 5, -3, 0]);
        core.endFill();
        core.beginFill(0xffffff, 1);
        core.drawCircle(0, 0, 2);
        core.endFill();
    }

    function update(dt:Float) {
        if (!alive) return;
        age += dt;

        x += Math.cos(angle) * speed * dt;
        y += Math.sin(angle) * speed * dt;

        trailTimer += dt;
        if (trailTimer > 0.02) {
            trailTimer = 0;
            for (i in 0...2) {
                var p = scene.getParticle();
                p.x = x + randRange(-4, 4);
                p.y = y + randRange(-4, 4);
                p.vx = -Math.cos(angle) * 30 + randRange(-20, 20);
                p.vy = -Math.sin(angle) * 30 + randRange(-20, 20);
                p.life = randRange(0.3, 0.6);
                p.maxLife = p.life;
                p.size = randRange(3, 6);
                p.color = 0x88ddff;
                p.type = Glowing;
                p.glow = true;
                p.fade = true;
                p.drag = 0.9;
            }
        }

        core.rotation += dt * 10;

        for (e in scene.enemies) {
            if (e.dead) continue;
            var dx = e.x - x;
            var dy = e.y - y;
            if (dx * dx + dy * dy < 18 * 18) {
                explode();
                return;
            }
        }

        if (x < -50 || x > scene.width + 50 || y < -50 || y > scene.height + 50) {
            alive = false;
            remove();
        }
    }

    function explode() {
        alive = false;

        for (i in 0...25) {
            var p = scene.getParticle();
            var a = Math.random(Math.PI * 2);
            var s = randRange(60, 200);
            p.x = x;
            p.y = y;
            p.vx = Math.cos(a) * s;
            p.vy = Math.sin(a) * s;
            p.life = randRange(0.4, 0.8);
            p.maxLife = p.life;
            p.size = randRange(2, 6);
            var colors = [0x88ddff, 0xaaddff, 0xddffff, 0xffffff];
            p.color = colors[Std.int(Math.random(4))];
            p.type = Spark;
            p.glow = true;
            p.fade = true;
            p.gravity = 80;
            p.drag = 0.93;
        }

        SpellSystem.spawnRing(x, y, 0x88ddff, 70, 0.4, scene.fxLayer, scene);

        for (e in scene.enemies) {
            if (e.dead) continue;
            var dx = e.x - x;
            var dy = e.y - y;
            if (dx * dx + dy * dy < 70 * 70) {
                scene.dealDamage(e, 50, dx * 1.2, dy * 1.2);
                e.vx *= 0.3;
                e.vy *= 0.3;
            }
        }

        remove();
    }

    override function sync(ctx:h2d.RenderContext) {
        super.sync(ctx);
        if (alive) update(ctx.elapsedTime);
    }
}

// ========== 剑气投射物 ==========
class SwordProjectile extends Object {
    var scene:GameScene;
    var angle:Float;
    var speed:Float = 600;
    var alive:Bool = true;
    var core:Graphics;
    var age:Float = 0;
    var trailTimer:Float = 0;

    static inline function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
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

    public function new(parent:Object, x:Float, y:Float, tx:Float, ty:Float, a:Float, s:GameScene) {
        super(parent);
        this.x = x;
        this.y = y;
        this.angle = a;
        this.scene = s;

        core = new Graphics(this);
        redraw();
        rotation = angle;
    }

    function redraw() {
        core.clear();
        core.beginFill(0xffffff, 0.9);
        drawPolyShape(core, [30, 0, 15, -3, -10, -2, -15, 0, -10, 2, 15, 3]);
        core.endFill();

        core.beginFill(0xaaccff, 0.3);
        drawPolyShape(core, [35, 0, 15, -6, -15, -4, -20, 0, -15, 4, 15, 6]);
        core.endFill();

        core.beginFill(0xffffff, 1);
        core.drawCircle(30, 0, 2);
        core.endFill();
    }

    function update(dt:Float) {
        if (!alive) return;
        age += dt;

        x += Math.cos(angle) * speed * dt;
        y += Math.sin(angle) * speed * dt;

        trailTimer += dt;
        if (trailTimer > 0.01) {
            trailTimer = 0;
            var p = scene.getParticle();
            p.x = x - Math.cos(angle) * 15;
            p.y = y - Math.sin(angle) * 15;
            p.vx = -Math.cos(angle) * 20 + randRange(-10, 10);
            p.vy = -Math.sin(angle) * 20 + randRange(-10, 10);
            p.life = 0.2;
            p.maxLife = 0.2;
            p.size = randRange(2, 4);
            p.color = 0xeeeeff;
            p.type = Glowing;
            p.glow = true;
            p.fade = true;
            p.drag = 0.9;
        }

        for (e in scene.enemies) {
            if (e.dead) continue;
            var dx = e.x - x;
            var dy = e.y - y;
            if (dx * dx + dy * dy < 20 * 20) {
                scene.dealDamage(e, 40, Math.cos(angle) * 100, Math.sin(angle) * 100);
                for (i in 0...5) {
                    var p = scene.getParticle();
                    var sa = Math.random(Math.PI * 2);
                    var ss = randRange(50, 100);
                    p.x = e.x;
                    p.y = e.y;
                    p.vx = Math.cos(sa) * ss;
                    p.vy = Math.sin(sa) * ss;
                    p.life = 0.3;
                    p.maxLife = 0.3;
                    p.size = randRange(2, 4);
                    p.color = 0xeeeeff;
                    p.type = Spark;
                    p.glow = true;
                    p.fade = true;
                }
            }
        }

        if (x < -50 || x > scene.width + 50 || y < -50 || y > scene.height + 50) {
            alive = false;
            remove();
        }
    }

    override function sync(ctx:h2d.RenderContext) {
        super.sync(ctx);
        if (alive) update(ctx.elapsedTime);
    }
}

// ========== 空间漩涡 (袖里乾坤) ==========
class SpaceVortex extends Object {
    var scene:GameScene;
    var alive:Bool = true;
    var age:Float = 0;
    var duration:Float = 3.0;
    var radius:Float = 120;
    var core:Graphics;
    var swirl:Graphics;

    static inline function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }

    public function new(parent:Object, x:Float, y:Float, s:GameScene) {
        super(parent);
        this.x = x;
        this.y = y;
        this.scene = s;

        core = new Graphics(this);
        swirl = new Graphics(this);
    }

    function update(dt:Float) {
        if (!alive) return;
        age += dt;

        if (age >= duration) {
            // 最终爆炸
            alive = false;
            explode();
            return;
        }

        // 漩涡旋转
        swirl.rotation += dt * 8;
        core.rotation -= dt * 3;

        // 重绘
        swirl.clear();
        core.clear();

        var lifeRatio = 1.0 - (age / duration);

        // 漩涡螺旋线
        for (i in 0...6) {
            var startAngle = (i / 6) * Math.PI * 2 + age * 5;
            swirl.lineStyle(3, 0xaa44ff, 0.3 + lifeRatio * 0.3);
            swirl.moveTo(0, 0);
            for (j in 1...10) {
                var t = j / 10;
                var a = startAngle + t * Math.PI * 2;
                var r = radius * t;
                swirl.lineTo(Math.cos(a) * r, Math.sin(a) * r);
            }
        }

        // 中心球体
        core.beginFill(0x330066, 0.5);
        core.drawCircle(0, 0, 30);
        core.endFill();
        core.beginFill(0x6600aa, 0.6);
        core.drawCircle(0, 0, 18);
        core.endFill();
        core.beginFill(0xaa44ff, 0.8);
        core.drawCircle(0, 0, 10);
        core.endFill();
        core.beginFill(0xddaaff, 1);
        core.drawCircle(0, 0, 5);
        core.endFill();

        var pulse = 1.0 + Math.sin(age * 10) * 0.15;
        core.scaleX = pulse;
        core.scaleY = pulse;

        // 吸入敌人 + 持续伤害
        for (e in scene.enemies) {
            if (e.dead) continue;
            var dx = x - e.x;
            var dy = y - e.y;
            var distSq = dx * dx + dy * dy;
            if (distSq < radius * radius && distSq > 100) {
                var dist = Math.sqrt(distSq);
                var pullForce = 200 * dt;
                e.vx += (dx / dist) * pullForce;
                e.vy += (dy / dist) * pullForce;
            }
        }

        // 持续伤害
        if (Std.int(age * 4) != Std.int((age - dt) * 4)) {
            for (e in scene.enemies) {
                if (e.dead) continue;
                var dx = e.x - x;
                var dy = e.y - y;
                if (dx * dx + dy * dy < radius * radius) {
                    scene.dealDamage(e, 15, 0, 0);
                }
            }
        }

        // 漩涡粒子
        for (i in 0...3) {
            var p = scene.getParticle();
            var angle = Math.random(Math.PI * 2);
            var dist = randRange(radius * 0.5, radius);
            p.x = x + Math.cos(angle) * dist;
            p.y = y + Math.sin(angle) * dist;
            // 向中心吸入
            p.vx = -Math.cos(angle) * randRange(30, 80);
            p.vy = -Math.sin(angle) * randRange(30, 80);
            p.life = 0.5;
            p.maxLife = 0.5;
            p.size = randRange(2, 5);
            p.color = Math.random() > 0.5 ? 0xaa44ff : 0xddaaff;
            p.type = Glowing;
            p.glow = true;
            p.fade = true;
            p.drag = 0.95;
        }
    }

    function explode() {
        // 最终爆炸
        for (i in 0...40) {
            var p = scene.getParticle();
            var a = Math.random(Math.PI * 2);
            var s = randRange(100, 300);
            p.x = x;
            p.y = y;
            p.vx = Math.cos(a) * s;
            p.vy = Math.sin(a) * s;
            p.life = randRange(0.4, 1.0);
            p.maxLife = p.life;
            p.size = randRange(3, 8);
            var colors = [0x330066, 0x6600aa, 0xaa44ff, 0xddaaff, 0xffffff];
            p.color = colors[Std.int(Math.random(colors.length))];
            p.type = Spark;
            p.glow = true;
            p.fade = true;
            p.gravity = 30;
            p.drag = 0.93;
        }

        SpellSystem.spawnRing(x, y, 0xaa44ff, 150, 0.5, scene.fxLayer, scene);
        SpellSystem.spawnRing(x, y, 0xffffff, 80, 0.3, scene.fxLayer, scene);
        SpellSystem.spawnScreenFlash(0x440066, 0.3, 0.3, scene.fxLayer, scene);

        // 范围伤害
        for (e in scene.enemies) {
            if (e.dead) continue;
            var dx = e.x - x;
            var dy = e.y - y;
            if (dx * dx + dy * dy < 120 * 120) {
                scene.dealDamage(e, 100, dx * 2, dy * 2);
            }
        }

        remove();
    }

    override function sync(ctx:h2d.RenderContext) {
        super.sync(ctx);
        if (alive) update(ctx.elapsedTime);
    }
}

// ========== 金莲绽放 (莲花绽放) ==========
class LotusBloomEffect extends Object {
    var scene:GameScene;
    var alive:Bool = true;
    var age:Float = 0;
    var duration:Float = 1.5;
    var core:Graphics;

    static inline function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }

    public function new(parent:Object, x:Float, y:Float, s:GameScene) {
        super(parent);
        this.x = x;
        this.y = y;
        this.scene = s;

        core = new Graphics(this);
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

    function update(dt:Float) {
        if (!alive) return;
        age += dt;

        if (age >= duration) {
            alive = false;
            remove();
            return;
        }

        var t = age / duration;
        var lifeRatio = 1.0 - t;

        core.clear();

        // 莲花花瓣 (8片)
        var petalCount = 8;
        var bloomSize = 80 * (1.0 - Math.pow(1.0 - t, 3)); // ease-out

        for (i in 0...petalCount) {
            var angle = (i / petalCount) * Math.PI * 2;
            var px = Math.cos(angle) * bloomSize * 0.5;
            var py = Math.sin(angle) * bloomSize * 0.5;

            // 花瓣
            core.beginFill(0xffdd44, 0.3 * lifeRatio);
            drawPetal(core, px, py, angle, bloomSize * 0.4);
            core.endFill();

            core.beginFill(0xffaa00, 0.6 * lifeRatio);
            drawPetal(core, px, py, angle, bloomSize * 0.3);
            core.endFill();

            core.beginFill(0xffff88, 0.8 * lifeRatio);
            drawPetal(core, px, py, angle, bloomSize * 0.2);
            core.endFill();
        }

        // 中心金莲
        core.beginFill(0xffdd00, 0.9 * lifeRatio);
        core.drawCircle(0, 0, 15 * lifeRatio);
        core.endFill();
        core.beginFill(0xffffff, 1.0 * lifeRatio);
        core.drawCircle(0, 0, 8 * lifeRatio);
        core.endFill();
        core.beginFill(0xffdd00, 1.0);
        core.drawCircle(0, 0, 4 * lifeRatio);
        core.endFill();

        // 光波
        if (Std.int(age * 6) != Std.int((age - dt) * 6)) {
            SpellSystem.spawnRing(x, y, 0xffdd00, 100, 0.4, scene.fxLayer, scene);

            // 治疗玩家
            var player = scene.player;
            if (player != null && !player.dead) {
                player.hp = Math.min(player.maxHp, player.hp + 20);
            }

            // 伤害敌人
            for (e in scene.enemies) {
                if (e.dead) continue;
                var dx = e.x - x;
                var dy = e.y - y;
                if (dx * dx + dy * dy < 100 * 100) {
                    scene.dealDamage(e, 25, dx * 0.5, dy * 0.5);
                }
            }
        }

        // 金色粒子
        for (i in 0...2) {
            var p = scene.getParticle();
            var angle = Math.random(Math.PI * 2);
            var dist = randRange(20, 80);
            p.x = x + Math.cos(angle) * dist;
            p.y = y + Math.sin(angle) * dist;
            p.vx = -Math.cos(angle) * 30;
            p.vy = -Math.sin(angle) * 30 - 20;
            p.life = 0.6;
            p.maxLife = 0.6;
            p.size = randRange(3, 6);
            p.color = 0xffdd00;
            p.type = Glowing;
            p.glow = true;
            p.fade = true;
            p.drag = 0.95;
        }
    }

    function drawPetal(g:Graphics, x:Float, y:Float, angle:Float, size:Float) {
        var cosA = Math.cos(angle);
        var sinA = Math.sin(angle);
        // 椭圆形花瓣
        var points = [
            0.0, -size * 0.3,
            size * 0.5, -size * 0.1,
            size, 0.0,
            size * 0.5, size * 0.1,
            0.0, size * 0.3
        ];
        var rotated = [];
        var i = 0;
        while (i < points.length) {
            var px = points[i];
            var py = points[i + 1];
            rotated.push(x + px * cosA - py * sinA);
            rotated.push(y + px * sinA + py * cosA);
            i += 2;
        }
        drawPolyShape(g, rotated);
    }

    override function sync(ctx:h2d.RenderContext) {
        super.sync(ctx);
        if (alive) update(ctx.elapsedTime);
    }
}
