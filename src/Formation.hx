import h2d.Object;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Graphics;
import h2d.filter.Glow;
import hxd.Math;

/**
    Formation - 阵法系统 (融入中国元素)

    八卦阵: 乾坤震巽坎离艮兑 - 困敌减速+持续伤害
    五行阵: 金木水火土 - 相生相克,五行轮转攻击
    太极图: 阴阳两仪 - 增益回血+减伤
    天罡北斗阵: 北斗七星 - 星辰之力攻击+减速
    九宫格阵: 洛书九宫 - 九宫格困敌+范围爆炸
**/
class Formation extends Object {
    public var type:String;
    public var radius:Float = 120;
    public var age:Float = 0;
    public var duration:Float = 10.0;
    public var alive:Bool = true;

    var effectTimer:Float = 0;
    var rotationSpeed:Float = 0.5;

    var baseLayer:Graphics;
    var runeLayer:Graphics;
    var animLayer:Graphics;
    var coreLayer:Graphics;

    static var baguaNames = ["乾", "兑", "离", "震", "巽", "坎", "艮", "坤"];
    static var baguaColors = [0xFFD700, 0xffffff, 0xff6600, 0x66ff66, 0x66aaff, 0x3366ff, 0xaa6644, 0xffaa44];

    static var wuxingNames = ["金", "木", "水", "火", "土"];
    static var wuxingColors = [0xffff00, 0x00ff00, 0x0066ff, 0xff3300, 0xaa6633];

    // 北斗七星
    static var beidouNames = ["天枢", "天璇", "天玑", "天权", "玉衡", "开阳", "摇光"];
    static var beidouColors = [0xaabbff, 0x8899ff, 0x6677ff, 0x4455ff, 0x88aaff, 0xaaccff, 0xddeeff];

    // 九宫格
    static var jiugongNames = ["坎", "坤", "震", "巽", "中", "乾", "兑", "艮", "离"];
    static var jiugongColors = [0x3366ff, 0xffaa44, 0x66ff66, 0x66aaff, 0xFFD700, 0xffaa00, 0xffffff, 0xaa6644, 0xff6600];

    var taijiRotation:Float = 0;

    public function new(type:String, parent:Object) {
        super(parent);
        this.type = type;
        init();
    }

    function init() {
        baseLayer = new Graphics(this);
        runeLayer = new Graphics(this);
        animLayer = new Graphics(this);
        coreLayer = new Graphics(this);

        switch (type) {
            case "bagua":
                radius = 130;
                rotationSpeed = 0.3;
            case "wuxing":
                radius = 120;
                rotationSpeed = 0.5;
            case "taiji":
                radius = 110;
                rotationSpeed = 0.4;
            case "beidou":
                radius = 140;
                rotationSpeed = 0.2;
            case "jiugong":
                radius = 130;
                rotationSpeed = 0.15;
        }

        drawFormation();
    }

    function drawFormation() {
        switch (type) {
            case "bagua": drawBagua();
            case "wuxing": drawWuxing();
            case "taiji": drawTaiji();
            case "beidou": drawBeidou();
            case "jiugong": drawJiugong();
        }
    }

    // 辅助: 设置线宽和颜色
    inline function setLine(g:Graphics, width:Float, color:Int, alpha:Float = 1) {
        g.lineStyle(width, color, alpha);
    }

    // 辅助: 画多边形
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

    // ========== 八卦阵 ==========
    function drawBagua() {
        baseLayer.clear();
        runeLayer.clear();

        var r = radius;

        // 外圈双环
        setLine(baseLayer, 3, 0xFFD700);
        baseLayer.drawCircle(0, 0, r);
        setLine(baseLayer, 1.5, 0xffaa00);
        baseLayer.drawCircle(0, 0, r - 8);
        baseLayer.drawCircle(0, 0, r + 6);

        // 八卦符文位置(8个方位)
        for (i in 0...8) {
            var angle = (i / 8) * Math.PI * 2 - Math.PI / 2;
            var rx = Math.cos(angle) * (r - 4);
            var ry = Math.sin(angle) * (r - 4);

            drawTrigram(runeLayer, rx, ry, angle, baguaColors[i], i);

            // 连线到中心
            setLine(baseLayer, 1, 0xFFD700, 0.15);
            baseLayer.moveTo(0, 0);
            baseLayer.lineTo(rx, ry);
        }

        // 中心法阵
        setLine(baseLayer, 2, 0xFFD700);
        baseLayer.drawCircle(0, 0, 25);
        setLine(baseLayer, 1, 0xFFD700);
        baseLayer.drawCircle(0, 0, 18);

        drawCentralRune(runeLayer, 0xFFD700);
    }

