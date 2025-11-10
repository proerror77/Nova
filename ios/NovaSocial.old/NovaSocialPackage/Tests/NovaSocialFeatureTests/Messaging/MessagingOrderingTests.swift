import Testing
import Foundation

@Suite("Messaging Ordering & De-dup")
struct MessagingOrderingTests {
    struct MessageDtoTest: Equatable { let id: UUID; let sequenceNumber: Int64 }

    final class OrderingBufferTest {
        private var ids = Set<UUID>()
        private var seqs = Set<Int64>()
        private(set) var items: [MessageDtoTest] = []
        func appendIfNew(_ m: MessageDtoTest) -> Bool {
            if ids.contains(m.id) || seqs.contains(m.sequenceNumber) { return false }
            ids.insert(m.id); seqs.insert(m.sequenceNumber)
            items.append(m)
            items.sort { $0.sequenceNumber < $1.sequenceNumber }
            return true
        }
    }

    @Test("keeps order by sequenceNumber and removes duplicates")
    func testOrderAndDedup() {
        let buf = OrderingBufferTest()
        _ = buf.appendIfNew(.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, sequenceNumber: 2))
        _ = buf.appendIfNew(.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, sequenceNumber: 1))
        #expect(buf.items.map{ $0.sequenceNumber } == [1,2])
        // dup by id
        #expect(buf.appendIfNew(.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, sequenceNumber: 9)) == false)
        // dup by sequence
        #expect(buf.appendIfNew(.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, sequenceNumber: 2)) == false)
    }
}

