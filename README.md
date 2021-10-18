# PublicCalendar

Service that fetches swedish public holidays etc from www.kalender.se.

## Usage

The `publisher(for: on:)` method can be great for observing changes to the calendar.   
```swift 
var cancellables = Set<AnyCancellable>()

let publicCalendar = PublicCalendar(fetchAutomatically: true)
/// subscribe to the latest events by the following filters. If the database is empty waiting to be fetched the result will be empty.
publicCalendar.publisher(for: [.holidays], on: Date()).sink { events in 
    /// the latest events
}.store(in: &cancellables)
``` 

If you want to make sure the values you get are current (and not failty due to an empty database) you can always use fetch. While you can force an update you probably don't need to. If there's a need to for an update the library will fetch new values.
```swift 

let publicCalendar = PublicCalendar(fetchAutomatically: true)
publicCalendar.fetch().sink { db in 
    let events = db.events(on: Date(), in: [.holidays])
}.store(in: &cancellables)
``` 

## TODO

- [x] code-documentation
- [x] write tests
- [x] complete package documentation
- [ ] create a reusable custom publisher for latest or wait for update -scenarios.
