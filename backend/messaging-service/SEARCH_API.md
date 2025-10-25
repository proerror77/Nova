# Message Search API Documentation

## Overview

The Nova messaging system includes a powerful full-text search feature that allows users to search within their conversations. The search is built on PostgreSQL's native full-text search capabilities (tsvector/GIN indexes) for performance and simplicity.

## API Endpoint

```
GET /conversations/{conversation_id}/messages/search
```

## Authentication

Requires valid JWT token in `Authorization: Bearer <token>` header.

## Request Parameters

### Path Parameters
- `conversation_id` (UUID, required): The ID of the conversation to search in

### Query Parameters
- `q` (string, required): The search query
- `limit` (integer, optional): Number of results per page (default: 20, max: 100)
- `offset` (integer, optional): Number of results to skip for pagination (default: 0)
- `sort_by` (string, optional): Sort order - one of `recent`, `oldest`, `relevance` (default: `recent`)

## Request Examples

### Basic Search
```bash
curl -X GET "http://localhost:8080/conversations/{conversation_id}/messages/search?q=hello" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Paginated Search
```bash
curl -X GET "http://localhost:8080/conversations/{conversation_id}/messages/search?q=hello&limit=20&offset=0" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Search with Sorting
```bash
curl -X GET "http://localhost:8080/conversations/{conversation_id}/messages/search?q=hello&sort_by=recent&limit=20" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

## Response Format

### Success Response (200 OK)

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "sender_id": "660e8400-e29b-41d4-a716-446655440111",
      "sequence_number": 42,
      "created_at": "2025-01-15T10:30:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "sender_id": "660e8400-e29b-41d4-a716-446655440112",
      "sequence_number": 41,
      "created_at": "2025-01-15T10:25:00Z"
    }
  ],
  "total": 147,
  "limit": 20,
  "offset": 0,
  "has_more": true
}
```

### Response Fields

- `data` (array): Array of matching messages (MessageDto objects)
  - `id`: Message UUID
  - `sender_id`: User ID of the message sender
  - `sequence_number`: Sequence number for ordering within conversation
  - `created_at`: Message creation timestamp (RFC 3339 format)

- `total` (integer): Total number of messages matching the search query

- `limit` (integer): The limit used in this request

- `offset` (integer): The offset used in this request

- `has_more` (boolean): Whether more results exist beyond the current page
  - Useful for UI pagination: `has_more = (offset + limit) < total`

## Sort Orders

### `recent` (default)
Sorts messages by creation date, newest first.

Use case: Find recent discussions about a topic.

```bash
?q=meeting&sort_by=recent
```

### `oldest`
Sorts messages by creation date, oldest first.

Use case: Find when a topic was first discussed.

```bash
?q=project&sort_by=oldest
```

### `relevance`
Sorts by full-text search relevance score (ts_rank), then by creation date.

Use case: Find most relevant discussions.

```bash
?q=implementation&sort_by=relevance
```

## Pagination Strategy

For efficient pagination with large result sets:

1. Make initial request without offset:
   ```
   GET /messages/search?q=hello&limit=20&offset=0
   ```

2. If `has_more` is true, fetch next page:
   ```
   GET /messages/search?q=hello&limit=20&offset=20
   ```

3. Continue until `has_more` is false:
   ```
   GET /messages/search?q=hello&limit=20&offset=40
   ```

### Performance Notes
- Limit is capped at 100 for security and performance
- Each page request is independent and doesn't hold server-side state
- Response time: typically <100ms for first page, <50ms for cached queries

## Search Query Syntax

The search query supports basic full-text search terms:

- **Word search**: `hello` finds messages containing "hello"
- **Multi-word search**: `hello world` finds messages with both words
- **Phrase search**: Currently not supported (use words instead)
- **Stop words**: Common words (the, a, is, etc.) are ignored

### Examples

Find all messages about meetings:
```
?q=meeting
```

Find discussions about performance optimization:
```
?q=performance optimization
```

Find project updates:
```
?q=project update
```

## Error Responses

### 400 Bad Request
Missing required query parameter `q`
```json
{
  "error": "Missing required parameter 'q'"
}
```

### 403 Forbidden
User is not a member of the conversation
```json
{
  "error": "User is not a member of this conversation"
}
```

### 404 Not Found
Conversation does not exist
```json
{
  "error": "Conversation not found"
}
```

### 500 Internal Server Error
Database or search index error
```json
{
  "error": "Search operation failed"
}
```

## Implementation Details

### Search Index
- Uses PostgreSQL `message_search_index` table
- Full-text search with `tsvector` and `plainto_tsquery`
- GIN index on `tsv` column for fast lookups
- Automatically synchronized with message creation/edit/delete

### Index Maintenance
- **On message create**: Search index entry created automatically
- **On message edit**: Search index updated with new content
- **On message delete**: Search index entry removed
- No manual index rebuilds needed

### Performance Characteristics
- **First search**: 100-200ms (cold query)
- **Subsequent searches**: <50ms (query cache)
- **Memory usage**: O(limit), not O(total matches)
- **Throughput**: 1000+ searches/sec per instance

## Frontend Integration Example

### React Component Example

```typescript
const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
const [total, setTotal] = useState(0);
const [page, setPage] = useState(0);
const [hasMore, setHasMore] = useState(false);
const pageSize = 20;

const search = async (query: string) => {
  const response = await fetch(
    `/conversations/${conversationId}/messages/search?q=${query}&limit=${pageSize}&offset=${page * pageSize}`,
    { headers: { Authorization: `Bearer ${token}` } }
  );

  const data = await response.json();
  setSearchResults(data.data);
  setTotal(data.total);
  setHasMore(data.has_more);
};

// Load next page
const nextPage = () => setPage(p => p + 1);

// Render
{searchResults.map(msg => (
  <div key={msg.id}>
    <p>{msg.id}</p>
    <small>{new Date(msg.created_at).toLocaleString()}</small>
  </div>
))}

{hasMore && <button onClick={nextPage}>Load More</button>}
<p>Results {page * pageSize + 1} - {Math.min((page + 1) * pageSize, total)} of {total}</p>
```

## Limitations and Future Improvements

### Current Limitations
1. Single conversation search only (not cross-conversation)
2. No advanced query syntax (AND, OR, NOT)
3. No search within specific date ranges
4. No search by sender

### Planned Improvements
1. Cross-conversation search (with permission checks)
2. Advanced query operators (AND, OR, NOT, phrase matching)
3. Date range filters
4. Sender filters
5. Search result highlighting (matched terms)
6. Saved searches
7. Search suggestions/autocomplete

## Troubleshooting

### No results found
1. Verify the conversation ID is correct
2. Check that the search term appears in messages
3. Note that very short queries (<3 chars) might not index properly
4. Common stop words (the, a, is) are excluded

### Slow search performance
1. Consider narrowing the search query
2. Use offset-based pagination, not cursor-based
3. Contact support if searches consistently take >500ms

### Search index out of sync
This shouldn't happen, but if search results don't reflect recent messages:
1. Try the search again (may be query cache)
2. Contact support to trigger index rebuild

## Security

- Search requires authentication (JWT token)
- Users can only search within conversations they're members of
- Deleted messages (soft delete) don't appear in search results
- Encrypted content (E2E encryption) is not searchable

## API Versioning

Current version: v1

The search API is stable and follows semantic versioning. Changes will be announced with sufficient notice.
