import Foundation

/// OrderingBuffer maintains in-order message list and de-duplicates by id and sequence number.
final class OrderingBuffer: @unchecked Sendable {
    private var byId = Set<UUID>()
    private var bySeq = Set<Int64>()
    private var items: [MessageDto] = []

    func appendIfNew(_ m: MessageDto) -> Bool {
        if byId.contains(m.id) || bySeq.contains(m.sequenceNumber) { return false }
        byId.insert(m.id)
        bySeq.insert(m.sequenceNumber)
        items.append(m)
        items.sort { $0.sequenceNumber < $1.sequenceNumber }
        return true
    }

    func snapshot() -> [MessageDto] { items }
    func clear() { byId.removeAll(); bySeq.removeAll(); items.removeAll() }
}

