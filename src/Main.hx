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
        // 添加所有用到的中文字符(去重)
        chars += "修仙演义青云道长筑基后期魔练气层击杀气血灵力阵法八卦五行太极乾坤震巽坎离艮兑金木水火土三昧真九天玄冰诀万剑归宗雷破不足移动鼠标瞄准释放切换点击敌施法";
        // 新增: 境界体系
        chars += "元婴化神丹妖兽将邪仙分影术莲花绽放袖里天罡北斗挪移宫格突";
        // 新增: 敌人名称与行为
        chars += "角甲袍爪牙獠皮绿长发飘逸四足";
        // 新增: UI文字
        chars += "修为境界突破经验冷却中邪魔";
        return chars;
    }

    override function update(dt:Float) {
        super.update(dt);
    }

    static function main() {
        new Main();
    }
}
