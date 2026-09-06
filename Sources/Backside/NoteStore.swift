import Foundation

final class NoteStore {
    private let prefix = "Backside.note."

    func note(for key: String) -> String {
        UserDefaults.standard.string(forKey: prefix + key) ?? ""
    }

    func save(_ note: String, for key: String) {
        UserDefaults.standard.set(note, forKey: prefix + key)
    }
}
