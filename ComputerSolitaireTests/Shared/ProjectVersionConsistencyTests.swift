import XCTest

/// Guards the version settings in project.pbxproj. The two app targets each
/// expose their own Version and Build fields in Xcode, so a pane edit can
/// silently fork the values apart; these tests fail the suite the moment the
/// project file disagrees with itself.
final class ProjectVersionConsistencyTests: XCTestCase {
    func testMarketingVersionIsIdenticalEverywhere() throws {
        let values = try values(forSetting: "MARKETING_VERSION")
        XCTAssertFalse(values.isEmpty, "project.pbxproj defines no MARKETING_VERSION")
        XCTAssertEqual(
            values.count, 1,
            "MARKETING_VERSION has diverged across targets: \(values.sorted())"
        )
    }

    func testBuildNumberIsIdenticalEverywhere() throws {
        let values = try values(forSetting: "CURRENT_PROJECT_VERSION")
        XCTAssertFalse(values.isEmpty, "project.pbxproj defines no CURRENT_PROJECT_VERSION")
        XCTAssertEqual(
            values.count, 1,
            "CURRENT_PROJECT_VERSION has diverged across targets: \(values.sorted())"
        )
    }

    /// Values of every unconditional `NAME = value;` line. Conditional
    /// variants such as `"NAME[sdk=macosx*]"` are quoted, so they never
    /// start a trimmed line with the bare setting name.
    private func values(forSetting name: String) throws -> Set<String> {
        var values: Set<String> = []
        for line in try projectFileContents().split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(name) = "), trimmed.hasSuffix(";") else { continue }
            values.insert(String(trimmed.dropFirst("\(name) = ".count).dropLast()))
        }
        return values
    }

    private func projectFileContents() throws -> String {
        let projectFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Shared
            .deletingLastPathComponent() // ComputerSolitaireTests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("ComputerSolitaire.xcodeproj/project.pbxproj")
        return try String(contentsOf: projectFile, encoding: .utf8)
    }
}
