#!/usr/bin/env bash
set -euo pipefail

MILVUS_URL=${MILVUS_URL:-http://localhost:9091}
COLLECTION=${MILVUS_COLLECTION:-video_embeddings}
DIM=${EMBEDDING_DIM:-512}

echo "Milvus URL: $MILVUS_URL"
echo "Collection: $COLLECTION (dim=$DIM)"

echo "Checking collection..."
if curl -sf "$MILVUS_URL/v1/vector_db/collections/$COLLECTION" >/dev/null; then
  echo "Collection exists: $COLLECTION"
  exit 0
fi

echo "Creating collection..."
curl -sS -X POST "$MILVUS_URL/v1/vector_db/collections" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$COLLECTION\",\"dimension\":$DIM,\"metric\":\"cosine\",\"shards\":1}" \
  | sed -e 's/.*/OK/'

echo "Done."