    function drawTrigram(g:Graphics, x:Float, y:Float, angle:Float, color:Int, index:Int) {
        // 手动旋转坐标绘制三爻卦象
        var cosA = Math.cos(angle + Math.PI / 2);
        var sinA = Math.sin(angle + Math.PI / 2);

        // 根据index确定卦象
        var yao:Array<Bool>; // true=阳爻(实线), false=阴爻(断线)
        switch (index) {
            case 0: yao = [true, true, true];      // 乾
            case 1: yao = [true, true, false];     // 兑
            case 2: yao = [true, false, true];     // 离
            case 3: yao = [false, false, true];    // 震
            case 4: yao = [true, false, false];    // 巽
            case 5: yao = [false, true, false];    // 坎
            case 6: yao = [false, true, true];     // 艮
            default: yao = [false, false, false];  // 坤
        }

        setLine(g, 2, color, 1);
        var yOff = -8.0;
        for (i in 0...3) {
            if (yao[i]) {
                // 阳爻 - 实线
                var x1 = -8, y1 = yOff, x2 = 8, y2 = yOff;
                g.moveTo(x + x1 * cosA - y1 * sinA, y + x1 * sinA + y1 * cosA);
                g.lineTo(x + x2 * cosA - y2 * sinA, y + x2 * sinA + y2 * cosA);
            } else {
                // 阴爻 - 断线
                var x1 = -8, y1 = yOff, x2 = -2, y2 = yOff;
                g.moveTo(x + x1 * cosA - y1 * sinA, y + x1 * sinA + y1 * cosA);
                g.lineTo(x + x2 * cosA - y2 * sinA, y + x2 * sinA + y2 * cosA);
                x1 = 2; x2 = 8;
                g.moveTo(x + x1 * cosA - y1 * sinA, y + x1 * sinA + y1 * cosA);
                g.lineTo(x + x2 * cosA - y2 * sinA, y + x2 * sinA + y2 * cosA);
            }
            yOff += 5;
        }
    }

    // ========== 五行阵 ==========
    function drawWuxing() {
        baseLayer.clear();
        runeLayer.clear();

        var r = radius;

        // 外圈
        setLine(baseLayer, 3, 0x00ff88);
        baseLayer.drawCircle(0, 0, r);
        setLine(baseLayer, 1, 0x00aa66);
        baseLayer.drawCircle(0, 0, r - 6);

        // 五角星(五行相克线)
        setLine(baseLayer, 2, 0x00ff88, 0.3);
        var starPoints = [];
        for (i in 0...5) {
            var a = (i / 5) * Math.PI * 2 - Math.PI / 2;
            starPoints.push({x: Math.cos(a) * (r - 15), y: Math.sin(a) * (r - 15)});
        }
        // 相克线: 0->2->4->1->3->0
        var keOrder = [0, 2, 4, 1, 3];
        baseLayer.moveTo(starPoints[keOrder[0]].x, starPoints[keOrder[0]].y);
        for (i in 1...5) {
            baseLayer.lineTo(starPoints[keOrder[i]].x, starPoints[keOrder[i]].y);
        }
        baseLayer.lineTo(starPoints[keOrder[0]].x, starPoints[keOrder[0]].y);

        // 五行节点
        for (i in 0...5) {
            var a = (i / 5) * Math.PI * 2 - Math.PI / 2;
            var px = Math.cos(a) * (r - 15);
            var py = Math.sin(a) * (r - 15);

            baseLayer.beginFill(wuxingColors[i], 0.3);
            baseLayer.drawCircle(px, py, 14);
            baseLayer.endFill();
            baseLayer.beginFill(wuxingColors[i], 0.6);
            baseLayer.drawCircle(px, py, 10);
            baseLayer.endFill();

            drawWuxingSymbol(runeLayer, px, py, i, wuxingColors[i]);

            // 相生线(相邻连线)
            var next = (i + 1) % 5;
            var na = (next / 5) * Math.PI * 2 - Math.PI / 2;
            var nx = Math.cos(na) * (r - 15);
            var ny = Math.sin(na) * (r - 15);
            setLine(baseLayer, 1.5, 0x00ff88, 0.5);
            baseLayer.moveTo(px, py);
            baseLayer.lineTo(nx, ny);
        }

        // 中心
        setLine(baseLayer, 2, 0x00ff88);
        baseLayer.drawCircle(0, 0, 20);
        drawCentralRune(runeLayer, 0x00ff88);
    }

