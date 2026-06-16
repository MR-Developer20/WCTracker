import Foundation
import CoreLocation
import WeatherKit

// MARK: - Shared config

enum APIConfig {
    /// ESPN's free, unauthenticated FIFA World Cup site API (same feed ESPN.com uses).
    static let espnBase = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world"

    static func json(from url: URL, session: URLSession) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError(message: "HTTP \(http.statusCode)", isNotFound: http.statusCode == 404)
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }
}

// MARK: - Match summary (lineups, events, stats, venue)

actor MatchSummaryService {
    private let base: String
    private let session = APIConfig.makeSession()
    private var cache: [String: (at: Date, detail: MatchDetail)] = [:]
    private let ttl: TimeInterval = 8

    init(base: String = APIConfig.espnBase) { self.base = base }

    func detail(eventId: String, homeTeamId: String, awayTeamId: String, force: Bool = false) async throws -> MatchDetail {
        if !force, let hit = cache[eventId], Date().timeIntervalSince(hit.at) < ttl { return hit.detail }
        var comps = URLComponents(string: "\(base)/summary")
        comps?.queryItems = [URLQueryItem(name: "event", value: eventId)]
        guard let url = comps?.url else { throw APIError(message: "Bad summary URL") }
        let json = try await APIConfig.json(from: url, session: session)
        let detail = ESPNSummaryParser.parse(json, homeTeamId: homeTeamId, awayTeamId: awayTeamId, eventId: eventId)
        cache[eventId] = (Date(), detail)
        return detail
    }
}

// MARK: - Weather (WeatherKit primary, Open-Meteo switchable)

enum WeatherSource: String, CaseIterable, Identifiable {
    case weatherKit = "WeatherKit"
    case openMeteo = "Open-Meteo"
    var id: String { rawValue }
}

/// Orchestrates geocoding + the two weather providers. Named to avoid colliding
/// with Apple's `WeatherKit.WeatherService`.
final class MatchWeatherService {
    private let session = APIConfig.makeSession()
    private let weatherKit = WeatherKit.WeatherService.shared

    /// Returns weather for a venue using the requested source, auto-falling back to
    /// Open-Meteo when WeatherKit is unavailable (e.g. an unprovisioned simulator).
    func weather(for venue: VenueInfo, source: WeatherSource) async -> MatchWeather? {
        guard let coords = await coordinates(for: venue) else { return nil }
        if source == .weatherKit {
            if let wk = try? await weatherKitReading(coords) { return wk }
            // fall through to Open-Meteo
        }
        return try? await openMeteoReading(coords)
    }

    // MARK: Geocoding (Open-Meteo — no key, feeds both weather providers)

    private func coordinates(for venue: VenueInfo) async -> CLLocationCoordinate2D? {
        guard let name = venue.city ?? venue.name,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json"),
              let json = try? await APIConfig.json(from: url, session: session),
              let first = json.field(["results"])?.arrayValue?.first,
              let lat = first.field(["latitude"])?.doubleValue,
              let lon = first.field(["longitude"])?.doubleValue
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: WeatherKit

    private func weatherKitReading(_ c: CLLocationCoordinate2D) async throws -> MatchWeather {
        let weather = try await weatherKit.weather(for: CLLocation(latitude: c.latitude, longitude: c.longitude))
        let cur = weather.currentWeather
        return MatchWeather(
            temperatureC: cur.temperature.converted(to: .celsius).value,
            condition: cur.condition.description,
            symbolName: cur.symbolName,
            windKph: cur.wind.speed.converted(to: .kilometersPerHour).value,
            humidity: Int((cur.humidity * 100).rounded()),
            source: .weatherKit)
    }

    // MARK: Open-Meteo

    private func openMeteoReading(_ c: CLLocationCoordinate2D) async throws -> MatchWeather {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code&temperature_unit=celsius&wind_speed_unit=kmh")!
        let json = try await APIConfig.json(from: url, session: session)
        let cur = json.field(["current"])
        let code = cur?.int("weather_code") ?? -1
        let (desc, symbol) = Self.wmo(code)
        return MatchWeather(
            temperatureC: cur?.field(["temperature_2m"])?.doubleValue ?? 0,
            condition: desc,
            symbolName: symbol,
            windKph: cur?.field(["wind_speed_10m"])?.doubleValue,
            humidity: cur?.int("relative_humidity_2m"),
            source: .openMeteo)
    }

    /// WMO weather-interpretation code → (description, SF Symbol).
    static func wmo(_ code: Int) -> (String, String) {
        switch code {
        case 0: return ("Clear", "sun.max.fill")
        case 1, 2: return ("Partly Cloudy", "cloud.sun.fill")
        case 3: return ("Overcast", "cloud.fill")
        case 45, 48: return ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67: return ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77: return ("Snow", "cloud.snow.fill")
        case 80, 81, 82: return ("Rain Showers", "cloud.heavyrain.fill")
        case 85, 86: return ("Snow Showers", "cloud.snow.fill")
        case 95, 96, 99: return ("Thunderstorm", "cloud.bolt.rain.fill")
        default: return ("—", "cloud.fill")
        }
    }
}

// MARK: - JSONValue numeric helper

extension JSONValue {
    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}
