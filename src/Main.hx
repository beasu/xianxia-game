import hxd.App;
import hxd.res.DefaultFont;
import hxd.res.FontBuilder;
import haxe.ui.core.Screen;
import haxe.ui.Toolkit;
import Std;

#if js
import js.Browser;
#end

class Main extends App {
    public static var inst:Main;

    public var game:GameScene;
    public static var cjkFont:h2d.Font;

    override function init() {
        inst = this;
        engine.backgroundColor = 0x0a0a1a;

        // 初始化 HaxeUI Toolkit
        Toolkit.init();

        // 创建支持中文的字体并替换默认字体
        #if js
        untyped js.Browser.window.Main = Main;

        // 用 2x 超采样创建字体: 先以 32px 渲染高分辨率纹理, 再 resizeTo(16) 缩小
        // 这样纹理是 2x 分辨率, 显示时缩小一半, 效果远优于直接 16px 渲染
        // 按优先级尝试中文字体: SimHei(黑体) > Microsoft YaHei(微软雅黑) > PingFang SC > 默认
        var fontNames = ["SimHei", "Microsoft YaHei", "PingFang SC", "Heiti SC", "WenQuanYi Micro Hei"];
        var fontCreated = false;
        for (fName in fontNames) {
            try {
                cjkFont = FontBuilder.getFont(fName, 32, { chars: getCJKChars(), antiAliasing: true });
                cjkFont.resizeTo(16);
                @:privateAccess h3d.Engine.getCurrent().resCache.set(hxd.res.DefaultFont, cjkFont);
                Browser.console.log('[FONT] OK: "' + fName + '" 32px -> resizeTo(16), 2x supersampling');
                fontCreated = true;
                break;
            } catch(e:Dynamic) {
                Browser.console.log('[FONT] Skip "' + fName + '": ' + Std.string(e));
            }
        }
        if (!fontCreated) {
            // fallback: 直接 16px 渲染
            for (fName in fontNames) {
                try {
                    cjkFont = FontBuilder.getFont(fName, 16, { chars: getCJKChars(), antiAliasing: true });
                    @:privateAccess h3d.Engine.getCurrent().resCache.set(hxd.res.DefaultFont, cjkFont);
                    Browser.console.log('[FONT] Fallback OK: "' + fName + '" 16px');
                    fontCreated = true;
                    break;
                } catch(_) {}
            }
            if (!fontCreated) {
                cjkFont = hxd.res.DefaultFont.get();
                Browser.console.log("[FONT] All CJK fonts failed, using DefaultFont (中文可能不显示)");
            }
        }
        #else
        cjkFont = hxd.res.DefaultFont.get();
        #end

        game = new GameScene();
        setScene(game);
    }

    static function getCJKChars():String {
        var chars = hxd.Charset.ASCII;
        // 自动提取的所有中文字符(去重)
        chars += "一七万三上下不与世业丝两个中丹为主丽举么义之乘九书买乾了争事于云互五亡交享亮人什仇仍从他仙令以仪仲件优会伤估位低体佛佩使供依侧保信修倍值做元先光克兑兜入全八六共关其兼兽内册再冥冰冲决冷冻净准凋减凝凡出击分切列创初判到制前剑力办功加动助劫势勺包化北升半华单卖卦印却历去双反发取受变叠口只可史右号合同名后向含吸员周和品响售善嘴器四回因困围国图圆圈土在地场坎坐坠坤型基境增士声处备复外多够大天太夫失头夺如妖妙始婪婴子字存宗定宝实宫害家容宽察对寻寿射将小少尖尘尝尽尾局层屏属屠山巡巢左已巽币市布带帧常帽年并幻幽庄序库应底度建开异引弟张弯弱弹强归当录形影径得御循微德心忆志快态性总恢息恶悬情意感慢慧戏成或战所手才打执扩扭找技投拍拖招拟拿持指按挪换据掌排接提搜摆摇擎支收攻放效敌教散数整文斗料斩断新方施旋无日旧时明易星映昧昭是显晕景晶智暗暴曲更替最有期木未本术机杀权材条来板极果枢架柄染查柱标栏树核根格框检椭楷概模次正步死殊残段每毛气水汐没治法波注泽洛活流测济浓浪浮消涡淡深添清渊渐渡渲游源满演漩漫潮火灭灵炸点炼烁烈焰然照爆爪爻片版牙物特状狂献獠玄率玉玑玩环现珠球理璇瓣生用由甲电画界留疗疯白的皮益盔盖目直相眉真眼睛瞄瞬石破础确示神禁离秒积称移穴空突立符第等筑策简算管簪类粒系素索紫累红级纪纯纹线练组细终经绕绘给统续绸综绽绿缉缓缝缩罡置老者而耗耳肤肩背胸能脉脏腰腿臂自至艮良色节芒花苍范草药莲获落著虚融螺血行衡衣表衬衰袍袖被裁裂装褶覆观角触计订认让记设诀评试详谁调象负贡责败货质贪购资赋赏赖赤走起足跑路身轨转轮轻载辅辑输辰边达过运近返这连退逃透逐通速造逸逻遍道邪邻部都配采释里重野量金链锐长门闪闲间阁阅队阳阴阵阶附除随集零雷震青静非靠面顶顺领颜额飘飞饰驱驻验高髻魔鱼黑默鼎鼠齐龄暂停速增加减倍率倍速时时间倍→☀⛈❄、。【】且丘丛东临乃乎也乱二些产亲仅代价任份伏传伪但何余作例侠侣侵便倒债倾偏偶傅储像允充兆免公兵具况凌几划则删利刷刺削剩劈务匹区十千午占危即卷压原参及友叛古叹各否启命喷嗣噪噬固均域堪填墨壳夜央奏女好姓姻威孔学它守完密寸导尔尺居展岁崩差师幅幕干平幸广廓延弃式弦弧待很徒忠忽怒恕悟懒我戮扇扣扫承把抖折护报抵担拉拜拥择括挂挡振捕损捡捷授掉探控推描插援携摘摩撒撞擅操擦改斑族昏昼晋晓晚普晴月服朗朝束构林枚枯柏某柔样案棕森槛横橙欠欲歇止此殒毁母比民汇沙洗海涌涨混溃滑滔滴漠激灰灼烟烧熟燃父爽牛牵犹狠独猎猛略盛盟盾看眩眷着瞳知矩短碎碰磁社种秘窃窗竭端筛簇米精糊紊繁织结继维编缘缠网罚翠翻考联聚肆育脚脱腥致舆艳苏若茂荡蓝藏虐虑蜕蠢补裔裕要见规视觉警许访证识诚诞询该读谋谱貌超越趋跃距跟跳踪软轴较辈辉辟辨还进远迟迷追送适逆选递遗遭遮遵避醒钟钮钵铁锁锋键镜闭问阈阔防阻际降限陨险隐隔障难雅雨雪雾需霭露韵顾顿预频题风首骨魂魄魅鲜鸣鹜黄黎，：🌅🌧🌫🐌💫🔥🛡🦅";

        return chars;
    }

    override function update(dt:Float) {
        super.update(dt);
    }

    static function main() {
        new Main();
    }
}