    function drawWuxingSymbol(g:Graphics, x:Float, y:Float, index:Int, color:Int) {
        setLine(g, 1.5, color, 1);

        switch (index) {
            case 0: // 金 - 锐角形
                g.beginFill(color, 0.5);
                drawPolyShape(g, [x, y - 6, x + 4, y + 3, x - 4, y + 3]);
                g.endFill();
            case 1: // 木 - 树形
                g.moveTo(x, y - 6);
                g.lineTo(x, y + 6);
                g.moveTo(x - 4, y - 2);
                g.lineTo(x, y - 6);
                g.lineTo(x + 4, y - 2);
            case 2: // 水 - 波浪
                g.moveTo(x - 5, y);
                g.lineTo(x - 2, y - 3);
                g.lineTo(x + 1, y);
                g.lineTo(x + 4, y - 3);
            case 3: // 火 - 火焰形
                g.beginFill(color, 0.5);
                drawPolyShape(g, [x, y - 6, x + 3, y, x + 2, y + 4, x - 2, y + 4, x - 3, y]);
                g.endFill();
            case 4: // 土 - 方形
                g.drawRect(x - 4, y - 4, 8, 8);
        }
    }

    // ========== 太极图 ==========
    function drawTaiji() {
        baseLayer.clear();
        runeLayer.clear();

        var r = radius;

        // 外圈
        setLine(baseLayer, 3, 0xffffff);
        baseLayer.drawCircle(0, 0, r);
        setLine(baseLayer, 1, 0xaaaaaa);
        baseLayer.drawCircle(0, 0, r - 6);

        // 太极图(阴阳鱼)
        drawTaijiDiagram(baseLayer, 0, 0, r - 12);

        // 外围八卦装饰
        for (i in 0...8) {
            var angle = (i / 8) * Math.PI * 2;
            var rx = Math.cos(angle) * (r + 2);
            var ry = Math.sin(angle) * (r + 2);
            setLine(baseLayer, 1, 0xffffff, 0.3);
            baseLayer.moveTo(rx, ry);
            baseLayer.lineTo(rx + Math.cos(angle) * 5, ry + Math.sin(angle) * 5);
        }
    }

    function drawTaijiDiagram(g:Graphics, cx:Float, cy:Float, r:Float) {
        // 阳鱼(白) - 底层大圆
        g.beginFill(0xffffff, 0.9);
        g.drawCircle(cx, cy, r);
        g.endFill();

        // 阴鱼(黑) - 右半
        g.beginFill(0x000000, 0.9);
        g.drawCircle(cx + r * 0.5, cy, r * 0.5);
        g.endFill();

        // 阳鱼(白) - 左半的小圆
        g.beginFill(0xffffff, 0.9);
        g.drawCircle(cx - r * 0.5, cy, r * 0.5);
        g.endFill();

        // S曲线 - 用黑色半圆覆盖右侧
        g.beginFill(0x000000, 0.9);
        g.drawCircle(cx + r * 0.5, cy, r * 0.5);
        g.endFill();

        // 阳中之阴(黑点)
        g.beginFill(0x000000, 0.9);
        g.drawCircle(cx - r * 0.5, cy, r * 0.15);
        g.endFill();

        // 阴中之阳(白点)
        g.beginFill(0xffffff, 0.9);
        g.drawCircle(cx + r * 0.5, cy, r * 0.15);
        g.endFill();

        // 外圆边界
        setLine(g, 2, 0xffffff);
        g.drawCircle(cx, cy, r);
    }

