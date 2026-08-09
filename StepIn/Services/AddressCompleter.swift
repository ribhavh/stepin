import Foundation
import MapKit

/// Google-Maps-style autocomplete: feeds a query fragment to
/// `MKLocalSearchCompleter` and publishes address + place suggestions, biased to
/// NYC. `@Observable` so SwiftUI updates as results stream in.
@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = GeocodeService.nycRegion
    }

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                suggestions = []
            } else {
                completer.queryFragment = trimmed
            }
        }
    }

    func clear() {
        suggestions = []
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
