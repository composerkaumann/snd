import Foundation

enum AlfredCommand {
    private struct Items: Encodable {
        let items: [Item]
    }

    private struct Item: Encodable {
        let title: String
        let subtitle: String
        let arg: [String]?
    }

    static func handle(_ arguments: ArraySlice<String>) -> Bool {
        let value = arguments.dropFirst().first ?? ""
        switch arguments.first {
        case "--alfred-list":
            let items: [Item]
            do {
                items = try results(matching: value.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                items = [Item(title: "Heliväljundeid ei saanud lugeda",
                              subtitle: error.localizedDescription, arg: nil)]
            }
            do {
                let data = try JSONEncoder().encode(Items(items: items))
                FileHandle.standardOutput.write(data)
            } catch {
                fail(error)
            }
            return true
        case "--alfred-select":
            do {
                try AudioOutputs.select(uid: value)
            } catch {
                fail(error)
            }
            return true
        default:
            return false
        }
    }

    private static func results(matching prefix: String) throws -> [Item] {
        if prefix.isEmpty {
            return [Item(title: "Ava heliväljundite valija",
                         subtitle: "Otsimiseks sisesta väljundi nime algus", arg: ["open"])]
        }

        let matches = try AudioOutputs.list().filter { output in
            output.name.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive],
                              locale: .current) != nil
        }
        guard !matches.isEmpty else {
            return [Item(title: "Sobivat heliväljundit pole", subtitle: "Nime algus „\(prefix)”", arg: nil)]
        }

        let current = try? AudioOutputs.current()
        return matches.map { output in
            Item(title: output.name, subtitle: output.id == current ? "Kasutusel" : "Vali heliväljund",
                 arg: ["select", output.uid])
        }
    }

    private static func fail(_ error: Error) -> Never {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        exit(EXIT_FAILURE)
    }
}
