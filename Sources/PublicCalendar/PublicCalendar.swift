import Foundation
import Combine
import SwiftSoup
import AutomatedFetcher

public extension Dictionary where Key == PublicCalendar.Category, Value == [PublicCalendar.Event] {
    func isHoliday(date:Date) -> Bool {
        self[.holidays]?.contains { event in Calendar.current.isDate(event.date, inSameDayAs: date) } == true
    }
    func events(on date:Date = Date(), in categories:[PublicCalendar.Category]) -> [PublicCalendar.Event] {
        var events = [PublicCalendar.Event]()
        for f in categories {
            events.append(contentsOf: self[f]?.filter { Calendar.current.isDate($0.date, inSameDayAs: date) } ?? [])
        }
        return events.sorted { $0.date < $1.date }
    }
    static func fileUrl() throws -> URL {
        let documentDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor:nil, create:false)
        return documentDirectory.appendingPathComponent("HoldiayEvents.json")
    }
    func write() {
        let enc = JSONEncoder()
        do {
            let data = try enc.encode(self)
            try data.write(to: Self.fileUrl())
        } catch {
            debugPrint(error)
        }
    }
    static func read() -> Self? {
        do {
            let data = try Data(contentsOf: fileUrl())
            let res = try JSONDecoder().decode(Self.self, from: data)
            return res.isEmpty ? nil : res
        } catch {
            debugPrint(error)
        }
        return nil
    }
    static func delete() {
        do {
            try FileManager.default.removeItem(at: Self.fileUrl())
        } catch {
            debugPrint(error)
        }
    }
}

public class PublicCalendar : ObservableObject {
    private typealias DBSubscriber = CurrentValueSubject<DB,Never>
    public typealias DBPublisher = AnyPublisher<DB,Never>
    public typealias DB = [Category:[Event]]
    public struct Event: Codable, Hashable, Equatable, Identifiable {
        public var id:String {
            return category.rawValue + "-" + title + "-" + date.description
        }
        public var title:String
        public var date:Date
        public var category:Category
        public init(title:String,date:Date,category:Category) {
            self.title = title
            self.date = date
            self.category = category
        }
    }
    public enum PublicCalendarError : Error {
        case instanceDead
    }
    public enum Category : String, CaseIterable, Codable, Equatable {
        case holidays
        case flagdays
        case undays
        case nights
        case themedays
        case informationdays
        var url:URL {
            switch self {
            case .holidays: return URL(string:"https://www.kalender.se/helgdagar")!
            case .flagdays: return URL(string:"https://www.kalender.se/flaggdagar")!
            case .undays: return URL(string:"https://www.kalender.se/fn-dagar")!
            case .nights: return URL(string:"https://www.kalender.se/aftnar")!
            case .themedays: return URL(string:"https://www.kalender.se/temadagar")!
            case .informationdays: return URL(string:"https://www.kalender.se/samhallsinformation")!
            }
        }
    }
    
    private var publishers = Set<AnyCancellable>()
    private let latestSubject:DBSubscriber
    private let automatedFetcher:AutomatedFetcher<DB>
    private var previewData:Bool
    
    public let latest:DBPublisher
    
    @Published public var fetchAutomatically = true {
        didSet { automatedFetcher.isOn = fetchAutomatically }
    }
    public init(fetchAutomatically:Bool = false, previewData:Bool = false) {
        let db = DB.read() ?? [:]
        
        latestSubject = .init(db)
        latest = latestSubject.eraseToAnyPublisher()
        let date = UserDefaults.standard.object(forKey: "LastHolidayFetch") as? Date
        automatedFetcher = AutomatedFetcher<DB>.init(latestSubject, lastFetch:date, isOn: fetchAutomatically, timeInterval: 60*60*24)
        
        self.previewData = previewData
        self.fetchAutomatically = true
        self.automatedFetcher.triggered.sink { [weak self] in
            self?.fetch()
        }.store(in: &publishers)
        if fetchAutomatically {
            fetch()
        }
    }
    public func publisher(for categories:[Category] = Category.allCases, on date:Date = Date()) -> AnyPublisher<[Event],Never> {
        return latest.map { db in
            return db.events(on: date, in: categories)
        }.eraseToAnyPublisher()
    }
    public func fetch(force:Bool = false) {
        if previewData {
            latestSubject.send(Self.previewData)
            return
        }
        if force == false && automatedFetcher.shouldFetch && latestSubject.value.isEmpty == false {
            return
        }
        var p:AnyCancellable? = nil
        automatedFetcher.started()
        p = getContent().receive(on: DispatchQueue.main).sink { [weak self] completion in
            if case .failure(let error) = completion {
                debugPrint(error)
            }
            self?.automatedFetcher.failed()
            if let p = p {
                self?.publishers.remove(p)
            }
        } receiveValue: { [weak self] db in
            self?.latestSubject.send(db)
            self?.automatedFetcher.completed()
            if let p = p {
                self?.publishers.remove(p)
            }
        }
        if let p = p {
            publishers.insert(p)
        }
    }
    public func purge() {
        DB.delete()
        UserDefaults.standard.removeObject(forKey: "LastHolidayFetch")
        self.latestSubject.send([:])
    }
    private func getContent() -> AnyPublisher<DB,Error> {
       func crawlContent(for category:Category) throws -> [Event]{
            var arr = [Event]()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let holidays = try Data(contentsOf: category.url)
            guard let holidayHTML = String(data: holidays, encoding: .utf8) else {
                debugPrint("cannot decode string for \(category.url.absoluteString)")
                return arr
            }
            let els = try SwiftSoup.parse(holidayHTML).select(".table").select("tr")
            for (index, element) in els.array().enumerated() {
                if index == 0 {
                    continue
                }
                let tds = try element.select("td")
                let day = try tds[0].text()
                let title = try tds[1].select("a").text()
                guard let date = formatter.date(from: day) else {
                    debugPrint("cannot format date for \(category.url.absoluteString) from \"\(day)\"")
                    continue
                }
                let calDay = Event(title: title, date: date, category: category)
                arr.append(calDay)
            }
            return arr.sorted { $0.date < $1.date }
        }
        let subject = PassthroughSubject<DB,Error>()
        DispatchQueue.global().async {
            var res = DB()
            for c in Category.allCases {
                do {
                    res[c] = try crawlContent(for: c)
                } catch {
                    debugPrint(error)
                }
            }
            res.write()
            UserDefaults.standard.setValue(Date(), forKey: "LastHolidayFetch")
            subject.send(res)
        }
        return subject.eraseToAnyPublisher()
    }
    public static let previewData: DB = [
        .holidays: [.init(title: "Preview event", date: Date(), category: .holidays)]
    ]
    public static let previewInstance = PublicCalendar(previewData: true)
}
