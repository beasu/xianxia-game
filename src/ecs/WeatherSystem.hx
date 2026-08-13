package ecs;

// ============================================================
//  WeatherSystem.hx - 天气系统
//  priority: 12 (仅次于意图系统, 天气影响全局修正)
//
//  天气类型: clear(晴) / rain(雨) / snow(雪) / thunder(雷暴) / fog(雾)
//  影响:
//    - 灵<6气浓度倍率: 雨天+20%, 雷暴-10%, 雾天+15%, 雪天-5%
//    - 法术修正: 雨天火系-30%/冰系+20%, 雪天冰系+40%/火系-40%, 雷暴雷系+50%
//    - 移动速度: 雨天-10%, 雪天-20%, 雾天-15%
//    - 可见度: 雾天-50%, 雪天-20%
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class WeatherSystem implements ISystem {
    public var priority:Int = 12;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var minDuration:Float = 120;     // 最短持续时间(秒)
    public var maxDuration:Float = 300;     // 最长持续时间(秒)
    public var transitionTime:Float = 5;    // 过渡时间(秒)

    // 天气概率权重
    var weatherWeights:Array<{type:String, weight:Float}> = [
        {type: "clear", weight: 40},
        {type: "rain", weight: 25},
        {type: "snow", weight: 15},
        {type: "thunder", weight: 8},
        {type: "fog", weight: 12}
    ];

    // 天气配置表
    var weatherConfigs:Map<String, {spiritMul:Float, fireMul:Float, iceMul:Float, thunderMul:Float, moveMul:Float, visibility:Float}>;

    public var state:WeatherState;

    public function new() {
        state = new WeatherState();
        state.remainingTime = randRange(minDuration, maxDuration);

        weatherConfigs = [
            "clear"   => {spiritMul: 1.0, fireMul: 1.0, iceMul: 1.0, thunderMul: 1.0, moveMul: 1.0, visibility: 1.0},
            "rain"    => {spiritMul: 1.2, fireMul: 0.7, iceMul: 1.2, thunderMul: 1.1, moveMul: 0.9, visibility: 0.8},
            "snow"    => {spiritMul: 0.95, fireMul: 0.6, iceMul: 1.4, thunderMul: 0.9, moveMul: 0.8, visibility: 0.8},
            "thunder" => {spiritMul: 0.9, fireMul: 1.0, iceMul: 1.0, thunderMul: 1.5, moveMul: 0.85, visibility: 0.7},
            "fog"     => {spiritMul: 1.15, fireMul: 0.9, iceMul: 1.1, thunderMul: 0.95, moveMul: 0.85, visibility: 0.5}
        ];

        applyWeatherConfig("clear");
    }

    public function update(world:WorldEngine, dt:Float):Void {
        state.remainingTime -= dt;

        // 过渡阶段
        if (state.transitionTimer > 0) {
            state.transitionTimer -= dt;
            if (state.transitionTimer <= 0) {
                // 过渡完成, 切换天气
                state.type = state.nextType;
                applyWeatherConfig(state.type);
                world.emitEvent(new WorldEvent(-1, -1, "WeatherChange",
                    "天气转为" + weatherName(state.type)
                ));
            }
        }

        // 天气到期, 选择下一个天气
        if (state.remainingTime <= 0 && state.transitionTimer <= 0) {
            var nextType = pickWeather();
            if (nextType != state.type) {
                state.nextType = nextType;
                state.transitionTimer = transitionTime;
            }
            state.remainingTime = randRange(minDuration, maxDuration);
        }

        // 雷暴天气: 随机劈雷
        if (state.type == "thunder" && Math.random() < 0.01) {
            var tx = randRange(0, world.worldWidth);
            var ty = randRange(0, world.worldHeight);
            world.emitEvent(new WorldEvent(-1, -1, "WeatherLightning",
                "天降异雷于(" + Std.int(tx) + "," + Std.int(ty) + ")处"
            ));
        }

        // 雨雪天气: 影响灵脉
        if (world.tickCount % world.ticksPerDay == 0) {
            // 每日更新: 雨天增加灵脉密度
            if (state.type == "rain" || state.type == "fog") {
                for (v in world.spiritVeins) {
                    v.currentDensity *= 1.02;
                }
            }
        }
    }

    function applyWeatherConfig(type:String):Void {
        var cfg = weatherConfigs[type];
        if (cfg == null) return;
        state.spiritMul = cfg.spiritMul;
        state.fireMul = cfg.fireMul;
        state.iceMul = cfg.iceMul;
        state.thunderMul = cfg.thunderMul;
        state.moveMul = cfg.moveMul;
        state.visibility = cfg.visibility;
    }

    function pickWeather():String {
        var totalWeight = 0.0;
        for (w in weatherWeights) totalWeight += w.weight;
        var roll = Math.random() * totalWeight;
        for (w in weatherWeights) {
            roll -= w.weight;
            if (roll <= 0) return w.type;
        }
        return "clear";
    }

    function weatherName(type:String):String {
        return switch (type) {
            case "clear": "天晴";
            case "rain": "下雨";
            case "snow": "飘雪";
            case "thunder": "雷暴";
            case "fog": "雾霭";
            default: "晴朗";
        };
    }

    // 获取指定元素法术的伤害修正
    public function getSpellMul(element:String):Float {
        return switch (element) {
            case "fire": state.fireMul;
            case "ice": state.iceMul;
            case "thunder": state.thunderMul;
            default: 1.0;
        };
    }

    function randRange(min:Float, max:Float):Float {
        return min + Math.random(max - min);
    }
}
