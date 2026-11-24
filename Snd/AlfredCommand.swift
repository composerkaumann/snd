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
                items = [Item(title: SndLanguage.text("Could not list sound outputs"),
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
                let selection = try AudioOutputs.select(uid: value)
                print(SndLanguage.outputConfirmation(for: selection.name, changed: selection.changed))
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
            return [Item(title: SndLanguage.text("Open the sound output picker"),
                         subtitle: SndLanguage.text("Type the beginning of an output name to search"), arg: ["open"])]
        }

        let matches = try AudioOutputs.list().filter { output in
            output.name.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive],
                              locale: .current) != nil
        }
        guard !matches.isEmpty else {
            return [Item(title: SndLanguage.text("No matching sound output"),
                         subtitle: SndLanguage.text("Name starts with “%@”", prefix), arg: nil)]
        }

        let current = try? AudioOutputs.current()
        return matches.map { output in
            let subtitle = output.id == current ? SndLanguage.text("In Use") : SndLanguage.text("Select sound output")
            return Item(title: output.name, subtitle: subtitle,
                 arg: ["select", output.uid])
        }
    }

    private static func fail(_ error: Error) -> Never {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        exit(EXIT_FAILURE)
    }
}
