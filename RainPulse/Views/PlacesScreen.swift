import SwiftUI
import MapKit

struct PlacesScreen: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var places: PlacesModel
    @EnvironmentObject private var location: LocationManager

    @StateObject private var search = PlaceSearch()
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                if !search.query.isEmpty {
                    Section("Results") {
                        ForEach(search.results, id: \.self) { result in
                            Button {
                                Task { await add(result) }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(result.title).foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        HStack {
                            Image(systemName: "location.fill").foregroundStyle(Color.accentColor)
                            Text(location.placeName ?? String(localized: "Current Location"))
                            Spacer()
                            Text("Always on").font(.caption).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Rain alerts always cover your current location.")
                    }

                    Section {
                        ForEach($places.places) { $place in
                            PlaceRow(place: $place, alertsAllowed: store.tier >= .essential) {
                                showPaywall = true
                            }
                        }
                        .onDelete(perform: places.remove)
                        .onMove(perform: places.move)
                    } header: {
                        Text("Saved places (\(places.places.count)/\(store.tier.maxSavedPlaces))")
                    } footer: {
                        if store.tier == .free {
                            Button("Track up to 20 places with alerts — upgrade") { showPaywall = true }
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Places")
            .searchable(text: $search.query, prompt: "Search city or address")
            .toolbar { EditButton() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .overlay {
                if search.query.isEmpty && places.places.isEmpty {
                    ContentUnavailableView("No saved places",
                                           systemImage: "star",
                                           description: Text("Search above to add home, work or anywhere you travel."))
                        .padding(.top, 140)
                }
            }
        }
    }

    private func add(_ completion: MKLocalSearchCompletion) async {
        guard places.places.count < store.tier.maxSavedPlaces else {
            showPaywall = true
            return
        }
        if let place = await search.resolve(completion) {
            places.add(place)
            search.query = ""
        }
    }
}

private struct PlaceRow: View {
    @Binding var place: Place
    let alertsAllowed: Bool
    let onLocked: () -> Void

    @State private var forecast: Forecast?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body.weight(.medium))
                Text(forecast?.nowcastSummary() ?? " ")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let forecast {
                Image(systemName: WeatherCode.symbol(forecast.current.weatherCode))
                    .symbolRenderingMode(.multicolor)
                Text(Fmt.temperature(forecast.current.temperature)).monospacedDigit()
            }
            Button {
                if alertsAllowed { place.alertsEnabled.toggle() } else { onLocked() }
            } label: {
                Image(systemName: alertsAllowed && place.alertsEnabled ? "bell.fill" : "bell.slash")
                    .foregroundStyle(alertsAllowed && place.alertsEnabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rain alerts")
        }
        .task {
            forecast = try? await ForecastService.shared.forecast(latitude: place.latitude,
                                                                   longitude: place.longitude, days: 1)
        }
    }
}

/// MapKit autocomplete for cities and addresses worldwide.
@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    func resolve(_ completion: MKLocalSearchCompletion) async -> Place? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        return Place(name: completion.title, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
