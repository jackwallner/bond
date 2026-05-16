import Foundation
import Testing

@testable import Bond

struct CoupleDTOTests {
    private let partnerA = UUID()
    private let partnerB = UUID()
    private let stranger = UUID()

    @Test func partnerId_selfIsA_returnsB() {
        let c = CoupleDTO(id: UUID(), partnerA: partnerA, partnerB: partnerB, pairedAt: nil, solo: false)
        #expect(c.partnerId(forSelf: partnerA) == partnerB)
    }

    @Test func partnerId_selfIsB_returnsA() {
        let c = CoupleDTO(id: UUID(), partnerA: partnerA, partnerB: partnerB, pairedAt: nil, solo: false)
        #expect(c.partnerId(forSelf: partnerB) == partnerA)
    }

    @Test func partnerId_stranger_returnsNil() {
        let c = CoupleDTO(id: UUID(), partnerA: partnerA, partnerB: partnerB, pairedAt: nil, solo: false)
        #expect(c.partnerId(forSelf: stranger) == nil)
    }

    @Test func partnerId_solo_sameUser() {
        let me = UUID()
        let c = CoupleDTO(id: UUID(), partnerA: me, partnerB: me, pairedAt: nil, solo: true)
        #expect(c.partnerId(forSelf: me) == me)
    }

    @Test func codable_roundTrip() throws {
        let original = CoupleDTO(id: UUID(), partnerA: partnerA, partnerB: partnerB, pairedAt: .now, solo: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CoupleDTO.self, from: data)
        #expect(decoded == original)
    }
}
