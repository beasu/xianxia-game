package ecs;

// ============================================================
//  IComponent.hx - ECS 组件接口
//  所有组件都是纯数据，不包含逻辑
// ============================================================

interface IComponent {
}

// ============================================================
//  Entity.hx - 实体容器
//  实体只是一组组件的 ID 载体，本身无逻辑
// ============================================================

class Entity {
    public var id:Int;
    public var name:String;
    public var alive:Bool = true;
    public var isPlayer:Bool = false;

    var components:Map<String, IComponent> = [];

    static var nextId:Int = 0;

    public function new(?name:String) {
        this.id = nextId++;
        this.name = name != null ? name : "entity_" + id;
    }

    public function add(c:IComponent):Entity {
        components.set(Type.getClassName(Type.getClass(c)), c);
        return this;
    }

    public function get<T:(IComponent)>(cl:Class<T>):T {
        return cast components.get(Type.getClassName(cl));
    }

    public function has(cl:Class<IComponent>):Bool {
        return components.exists(Type.getClassName(cl));
    }

    public function remove(cl:Class<IComponent>):Void {
        components.remove(Type.getClassName(cl));
    }
}

// ============================================================
//  ISystem.hx - 系统接口
//  每个系统处理一类逻辑，按优先级被 WorldEngine 调度
// ============================================================

interface ISystem {
    public var priority:Int;       // 调度优先级(小的先执行)
    public var enabled:Bool;
    public function update(world:WorldEngine, dt:Float):Void;
}
