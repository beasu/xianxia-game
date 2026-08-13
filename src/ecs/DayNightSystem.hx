package ecs;

// ============================================================
//  DayNightSystem.hx - 日月星辰昼夜交替
//  priority: 11 (最先执行, 昼夜影响后续所有系统的行为)
//
//  一个世界日 = ticksPerDay 个 tick
//  昼夜比例: 日间60% / 夜间40%
//  - dawn  (日出): 0.20-0.25
//  - day   (白天): 0.25-0.75
//  - dusk  (日落): 0.75-0.80
//  - night (夜间): 0.80-1.20(回绕)
//
//  影响:
//    - 妖兽活跃度: 夜间 x1.8, 黄昏 x1.3
//    - 正道修士活跃度: 白天 x1.2, 夜间 x0.7
//    - 灵气浓度: 夜间 x1.15 (太阴之气)
//    - NPC 意图: 夜间妖兽更倾向攻击, 白天修士更倾向修炼/交易
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class DayNightSystem implements ISystem {
    public var priority:Int = 11;
    public var enabled:Bool = true;

    public var state:DayNightState;

    // === 可调参数 ===
    public var dayRatio:Float = 0.6;       // 白天占比
    public var nightSpiritBonus:Float = 1.15; // 夜间灵气加成
    public var nightYaoshouBonus:Float = 1.8; // 夜间妖兽活跃度
    public var dayCultivatorBonus:Float = 1.2; // 白天修士活跃度

    public function new() {
        state = new DayNightState();
    }

    public function update(world:WorldEngine, dt:Float):Void {
        // 计算当前时间(0-1 循环)
        var dayProgress = (world.tickCount % world.ticksPerDay) / world.ticksPerDay;
        state.timeOfDay = dayProgress;

        // 判断昼夜阶段
        var prevNight = state.isNight;

        if (dayProgress < 0.20) {
            state.dayPhase = "night";
            state.isNight = true;
        } else if (dayProgress < 0.25) {
            state.dayPhase = "dawn";
            state.isNight = false;
        } else if (dayProgress < 0.75) {
            state.dayPhase = "day";
            state.isNight = false;
        } else if (dayProgress < 0.80) {
            state.dayPhase = "dusk";
            state.isNight = false;
        } else {
            state.dayPhase = "night";
            state.isNight = true;
        }

        // 计算修正系数
        switch (state.dayPhase) {
            case "dawn":
                state.yaoshouActivityMul = 1.0;
                state.cultivatorActivityMul = 1.0;
                state.spiritMul = 1.05;
                state.darkness = 0.15;
            case "day":
                state.yaoshouActivityMul = 0.5;
                state.cultivatorActivityMul = dayCultivatorBonus;
                state.spiritMul = 1.0;
                state.darkness = 0;
            case "dusk":
                state.yaoshouActivityMul = 1.3;
                state.cultivatorActivityMul = 0.8;
                state.spiritMul = 1.1;
                state.darkness = 0.15;
            case "night":
                state.yaoshouActivityMul = 1.8;
                state.cultivatorActivityMul = 0.6;
                state.spiritMul = 1.15;
                state.darkness = 0.25;
        }

        // 昼夜切换事件
        if (prevNight != state.isNight) {
            if (state.isNight) {
                world.emitEvent(new WorldEvent(-1, -1, "NightFall",
                    "夜幕降临, 妖兽蠢蠢欲动..."
                ));
            } else {
                world.emitEvent(new WorldEvent(-1, -1, "DawnBreak",
                    "天光破晓, 万物苏醒"
                ));
            }
        }

        // 影响 NPC 意图: 夜间妖兽更攻击性
        for (e in world.entities) {
            if (!e.alive || e.isPlayer) continue;
            var npc = e.get(NPCStateComp);
            var intent = e.get(IntentComp);
            if (npc == null || intent == null) continue;

            if (npc.npcType == "yaoshou") {
                // 妖兽夜间攻击性提升
                intent.aggression = Math.min(1.0, intent.aggression + (state.yaoshouActivityMul - 1.0) * dt * 0.5);
                // 夜间妖兽如果闲置, 有概率变为游荡寻找猎物
                if (state.isNight && intent.currentIntent == Idle && Math.random() < 0.01) {
                    intent.currentIntent = Wander;
                }
            } else if (npc.npcType == "cultivator") {
                // 正道修士夜间更倾向修炼
                if (!state.isNight && intent.currentIntent == Idle && Math.random() < 0.008) {
                    intent.currentIntent = Cultivate;
                }
                if (state.isNight && intent.currentIntent == Trade) {
                    // 夜间不交易
                    intent.currentIntent = Cultivate;
                }
            }
        }
    }

    // 获取当前是否夜间
    public function isNight():Bool {
        return state.isNight;
    }

    // 获取当前阶段名
    public function getPhaseName():String {
        return switch (state.dayPhase) {
            case "dawn": "黎明";
            case "day": "白昼";
            case "dusk": "黄昏";
            case "night": "夜晚";
            default: "白昼";
        };
    }
}
