import Foundation
import Testing

@testable import Bond

struct ProfileDTOTests {
    @Test func codable_roundTrip() throws {
        let original = ProfileDTO(
            id: UUID(),
            displayName: "Alice",
            avatarUrl: "https://example.com/avatar.png",
            apnsToken: "abc123token",
            createdAt: .now
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProfileDTO.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.displayName == "Alice")
        #expect(decoded.avatarUrl == "https://example.com/avatar.png")
        #expect(decoded.apnsToken == "abc123token")
    }

    @Test func codable_optionalFields_nil() throws {
        let original = ProfileDTO(id: UUID(), displayName: nil, avatarUrl: nil, apnsToken: nil, createdAt: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProfileDTO.self, from: data)
        #expect(decoded == original)
    }
}
