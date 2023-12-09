import ComposableArchitecture
import SwiftUI

extension String: Error { }

struct NumberFactClient {
  var fetch: @Sendable (Int) async throws -> String
}
extension NumberFactClient: DependencyKey {
  static let liveValue = Self { number in
    let (data, _) = try await URLSession.shared.data(
      from: URL(string: "http://www.numbersapi.com/\(number)")!
    )
    return String(decoding: data, as: UTF8.self)
  }
//  static let previewValue: NumberFactClient = Self { number in
//    throw "Failed to fetch fact"
//  }
}

extension DependencyValues {
  var numberFact: NumberFactClient {
    get { self[NumberFactClient.self] }
    set { self[NumberFactClient.self] = newValue }
  }
}

struct CounterFeature: Reducer {
  struct State: Equatable {
    var count = 0
    var fact: String?
    var isLoadingFact = false
    var isTimerOn = false
    var errorMessage: String?
  }
  enum Action: Equatable {
    case decrementButtonTapped
    case factResponse(String)
    case factResponseError(String)
    case getFactButtonTapped
    case incrementButtonTapped
    case timerTicked
    case toggleTimerButtonTapped
  }
  private enum CancelID {
    case timer
  }
  @Dependency(\.continuousClock) var clock
  @Dependency(\.numberFact) var numberFact
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .decrementButtonTapped:
        state.count -= 1
        state.fact = nil
        state.errorMessage = nil
        return .none

      case let .factResponse(fact):
        state.fact = fact
        state.errorMessage = nil
        state.isLoadingFact = false
        return .none

      case let .factResponseError(errorMessage):
        state.fact = nil
        state.errorMessage = errorMessage
        state.isLoadingFact = false
        return .none

      case .getFactButtonTapped:
        state.fact = nil
        state.errorMessage = nil
        state.isLoadingFact = true
        return .run { [count = state.count] send in
          do {
            await send(
              .factResponse(try await self.numberFact.fetch(count))
            )
          } catch {
            await send(.factResponseError("Failed to fetch fact"))
          }
        }

      case .incrementButtonTapped:
        state.count += 1
        state.fact = nil
        state.errorMessage = nil
        return .none

      case .timerTicked:
        state.count += 1
        return .none

      case .toggleTimerButtonTapped:
        state.isTimerOn.toggle()
        if state.isTimerOn {
          return .run { send in
            for await _ in self.clock.timer(interval: .seconds(1)) {
              await send(.timerTicked)
            }
          }
          .cancellable(id: CancelID.timer)
        } else {
          return .cancel(id: CancelID.timer)
        }
      }
    }
  }
}

struct ContentView: View {
  let store: StoreOf<CounterFeature>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Form {
        Section {
          Text("\(viewStore.count)")
          Button("Decrement") {
            viewStore.send(.decrementButtonTapped)
          }
          Button("Increment") {
            viewStore.send(.incrementButtonTapped)
          }
        }
        Section {
          Button {
            viewStore.send(.getFactButtonTapped)
          } label: {
            HStack {
              Text("Get fact")
              if viewStore.isLoadingFact {
                Spacer()
                ProgressView()
              }
            }
          }
          if let fact = viewStore.fact {
            Text(fact)
          } else if let errorMessage = viewStore.errorMessage {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
        Section {
          if viewStore.isTimerOn {
            Button("Stop timer") {
              viewStore.send(.toggleTimerButtonTapped)
            }
          } else {
            Button("Start timer") {
              viewStore.send(.toggleTimerButtonTapped)
            }
          }
        }
      }
    }
  }
}

#Preview {
  ContentView(
    store: Store(initialState: CounterFeature.State()) {
      CounterFeature()
        ._printChanges()
    }
  )
}
