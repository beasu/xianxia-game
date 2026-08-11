import hxd.App;
import hxd.res.DefaultFont;
import hxd.res.FontBuilder;
import haxe.ui.core.Screen;
import haxe.ui.Toolkit;

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
        // 暴露到全局便于调试
        untyped js.Browser.window.Main = Main;
        try {
            cjkFont = FontBuilder.getFont("Microsoft YaHei", 14, { chars: getCJKChars() });
            @:privateAccess h3d.Engine.getCurrent().resCache.set(hxd.res.DefaultFont, cjkFont);
        } catch(e:Dynamic) {
            cjkFont = hxd.res.DefaultFont.get();
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
        chars += "一七万三上下不与世业丝两个中丹为主丽举么义之乘九书买乾了争事于云互五亡交享亮人什仇仍从他仙令以仪仲件优会伤估位低体佛佩使供依侧保信修倍值做元先光克兑兜入全八六共关其兼兽内册再冥冰冲决冷冻净准凋减凝凡出击分切列创初判到制前剑力办功加动助劫势勺包化北升半华单卖卦印却历去双反发取受变叠口只可史右号合同名后向含吸员周和品响售善嘴器四回因困围国图圆圈土在地场坎坐坠坤型基境增士声处备复外多够大天太夫失头夺如妖妙始婪婴子字存宗定宝实宫害家容宽察对寻寿射将小少尖尘尝尽尾局层屏属屠山巡巢左已巽币市布带帧常帽年并幻幽庄序库应底度建开异引弟张弯弱弹强归当录形影径得御循微德心忆志快态性总恢息恶悬情意感慢慧戏成或战所手才打执扩扭找技投拍拖招拟拿持指按挪换据掌排接提搜摆摇擎支收攻放效敌教散数整文斗料斩断新方施旋无日旧时明易星映昧昭是显晕景晶智暗暴曲更替最有期木未本术机杀权材条来板极果枢架柄染查柱标栏树核根格框检椭楷概模次正步死殊残段每毛气水汐没治法波注泽洛活流测济浓浪浮消涡淡深添清渊渐渡渲游源满演漩漫潮火灭灵炸点炼烁烈焰然照爆爪爻片版牙物特状狂献獠玄率玉玑玩环现珠球理璇瓣生用由甲电画界留疗疯白的皮益盔盖目直相眉真眼睛瞄瞬石破础确示神禁离秒积称移穴空突立符第等筑策简算管簪类粒系素索紫累红级纪纯纹线练组细终经绕绘给统续绸综绽绿缉缓缝缩罡置老者而耗耳肤肩背胸能脉脏腰腿臂自至艮良色节芒花苍范草药莲获落著虚融螺血行衡衣表衬衰袍袖被裁裂装褶覆观角触计订认让记设诀评试详谁调象负贡责败货质贪购资赋赏赖赤走起足跑路身轨转轮轻载辅辑输辰边达过运近返这连退逃透逐通速造逸逻遍道邪邻部都配采释里重野量金链锐长门闪闲间阁阅队阳阴阵阶附除随集零雷震青静非靠面顶顺领颜额飘飞饰驱驻验高髻魔鱼黑默鼎鼠齐龄";
        return chars;
    }

    override function update(dt:Float) {
        super.update(dt);
    }

    static function main() {
        new Main();
    }
}