    // ========== 天罡北斗阵 ==========
    function drawBeidou() {
        baseLayer.clear();
        runeLayer.clear();

        var r = radius;

        // 外圈
        setLine(baseLayer, 3, 0xaaaaff);
        baseLayer.drawCircle(0, 0, r);
        setLine(baseLayer, 1, 0x6677aa);
        baseLayer.drawCircle(0, 0, r - 6);

        // 北斗七星连线 (斗柄到斗勺)
        var starPos = [];
        for (i in 0...7) {
            var a = (i / 6) * Math.PI * 0.8 - Math.PI * 0.3;
            var dist = r * 0.6;
            starPos.push({x: Math.cos(a) * dist, y: Math.sin(a) * dist});
        }

        // 连线
        setLine(baseLayer, 2, 0xaaaaff, 0.4);
        baseLayer.moveTo(starPos[0].x, starPos[0].y);
        for (i in 1...starPos.length) {
            baseLayer.lineTo(starPos[i].x, starPos[i].y);
        }

        // 星位点
        for (i in 0...7) {
            var sp = starPos[i];
            baseLayer.beginFill(beidouColors[i], 0.2);
            baseLayer.drawCircle(sp.x, sp.y, 14);
            baseLayer.endFill();
            baseLayer.beginFill(beidouColors[i], 0.5);
            baseLayer.drawCircle(sp.x, sp.y, 9);
            baseLayer.endFill();
            baseLayer.beginFill(0xffffff, 0.8);
            baseLayer.drawCircle(sp.x, sp.y, 4);
            baseLayer.endFill();

            // 五角星标记
            setLine(runeLayer, 1.5, beidouColors[i], 0.8);
            for (j in 0...5) {
                var a1 = (j / 5) * Math.PI * 2 - Math.PI / 2;
                var a2 = ((j + 2) / 5) * Math.PI * 2 - Math.PI / 2;
                runeLayer.moveTo(sp.x + Math.cos(a1) * 6, sp.y + Math.sin(a1) * 6);
                runeLayer.lineTo(sp.x + Math.cos(a2) * 6, sp.y + Math.sin(a2) * 6);
            }
        }

        // 外围星辰装饰
        for (i in 0...24) {
            var angle = (i / 24) * Math.PI * 2;
            var dr = r + 4;
            var px = Math.cos(angle) * dr;
            var py = Math.sin(angle) * dr;
            baseLayer.beginFill(0xaabbff, 0.4);
            baseLayer.drawCircle(px, py, 2);
            baseLayer.endFill();
        }

        // 中心
        setLine(baseLayer, 2, 0xaaaaff);
        baseLayer.drawCircle(0, 0, 25);
        drawCentralRune(runeLayer, 0xaaaaff);
    }

    // ========== 九宫格阵 ==========
    function drawJiugong() {
        baseLayer.clear();
        runeLayer.clear();

        var r = radius;

        // 外圈
        setLine(baseLayer, 3, 0xFFD700);
        baseLayer.drawCircle(0, 0, r);
        setLine(baseLayer, 1, 0xaa8800);
        baseLayer.drawCircle(0, 0, r - 6);

        // 九宫格 (3x3)
        var gridSize = r * 0.7;
        var cellSize = gridSize * 2 / 3;

        for (row in 0...3) {
            for (col in 0...3) {
                var cx = -gridSize + col * cellSize + cellSize / 2;
                var cy = -gridSize + row * cellSize + cellSize / 2;
                var idx = row * 3 + col;

                // 格子边框
                setLine(baseLayer, 2, 0xFFD700, 0.5);
                baseLayer.drawRect(cx - cellSize / 2, cy - cellSize / 2, cellSize, cellSize);

                // 格子内符文
                baseLayer.beginFill(jiugongColors[idx], 0.15);
                baseLayer.drawRect(cx - cellSize / 2, cy - cellSize / 2, cellSize, cellSize);
                baseLayer.endFill();

                // 符文圆
                baseLayer.beginFill(jiugongColors[idx], 0.3);
                baseLayer.drawCircle(cx, cy, cellSize * 0.3);
                baseLayer.endFill();

                setLine(runeLayer, 1.5, jiugongColors[idx], 0.8);
                // 简化的卦象符号
                var yao = switch (idx) {
                    case 0: [false, true, false];
                    case 1: [false, false, false];
                    case 2: [false, false, true];
                    case 3: [true, false, false];
                    case 4: [true, true, true];
                    case 5: [true, true, false];
                    case 6: [false, true, true];
                    case 7: [false, false, false];
                    default: [true, false, true];
                };
                var yOff = -5.0;
                for (yi in 0...3) {
                    if (yao[yi]) {
                        runeLayer.moveTo(cx - 6, cy + yOff);
                        runeLayer.lineTo(cx + 6, cy + yOff);
                    } else {
                        runeLayer.moveTo(cx - 6, cy + yOff);
                        runeLayer.lineTo(cx - 1, cy + yOff);
                        runeLayer.moveTo(cx + 1, cy + yOff);
                        runeLayer.lineTo(cx + 6, cy + yOff);
                    }
                    yOff += 4;
                }
            }
        }

        // 中心法阵
        setLine(baseLayer, 2, 0xFFD700);
        baseLayer.drawCircle(0, 0, 20);
        drawCentralRune(runeLayer, 0xFFD700);
    }

