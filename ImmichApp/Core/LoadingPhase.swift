import Foundation

enum LoadingPhase<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}
