import SwiftUI

/// A dependency collection that provides resolutions for object instances.
open class Dependencies {
    
    /// Composition root container of dependencies.
    public static var root = Dependencies()

    /// Stored object instance factories.
    private(set) var factories = [String: Factory]()
    
    /// Construct dependency resolutions.
    public init(@FactoryBuilder _ factories: () -> [Factory]) {
        factories().forEach { add($0) }
    }
    
    /// Construct dependency resolution.
    public init(@FactoryBuilder _ factory: () -> Factory) {
        add(factory())
    }

    public init(@ModuleBuilder _ modules: () -> [Module]) {
        modules().forEach { self.add(dependencies: $0.dependencies) }
    }

    public init(@ModuleBuilder _ module: () -> Module) {
        add(dependencies: module().dependencies)
    }
    
    public init(@DependenciesProtocolBuilder _ dependencies: () -> [DependenciesProtocol]) {
        dependencies().forEach {
            if let factory = $0 as? Factory {
                self.add(factory)
            } else if let module = $0 as? Module {
                self.add(dependencies: module.dependencies)
            }
        }
    }

    public init(@DependenciesProtocolBuilder _ depedency: () -> DependenciesProtocol) {
        if let factory = depedency() as? Factory {
            self.add(factory)
        } else if let module = depedency() as? Module {
            self.add(dependencies: module.dependencies)
        }
    }
    
    /// Assigns the current container to the composition root.
    open func build() {
        self.factories.forEach { entry in
            let (key, value) = entry
            Self.root.factories[key] = value
        }
        
        print("[FACTORIES]: \(Self.root.description)")
    }

    /// Resolves through inference and returns an instance of the
    /// given type from the current default container.
    /// If the dependency is not found, an exception will occur.
    public static func resolve<T>(for name: String? = nil) -> T {
        let name = name ?? String(describing: T.self)

        if let value: T = Self.root.factories[name]?.storage  as? T {
            return value
        }

        guard let object: T = Self.root.factories[name]?.resolve() as? T else {
            fatalError("Dependency '\(T.self)' not resolved!")
        }
        Self.root.factories[name]?.storage = object

        return object
    }

    public static func resolveAll<T>(for name: String? = nil) -> [T] {
        let result: [T] = Self.root.factories.compactMap { entry -> T? in
            let (_, factory) = entry
            if let object = factory.storage {
                return (object as? T)
            } else {
                let object = factory.resolve()
                factory.storage = object
                return (object as? T)
            }
        }
        return result
    }

    fileprivate init() {}
    deinit { factories.removeAll() }
    
    public var description: String {
        var description: String = ""
        self.factories.forEach {
            description = "\(description)\(description.isEmpty ? "" : ",") \($1.description)"
        }
        return description
    }
}

private extension Dependencies {

    /// Registers a specific type and its instantiating factory.
    func add(_ factory: Factory) {
        factories[factory.name] = factory
        if factory.strategy == .eager {
            _ = Dependencies.resolve() as Any
        }
    }

    func add(dependencies: Dependencies) {
        dependencies.factories.forEach { entry in
            let (_, factory) = entry
            add(factory)
        }
    }
}

// MARK: Public API
public protocol DependenciesProtocol {
}

public enum ResolverStrategy {
    case lazy
    case eager
}
/// A type that contributes to the object graph.
public class Factory: CustomStringConvertible, DependenciesProtocol {
    fileprivate let name: String
    fileprivate let resolve: () -> Any
    fileprivate var storage: Any?
    fileprivate let strategy: ResolverStrategy

    public init<T>(_ name: String? = nil, strategy: ResolverStrategy = .lazy, _ resolve: @escaping () -> T) {
        self.name = name ?? String(describing: T.self)
        self.strategy = strategy
        self.resolve = resolve
        self.storage = nil
    }
    
    public var description: String {
        "\(name)"
    }
}

/// Collection of dependencies
public protocol Module: DependenciesProtocol {
    var dependencies: Dependencies { get }
}

public extension Dependencies {
    
    /// DSL for declaring modules within the container dependency initializer.
    @resultBuilder struct FactoryBuilder {
        public static func buildBlock(_ factories: Factory...) -> [Factory] { factories }
        public static func buildBlock(_ factory: Factory) -> Factory { factory }
    }

    @resultBuilder struct ModuleBuilder {
        public static func buildBlock(_ modules: Module...) -> [Module] { modules }
        public static func buildBlock(_ module: Module) -> Module { module }
    }
    
    @resultBuilder struct DependenciesProtocolBuilder {
        public static func buildBlock(_ dependencies: DependenciesProtocol...) -> [DependenciesProtocol] { dependencies }
        public static func buildBlock(_ dependency: DependenciesProtocol) -> DependenciesProtocol { dependency }
    }
}

/// Resolves an instance from the dependency injection container.
@propertyWrapper
public class InjectedSingleton<Value> {
    public var wrappedValue: Value {
        return Dependencies.resolve()
    }
    
    public init() {
    }
}

@available(iOS 13.0, *)
@propertyWrapper
public struct InjectedObservedObjectSingleton<Value: ObservableObject>: DynamicProperty {
    
    @ObservedObject private var _wrappedValue: Value

    public var wrappedValue: Value {
        __wrappedValue.wrappedValue
    }
    
    public init() {
        let resolvedValue: Value = Dependencies.resolve() as Value
        self.__wrappedValue = ObservedObject<Value>(initialValue: resolvedValue)
    }
 
    public var projectedValue: ObservedObject<Value>.Wrapper {
        return __wrappedValue.projectedValue
    }
}