    // ========== 中心符文 ==========
    function drawCentralRune(g:Graphics, color:Int) {
        setLine(g, 1.5, color, 1);
        // 六芒星
        var r = 12;
        for (i in 0...2) {
            var offset = i * Math.PI / 2;
            g.moveTo(Math.cos(offset) * r, Math.sin(offset) * r);
            for (j in 1...4) {
                var a = offset + (j / 3) * Math.PI * 2;
                g.lineTo(Math.cos(a) * r, Math.sin(a) * r);
            }
            g.lineTo(Math.cos(offset) * r, Math.sin(offset) * r);
        }
        g.beginFill(color, 0.8);
        g.drawCircle(0, 0, 3);
        g.endFill();
    }

    // ========== 更新 ==========
    public function update(dt:Float) {
        age += dt;

        runeLayer.rotation += rotationSpeed * dt;
        animLayer.rotation -= rotationSpeed * 0.7 * dt;

        if (type == "taiji") {
            taijiRotation += dt * 0.8;
            baseLayer.rotation = taijiRotation * 0.3;
        }

        var pulse = 1.0 + Math.sin(age * 2) * 0.03;
        baseLayer.scaleX = pulse;
        baseLayer.scaleY = pulse;

        animLayer.clear();
        drawAnimation(dt);

        if (age > duration) {
            alpha -= dt * 2;
            if (alpha <= 0) {
                alive = false;
                destroy();
            }
        }

        effectTimer += dt;
        if (effectTimer > 0.5) {
            effectTimer = 0;
            applyAreaEffect();
        }
    }

