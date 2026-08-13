package ecs;

// ============================================================
//  PhysicsSystem.hx - 轻量级物理系统
//  priority: 5 (在所有游戏逻辑系统之前执行)
//
//  为什么不用 NAPE/Box2D:
//    1. Heaps.io + Haxe 生态中, NAPE 是主流 2D 物理引擎, 但:
//       - NAPE 已停止维护(最后更新 2018), Haxe 4.x 兼容性不稳定
//       - Box2D Haxe 移植版同样维护停滞
//       - 引入完整物理引擎会大幅增加编译体积(~500KB)和运行开销
//       - 修仙游戏不需要刚体碰撞/铰链/弹簧等完整物理模拟
//    2. 本游戏需要的"物理感":
//       - 投射物有惯性(弧线/抛物线)
//       - 击退有方向性和力度
//       - 地形影响移动(摩擦/减速)
//       - 碰撞检测(投射物 vs 实体)
//    3. 自研轻量物理系统更可控, 与 ECS 架构无缝集成
//
//  功能:
//    - 投射物物理: 速度积分 + 重力/阻力 + 生命周期
//    - 击退物理: 冲量应用 + 摩擦衰减
//    - 碰撞检测: 圆形碰撞(投射物 vs 实体)
//    - 地形摩擦: 从 TerrainSystem 获取摩擦系数, 影响移动
//    - 力场效果: 法术留下的区域效果(减速/牵引/击飞)
// ============================================================

import hxd.Math;
import ecs.Entity.ISystem;
import ecs.Entity.Entity;
import ecs.Components;
import ecs.WorldEngine.WorldEvent;

class PhysicsSystem implements ISystem {
    public var priority:Int = 5;
    public var enabled:Bool = true;

    // === 可调参数 ===
    public var globalGravity:Float = 0;         // 全局重力(修仙世界默认无重力)
    public var globalDrag:Float = 0.98;          // 全局空气阻力
    public var knockbackDecay:Float = 0.85;      // 击退衰减系数
    public var minVelocity:Float = 5;            // 最小有效速度(低于此值视为静止)
    public var collisionRadius:Float = 25;       // 实体碰撞半径

    // 活跃力场列表
    public var forceFields:Array<ForceField> = [];

    public function new() {}

    public function update(world:WorldEngine, dt:Float):Void {
        // 1. 实体物理积分: 速度 -> 位置
        updateEntityPhysics(world, dt);

        // 2. 力场效果: 影响力场内的实体
        updateForceFields(world, dt);

        // 3. 碰撞检测: 实体 vs 实体(简化版, 仅检测近距离)
        checkCollisions(world, dt);
    }

    function updateEntityPhysics(world:WorldEngine, dt:Float):Void {
        for (e in world.entities) {
            if (!e.alive) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;

            // 获取地形摩擦(如果有 TerrainSystem)
            var friction = globalDrag;
            for (s in world.systems) {
                var ts = Std.downcast(s, TerrainSystem);
                if (ts != null) {
                    var cell = ts.getCellAt(pos.x, pos.y);
                    if (cell != null) {
                        friction = cell.friction;
                    }
                    break;
                }
            }

            // 应用速度积分
            pos.x += pos.vx * dt;
            pos.y += pos.vy * dt;

            // 应用阻力/摩擦
            pos.vx *= Math.pow(friction, dt * 60);
            pos.vy *= Math.pow(friction, dt * 60);

            // 应用全局重力(如果有)
            if (globalGravity > 0) {
                pos.vy += globalGravity * dt;
            }

            // 速度过低则归零
            var speed = Math.sqrt(pos.vx * pos.vx + pos.vy * pos.vy);
            if (speed < minVelocity) {
                pos.vx = 0;
                pos.vy = 0;
            }

            // 世界边界碰撞(弹回)
            if (pos.x < 0) { pos.x = 0; pos.vx = Math.abs(pos.vx) * 0.5; }
            if (pos.x > world.worldWidth) { pos.x = world.worldWidth; pos.vx = -Math.abs(pos.vx) * 0.5; }
            if (pos.y < 0) { pos.y = 0; pos.vy = Math.abs(pos.vy) * 0.5; }
            if (pos.y > world.worldHeight) { pos.y = world.worldHeight; pos.vy = -Math.abs(pos.vy) * 0.5; }
        }
    }

