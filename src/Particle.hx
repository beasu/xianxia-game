import h2d.Object;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Graphics;
import h2d.Text;
import h2d.filter.Glow;
import hxd.Math;

/**
    Particle - 粒子(法术特效/伤害数字)
**/
enum ParticleType {
    Normal;
    Glowing;
    Trail;
    DamageNumber;
    DeathBurst;
    Spark;
    Rune;
    Ring;
    Slash;
}

class Particle extends Object {
    public var active:Bool = true;
    public var type:ParticleType = Normal;

    public var vx:Float = 0;
    public var vy:Float = 0;
    public var life:Float = 1.0;
    public var maxLife:Float = 1.0;
    public var size:Float = 4;
    public var color:Int = 0xffffff;
    public var gravity:Float = 0;
    public var fade:Bool = true;
    public var glow:Bool = false;
    public var rotSpeed:Float = 0;
    public var text:String;
    public var drag:Float = 0.98;

    public var trailLength:Int = 0;
    public var trailPoints:Array<{x:Float, y:Float}> = [];

    public var ringExpand:Float = 0;
    public var ringMaxRadius:Float = 0;

    public var wobble:Float = 0;
    public var wobbleFreq:Float = 0;

    var gfx:Graphics;
    var txt:Text;
    var glowFilter:Glow;

    // 辅助方法: 绘制多边形
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

    public function new(parent:Object) {
        super(parent);
        gfx = new Graphics(this);
        gfx.visible = false;
        txt = new Text(Main.cjkFont, this);
        txt.visible = false;
        txt.textAlign = Center;
        glowFilter = new Glow(0xffffff, 0.8, 4, 2, 1, true);
    }

    public function reset() {
        visible = true;
        alpha = 1;
        vx = 0;
        vy = 0;
        life = 1;
        maxLife = 1;
        size = 4;
        color = 0xffffff;
        gravity = 0;
        fade = true;
        glow = false;
        rotation = 0;
        rotSpeed = 0;
        text = null;
        drag = 0.98;
        trailLength = 0;
        trailPoints = [];
        ringExpand = 0;
        ringMaxRadius = 0;
        wobble = 0;
        wobbleFreq = 0;
        x = 0;
        y = 0;
        scaleX = 1;
        scaleY = 1;
        gfx.clear();
        gfx.visible = false;
        txt.visible = false;
        txt.text = "";
        filter = null;
        glowFilter = new Glow(0xffffff, 0.8, 4, 2, 1, true);
    }

    public function update(dt:Float) {
        if (!active) return;

        life -= dt;
        if (life <= 0) {
            GameScene.inst.recycleParticle(this);
            return;
        }

        vy += gravity * dt;
        x += vx * dt;
        y += vy * dt;
        vx *= Math.pow(drag, dt * 60);
        vy *= Math.pow(drag, dt * 60);

        rotation += rotSpeed * dt;

        if (trailLength > 0) {
            trailPoints.unshift({x: x, y: y});
            if (trailPoints.length > trailLength) trailPoints.pop();
        }

        if (ringExpand > 0) {
            var t = 1 - (life / maxLife);
            ringMaxRadius = ringExpand * t;
        }

        render();
    }

    function render() {
        var lifeRatio = life / maxLife;

        switch (type) {
            case DamageNumber:
                gfx.clear();
                gfx.visible = false;
                txt.visible = true;
                txt.text = text;
                txt.textColor = color;
                txt.scaleX = size / 8.0;
                txt.scaleY = size / 8.0;
                txt.alpha = fade ? lifeRatio : 1;
                if (glow) {
                    txt.dropShadow = {dx: 1, dy: 1, color: 0x000000, alpha: 0.8};
                }

            case Ring:
                gfx.visible = true;
                gfx.clear();
                gfx.lineStyle(2 + lifeRatio * 3, color, 1);
                gfx.beginFill(color, lifeRatio * 0.2);
                gfx.drawCircle(0, 0, ringMaxRadius);
                gfx.endFill();
                if (glow) {
                    // filter = glowFilter; // 禁用Glow以提升WebGL JS性能
                }

            case Slash:
                gfx.visible = true;
                gfx.clear();
                var len = size * (1 + (1 - lifeRatio) * 3);
                gfx.lineStyle(0);
                gfx.beginFill(color, lifeRatio);
                drawPolyShape(gfx, [
                    0, -2,
                    len * 0.3, -1,
                    len, 0,
                    len * 0.3, 1,
                    0, 2
                ]);
                gfx.endFill();
                gfx.rotation = rotation;
                if (glow) {
                    // filter = glowFilter; // 禁用Glow以提升WebGL JS性能
                }

            case Trail:
                gfx.visible = true;
                gfx.clear();
                if (trailPoints.length > 1) {
                    for (i in 0...trailPoints.length - 1) {
                        var p1 = trailPoints[i];
                        var alphaVal = (1 - i / trailPoints.length) * lifeRatio;
                        gfx.lineStyle(0);
                        gfx.beginFill(color, alphaVal);
                        var r = size * (1 - i / trailPoints.length);
                        gfx.drawCircle(p1.x - x, p1.y - y, r);
                        gfx.endFill();
                    }
                }
                gfx.beginFill(color, lifeRatio);
                gfx.drawCircle(0, 0, size);
                gfx.endFill();
                if (glow) {
                    // filter = glowFilter; // 禁用Glow以提升WebGL JS性能
                }

            default:
                gfx.visible = true;
                gfx.clear();

                if (type == Rune) {
                    gfx.lineStyle(1.5, color, 1);
                    gfx.beginFill(color, lifeRatio * 0.3);
                    var r = size;
                    gfx.moveTo(r, 0);
                    for (i in 1...7) {
                        var a = (i / 6) * Math.PI * 2 + rotation;
                        gfx.lineTo(Math.cos(a) * r, Math.sin(a) * r);
                    }
                    gfx.endFill();
                    gfx.beginFill(color, lifeRatio * 0.5);
                    gfx.drawCircle(0, 0, size * 0.4);
                    gfx.endFill();
                } else if (type == Spark) {
                    gfx.lineStyle(0);
                    gfx.beginFill(color, lifeRatio);
                    drawPolyShape(gfx, [
                        0, -size * 2,
                        size * 0.3, -size * 0.3,
                        size * 2, 0,
                        size * 0.3, size * 0.3,
                        0, size * 2,
                        -size * 0.3, size * 0.3,
                        -size * 2, 0,
                        -size * 0.3, -size * 0.3
                    ]);
                    gfx.endFill();
                } else {
                    gfx.beginFill(color, fade ? lifeRatio : 1);
                    gfx.drawCircle(0, 0, size * (fade ? lifeRatio : 1));
                    gfx.endFill();

                    if (glow) {
                        gfx.beginFill(color, lifeRatio * 0.2);
                        gfx.drawCircle(0, 0, size * 2);
                        gfx.endFill();
                    }
                }

                if (glow) {
                    // filter = glowFilter; // 禁用Glow以提升WebGL JS性能
                }
                gfx.rotation = rotation;
        }
    }
}
