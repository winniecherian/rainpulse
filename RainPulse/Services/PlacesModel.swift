import Foundation
import WidgetKit

/// Saved places, persisted to the App Group so the widget can read them.
@MainActor
final class PlacesModel: ObservableObject {
    @Published var places: [Place] {
        didSet {
            SharedStore.savePlaces(places)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    init() {
        places = SharedStore.loadPlaces()
    }

    func add(_ place: Place) {
        guard !places.contains(where: {
            abs($0.latitude - place.latitude) < 0.01 && abs($0.longitude - place.longitude) < 0.01
        }) else { return }
        places.append(place)
    }

    func remove(at offsets: IndexSet) {
        places.remove(atOffsets: offsets)
    }

    func move(from source: IndexSet, to destination: Int) {
        places.move(fromOffsets: source, toOffset: destination)
    }
}