    function updateForceFields(world:WorldEngine, dt:Float):Void {
        var i = forceFields.length;
        while (i-- > 0) {
            var field = forceFields[i];
            field.lifetime -= dt;
            if (field.lifetime <= 0) {
                forceFields.splice(i, 1);
                continue;
            }

            // 影响力场内的实体
            for (e in world.entities) {
                if (!e.alive) continue;
                var pos = e.get(PositionComp);
                if (pos == null) continue;

                var dx = pos.x - field.x;
                var dy = pos.y - field.y;
                var dist = Math.sqrt(dx * dx + dy * dy);

                if (dist < field.radius) {
                    var strength = field.strength * (1 - dist / field.radius); // 距离越近越强

                    switch (field.type) {
                        case "pull":   // 牵引(向中心)
                            if (dist > 1) {
                                pos.vx -= (dx / dist) * strength * dt;
                                pos.vy -= (dy / dist) * strength * dt;
                            }
                        case "push":   // 击退(向外)
                            if (dist > 1) {
                                pos.vx += (dx / dist) * strength * dt;
                                pos.vy += (dy / dist) * strength * dt;
                            }
                        case "slow":   // 减速
                            pos.vx *= Math.pow(1 - strength * 0.5, dt * 60);
                            pos.vy *= Math.pow(1 - strength * 0.5, dt * 60);
                        case "lift":   // 击飞(向上)
                            pos.vy -= strength * dt;
                    }
                }
            }
        }
    }

    function checkCollisions(world:WorldEngine, dt:Float):Void {
        // 简化的碰撞检测: 只检查相邻实体
        // 优化: 跳过速度为0的实体
        var movingEntities:Array<Entity> = [];
        for (e in world.entities) {
            if (!e.alive) continue;
            var pos = e.get(PositionComp);
            if (pos == null) continue;
            var speed = Math.sqrt(pos.vx * pos.vx + pos.vy * pos.vy);
            if (speed > minVelocity) {
                movingEntities.push(e);
            }
        }

        // 移动实体 vs 所有实体
        for (a in movingEntities) {
            var posA = a.get(PositionComp);
            for (b in world.entities) {
                if (a == b || !b.alive) continue;
                var posB = b.get(PositionComp);
                if (posB == null) continue;

                var dx = posA.x - posB.x;
                var dy = posA.y - posB.y;
                var distSq = dx * dx + dy * dy;
                var minDist = collisionRadius * 2;

                if (distSq < minDist * minDist && distSq > 0.01) {
                    var dist = Math.sqrt(distSq);
                    var overlap = minDist - dist;
                    var nx = dx / dist;
                    var ny = dy / dist;

                    // 分离
                    posA.x += nx * overlap * 0.5;
                    posA.y += ny * overlap * 0.5;
                    posB.x -= nx * overlap * 0.5;
                    posB.y -= ny * overlap * 0.5;

                    // 弹性碰撞(简化: 交换法向速度分量)
                    var vAN = posA.vx * nx + posA.vy * ny;
                    var vBN = posB.vx * nx + posB.vy * ny;
                    posA.vx += (vBN - vAN) * nx * 0.5;
                    posA.vy += (vBN - vAN) * ny * 0.5;
                    posB.vx += (vAN - vBN) * nx * 0.5;
                    posB.vy += (vAN - vBN) * ny * 0.5;
                }
            }
        }
    }

    // 添加力场
    public function addForceField(field:ForceField):Void {
        forceFields.push(field);
    }

    // 施加击退冲量
    public function applyKnockback(entity:Entity, fromX:Float, fromY:Float, force:Float):Void {
        var pos = entity.get(PositionComp);
        if (pos == null) return;
        var dx = pos.x - fromX;
        var dy = pos.y - fromY;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 1) { dx = 1; dist = 1; }
        pos.vx += (dx / dist) * force;
        pos.vy += (dy / dist) * force;
    }
}

// 力场定义
class ForceField {
    public var x:Float;
    public var y:Float;
    public var radius:Float;
    public var type:String;     // pull/push/slow/lift
    public var strength:Float;
    public var lifetime:Float;

    public function new(x:Float, y:Float, radius:Float, type:String, strength:Float, lifetime:Float) {
        this.x = x;
        this.y = y;
        this.radius = radius;
        this.type = type;
        this.strength = strength;
        this.lifetime = lifetime;
    }
}