    function drawAnimation(dt:Float) {
        switch (type) {
            case "bagua":
                for (i in 0...8) {
                    var angle = (i / 8) * Math.PI * 2 + age * rotationSpeed;
                    var r = radius - 4;
                    var px = Math.cos(angle) * r;
                    var py = Math.sin(angle) * r;
                    animLayer.beginFill(baguaColors[i], 0.6 + Math.sin(age * 3 + i) * 0.3);
                    animLayer.drawCircle(px, py, 4);
                    animLayer.endFill();
                }
                var pulseR = 10 + Math.sin(age * 4) * 5;
                animLayer.beginFill(0xFFD700, 0.3);
                animLayer.drawCircle(0, 0, pulseR);
                animLayer.endFill();

            case "wuxing":
                for (i in 0...5) {
                    var baseAngle = (i / 5) * Math.PI * 2 - Math.PI / 2;
                    var flowAngle = baseAngle + age * rotationSpeed;
                    var r = radius - 15;
                    var px = Math.cos(flowAngle) * r;
                    var py = Math.sin(flowAngle) * r;

                    animLayer.beginFill(wuxingColors[i], 0.7);
                    animLayer.drawCircle(px, py, 5);
                    animLayer.endFill();

                    for (j in 1...5) {
                        var trailAngle = flowAngle - j * 0.08;
                        var tx = Math.cos(trailAngle) * r;
                        var ty = Math.sin(trailAngle) * r;
                        animLayer.beginFill(wuxingColors[i], 0.3 - j * 0.05);
                        animLayer.drawCircle(tx, ty, 3);
                        animLayer.endFill();
                    }
                }

            case "taiji":
                for (i in 0...12) {
                    var angle = (i / 12) * Math.PI * 2 + age * 0.8;
                    var r = radius * 0.5 + Math.sin(age * 2 + i) * 20;
                    var px = Math.cos(angle) * r;
                    var py = Math.sin(angle) * r;
                    var isYang = i % 2 == 0;
                    animLayer.beginFill(isYang ? 0xffffff : 0x333366, 0.3);
                    animLayer.drawCircle(px, py, 3);
                    animLayer.endFill();
                }

            case "beidou":
                // 七星脉动
                for (i in 0...7) {
                    var a = (i / 6) * Math.PI * 0.8 - Math.PI * 0.3;
                    var dist = radius * 0.6;
                    var px = Math.cos(a) * dist;
                    var py = Math.sin(a) * dist;
                    var pulse = 0.5 + Math.sin(age * 4 + i * 0.8) * 0.5;
                    animLayer.beginFill(beidouColors[i], pulse * 0.5);
                    animLayer.drawCircle(px, py, 12);
                    animLayer.endFill();
                    animLayer.beginFill(0xffffff, pulse * 0.6);
                    animLayer.drawCircle(px, py, 5);
                    animLayer.endFill();
                }
                // 星辰轨道
                for (i in 0...12) {
                    var angle = (i / 12) * Math.PI * 2 + age * 0.5;
                    var r = radius * 0.8 + Math.sin(age * 3 + i) * 10;
                    var px = Math.cos(angle) * r;
                    var py = Math.sin(angle) * r;
                    animLayer.beginFill(0xaabbff, 0.3);
                    animLayer.drawCircle(px, py, 2);
                    animLayer.endFill();
                }

            case "jiugong":
                // 九宫格交替闪烁
                for (row in 0...3) {
                    for (col in 0...3) {
                        var gridSize = radius * 0.7;
                        var cellSize = gridSize * 2 / 3;
                        var cx = -gridSize + col * cellSize + cellSize / 2;
                        var cy = -gridSize + row * cellSize + cellSize / 2;
                        var idx = row * 3 + col;
                        var pulse = 0.3 + Math.sin(age * 3 + idx * 0.7) * 0.3;
                        animLayer.beginFill(jiugongColors[idx], pulse);
                        animLayer.drawCircle(cx, cy, cellSize * 0.25);
                        animLayer.endFill();
                    }
                }
                // 流转粒子
                var flowAngle = age * 1.5;
                var flowR = radius * 0.5;
                animLayer.beginFill(0xFFD700, 0.6);
                animLayer.drawCircle(Math.cos(flowAngle) * flowR, Math.sin(flowAngle) * flowR, 4);
                animLayer.endFill();
        }
    }

    public function applyEffect(target:Cultivator, dt:Float) {
        switch (type) {
            case "bagua":
                target.vx *= 0.95;
                target.vy *= 0.95;
            case "beidou":
                // 北斗阵: 减速+持续星辰伤害
                target.vx *= 0.93;
                target.vy *= 0.93;
            case "jiugong":
                // 九宫阵: 强力困敌
                target.vx *= 0.9;
                target.vy *= 0.9;
            case "wuxing":
                // 在applyAreaEffect中处理
            case "taiji":
                if (target.isPlayer) {
                    target.hp = Math.min(target.maxHp, target.hp + 10 * dt);
                }
            default:
        }
    }

    function applyAreaEffect() {
        if (GameScene.inst == null) return;

        switch (type) {
            case "bagua":
                for (e in GameScene.inst.enemies) {
                    if (e.dead) continue;
                    var dx = e.x - x;
                    var dy = e.y - y;
                    if (dx * dx + dy * dy < radius * radius) {
                        GameScene.inst.dealDamage(e, 5, 0, 0);
                        var p = GameScene.inst.getParticle();
                        p.x = e.x;
                        p.y = e.y;
                        p.vx = Math.random(60) - 30;
                        p.vy = Math.random(40) - 60;
                        p.life = 0.4;
                        p.maxLife = 0.4;
                        p.size = 3;
                        p.color = 0xFFD700;
                        p.type = Glowing;
                        p.glow = true;
                        p.fade = true;
                    }
                }

            case "wuxing":
                var element = Std.int(age * 2) % 5;
                for (e in GameScene.inst.enemies) {
                    if (e.dead) continue;
                    var dx = e.x - x;
                    var dy = e.y - y;
                    if (dx * dx + dy * dy < radius * radius) {
                        GameScene.inst.dealDamage(e, 8, dx * 0.3, dy * 0.3);
                        var p = GameScene.inst.getParticle();
                        p.x = e.x;
                        p.y = e.y;
                        p.vx = Math.random(80) - 40;
                        p.vy = Math.random(60) - 80;
                        p.life = 0.5;
                        p.maxLife = 0.5;
                        p.size = 4;
                        p.color = wuxingColors[element];
                        p.type = Spark;
                        p.glow = true;
                        p.fade = true;
                    }
                }

            case "taiji":
                var p = GameScene.inst.player;
                for (i in 0...3) {
                    var particle = GameScene.inst.getParticle();
                    var angle = Math.random(Math.PI * 2);
                    particle.x = p.x + Math.cos(angle) * 20;
                    particle.y = p.y + Math.sin(angle) * 20;
                    particle.vx = Math.cos(angle) * -30;
                    particle.vy = Math.sin(angle) * -30 - 20;
                    particle.life = 0.5;
                    particle.maxLife = 0.5;
                    particle.size = 3;
                    particle.color = 0xffffff;
                    particle.type = Glowing;
                    particle.glow = true;
                    particle.fade = true;
                }

            case "beidou":
                // 北斗阵: 随机星辰打击
                var starIdx = Std.int(age * 3) % 7;
                for (e in GameScene.inst.enemies) {
                    if (e.dead) continue;
                    var dx = e.x - x;
                    var dy = e.y - y;
                    if (dx * dx + dy * dy < radius * radius) {
                        GameScene.inst.dealDamage(e, 10, 0, 0);
                        // 星辰粒子
                        var p = GameScene.inst.getParticle();
                        p.x = e.x;
                        p.y = e.y;
                        p.vx = Math.random(40) - 20;
                        p.vy = Math.random(40) - 60;
                        p.life = 0.6;
                        p.maxLife = 0.6;
                        p.size = randRange2(3, 6);
                        p.color = beidouColors[starIdx];
                        p.type = Spark;
                        p.glow = true;
                        p.fade = true;
                        p.gravity = 30;
                    }
                }
                // 随机星辰光柱
                if (Math.random() < 0.5) {
                    var angle = Math.random(Math.PI * 2);
                    var dist = Math.random(radius * 0.7);
                    var px = x + Math.cos(angle) * dist;
                    var py = y + Math.sin(angle) * dist;
                    var p = GameScene.inst.getParticle();
                    p.x = px;
                    p.y = py;
                    p.vx = 0;
                    p.vy = 0;
                    p.life = 0.3;
                    p.maxLife = 0.3;
                    p.size = randRange2(5, 10);
                    p.color = 0xaabbff;
                    p.type = Glowing;
                    p.glow = true;
                    p.fade = true;
                }

            case "jiugong":
                // 九宫阵: 按九宫顺序爆炸
                var cellIdx = Std.int(age * 2) % 9;
                var row = Std.int(cellIdx / 3);
                var col = cellIdx % 3;
                var gridSize = radius * 0.7;
                var cellSize = gridSize * 2 / 3;
                var cx = x - gridSize + col * cellSize + cellSize / 2;
                var cy = y - gridSize + row * cellSize + cellSize / 2;

                for (e in GameScene.inst.enemies) {
                    if (e.dead) continue;
                    var dx = e.x - cx;
                    var dy = e.y - cy;
                    if (dx * dx + dy * dy < cellSize * cellSize) {
                        GameScene.inst.dealDamage(e, 12, dx * 0.5, dy * 0.5);
                    }
                }
                // 格子爆发粒子
                for (i in 0...5) {
                    var p = GameScene.inst.getParticle();
                    var a = Math.random(Math.PI * 2);
                    var s = randRange2(30, 80);
                    p.x = cx;
                    p.y = cy;
                    p.vx = Math.cos(a) * s;
                    p.vy = Math.sin(a) * s;
                    p.life = 0.4;
                    p.maxLife = 0.4;
                    p.size = randRange2(2, 5);
                    p.color = jiugongColors[cellIdx];
                    p.type = Spark;
                    p.glow = true;
                    p.fade = true;
                }

            default:
        }
    }

    static inline function randRange2(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }

    public function destroy() {
        alive = false;
        if (parent != null) remove();
    }
}
